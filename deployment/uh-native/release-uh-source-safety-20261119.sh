#!/usr/bin/env bash
set -Eeuo pipefail
P=/srv/uhde/candidates/uh-petitions-native-source-safety-20261119
NEW_WEB=sha256:cb6eb57f6ad81a60741c207c120a715f04ad4f22ff3037c73c7d46fd30a09dcc
NEW_WORKER=sha256:660a6d1acd100f48ba4e2411e5c9f6036e32eff91c3d68a3bca36b8dd8e7ddb5
OLD_WEB=sha256:6675bd754e5c6914c6ffc3dc231dc3254375ff7b5b7ae63c9580a01370fd047a
OLD_WORKER=sha256:2416fd6aaca8cf974c5ea59cc9913da1f8153b2dc474444d3584f4af577c5109
BACK_WEB=uh-petitions-web-before-source-safety-20261119
BACK_WORKER=uh-petitions-worker-before-source-safety-20261119
test "$(docker inspect uh-petitions-web --format '{{.Image}}')" = "$OLD_WEB"
test "$(docker inspect uh-petitions-worker --format '{{.Image}}')" = "$OLD_WORKER"
test "$(docker image inspect uhparliament/e-petitions:uh-source-safety-web-20261119 --format '{{.Id}}')" = "$NEW_WEB"
test "$(docker image inspect uhparliament/e-petitions:uh-source-safety-worker-20261119 --format '{{.Id}}')" = "$NEW_WORKER"
test "$(stat -c %a "$P/web.env")" = 600
test "$(stat -c %a "$P/worker.env")" = 600
test -s "$P/verification/petitions-pre-release-20261119.dump"
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
for x in "$BACK_WEB" "$BACK_WORKER"; do
 if docker inspect "$x" >/dev/null 2>&1;then echo "Existing rollback container: $x" >&2; exit 23;fi
done
# The old worker is quiescent. No queued emails are present.
if docker inspect uh-petitions-source-safety-qa >/dev/null 2>&1;then
 docker stop -t 15 uh-petitions-source-safety-qa >/dev/null
fi
rollback() {
 code=$?
 trap - ERR
 echo "SOURCE_SAFETY_ROLLBACK initiating due to exit $code" >&2
 for now in uh-petitions-web uh-petitions-worker;do
  if docker inspect "$now" >/dev/null 2>&1;then docker rm -f "$now" >/dev/null || true;fi
 done
 for old in "$BACK_WEB" "$BACK_WORKER";do
  name=uh-petitions-web
  [[ "$old" == "$BACK_WORKER" ]] && name=uh-petitions-worker
  if docker inspect "$old" >/dev/null 2>&1;then docker rename "$old" "$name" && docker start "$name" >/dev/null;fi
 done
 exit "$code"
}
trap rollback ERR
docker stop -t 20 uh-petitions-worker >/dev/null
docker rename uh-petitions-worker "$BACK_WORKER"
docker run -d --name uh-petitions-worker --restart unless-stopped \
 --network uh-parliament-services --env-file "$P/worker.env" \
 -v uh-petitions-storage:/app/storage:z \
 uhparliament/e-petitions:uh-source-safety-worker-20261119 \
 bundle exec rake jobs:work >/dev/null
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true
docker stop -t 20 uh-petitions-web >/dev/null
docker rename uh-petitions-web "$BACK_WEB"
docker run -d --name uh-petitions-web --restart unless-stopped \
 --network uh-parliament-services -p 127.0.0.1:55410:3000 \
 --env-file "$P/web.env" -v uh-petitions-storage:/app/storage:z \
 uhparliament/e-petitions:uh-source-safety-web-20261119 \
 bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null
python3 - <<'PY'
import requests,time
base='https://petition.parliament.uhrblx.com'
for i in range(30):
 try:
  r=requests.get(base+'/archived/petitions',timeout=6)
  if r.status_code==200:break
 except requests.RequestException:pass
 time.sleep(1)
else:raise AssertionError('archive unavailable after release')
for path in ('/','/help','/privacy','/standards','/cookies','/accessibility','/archived/petitions'):
 r=requests.get(base+path,timeout=10)
 assert r.status_code==200,(path,r.status_code)
 if path=='/':
  assert 'Find petitions' in r.text
  assert 'Electronic petitions are not currently open' in r.text
r=requests.get(base+'/crown-copyright',allow_redirects=False,timeout=10)
assert r.status_code==302 and r.headers.get('Location')=='https://nationalarchives.gov.uhrblx.com/doc/open-government-licence/version/3/'
r=requests.get(base+'/petitions/start',allow_redirects=False,timeout=10)
assert r.status_code in (301,302,303),r.status_code
r=requests.get('https://moderate.petition.parliament.uhrblx.com/admin/login',timeout=10)
assert r.status_code==200 and 'authenticator_code' in r.text
print('PRODUCTION_UH_PETITIONS_PUBLIC_AND_STAFF_ENTRY_PASS')
PY
test "$(docker inspect uh-petitions-web --format '{{.Image}}')" = "$NEW_WEB"
test "$(docker inspect uh-petitions-worker --format '{{.Image}}')" = "$NEW_WORKER"
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
trap - ERR
rm -f "$P/web.env" "$P/worker.env"
echo "RELEASE_SUCCESS_WEB=$NEW_WEB WORKER=$NEW_WORKER ROLLBACK_CONTAINERS=$BACK_WEB,$BACK_WORKER"