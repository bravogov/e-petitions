#!/usr/bin/env bash
set -Eeuo pipefail
WEB=uh-petitions-web
WORKER=uh-petitions-worker
WB=uh-petitions-web-before-address-format-20261118
WK=uh-petitions-worker-before-address-format-20261118
DIR=/run/uh-petitions-address-fix-20261118
IMG_WEB=uhparliament/e-petitions:uh-smtp-web-20261118-9b605161
IMG_WORKER=uhparliament/e-petitions:uh-smtp-worker-20261118-9b605161
OLD_WEB=sha256:1daa1b20ca309a405375875899e5a725046f734a015ea5e2dba0bbc0dfaf8c3f
OLD_WORKER=sha256:2416fd6aaca8cf974c5ea59cc9913da1f8153b2dc474444d3584f4af577c5109
NEW_WEB=sha256:1daa1b20ca309a405375875899e5a725046f734a015ea5e2dba0bbc0dfaf8c3f
NEW_WORKER=sha256:2416fd6aaca8cf974c5ea59cc9913da1f8153b2dc474444d3584f4af577c5109
test "$(docker inspect "$WEB" --format '{{.Image}}')" = "$OLD_WEB"
test "$(docker inspect "$WORKER" --format '{{.Image}}')" = "$OLD_WORKER"
test "$(docker image inspect "$IMG_WEB" --format '{{.Id}}')" = "$NEW_WEB"
test "$(docker image inspect "$IMG_WORKER" --format '{{.Id}}')" = "$NEW_WORKER"
for f in web.env worker.env;do test "$(stat -c %a "$DIR/$f")" = 600;done
for c in "$WB" "$WK";do if docker inspect "$c" >/dev/null 2>&1;then echo "Rollback container collision: $c" >&2;exit 3;fi;done
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
rollback(){
 rc=$?
 trap - ERR
 echo "Release failed; returning both service containers to their previous images (code $rc)" >&2
 for spec in "$WORKER $WK" "$WEB $WB";do
  set -- $spec
  if docker inspect "$2" >/dev/null 2>&1;then
    if docker inspect "$1" >/dev/null 2>&1;then docker rm -f "$1" >/dev/null 2>&1 || true;fi
    docker rename "$2" "$1" || true
    docker start "$1" >/dev/null 2>&1 || true
  fi
 done
 exit "$rc"
}
trap rollback ERR
docker stop -t 20 "$WEB" >/dev/null
docker rename "$WEB" "$WB"
docker run -d --name "$WEB" --restart unless-stopped \
 --network uh-parliament-services -p 127.0.0.1:55410:3000 \
 -v uh-petitions-storage:/app/storage:z \
 --env-file "$DIR/web.env" "$IMG_WEB" \
 bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null
python3 - <<'PY'
import requests,time
base="https://petition.parliament.uhrblx.com"
for i in range(35):
 try:
  if requests.get(base+"/archived/petitions",timeout=5).status_code==200:break
 except requests.RequestException:pass
 time.sleep(1)
else:raise RuntimeError("Petitions archive did not recover")
for path in ("/","/help","/privacy","/standards","/cookies","/accessibility","/archived/petitions"):
 r=requests.get(base+path,timeout=12)
 assert r.status_code==200,(path,r.status_code)
 assert "uk-parliament-logo" not in r.text,path
 if path=="/":
  assert "Electronic petitions are not currently open" in r.text
  assert "Find petitions" in r.text and 'id="start-petition"' not in r.text
r=requests.get(base+"/crown-copyright",timeout=10,allow_redirects=False)
assert r.status_code==302 and r.headers.get("Location")=="https://nationalarchives.gov.uhrblx.com/doc/open-government-licence/version/3/"
r=requests.get(base+"/petitions/start",timeout=10,allow_redirects=False)
assert r.status_code==302
r=requests.get("https://moderate.petition.parliament.uhrblx.com/admin/login",timeout=10)
assert r.status_code==200 and "authenticator_code" in r.text
print("POST_WEB_CUTOVER_PASS")
PY
docker stop -t 20 "$WORKER" >/dev/null
docker rename "$WORKER" "$WK"
docker run -d --name "$WORKER" --restart unless-stopped \
 --network uh-parliament-services -v uh-petitions-storage:/app/storage:z \
 --env-file "$DIR/worker.env" "$IMG_WORKER" \
 bundle exec rake jobs:work >/dev/null
for c in "$WEB" "$WORKER";do
 test "$(docker inspect "$c" --format '{{.State.Running}}')" = true
 docker exec "$c" sh -lc 'RAILS_ENV=production bundle exec rails runner "s=ActionMailer::Base.smtp_settings;raise %(WRONG_SMTP) unless s[:address]==%(smtp-relay.gmail.com)&&s[:port]==587&&Rails.application.config.action_mailer.raise_delivery_errors;puts %(LIVE_SMTP_OK)"' | grep -q LIVE_SMTP_OK
done
test "$(docker inspect "$WEB" --format '{{.Image}}')" = "$NEW_WEB"
test "$(docker inspect "$WORKER" --format '{{.Image}}')" = "$NEW_WORKER"
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
for c in "$WEB" "$WORKER"; do
 docker exec "$c" sh -lc 'RAILS_ENV=production bundle exec rails runner "%w(EPETITIONS_FROM EPETITIONS_FEEDBACK).each{|k| a=Mail::AddressList.new(ENV.fetch(k)).addresses;abort(:INVALID) unless a.length==1&&a.first.address.match?(/\A[^\s<>]+@[^\s<>]+\z/)};puts :ADDRESSES_OK"' | grep -q ADDRESSES_OK
done
trap - ERR
rm -f "$DIR/web.env" "$DIR/worker.env"
rmdir "$DIR"
echo "RELEASE_VERIFIED web=$NEW_WEB worker=$NEW_WORKER rollback=$WB,$WK commit=9b6051614b5730e609617cbb16f5b82fab2d232b"
