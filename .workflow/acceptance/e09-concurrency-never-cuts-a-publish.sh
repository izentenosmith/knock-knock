#!/usr/bin/env bash
# E09 (and F6, F21) — on a feature PR, a second quick push cancels the older run; on main, two runs
# of different commits that overlap in time both finish green, and no main or tag run is ever cancelled.
# ACTS (feature half): pushes two empty commits in quick succession to branch
# acceptance/concurrency with a draft PR into dev, then closes it and deletes the branch.
# Observe only: OLD=<run id> NEW=<run id> for the feature half; the main/tag half always observes.
. "$(dirname "$0")/lib.sh"

# Half 1 — main and tags: never cancelled, across all history.
runs=$(gh run list -R "$REPO" --workflow ci.yml --limit 1000 --json databaseId,headBranch,event,conclusion 2>/dev/null) \
  || fail "no ci.yml workflow in $REPO"
cancelled=$(jq -r '.[] | select(.event == "push" and (.headBranch == "main" or (.headBranch | startswith("level-"))) and .conclusion == "cancelled") | .databaseId' <<<"$runs")
[ -z "$cancelled" ] || fail "runs on main or a level tag were cancelled: $cancelled"
# Two main runs of different commits that overlapped in time, both green. Re-running one while
# another is in progress makes such a pair; MAIN_PAIR="<run>:<attempt> <run>:<attempt>" names it
# (attempts, because a later re-run replaces a run's latest timings).
# The window of an attempt is its jobs' (a run queued behind another can still report an early start).
attempt() {
  local run jobs
  run=$(gh api "repos/$REPO/actions/runs/${1%:*}/attempts/${1#*:}" --jq '{id, head_branch, event, head_sha, conclusion}')
  jobs=$(gh api "repos/$REPO/actions/runs/${1%:*}/attempts/${1#*:}/jobs" \
    --jq '[.jobs[] | select(.conclusion != "skipped")] | {run_started_at: (map(.started_at) | min), updated_at: (map(.completed_at) | max)}')
  jq -s add <<<"$run$jobs"
}
overlap=""
if [ -n "${MAIN_PAIR:-}" ]; then
  read -r a b <<<"$MAIN_PAIR"
  fresh "${a%:*}"; fresh "${b%:*}"
  overlap=$(jq -rs '.[0] as $a | .[1] as $b
    | select(all(.[]; .head_branch == "main" and .event == "push" and .conclusion == "success"))
    | select($a.head_sha != $b.head_sha and $a.run_started_at < $b.updated_at and $b.run_started_at < $a.updated_at)
    | "\($a.id)+\($b.id)"' <<<"$(attempt "$a")$(attempt "$b")")
fi
[ -n "$overlap" ] || fail "no overlapping pair of green main runs of different commits observed (set MAIN_PAIR, or re-run one main run while another is in progress)"

# Half 2 — a feature PR: the older run is cancelled by the newer one.
branch=acceptance/concurrency
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  git -C "$work" commit -q --allow-empty -m "test: concurrency 1 (acceptance E09)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  gh pr create -R "$REPO" --base dev --head "$branch" --draft --title "acceptance E09: concurrency (do not merge)" --body "Throwaway PR for acceptance test E09." >/dev/null
  old_sha=$(git -C "$work" rev-parse HEAD); sleep 15
  git -C "$work" commit -q --allow-empty -m "test: concurrency 2 (acceptance E09)"
  git -C "$work" push -q origin "HEAD:refs/heads/$branch"
  NEW=$(wait_run "$(git -C "$work" rev-parse HEAD)" pull_request)
  OLD=$(gh run list -R "$REPO" --workflow ci.yml --commit "$old_sha" --limit 1 --json databaseId -q '.[0].databaseId')
  gh pr close -R "$REPO" "$branch" --delete-branch >/dev/null
fi
[ -n "${OLD:-}" ] && [ -n "${NEW:-}" ] || fail "feature half not observed yet: run with ACT=1 (pushes a throwaway PR, ask first) or set OLD and NEW"
fresh "$OLD"
[ "$(gh run view -R "$REPO" "$OLD" --json conclusion -q .conclusion)" = cancelled ] || fail "older run $OLD wasn't cancelled"
[ "$(gh run view -R "$REPO" "$NEW" --json conclusion -q .conclusion)" = success ] || fail "newer run $NEW didn't finish green"

pass "feature run $OLD was cancelled by $NEW; no main or tag run was ever cancelled"
