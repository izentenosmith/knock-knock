#!/usr/bin/env bash
# E08 — a PR into main from any branch but dev fails only-dev-to-main with the rule in its output,
# and a branch name carrying shell syntax isn't executed anywhere: the name below would print
# "beef" if it were, and no job of any workflow run for that branch printed it.
# ACTS: pushes branch 'acceptance/x-$(printf${IFS}%x${IFS}48879>&2)', opens a draft PR into main,
# waits for its runs, then closes it and deletes the branch.
# Observe only: RUN=<id of that PR's only-dev-to-main.yml run> (it must be that branch's run).
. "$(dirname "$0")/lib.sh"

branch='acceptance/x-$(printf${IFS}%x${IFS}48879>&2)'
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  git -C "$work" commit -q --allow-empty -m "test: not from dev (acceptance E08, never merge)"
  sha=$(git -C "$work" rev-parse HEAD)
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  gh pr create -R "$REPO" --base main --head "$branch" --draft --title "acceptance E08: not from dev (do not merge)" --body "Throwaway PR for acceptance test E08." >/dev/null
  RUN=$(WF=only-dev-to-main.yml wait_run "$sha" pull_request "$branch")
  WF=ci.yml wait_run "$sha" pull_request "$branch" >/dev/null
  WF=dry-run.yml wait_run "$sha" pull_request "$branch" >/dev/null
  gh pr close -R "$REPO" "$branch" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR into main, ask first) or set RUN=<id>"
fresh "$RUN"
[ "$(gh run view -R "$REPO" "$RUN" --json headBranch -q .headBranch)" = "$branch" ] || fail "run $RUN isn't the payload branch's run"

IFS=$'\t' read -r job conclusion <<<"$(job_named "$RUN" only-dev-to-main)"
[ "${conclusion:-}" = failure ] || fail "only-dev-to-main concluded ${conclusion:-missing}, expected failure"
has "$(job_output "$job")" '^main only accepts PRs from dev' || fail "the failure doesn't state the rule"

sha=$(gh run view -R "$REPO" "$RUN" --json headSha -q .headSha)
runs=$(gh run list -R "$REPO" --commit "$sha" --branch "$branch" --limit 20 --json databaseId -q '.[].databaseId')
[ "$(wc -w <<<"$runs" | tr -d ' ')" -ge 3 ] || fail "expected the ci, dry-run and only-dev-to-main runs for $branch, got: $runs"
for r in $runs; do
  while IFS=$'\t' read -r name concl id; do
    [ -n "$id" ] && [ "$id" != null ] && [ "$concl" != skipped ] || continue
    if has "$(job_output "$id")" beef; then fail "the branch name was executed in '$name' (run $r)"; fi
  done < <(jobs_of "$r")
done

pass "a PR into main from '$branch' failed only-dev-to-main, and no job of its $(wc -w <<<"$runs" | tr -d ' ') runs executed the name"
