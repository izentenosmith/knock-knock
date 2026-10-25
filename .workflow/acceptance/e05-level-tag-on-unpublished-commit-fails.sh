#!/usr/bin/env bash
# E05 — a level-* tag on a commit whose sha-<7> isn't in GHCR fails publish with a message that
# the commit was never published from main, and creates that level tag for no service.
# ACTS: pushes branch acceptance/unpublished (an empty commit on dev; branch pushes don't
# trigger CI) and tag level-99-acceptance-unpublished on it, waits for CI, then deletes both.
# Must run BEFORE the level-* tag ruleset exists, or the tag can never be deleted again.
# Observe only: RUN=<id of the tag's ci.yml run>.
. "$(dirname "$0")/lib.sh"
# Release history: this observes the level-01-pipeline release as it ran (workflows at 52dd932).
# The current promotion code is covered by l2 until the next level's tag runs it on GitHub.
HISTORY=1

level=level-99-acceptance-unpublished
if acts; then
  [ "$(gh api "repos/$REPO/rulesets" -q 'length')" = 0 ] || fail "a ruleset exists; $level could never be deleted, refusing to act"
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  git -C "$work" commit -q --allow-empty -m "test: a commit main never published (acceptance E05)"
  sha=$(git -C "$work" rev-parse HEAD)
  git -C "$work" push -q -f origin "HEAD:refs/heads/acceptance/unpublished"
  git -C "$work" tag -a "$level" -m "acceptance E05: never published" && git -C "$work" push -q origin "refs/tags/$level"
  RUN=$(wait_run "$sha" push)
  git -C "$work" push -q origin --delete "refs/tags/$level" "refs/heads/acceptance/unpublished"
  git -C "$ROOT" tag -d "$level" >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway tag, ask first) or set RUN=<id>"

pub=$(publish_jobs "$RUN" publish | awk -F'\t' 'index($1, "publish / promote") == 1')
[ -n "$pub" ] || fail "run $RUN has no promote jobs"
while IFS=$'\t' read -r name conclusion id; do
  [ "$conclusion" = failure ] || fail "$name concluded $conclusion, expected failure"
  has "$(job_output "$id")" '(never published from main|isn.t on main)' -E || fail "$name failed without saying the commit was never published from main"
done <<<"$pub"
for svc in $SERVICES; do
  if exists_in_ghcr "$IMAGE-$svc:$level"; then fail "$svc got the tag $level anyway"; fi
done

pass "(history, level-01 release) a level tag on an unpublished commit failed (run $RUN) and tagged nothing"
