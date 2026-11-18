#!/usr/bin/env bash
set -Eeuo pipefail
OLD=uh-petitions-web
ROLLBACK=uh-petitions-web-before-logo-crop-20261118
IMAGE=uhparliament/e-petitions:legible-identity-20261118-candidate
ENV_FILE=/run/uh-parliament-petitions-crop/runtime.env
EXPECTED_CURRENT=sha256:554fd7d831b04623cf7c0db8026c63c697b6f00f27af9d63f339ad64bf41967d
EXPECTED_NEW=sha256:948563657705c63b0cf62bd002b9a6d712a149e1a20ebfb6ab85e8f7cfe1c9e0
test "$(docker inspect "$OLD" --format '{{.Image}}')" = "$EXPECTED_CURRENT"
test "$(docker image inspect "$IMAGE" --format '{{.Id}}')" = "$EXPECTED_NEW"
test "$(stat -c %a "$ENV_FILE")" = 600
test "$(docker inspect uh-petitions-worker --format '{{.State.Status}}')" = running
test "$(docker inspect uh-petitions-postgres --format '{{.State.Status}}')" = running
test "$(curl -ksS -o /dev/null -w '%{http_code}' https://petition.parliament.uhrblx.com/archived/petitions)" = 200
if docker inspect "$ROLLBACK" >/dev/null 2>&1;then echo 'Rollback collision: refused' >&2;exit 2;fi
on_error(){
 local code=$?
 echo "APPROVED_LOGO_DISPLAY_RELEASE_FAILURE=$code; RESTORING_OLD_CONTAINER" >&2
 if docker inspect "$OLD" >/dev/null 2>&1;then docker rm -f "$OLD" >/dev/null 2>&1 || true;fi
 if docker inspect "$ROLLBACK" >/dev/null 2>&1;then
   docker rename "$ROLLBACK" "$OLD" || true
   docker start "$OLD" >/dev/null 2>&1 || true
 fi
 exit "$code"
}
trap on_error ERR
docker stop -t 20 "$OLD" >/dev/null
docker rename "$OLD" "$ROLLBACK"
docker run -d --name "$OLD" --restart unless-stopped --network uh-parliament-services \
 -p 127.0.0.1:55410:3000 -v uh-petitions-storage:/app/storage:z \
 --env-file "$ENV_FILE" "$IMAGE" \
 bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null
ready=false
for n in $(seq 1 25);do
 code=$(curl -ksS --max-time 4 -H 'Host: petition.parliament.uhrblx.com' -H 'X-Forwarded-Proto: https' -o /dev/null -w '%{http_code}' http://127.0.0.1:55410/archived/petitions || true)
 staff=$(curl -ksS --max-time 4 -H 'Host: moderate.petition.parliament.uhrblx.com' -H 'X-Forwarded-Proto: https' -o /dev/null -w '%{http_code}' http://127.0.0.1:55410/admin/login || true)
 if [[ "$code" == 200 && "$staff" == 200 ]];then ready=true;break;fi
 sleep 1
done
test "$ready" = true
python3 - <<'PY'
import requests
base='https://petition.parliament.uhrblx.com'
s=requests.Session()
for path in ('/','/help','/privacy','/standards','/cookies','/accessibility','/archived/petitions'):
 r=s.get(base+path,timeout=10)
 assert r.status_code==200,(path,r.status_code)
 assert 'uk-parliament-logo' not in r.text,(path,'UK parliamentary mark still rendered')
 assert 'uh-government-coat-of-arms' not in r.text,(path,'unapproved Government identity rendered')
 assert 'uh-parliament-logo.png' in r.text,(path,'approved Parliament mark missing')
 if path=='/':
  assert 'Find petitions' in r.text and 'Electronic petitions are not currently open' in r.text
  assert 'British citizens or UK residents' not in r.text
  assert 'class="uh-parliament-brand-crop"' in r.text
  assert 'id="start-petition"' not in r.text
for path in ('/favicon.svg','/assets/frontend/uk-parliament-logo-ac0b62ff.svg'):
 assert s.get(base+path,timeout=10).status_code==404,(path,'old asset remains')
assert s.get(base+'/petitions/start',timeout=10,allow_redirects=False).status_code==302
r=s.get('https://moderate.petition.parliament.uhrblx.com/admin/login',timeout=10)
assert r.status_code==200 and 'authenticator_code' in r.text
print('PUBLIC_ORIGINAL_ARTWORK_AND_MFA_CHECKS_PASS')
PY
test "$(docker inspect uh-petitions-worker --format '{{.State.Status}}')" = running
test "$(docker inspect uh-petitions-postgres --format '{{.State.Status}}')" = running
test "$(docker inspect "$ROLLBACK" --format '{{.Image}}')" = "$EXPECTED_CURRENT"
trap - ERR
echo "APPROVED_LOGO_DISPLAY_RELEASE_OK OLD_ARCHIVE_ROLLBACK=$ROLLBACK"
