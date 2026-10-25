#!/usr/bin/env bash
# E07 — an active ruleset on refs/tags/level-* blocks updating and deleting those tags, still
# allows creating them, and has no bypass actors. Observed through the API: actually deleting
# or moving a real level tag to test it would be the very thing the ruleset exists to prevent.
. "$(dirname "$0")/lib.sh"

ids=$(gh api "repos/$REPO/rulesets" -q '.[] | select(.target == "tag") | .id' 2>/dev/null || true)
[ -n "$ids" ] || fail "no tag ruleset in $REPO"
for id in $ids; do
  r=$(gh api "repos/$REPO/rulesets/$id")
  jq -e '.conditions.ref_name.include | index("refs/tags/level-*")' <<<"$r" >/dev/null || continue
  [ "$(jq -r .enforcement <<<"$r")" = active ] || fail "ruleset $id isn't active"
  types=$(jq -r '[.rules[].type] | sort | join(" ")' <<<"$r")
  grep -qw deletion <<<"$types" || fail "ruleset $id doesn't block deletion (rules: $types)"
  grep -qw update <<<"$types" || fail "ruleset $id doesn't block updates (rules: $types)"
  if grep -qw creation <<<"$types"; then fail "ruleset $id blocks creating level tags"; fi
  [ "$(jq '.bypass_actors | length' <<<"$r")" = 0 ] || fail "ruleset $id has bypass actors"
  pass "level-* tags can be created but never moved or deleted (ruleset $id)"
  exit 0
done
fail "no tag ruleset covers refs/tags/level-*"
