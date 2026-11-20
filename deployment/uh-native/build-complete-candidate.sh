#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
test -z "$(git status --porcelain)" || { echo 'Dirty source checkout; commit and review first.' >&2; exit 2; }
SOURCE_SHA="$(git rev-parse HEAD)"
test "$(git rev-parse --show-toplevel)" = "$ROOT"
BASE='uhparliament/e-petitions:uh-arms-github-91fb990-20261026'
EXPECTED='sha256:8b46305f42e74bc01ce574e5db987a0609ec862e90d4a96a970670d1c25bdbd7'
LOCAL='uh-local/petitions-upstream:sha-8b46305f42e74bc01ce574e5db987a0609ec862e90d4a96a970670d1c25bdbd7'
ACTUAL="$(docker image inspect --format '{{.Id}}' "$BASE")"
test "$ACTUAL" = "$EXPECTED" || { echo 'Original Rails runtime image digest mismatch.' >&2; exit 2; }
AVAIL="$(df -Pk / | awk 'NR==2 {print $4}')"
test "$AVAIL" -gt 15728640 || { echo 'Less than 15 GiB available; no build attempted.' >&2; exit 2; }
sha256sum public/uh-parliament-brand/uh-parliament-logo.png
docker tag "$BASE" "$LOCAL"
TAG="uhparliament/e-petitions:uh-owner-${SOURCE_SHA:0:12}-full-candidate"
docker build --pull=false --build-arg SOURCE_REVISION="$SOURCE_SHA" -f deployment/uh-native/Dockerfile.full -t "$TAG" .
docker image inspect "$TAG" --format 'SOURCE={{index .Config.Labels "org.opencontainers.image.source"}} REVISION={{index .Config.Labels "org.opencontainers.image.revision"}} IMAGE={{.Id}}'
echo "Built complete-source isolated candidate: $TAG"
echo 'No production containers, databases or routing changed.'
