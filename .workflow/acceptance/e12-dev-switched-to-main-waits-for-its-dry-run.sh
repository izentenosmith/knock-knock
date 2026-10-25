#!/usr/bin/env bash
# E12 (F42) — release-ready only ever comes from a PR's own dry run: on dev's tip no run other than
# a dry-run.yml run produced a release-ready check, and a PR from dev that is switched to main is
# BLOCKED until its dry run (started by the switch) passes.
# ACTS: pushes branch acceptance/target (main's tip), opens a PR dev → acceptance/target, switches
# its base to main, reads the merge state while the dry run runs and after it passes, then
# closes the PR (never merged) and deletes acceptance/target. Run it on a dev tip that has no PR
# into main yet. Observe only: RUN=<the dry-run.yml run> PR=<its number>.
. "$(dirname "$0")/lib.sh"

if acts; then
  git -C "$ROOT" fetch -q origin dev main
  sha=$(git -C "$ROOT" rev-parse origin/dev)
  git -C "$ROOT" push -q -f origin "origin/main:refs/heads/acceptance/target"
  PR=$(gh pr create -R "$REPO" --base acceptance/target --head dev --title "acceptance E12: dev switched to main (do not merge)" --body "Throwaway PR for acceptance test E12." | grep -Eo '[0-9]+$')
  sleep 10
  gh pr edit -R "$REPO" "$PR" --base main >/dev/null
  sleep 20
  BEFORE_STATE=$(gh pr view -R "$REPO" "$PR" --json mergeStateStatus -q .mergeStateStatus)
  RUN=$(WF=dry-run.yml wait_run "$sha" pull_request dev)
  sleep 10
  AFTER_STATE=$(gh pr view -R "$REPO" "$PR" --json mergeStateStatus -q .mergeStateStatus)
  gh pr close -R "$REPO" "$PR" >/dev/null
  git -C "$ROOT" push -q origin --delete acceptance/target
fi
[ -n "${RUN:-}" ] && [ -n "${PR:-}" ] || fail "not observed yet: run with ACT=1 (opens a PR from dev, never merged; ask first) or set RUN and PR"
fresh "$RUN"
sha=$(gh run view -R "$REPO" "$RUN" --json headSha -q .headSha)
[ "$(gh run view -R "$REPO" "$RUN" --json event,headBranch -q '"\(.event) \(.headBranch)"')" = "pull_request dev" ] || fail "run $RUN isn't a dev PR's dry run"
[ "$(gh api "repos/$REPO/issues/$PR/events" --jq '[.[] | select(.event == "base_ref_changed")] | length')" -ge 1 ] || fail "PR #$PR's base was never changed"

# Every release-ready check on that commit belongs to a dry-run.yml run.
suites=$(gh api "repos/$REPO/actions/runs?head_sha=$sha&per_page=100" --jq '.workflow_runs[] | select(.path | endswith("/dry-run.yml")) | .check_suite_id')
strays=$(gh api "repos/$REPO/commits/$sha/check-runs?check_name=release-ready&per_page=100" --jq '.check_runs[] | "\(.check_suite.id) \(.conclusion)"' \
  | while read -r suite concl; do grep -qx "$suite" <<<"$suites" || echo "$suite:$concl"; done)
[ -z "$strays" ] || fail "release-ready checks on ${sha:0:7} came from runs other than a dry run: $strays"
IFS=$'\t' read -r _ gate <<<"$(job_named "$RUN" release-ready)"
[ "${gate:-}" = success ] || fail "release-ready concluded ${gate:-missing} in run $RUN"
if acts; then
  [ "$BEFORE_STATE" = BLOCKED ] || fail "while the dry run ran, the PR was $BEFORE_STATE, expected BLOCKED"
  [ "$AFTER_STATE" != BLOCKED ] || fail "after the dry run passed, the PR was still BLOCKED"
fi

pass "dev's tip carries release-ready only from its dry run (run $RUN)${BEFORE_STATE:+; switched PR #$PR was $BEFORE_STATE until it passed, then $AFTER_STATE}"
