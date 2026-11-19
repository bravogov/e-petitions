#!/usr/bin/env bash
set -Eeuo pipefail
WEB=uh-petitions-web
BACK=uh-petitions-web-before-mfa-role-20261118
IMG=uhparliament/e-petitions:uh-staff-role-20261118-aa9ba5da
OLD=sha256:1daa1b20ca309a405375875899e5a725046f734a015ea5e2dba0bbc0dfaf8c3f
NEW=sha256:6675bd754e5c6914c6ffc3dc231dc3254375ff7b5b7ae63c9580a01370fd047a
ENV=/run/uh-petitions-staff-role-production-20261118.env
test "$(docker inspect "$WEB" --format '{{.Image}}')" = "$OLD"
test "$(docker image inspect "$IMG" --format '{{.Id}}')" = "$NEW"
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
if docker inspect "$BACK" >/dev/null 2>&1; then echo 'Rollback name collision; refusing' >&2;exit 3;fi
python3 - <<'PY'
import subprocess,json,os
env=json.loads(subprocess.check_output(['docker','inspect','uh-petitions-web']))[0]['Config']['Env']
pairs=dict(x.split('=',1) for x in env if '=' in x)
assert len(pairs)==30
assert pairs['SMTP_GOOGLE_RELAY_ENABLED']=='true'
assert pairs['SMTP_RELAY_HOST']=='smtp-relay.gmail.com'
assert pairs['SMTP_RELAY_PORT']=='587'
assert all(pairs[k].count('\\')==0 for k in ('EPETITIONS_FROM','EPETITIONS_FEEDBACK'))
path='/run/uh-petitions-staff-role-production-20261118.env'
fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as file:
 for line in env:file.write(line+'\n')
print('Protected existing production environment preserved: 30 keys')
PY
test "$(stat -c %a "$ENV")" = 600
restore(){
 code=$?
 trap - ERR
 echo "Staff role release failed; restoring prior web image (code $code)" >&2
 if docker inspect "$BACK" >/dev/null 2>&1; then
  if docker inspect "$WEB" >/dev/null 2>&1;then docker rm -f "$WEB" >/dev/null 2>&1 || true;fi
  docker rename "$BACK" "$WEB" || true
  docker start "$WEB" >/dev/null 2>&1 || true
 fi
 exit "$code"
}
trap restore ERR
docker stop -t 20 "$WEB" >/dev/null
docker rename "$WEB" "$BACK"
docker run -d --name "$WEB" --restart unless-stopped \
 --network uh-parliament-services -p 127.0.0.1:55410:3000 \
 -v uh-petitions-storage:/app/storage:z \
 --env-file "$ENV" "$IMG" \
 bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null
python3 - <<'PY'
import time,requests
base='https://petition.parliament.uhrblx.com'
for i in range(30):
 try:
  if requests.get(base+'/archived/petitions',timeout=5).status_code==200:break
 except requests.RequestException:pass
 time.sleep(1)
else:raise RuntimeError('Archive did not recover')
for path in ('/','/help','/privacy','/standards','/cookies','/accessibility','/archived/petitions'):
 r=requests.get(base+path,timeout=10)
 assert r.status_code==200,(path,r.status_code)
 if path=='/':
  assert 'Electronic petitions are not currently open' in r.text
  assert 'Find petitions' in r.text
r=requests.get(base+'/crown-copyright',timeout=10,allow_redirects=False)
assert r.status_code==302 and r.headers['Location']=='https://nationalarchives.gov.uhrblx.com/doc/open-government-licence/version/3/'
r=requests.get(base+'/petitions/start',timeout=10,allow_redirects=False)
assert r.status_code==302
r=requests.get('https://moderate.petition.parliament.uhrblx.com/admin/login',timeout=10)
assert r.status_code==200 and 'authenticator_code' in r.text
print('PUBLIC_AND_STAFF_MFA_ENTRY_STILL_HEALTHY')
PY
test "$(docker inspect "$WEB" --format '{{.Image}}')" = "$NEW"
test "$(docker inspect uh-petitions-worker --format '{{.State.Running}}')" = true
test "$(docker inspect uh-petitions-postgres --format '{{.State.Running}}')" = true
docker exec "$WEB" sh -lc 'RAILS_ENV=production bundle exec rails runner "raise %(ROLES_INVALID) unless AdminUser::ROLES.sort==%w(moderator reviewer sysadmin);raise %(ACCOUNT_MISSING) unless AdminUser.count==1&&ParliamentStaffCredential.count==1;puts %(NATIVE_ROLES_AND_EXISTING_ACCOUNT_PRESERVED)"' | grep -q 'NATIVE_ROLES_AND_EXISTING_ACCOUNT_PRESERVED'
trap - ERR
rm -f "$ENV"
echo "STAFF_ROLE_RELEASE_OK web=$NEW worker_unchanged=true production_db_unchanged=true source=aa9ba5dac65b9789aa13e93ba893de3c6aa244b8 rollback=$BACK"
