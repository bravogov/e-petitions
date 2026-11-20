#!/usr/bin/env bash
# Original Rails e-petitions: bounded security-only web release. No database schema
# changes, petition intake enablement, publication edits or staff role grants.
set -Eeuo pipefail
exec 9>/run/lock/uh-parliament-petitions-web-release.lock
flock -n 9 || { echo "Another parliamentary petitions web release holds the lock" >&2; exit 40; }
ROOT=/srv/uhde/candidates/uh-petitions-sso-role-revalidation-20261120
OLD_IMAGE=sha256:5f098249caf29f74b290884ab880180d4d07b4dcba4efff017b1dee5136e66a8
NEW_IMAGE=uhparliament/e-petitions:sso-role-revalidated-web-20261120-99e5350
OLD_NAME=uh-petitions-web-before-sso-20261120
NEW_NAME=uh-petitions-web
ENVFILE=/run/uh-petitions-web-sso-20261120.env
BACKUP="$ROOT/evidence/petitions-pre-sso-20261120.dump"
test "$(docker inspect "$NEW_NAME" --format '{{.Image}}')" = "$OLD_IMAGE"
test "$(docker inspect "$NEW_NAME" --format '{{.State.Running}}')" = true
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
! docker inspect "$OLD_NAME" >/dev/null 2>&1
test -f "$ROOT/deployment/uh-native/Dockerfile.sso-role-revalidation-20261120"
git -C "$ROOT" merge-base --is-ancestor 99e535019335484636e47aebfc3ad3417dc9392f HEAD
test "$(docker image inspect uhparliament/e-petitions:feedback-audit-web-20261120 --format '{{.Id}}')" = "$OLD_IMAGE"
docker build --quiet -f "$ROOT/deployment/uh-native/Dockerfile.sso-role-revalidation-20261120" -t "$NEW_IMAGE" "$ROOT" >/dev/null
test "$(docker image inspect "$NEW_IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')" = 99e535019335484636e47aebfc3ad3417dc9392f
for file in app/models/admin_user.rb app/controllers/admin/omniauth_callbacks_controller.rb; do
  actual=$(docker run --rm --network none --entrypoint sha256sum "$NEW_IMAGE" "/app/$file" | awk '{print $1}')
  expected=$(sha256sum "$ROOT/$file" | awk '{print $1}')
  test "$actual" = "$expected"
done
umask 077
mkdir -p "$ROOT/evidence"
chmod 700 "$ROOT/evidence"
docker exec uh-petitions-postgres sh -c 'exec pg_dump -Fc --no-owner -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$BACKUP"
test -s "$BACKUP"
chmod 600 "$BACKUP"
# Preserve all existing runtime values without printing confidential settings.
python3 - "$ENVFILE" <<'PY'
import json,os,subprocess,sys
p=sys.argv[1]
c=json.loads(subprocess.check_output(['docker','inspect','uh-petitions-web']))[0]
with open(p,'w',encoding='utf-8') as f:
    for item in c['Config']['Env']:
        if '\n' in item or '\r' in item or '=' not in item:
            raise SystemExit('Unsupported environment entry; refusing release')
        f.write(item+'\n')
os.chmod(p,0o600)
PY
test "$(stat -c %a "$ENVFILE")" = 600
rollback() {
  code=$?
  trap - ERR
  echo "PETITIONS_SSO_ROLE_RELEASE_ROLLBACK_CODE=$code" >&2
  if docker inspect "$OLD_NAME" >/dev/null 2>&1; then
    if docker inspect "$NEW_NAME" >/dev/null 2>&1; then docker rm -f "$NEW_NAME" >/dev/null 2>&1 || true; fi
    docker rename "$OLD_NAME" "$NEW_NAME"
    docker start "$NEW_NAME" >/dev/null
  fi
  rm -f "$ENVFILE"
  exit "$code"
}
trap rollback ERR
# Recheck the running revision immediately before replacing it.
test "$(docker inspect "$NEW_NAME" --format '{{.Image}}')" = "$OLD_IMAGE"
docker stop -t 25 "$NEW_NAME" >/dev/null
docker rename "$NEW_NAME" "$OLD_NAME"
docker run -d --name "$NEW_NAME" --restart unless-stopped \
  --network uh-parliament-services -p 127.0.0.1:55410:3000 \
  --env-file "$ENVFILE" -v uh-petitions-storage:/app/storage:z \
  "$NEW_IMAGE" bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null
python3 - <<'PY'
import requests,time
public='https://petition.parliament.uhrblx.com'
admin='https://moderate.petition.parliament.uhrblx.com'
for i in range(35):
    try:
        if requests.get(public+'/help',timeout=5).status_code==200: break
    except requests.RequestException: pass
    time.sleep(1)
else:
    raise RuntimeError('Petitions native Rails web never became ready')
for path in ('/','/petitions','/help','/feedback','/privacy','/archived/petitions'):
    resp=requests.get(public+path,timeout=10)
    assert resp.status_code==200,(path,resp.status_code)
resp=requests.get(public+'/petitions/new',allow_redirects=False,timeout=10)
assert resp.status_code in (301,302,303) and resp.headers.get('Location','').endswith('/'),resp.status_code
resp=requests.get(admin+'/admin/login',timeout=10)
assert resp.status_code==200,resp.status_code
resp=requests.get(admin+'/admin/feedback',allow_redirects=False,timeout=10)
assert resp.status_code in (301,302,303) and '/admin/login' in resp.headers.get('Location',''),resp.status_code
print('PETITIONS_REAL_PUBLIC_ROUTES_UP_ADMIN_PROTECTED_CREATION_CLOSED')
PY
test "$(docker inspect "$NEW_NAME" --format '{{.State.Running}}')" = true
test "$(docker inspect "$NEW_NAME" --format '{{.Config.Image}}')" = "$NEW_IMAGE"
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
trap - ERR
rm -f "$ENVFILE"
echo "PETITIONS_SSO_ROLE_SECURITY_RELEASE_SUCCESS"
echo "SOURCE_REVISION=99e535019335484636e47aebfc3ad3417dc9392f"
echo "BACKUP=$BACKUP"
echo "ROLLBACK_CONTAINER=$OLD_NAME"
