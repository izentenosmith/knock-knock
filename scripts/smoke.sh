#!/usr/bin/env bash
# Fire N knocks at the API, check the contract, print the tally.
# Usage: scripts/smoke.sh [N]   (URL=... to knock somewhere else,
#                               EXPECT_VERSION=... to require that version in every answer)
set -euo pipefail

N=${1:-40}
URL=${URL:-http://localhost:8080/api/knock}
FIELDS='["lang","version","pod","node","pod_started","served","received_at","responded_at","took_us"]'
LANGS='go python rust ts'

answers=$(mktemp)
trap 'rm -f "$answers"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

for i in $(seq "$N"); do
  curl -fsS --max-time 5 "$URL" >>"$answers" || fail "knock $i of $N got no answer"
  echo >>"$answers"
done

bad=$(jq -s --argjson f "$FIELDS" '
  map(select(
    ($f - keys) != []
    or (.took_us | type != "number" or . < 0 or . != floor)
  )) | length' "$answers")
[ "$bad" -eq 0 ] || fail "$bad of $N answers break the contract (missing fields or bad took_us)"

seen=$(jq -rs 'map(.lang) | unique | join(" ")' "$answers")
[ "$seen" = "$LANGS" ] || fail "expected answers from '$LANGS', got '$seen'"

if [ -n "${EXPECT_VERSION:-}" ]; then
  versions=$(jq -rs 'map(.version) | unique | join(", ")' "$answers")
  [ "$versions" = "$EXPECT_VERSION" ] || fail "expected version $EXPECT_VERSION, got $versions"
fi

echo "$N knocks on $URL"
jq -rs 'group_by(.lang)[] | "  \(.[0].lang)\t\(length)"' "$answers"
echo "by pod"
jq -rs 'group_by(.pod)[] | "  \(.[0].lang)\t\(.[0].pod)\t\(length)"' "$answers"
echo "PASS"
