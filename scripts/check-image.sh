#!/usr/bin/env bash
# Start a backend image on its own and check that it answers the knock as <lang>, <version>.
# CI runs it on the image it is about to push, so what ships is what was checked.
# Usage: scripts/check-image.sh <image> <lang> <version>
set -euo pipefail

image=$1 lang=$2 version=$3
fail() { echo "::error::$image: $*" >&2; exit 1; }

id=$(docker run -d --rm --label knock-check -p 127.0.0.1::8080 "$image")
trap 'docker rm -f "$id" >/dev/null 2>&1 || true' EXIT
url="http://$(docker port "$id" 8080/tcp | head -1)/api/knock"

answer=""
for _ in $(seq 50); do
  answer=$(curl -fs --max-time 2 "$url" 2>/dev/null) && break
  sleep 0.2
done
[ -n "$answer" ] || fail "no answer on /api/knock"
[ "$(jq -r .lang <<<"$answer")" = "$lang" ] || fail "answered lang '$(jq -r .lang <<<"$answer")', not $lang"
[ "$(jq -r .version <<<"$answer")" = "$version" ] || fail "answered version '$(jq -r .version <<<"$answer")', not $version"
echo "$image answers as $lang, $version"
