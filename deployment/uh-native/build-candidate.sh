#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
test -z "$(git status --porcelain)" || { echo 'Commit source changes before building.' >&2; exit 2; }
SOURCE_SHA="$(git rev-parse HEAD)"
BASE='uhparliament/e-petitions:uh-arms-github-91fb990-20261026'
EXPECTED='sha256:8b46305f42e74bc01ce574e5db987a0609ec862e90d4a96a970670d1c25bdbd7'
LOCAL='uh-local/petitions-upstream:sha-8b46305f42e74bc01ce574e5db987a0609ec862e90d4a96a970670d1c25bdbd7'
ACTUAL="$(docker image inspect --format '{{.Id}}' "$BASE")"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Pinned installed Rails base digest does not match. Aborting.' >&2; exit 2; }
echo "Verified original e-petitions base image ID $ACTUAL"
printf '%s  %s\n' 'ab4fc9c480ce922746db6fe5f5a0d5792d5fdd3228e548ab0ea80c43b7df237b' 'public/uh-parliament-brand/uh-parliament-logo.png' | sha256sum -c -
docker tag "$BASE" "$LOCAL"
TAG="uhparliament/e-petitions:uh-native-${SOURCE_SHA:0:12}-candidate"
docker build --pull=false --network=none --build-arg SOURCE_REVISION="$SOURCE_SHA" -f deployment/uh-native/Dockerfile -t "$TAG" .
docker image inspect "$TAG" --format 'Built source={{index .Config.Labels "org.opencontainers.image.revision"}} image={{.Id}}'
echo "Candidate image: $TAG. This command does not deploy it."
