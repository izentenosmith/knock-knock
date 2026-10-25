#!/usr/bin/env bash
# E11 (F10) — a PR opened into dev and then switched to main gets only-dev-to-main re-run, failing,
# and can't be merged.
# ACTS: pushes branch acceptance/base-switch (an empty commit on dev), opens a PR into dev, waits
# for CI, switches its base to main, waits for only-dev-to-main, then closes it and deletes it.
# Observe only: RUN=<id of the only-dev-to-main.yml run after the switch>, PR=<its number>.
. "$(dirname "$0")/lib.sh"

branch=acceptance/base-switch
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  git -C "$work" commit -q --allow-empty -m "test: base switch (acceptance E11, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  PR=$(gh pr create -R "$REPO" --base dev --head "$branch" --title "acceptance E11: base switch (do not merge)" --body "Throwaway PR for acceptance test E11." | grep -Eo '[0-9]+$')
  wait_run "$sha" pull_request "$branch" >/dev/null
  gh pr edit -R "$REPO" "$PR" --base main >/dev/null
  RUN=$(WF=only-dev-to-main.yml wait_run "$sha" pull_request "$branch")
  sleep 5
  STATE=$(gh pr view -R "$REPO" "$PR" --json mergeStateStatus -q .mergeStateStatus)
  gh pr close -R "$REPO" "$PR" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] && [ -n "${PR:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR, ask first) or set RUN and PR"
fresh "$RUN"
[ "$(gh run view -R "$REPO" "$RUN" --json headBranch -q .headBranch)" = "$branch" ] || fail "run $RUN isn't $branch's run"
switched=$(gh api "repos/$REPO/issues/$PR/events" --jq '[.[] | select(.event == "base_ref_changed")] | length')
[ "$switched" -ge 1 ] || fail "PR #$PR never had its base changed"
[ "$(gh pr view -R "$REPO" "$PR" --json headRefName -q .headRefName)" = "$branch" ] || fail "PR #$PR isn't $branch's"

IFS=$'\t' read -r _ conclusion <<<"$(job_named "$RUN" only-dev-to-main)"
[ "${conclusion:-}" = failure ] || fail "only-dev-to-main concluded ${conclusion:-missing} after the base switch"
if acts; then [ "$STATE" = BLOCKED ] || fail "after the base switch the PR's merge state was $STATE, expected BLOCKED"; fi

pass "switching PR #$PR's base to main re-ran only-dev-to-main (run $RUN), which failed${STATE:+; the PR was $STATE}"
