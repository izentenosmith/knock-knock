#!/usr/bin/env bash
# Print the digest of an image reference, or nothing if it doesn't exist.
# "Doesn't exist" is only ever the registry's own answer: a missing tag ("<ref>: not found")
# or a package GHCR hasn't created yet (403 on the token request). Anything else exits 1,
# so a flaky registry never reads as "absent".
# With --revision <sha>, an image that exists but wasn't built from that commit (on every
# platform) exits 2, so callers can tell it apart from a registry error.
# Usage: scripts/image-digest.sh [--revision <sha>] <image:tag>
set -euo pipefail

revision=
if [ "${1:-}" = --revision ]; then
  revision=$2
  shift 2
fi
ref=$1

if ! out=$(docker buildx imagetools inspect "$ref" --format '{{json .}}' 2>&1); then
  answer=$(tail -n1 <<<"$out")
  [ "$answer" = "ERROR: $ref: not found" ] && exit 0
  grep -Eq '^ERROR: failed to authorize: failed to fetch (anonymous|oauth) token: unexpected status from (GET|POST) request to https://ghcr\.io/token\?[^ ]*: 403 Forbidden$' <<<"$answer" && exit 0
  echo "::error::can't tell whether $ref exists: $out" >&2
  exit 1
fi

if [ -n "$revision" ]; then
  # .image is one config for a single-platform image, or a map of platform -> config.
  if ! built_from=$(jq -r '.image | (if has("config") then [.] else [.[]] end)
      | map(.config.Labels["org.opencontainers.image.revision"] // "") | unique | join(",")' <<<"$out" 2>&1); then
    echo "::error::can't read the revision labels of $ref: $built_from" >&2
    exit 1
  fi
  if [ "$built_from" != "$revision" ]; then
    echo "::error::$ref exists but was built from revision '$built_from', not $revision" >&2
    exit 2
  fi
fi
jq -r .manifest.digest <<<"$out"
