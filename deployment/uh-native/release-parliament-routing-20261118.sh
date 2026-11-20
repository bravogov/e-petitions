#!/usr/bin/env bash
set -Eeuo pipefail
CURRENT="sha256:948563657705c63b0cf62bd002b9a6d712a149e1a20ebfb6ab85e8f7cfe1c9e0"
NEW="sha256:e263904c9185d79077fd379a9720c376f8ff286063c1824d7991776c641ca30c"
IMAGE="uhparliament/e-petitions:uh-routing-20261118-ba815625"
OLD="uh-petitions-web"
BACK="uh-petitions-web-before-routing-20261118"
ENV="/run/uh-parliament-petitions-route-20261118/runtime.env"
test "$(docker inspect "$OLD" --format '{{.Image}}')" = "$CURRENT"
test "$(docker image inspect "$IMAGE" --format '{{.Id}}')" = "$NEW"
test "$(stat -c %a "$ENV")" = 600
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
if docker inspect "$BACK" >/dev/null 2>&1; then echo 'Rollback container already exists; refusing.' >&2; exit 2; fi
if docker inspect uh-petitions-routing-qa-20261118 >/dev/null 2>&1; then
 docker stop -t 15 uh-petitions-routing-qa-20261118 >/dev/null
fi
restore() {
 rc=$?
 trap - ERR
 echo "Release failed, restoring previous petitions web container (exit $rc)" >&2
 if docker inspect "$BACK" >/dev/null 2>&1; then
   if docker inspect "$OLD" >/dev/null 2>&1; then docker rm -f "$OLD" >/dev/null || true; fi
   docker rename "$BACK" "$OLD"
 fi
 docker start "$OLD" >/dev/null 2>&1 || true
 exit "$rc"
}
trap restore ERR
docker stop -t 20 "$OLD" >/dev/null
docker rename "$OLD" "$BACK"
docker run -d --name "$OLD" --restart unless-stopped \
 --network uh-parliament-services -p 127.0.0.1:55410:3000 \
 -v uh-petitions-storage:/app/storage:z --env-file "$ENV" "$IMAGE" \
 bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null
python3 - <<'PY'
import requests,time
base="https://petition.parliament.uhrblx.com"
for i in range(35):
 try:
  r=requests.get(base+"/archived/petitions",timeout=6)
  if r.status_code==200:break
 except requests.RequestException:pass
 time.sleep(1)
else:raise RuntimeError("Web route unavailable")
for path in ["/","/help","/privacy","/standards","/cookies","/accessibility","/archived/petitions"]:
 r=requests.get(base+path,timeout=12)
 assert r.status_code==200,(path,r.status_code)
 assert "uk-parliament-logo" not in r.text,(path,"retired emblem")
 if path=="/":
  assert "Find petitions" in r.text and "Electronic petitions are not currently open" in r.text
  assert 'id="start-petition"' not in r.text
r=requests.get(base+"/crown-copyright",timeout=12,allow_redirects=False)
assert r.status_code==302,(r.status_code,r.text[:100])
assert r.headers.get("Location")=="https://nationalarchives.gov.uhrblx.com/doc/open-government-licence/version/3/"
assert "max-age" not in r.headers.get("Cache-Control","").lower()
r=requests.get(base+"/petitions/start",timeout=10,allow_redirects=False)
assert r.status_code==302,r.status_code
r=requests.get("https://moderate.petition.parliament.uhrblx.com/admin/login",timeout=12)
assert r.status_code==200 and "authenticator_code" in r.text
print("PRODUCTION_ROUTE_AND_EXISTING_CLOSED_SERVICE_CHECKS_PASS")
PY
test "$(docker inspect "$OLD" --format '{{.Image}}')" = "$NEW"
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true
trap - ERR
rm -f "$ENV"
rmdir /run/uh-parliament-petitions-route-20261118
echo "RELEASE_OK image=$NEW source=ba815625bf0d332a0b99187fe0c750a4c76afcb0 rollback=$BACK"
