#!/usr/bin/env bash
# CE02 — if the five images in k8s/ don't share exactly one tag, `cluster` fails before
# `kubectl apply`, saying the pins disagree, and the PR is BLOCKED.
# ACTS: pushes branch acceptance/disagreeing-pins (only the go image moves to another published
# tag, level-01-pipeline, so nothing fails to pull), opens a draft PR into dev, waits for CI,
# then closes the PR and deletes the branch. Never merged.
# Observe only: RUN=<id of that PR's ci.yml run>.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh" # for step, bind_run, merge_state

branch=acceptance/disagreeing-pins
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  ls "$work"/k8s/*.y*ml >/dev/null 2>&1 || fail "setup: dev has no k8s/ yet"
  perl -pi -e 's/(knock-knock-go):sha-[0-9a-f]{7}/$1:level-01-pipeline/g' "$work"/k8s/*.y*ml
  git -C "$work" diff --quiet && fail "setup: no go image pin to change in dev's k8s/"
  git -C "$work" commit -qam "test: pins that disagree (acceptance CE02, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  PR=$(gh pr create -R "$REPO" --base dev --head "$branch" --draft --title "acceptance CE02: disagreeing pins (do not merge)" --body "Throwaway PR for acceptance test CE02." | grep -Eo '[0-9]+$')
  RUN=$(wait_run "$sha" pull_request)
  gh pr ready -R "$REPO" "$PR" >/dev/null
  STATE=$(merge_state "$PR")
  gh pr close -R "$REPO" "$PR" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR into dev, ask first) or set RUN=<id>"
fresh "$RUN"
bind_run "$RUN" "$branch"

IFS=$'\t' read -r job conclusion <<<"$(job_named "$RUN" cluster)"
[ "${conclusion:-}" = failure ] || fail "cluster concluded ${conclusion:-missing} in run $RUN, expected failure"
out=$(job_output "$job")
[ -n "$out" ] || fail "can't read job cluster's output"
has "$out" 'pins disagree' -i || fail "the failure doesn't say the pins disagree"
for s in "Read the one tag k8s/ pins:failure" "Apply k8s/:skipped" "Wait for the ingress:skipped" "Smoke test through the ingress:skipped"; do
  got=$(step "$job" "${s%:*}")
  [ "$got" = "${s##*:}" ] || fail "step '${s%:*}' concluded '${got:-missing}', expected ${s##*:}"
done
if acts; then [ "$STATE" = BLOCKED ] || fail "the PR's merge state was $STATE, expected BLOCKED"; fi

pass "disagreeing pins failed cluster before applying (run $RUN)${STATE:+, and the PR was $STATE}"
