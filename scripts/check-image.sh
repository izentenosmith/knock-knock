#!/usr/bin/env bash
# Start a backend image on its own and check that it answers the knock as <lang>, <version>.
# CI runs it on the image it is about to push, so what ships is what was checked. On failure
# it prints the container's logs.
# Usage: scripts/check-image.sh <image> <lang> <version>
set -euo pipefail

image=$1 lang=$2 version=$3
id=$(docker run -d --label knock-check -p 127.0.0.1::8080 "$image")
trap 'docker rm -f "$id" >/dev/null 2>&1 || true' EXIT
fail() {
  echo "::error::$image: $*" >&2
  echo "--- container logs ---" >&2
  docker logs "$id" >&2 2>&1 || true
  exit 1
}

answer=""
for _ in $(seq 50); do
  if port=$(docker port "$id" 8080/tcp 2>/dev/null | head -1) && [ -n "$port" ]; then
    answer=$(curl -fs --max-time 2 "http://$port/api/knock" 2>/dev/null) && break
  elif [ "$(docker inspect -f '{{.State.Running}}' "$id")" != true ]; then
    fail "exited before answering"
  fi
  sleep 0.2
done
[ -n "$answer" ] || fail "no answer on /api/knock"
[ "$(jq -r .lang <<<"$answer")" = "$lang" ] || fail "answered lang '$(jq -r .lang <<<"$answer")', not $lang"
[ "$(jq -r .version <<<"$answer")" = "$version" ] || fail "answered version '$(jq -r .version <<<"$answer")', not $version"
echo "$image answers as $lang, $version"
