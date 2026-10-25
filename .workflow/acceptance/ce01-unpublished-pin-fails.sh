#!/usr/bin/env bash
# CE01 — a PR whose k8s/ pins a sha-<7> that GHCR doesn't have turns `cluster` red within its
# bounded wait, its output shows the pod dump with ErrImagePull / ImagePullBackOff, the smoke
# test never runs, and the PR is BLOCKED (cluster is required on dev).
# ACTS: pushes branch acceptance/unpublished-pin (all five pins → sha-0000000, never published),
# opens a draft PR into dev, waits for CI, then closes the PR and deletes the branch. Never merged.
# Observe only: RUN=<id of that PR's ci.yml run>.
. "$(dirname "$0")/lib.sh"

branch=acceptance/unpublished-pin
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  ls "$work"/k8s/*.y*ml >/dev/null 2>&1 || fail "setup: dev has no k8s/ yet"
  perl -pi -e 's/(knock-knock-[a-z]+):sha-[0-9a-f]{7}/$1:sha-0000000/g' "$work"/k8s/*.y*ml
  git -C "$work" commit -qam "test: pin an unpublished tag (acceptance CE01, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  PR=$(gh pr create -R "$REPO" --base dev --head "$branch" --draft --title "acceptance CE01: unpublished pin (do not merge)" --body "Throwaway PR for acceptance test CE01." | grep -Eo '[0-9]+$')
  RUN=$(wait_run "$sha" pull_request)
  gh pr ready -R "$REPO" "$PR" >/dev/null
  sleep 5
  STATE=$(gh pr view -R "$REPO" "$PR" --json mergeStateStatus -q .mergeStateStatus)
  gh pr close -R "$REPO" "$PR" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR into dev, ask first) or set RUN=<id>"
fresh "$RUN"

IFS=$'\t' read -r job conclusion <<<"$(job_named "$RUN" cluster)"
[ "${conclusion:-}" = failure ] || fail "cluster concluded ${conclusion:-missing} in run $RUN, expected failure"
out=$(job_output "$job")
[ -n "$out" ] || fail "can't read job cluster's output"
has "$out" 'sha-0000000' || fail "the failed run's output never mentions the unpublished pin"
has "$out" 'ErrImagePull|ImagePullBackOff' -E || fail "the failed run's output has no pod dump showing the pull failure"
if has "$out" 'knocks on |^FAIL: ' -E; then fail "the smoke test ran against a cluster that never came up"; fi
if acts; then [ "$STATE" = BLOCKED ] || fail "the PR's merge state was $STATE, expected BLOCKED"; fi

pass "an unpublished pin turned cluster red (run $RUN) with the pull failure in the log${STATE:+, and the PR was $STATE}"
