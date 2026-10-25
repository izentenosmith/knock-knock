#!/usr/bin/env bash
# Give a published image its level tag, at exactly the same digest. Level tags are immutable:
# one that already points at that digest is a no-op, and one that points anywhere else fails.
# The source (<image>:<version>) may still be publishing, so it is waited for, up to
# PROMOTE_WAIT_SECONDS (default 1200), checking every PROMOTE_POLL_SECONDS (default 30);
# registry errors meanwhile are retried, a source built from another commit fails at once.
# Usage: scripts/promote.sh <image> <version> <level-tag> <revision>
set -euo pipefail

image=$1 version=$2 level=$3 revision=$4
wait_for=${PROMOTE_WAIT_SECONDS:-1200}
poll=${PROMOTE_POLL_SECONDS:-30}
digest() { "$(dirname "$0")/image-digest.sh" "$@"; }

if ! [[ $level =~ ^level-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ ${#level} -gt 128 ]; then
  echo "::error::$level isn't a level tag: expected level-NN-<slug> (at most 128 characters), e.g. level-02-cluster" >&2
  exit 1
fi

deadline=$((SECONDS + wait_for))
while :; do
  if src=$(digest --revision "$revision" "$image:$version"); then
    [ -n "$src" ] && break
    waiting="waiting for $image:$version to be published"
    gave_up="$image:$version doesn't exist: this commit was never published from main"
  else
    [ $? = 2 ] && exit 1 # built from another commit: waiting won't help
    waiting="registry error looking up $image:$version, retrying"
    gave_up="couldn't look up $image:$version before the deadline (registry errors)"
  fi
  if [ $SECONDS -ge $deadline ]; then
    echo "::error::$gave_up" >&2
    exit 1
  fi
  echo "$waiting"
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
