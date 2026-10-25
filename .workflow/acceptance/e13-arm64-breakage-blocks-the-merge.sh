#!/usr/bin/env bash
# E13 (F5) — a change that only breaks the arm64 build (smoke, on amd64, stays green) fails that
# service's dry-run build, turns the required release-ready red, and blocks the PR into main.
# ACTS: pushes branch acceptance/arm64-only (python's Dockerfile fails on aarch64), opens a draft
# PR into main, waits for the dry run, then closes it and deletes the branch. Observe only: RUN=<dry-run.yml run>.
. "$(dirname "$0")/lib.sh"

branch=acceptance/arm64-only
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  sed -i.bak 's|^FROM python:3.13-slim$|&\nRUN [ "$(uname -m)" != aarch64 ] # broken on purpose (acceptance E13)|' "$work/backends/python/Dockerfile" && rm "$work/backends/python/Dockerfile.bak"
  grep -q 'aarch64' "$work/backends/python/Dockerfile" || fail "setup: couldn't break the arm64 build"
  git -C "$work" commit -qam "test: python fails to build on arm64 (acceptance E13, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  PR=$(gh pr create -R "$REPO" --base main --head "$branch" --draft --title "acceptance E13: arm64 only (do not merge)" --body "Throwaway PR for acceptance test E13." | grep -Eo '[0-9]+$')
  RUN=$(WF=dry-run.yml wait_run "$sha" pull_request "$branch")
  WF=ci.yml wait_run "$sha" pull_request "$branch" >/dev/null
  gh pr ready -R "$REPO" "$PR" >/dev/null; sleep 5
  STATE=$(gh pr view -R "$REPO" "$PR" --json mergeStateStatus -q .mergeStateStatus)
  gh pr close -R "$REPO" "$PR" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR into main, ask first) or set RUN=<id>"
# The run is of the broken branch, whose only difference is python's Dockerfile; freshness
# compares workflows and scripts, which it shares with the tree.
fresh "$RUN"
[ "$(gh run view -R "$REPO" "$RUN" --json headBranch -q .headBranch)" = "$branch" ] || fail "run $RUN isn't $branch's dry run"
sha=$(gh run view -R "$REPO" "$RUN" --json headSha -q .headSha)
ci=$(ci_run "$sha" pull_request "$branch")
IFS=$'\t' read -r _ smoke <<<"$(job_named "$ci" smoke)"
[ "${smoke:-}" = success ] || fail "smoke concluded ${smoke:-missing}: this should break only arm64"
dry=$(publish_jobs "$RUN" dry-run)
IFS=$'\t' read -r _ py id <<<"$(awk -F'\t' 'index($1, "dry-run / build (python,") == 1' <<<"$dry")"
[ "${py:-}" = failure ] || fail "python's dry-run build concluded ${py:-missing}, expected failure"
has "$(job_output "$id")" 'linux/arm64' || fail "python's dry-run failure doesn't mention linux/arm64"
IFS=$'\t' read -r _ gate <<<"$(job_named "$RUN" release-ready)"
[ "${gate:-}" = failure ] || fail "release-ready concluded ${gate:-missing}, expected failure"
if acts; then [ "$STATE" = BLOCKED ] || fail "the PR's merge state was $STATE, expected BLOCKED"; fi

pass "an arm64-only breakage failed python's dry run and release-ready (run $RUN)${STATE:+; the PR was $STATE}"
