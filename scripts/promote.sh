#!/usr/bin/env bash
# Give a published image its level tag, at exactly the same digest. Level tags are immutable:
# one that already points at that digest is a no-op, and one that points anywhere else fails.
# The source (<image>:<version>) may still be publishing, so it is waited for, up to
# PROMOTE_WAIT_SECONDS (default 1200), checking every PROMOTE_POLL_SECONDS (default 30).
# Usage: scripts/promote.sh <image> <version> <level-tag> <revision>
set -euo pipefail

image=$1 version=$2 level=$3 revision=$4
wait_for=${PROMOTE_WAIT_SECONDS:-1200}
poll=${PROMOTE_POLL_SECONDS:-30}
digest() { "$(dirname "$0")/image-digest.sh" "$@"; }

if ! [[ $level =~ ^level-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "::error::$level isn't a level tag: expected level-NN-<slug>, e.g. level-02-cluster" >&2
  exit 1
fi

deadline=$((SECONDS + wait_for))
while :; do
  src=$(digest --revision "$revision" "$image:$version") # a registry error or another revision fails here
  [ -n "$src" ] && break
  if [ $SECONDS -ge $deadline ]; then
    echo "::error::$image:$version doesn't exist: this commit was never published from main" >&2
    exit 1
  fi
  echo "waiting for $image:$version to be published"
  sleep "$poll"
done

dst=$(digest "$image:$level")
if [ "$dst" = "$src" ]; then
  echo "$image:$level is already $src: no-op"
  exit 0
elif [ -n "$dst" ]; then
  echo "::error::$image:$level is $dst, not $version ($src): level tags are immutable" >&2
  exit 1
fi

docker buildx imagetools create --tag "$image:$level" "$image:$version@$src"
dst=$(digest "$image:$level")
if [ "$dst" != "$src" ]; then
  echo "::error::$image:$level came out as '$dst', not $src" >&2
  exit 1
fi
echo "promoted $image:$version to $level @ $src"
