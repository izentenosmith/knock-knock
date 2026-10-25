#!/usr/bin/env bash
# Build one image for linux/amd64 and linux/arm64, once, into a staging registry; start the
# amd64 image from there and check it (backends); then, with --push, copy that exact index to
# <image>:<version>. What ships is byte-for-byte what was checked: the pushed digest is the
# staged one.
# Env: STAGING (registry host:port, default localhost:5000), BUILDER (buildx builder, optional).
# Usage: scripts/build-image.sh <service> <context> <image> <version> <revision> [--push]
set -euo pipefail

service=$1 context=$2 image=$3 version=$4 revision=$5 push=${6:-}
here=$(dirname "$0")
staged="${STAGING:-localhost:5000}/$service:$version"
source_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-izentenosmith/knock-knock}"

docker buildx build ${BUILDER:+--builder "$BUILDER"} "$context" \
  --platform linux/amd64,linux/arm64 \
  --build-arg VERSION="$version" \
  --label org.opencontainers.image.source="$source_url" \
  --label org.opencontainers.image.revision="$revision" \
  --label org.opencontainers.image.version="$version" \
  --provenance=false --sbom=false \
  --tag "$staged" --push
digest=$("$here/image-digest.sh" "$staged")
[ -n "$digest" ] || { echo "::error::built $staged but can't read it back" >&2; exit 1; }

if [ "$service" != frontend ]; then
  "$here/check-image.sh" "$staged@$digest" "$service" "$version"
fi

if [ "$push" != --push ]; then
  echo "dry run: built $image:$version for linux/amd64 and linux/arm64 and checked it, pushed nothing"
  exit 0
fi
docker buildx imagetools create --tag "$image:$version" "$staged@$digest"
pushed=$("$here/image-digest.sh" "$image:$version")
if [ "$pushed" != "$digest" ]; then
  echo "::error::pushed $image:$version came out as '$pushed', not the checked $digest" >&2
  exit 1
fi
echo "pushed $image:$version @ $digest (the image that was checked)"
