#!/usr/bin/env bash
# Print the digest of an image reference, or nothing if it doesn't exist.
# A missing tag says "not found"; a package that doesn't exist yet answers 403.
# Any other registry error exits 1, so a flaky registry never reads as "absent".
# Usage: scripts/image-digest.sh <image:tag>
set -euo pipefail

if out=$(docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>&1); then
  jq -r .digest <<<"$out"
elif ! grep -Eqi 'not found|403 Forbidden|denied' <<<"$out"; then
  echo "::error::can't tell whether $1 exists: $out" >&2
  exit 1
fi
