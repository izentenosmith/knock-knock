#!/usr/bin/env bash
# CE06 — a red smoke test through the ingress turns `cluster` red: a PR whose k8s/ breaks the
# Downward API for one backend (knock-go's NODE_NAME becomes the literal `local`) passes `smoke`
# (compose doesn't use k8s/), but `cluster`'s smoke step fails naming node and `local`, the job is
# red, and the PR is BLOCKED. (Static half: CE05, nothing in `cluster` tolerates a failure.)
# ACTS: pushes branch acceptance/broken-node-name, opens a draft PR into dev, waits for CI, then
# closes the PR and deletes the branch. Never merged.
# Observe only: RUN=<id of that PR's ci.yml run>.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh" # for step, bind_run, merge_state

branch=acceptance/broken-node-name
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  [ -f "$work/k8s/go.yaml" ] || fail "setup: dev has no k8s/go.yaml yet"
  perl -0pi -e 's/(- name: NODE_NAME\n\s+)valueFrom: \{ fieldRef: \{ fieldPath: spec\.nodeName \} \}/${1}value: local/' "$work/k8s/go.yaml"
  git -C "$work" diff --quiet && fail "setup: knock-go's NODE_NAME isn't wired the way this test expects"
  git -C "$work" commit -qam "test: NODE_NAME not wired for go (acceptance CE06, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  PR=$(gh pr create -R "$REPO" --base dev --head "$branch" --draft --title "acceptance CE06: red smoke in cluster (do not merge)" --body "Throwaway PR for acceptance test CE06." | grep -Eo '[0-9]+$')
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
IFS=$'\t' read -r _ smoke_conclusion <<<"$(job_named "$RUN" smoke)"
[ "${smoke_conclusion:-}" = success ] || fail "smoke concluded ${smoke_conclusion:-missing}; the break should only show in the cluster"
for s in "Wait for the ingress:success" "Smoke test through the ingress:failure"; do
  got=$(step "$job" "${s%:*}")
  [ "$got" = "${s##*:}" ] || fail "step '${s%:*}' concluded '${got:-missing}', expected ${s##*:}"
done
out=$(job_output "$job")
[ -n "$out" ] || fail "can't read job cluster's output"
has "$out" '^FAIL: .*node.*local' -E || fail "the cluster's smoke didn't fail on node local"
if acts; then [ "$STATE" = BLOCKED ] || fail "the PR's merge state was $STATE, expected BLOCKED"; fi

pass "a red smoke through the ingress turned cluster red (run $RUN) while smoke stayed green${STATE:+; the PR was $STATE}"
