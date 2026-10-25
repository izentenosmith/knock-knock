#!/usr/bin/env bash
# E01 (and F17) — on a PR into main, a failing smoke test publishes nothing, keeps the PR from
# being merged (smoke is required), and dumps `docker compose logs`. (The dry run is its own
# workflow and pushes nothing either way; F5's release-ready gate is e13's.)
# ACTS: pushes branch acceptance/broken-smoke (python backend broken on purpose), opens a draft
# PR into main, waits for CI, then closes the PR and deletes the branch. Never merged.
# Observe only: RUN=<id of that PR's ci.yml run> (and PR=<number> for the merge-state check).
. "$(dirname "$0")/lib.sh"

branch=acceptance/broken-smoke
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  printf 'raise RuntimeError("broken on purpose (acceptance E01)")\n' | cat - "$work/backends/python/main.py" >"$work/main.py.new"
  mv "$work/main.py.new" "$work/backends/python/main.py"
  git -C "$work" commit -qam "test: break the python backend on purpose (acceptance E01, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  PR=$(gh pr create -R "$REPO" --base main --head "$branch" --draft --title "acceptance E01: broken smoke (do not merge)" --body "Throwaway PR for acceptance test E01." | grep -Eo '[0-9]+$')
  RUN=$(wait_run "$sha" pull_request)
  gh pr ready -R "$REPO" "$PR" >/dev/null
  sleep 5
  STATE=$(gh pr view -R "$REPO" "$PR" --json mergeStateStatus -q .mergeStateStatus)
  gh pr close -R "$REPO" "$PR" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR into main, ask first) or set RUN=<id>"
fresh "$RUN"

IFS=$'\t' read -r job conclusion <<<"$(job_named "$RUN" smoke)"
[ "${conclusion:-}" = failure ] || fail "smoke concluded ${conclusion:-missing} in run $RUN, expected failure"
has "$(job_output "$job")" 'python-1 +\| .*RuntimeError: broken on purpose' -E || fail "the failed smoke's output has no docker compose logs from python"
ran=$(publish_jobs "$RUN" publish | awk -F'\t' '$2 != "skipped" && $2 != ""')
[ -z "$ran" ] || fail "publish ran after a failed smoke: $ran"
if acts; then [ "$STATE" = BLOCKED ] || fail "the PR's merge state was $STATE, expected BLOCKED"; fi

pass "a red smoke on a PR into main (run $RUN) published nothing${STATE:+, the PR was $STATE,} and dumped compose logs"
