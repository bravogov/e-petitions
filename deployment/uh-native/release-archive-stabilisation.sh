#!/usr/bin/env bash
set -Eeuo pipefail
# Scoped, reversible replacement of the running Parliament petitions web
# container only. Neither the PostgreSQL container nor worker is restarted.
OLD=uh-petitions-web
ROLLBACK=uh-petitions-web-before-archive-20261118
IMAGE=uhparliament/e-petitions:archive-fix-20261118-candidate
ENV_FILE=/run/uh-parliament-petitions-release/current-web.env
ORIGINAL=sha256:8b46305f42e74bc01ce574e5db987a0609ec862e90d4a96a970670d1c25bdbd7
EXPECTED_HOTFIX=sha256:3b097b4778d880157184967e5d9f5774888500bad78f8f971ace47138688f0a6
test -s "$ENV_FILE"
test "$(stat -c '%a' "$ENV_FILE")" = 600
test "$(docker image inspect "$IMAGE" --format '{{.Id}}')" = "$EXPECTED_HOTFIX"
test "$(docker inspect "$OLD" --format '{{.Image}}')" = "$ORIGINAL"
test "$(docker inspect "$OLD" --format '{{(index .HostConfig.PortBindings "3000/tcp" 0).HostPort}}')" = 55410
test "$(docker inspect uh-petitions-worker --format '{{.State.Status}}')" = running
test "$(docker inspect uh-petitions-postgres --format '{{.State.Status}}')" = running
test "$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 12 https://petition.parliament.uhrblx.com/archived/petitions)" = 500
if docker inspect "$ROLLBACK" >/dev/null 2>&1; then echo 'Rollback container already exists; refusing collision' >&2; exit 2; fi
if docker inspect uh-petitions-web-new >/dev/null 2>&1; then echo 'Unexpected new container; refusing collision' >&2; exit 2; fi

rollback() {
  local code=$?
  echo "RELEASE_FAILED=$code; attempting original-container rollback" >&2
  if docker inspect "$OLD" >/dev/null 2>&1; then
    docker rm -f "$OLD" >/dev/null 2>&1 || true
  fi
  if docker inspect "$ROLLBACK" >/dev/null 2>&1; then
    docker rename "$ROLLBACK" "$OLD" || true
    docker start "$OLD" >/dev/null 2>&1 || true
    echo "ORIGINAL_CONTAINER_RESTORED" >&2
  fi
  exit "$code"
}
trap rollback ERR
docker stop --time 20 "$OLD" >/dev/null
docker rename "$OLD" "$ROLLBACK"
docker run -d \
  --name "$OLD" \
  --restart unless-stopped \
  --network uh-parliament-services \
  -p 127.0.0.1:55410:3000 \
  -v uh-petitions-storage:/app/storage:z \
  --env-file "$ENV_FILE" \
  "$IMAGE" \
  bundle exec puma --no-config -b tcp://0.0.0.0:3000 -w 2 -t 3:5 >/dev/null

ready=false
for n in $(seq 1 24); do
  direct=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 4 \
    -H 'Host: petition.parliament.uhrblx.com' \
    -H 'X-Forwarded-Proto: https' \
    http://127.0.0.1:55410/archived/petitions 2>/dev/null || true)
  staff=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 4 \
    -H 'Host: moderate.petition.parliament.uhrblx.com' \
    -H 'X-Forwarded-Proto: https' \
    http://127.0.0.1:55410/admin/login 2>/dev/null || true)
  if [[ "$direct" == 200 && "$staff" == 200 ]]; then ready=true; break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then echo "New web failed direct HTTP health" >&2; false; fi
public=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 https://petition.parliament.uhrblx.com/archived/petitions)
moderate=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 https://moderate.petition.parliament.uhrblx.com/admin/login)
if [[ "$public" != 200 || "$moderate" != 200 ]];then echo "Public/staff edge health failed" >&2; false; fi
test "$(docker inspect "$ROLLBACK" --format '{{.Image}}')" = "$ORIGINAL"
test "$(docker inspect "$OLD" --format '{{.Image}}')" = "$EXPECTED_HOTFIX"
test "$(docker inspect uh-petitions-worker --format '{{.State.Status}}')" = running
test "$(docker inspect uh-petitions-postgres --format '{{.State.Status}}')" = running
trap - ERR
echo "RELEASE_OK PUBLIC_ARCHIVE=$public STAFF_LOGIN=$moderate ORIGINAL_ROLLBACK=$ROLLBACK"
echo "RELEASE_SCOPE=web-container-only CONTINUITY=worker/database-unchanged"
