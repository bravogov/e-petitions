#!/usr/bin/env bash
set -Eeuo pipefail
R=/srv/uhde/candidates/uh-petitions-feedback-native-20261119
OLD_WEB=sha256:cb6eb57f6ad81a60741c207c120a715f04ad4f22ff3037c73c7d46fd30a09dcc
OLD_WORKER=sha256:660a6d1acd100f48ba4e2411e5c9f6036e32eff91c3d68a3bca36b8dd8e7ddb5
NEW_WEB=sha256:5da75ce22e9776bd968e7d774559cc579a65232cf5c212e6565feddd40dbbd4f
NEW_WORKER=sha256:7974b0a91e0d5a84620a7784b44438753ae24b2c2b879f7f7e4d37359d5649dd
BACK_WEB=uh-petitions-web-before-feedback-20261119
BACK_WORKER=uh-petitions-worker-before-feedback-20261119
test "$(docker inspect uh-petitions-web --format '{{.Image}}')" = "$OLD_WEB"
test "$(docker inspect uh-petitions-worker --format '{{.Image}}')" = "$OLD_WORKER"
test "$(docker image inspect uhparliament/e-petitions:feedback-native-web-20261119 --format '{{.Id}}')" = "$NEW_WEB"
test "$(docker image inspect uhparliament/e-petitions:feedback-native-worker-20261119 --format '{{.Id}}')" = "$NEW_WORKER"
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
test -s "$R/evidence/feedback-pre-release-20261119.dump"
test "$(stat -c %a "$R/evidence/feedback-pre-release-20261119.dump")" = 600
test "$(stat -c %a "$R/web.env")" = 600
test "$(stat -c %a "$R/worker.env")" = 600
for c in "$BACK_WEB" "$BACK_WORKER"; do
  if docker inspect "$c" >/dev/null 2>&1; then
    echo "Rollback container name already exists: $c" >&2; exit 27
  fi
done

rollback() {
  status=$?
  trap - ERR
  echo "ROLLBACK_FEEDBACK_NATIVE_RELEASE: exit $status" >&2
  for entry in "$BACK_WEB:uh-petitions-web" "$BACK_WORKER:uh-petitions-worker"; do
    original="${entry%%:*}"
    restored="${entry#*:}"
    if docker inspect "$original" >/dev/null 2>&1; then
      if docker inspect "$restored" >/dev/null 2>&1; then
        docker rm -f "$restored" >/dev/null || true
      fi
      docker rename "$original" "$restored"
      docker start "$restored" >/dev/null
    fi
  done
  exit "$status"
}
trap rollback ERR

docker stop -t 25 uh-petitions-worker >/dev/null
docker rename uh-petitions-worker "$BACK_WORKER"
docker run -d --name uh-petitions-worker --restart unless-stopped \
  --network uh-parliament-services --env-file "$R/worker.env" \
  -v uh-petitions-storage:/app/storage:z \
  uhparliament/e-petitions:feedback-native-worker-20261119 \
  bundle exec rake jobs:work >/dev/null
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true

docker stop -t 25 uh-petitions-web >/dev/null
docker rename uh-petitions-web "$BACK_WEB"
docker run -d --name uh-petitions-web --restart unless-stopped \
  --network uh-parliament-services -p 127.0.0.1:55410:3000 \
  --env-file "$R/web.env" -v uh-petitions-storage:/app/storage:z \
  uhparliament/e-petitions:feedback-native-web-20261119 \
  bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null

python3 - <<'PY'
import time, requests
base="https://petition.parliament.uhrblx.com"
for n in range(30):
    try:
        res=requests.get(base+"/feedback",timeout=8)
        if res.status_code==200:break
    except requests.RequestException:
        pass
    time.sleep(1)
else:
    raise RuntimeError("Feedback release did not become reachable")
assert "United Hampshire Parliament contact page" in res.text
assert "petitionscommittee@parliament.uk" not in res.text
assert "0800 112 4272" not in res.text
print("FEEDBACK_PUBLIC_CONTACT_CORRECTED",res.status_code)
for path in ("/","/help","/privacy","/standards","/cookies","/accessibility","/archived/petitions","/feedback/thanks"):
    r=requests.get(base+path,timeout=10)
    assert r.status_code==200,(path,r.status_code)
print("PETITIONS_PUBLIC_PAGES_PRESERVED")
moderator="https://moderate.petition.parliament.uhrblx.com"
r=requests.get(moderator+"/admin/login",timeout=10)
assert r.status_code==200 and "authenticator_code" in r.text
r=requests.get(moderator+"/admin/feedback",timeout=10,allow_redirects=False)
assert r.status_code in (301,302,303)
assert "/admin/login" in r.headers.get("Location","")
print("STAFF_MFA_INTACT_AND_NEW_FEEDBACK_INBOX_PROTECTED")
r=requests.get(base+"/petitions/start",timeout=10,allow_redirects=False)
assert r.status_code in (301,302,303)
print("PETITION_CREATION_STILL_CLOSED")
PY
test "$(docker inspect uh-petitions-web --format '{{.Image}}')" = "$NEW_WEB"
test "$(docker inspect uh-petitions-worker --format '{{.Image}}')" = "$NEW_WORKER"
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
trap - ERR
rm -f "$R/web.env" "$R/worker.env"
echo "PETITIONS_FEEDBACK_NATIVE_RELEASE_SUCCESS"
