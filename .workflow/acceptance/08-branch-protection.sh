#!/usr/bin/env bash
# AT-08 — dev and main are protected in the nights-watch shape: a PR is required (0 approvals),
# admins included, no force pushes or deletions, not strict; required checks are `smoke` and
# `cluster` on dev, and `smoke` + `cluster` + `only-dev-to-main` + `release-ready` on main (`cluster`
# joined at level 2). Observed through the API only: attempting a real direct push would put a
# commit on dev if protection were missing.
. "$(dirname "$0")/lib.sh"

expect() { # branch, required checks (sorted, space-separated)
  local p
  p=$(gh api "repos/$REPO/branches/$1/protection" 2>/dev/null) || fail "$1 isn't protected"
  jq -e '.required_pull_request_reviews.required_approving_review_count == 0' <<<"$p" >/dev/null || fail "$1: a PR with 0 approvals isn't required"
  jq -e '.enforce_admins.enabled' <<<"$p" >/dev/null || fail "$1: admins aren't included"
  jq -e '.allow_force_pushes.enabled | not' <<<"$p" >/dev/null || fail "$1 allows force pushes"
  jq -e '.allow_deletions.enabled | not' <<<"$p" >/dev/null || fail "$1 allows deletion"
  jq -e '.required_status_checks.strict | not' <<<"$p" >/dev/null || fail "$1 requires up-to-date branches"
  got=$(jq -r '[.required_status_checks.contexts[]] | sort | join(" ")' <<<"$p")
  [ "$got" = "$2" ] || fail "$1 requires checks '$got', expected '$2'"
}
expect dev "cluster smoke"
expect main "cluster only-dev-to-main release-ready smoke"

pass "dev and main are protected like nights-watch"
