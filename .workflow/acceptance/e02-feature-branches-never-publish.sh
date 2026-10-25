#!/usr/bin/env bash
# E02 — a PR into dev, or a push to dev, never runs publish or the dry run, and no job in those
# runs holds packages: write (read from each job's "GITHUB_TOKEN Permissions" log section).
# Given: the newest PR into dev (PR=<n>) and dev's head on GitHub (SHA=<sha>).
. "$(dirname "$0")/lib.sh"

read -r pr pr_sha pr_branch <<<"$(pick_pr dev)"
[ -n "${pr_sha:-}" ] || fail "no PR into dev yet, so no run to observe"
dev_sha=${SHA:-$(remote_commit refs/heads/dev)}

for run in "$(ci_run "$pr_sha" pull_request "$pr_branch")" "$(ci_run "$dev_sha" push dev)"; do
  pub=$(publish_jobs "$run" | awk -F'\t' '$2 != "skipped"')
  [ -z "$pub" ] || fail "run $run ran publish: $(cut -f1 <<<"$pub" | tr '\n' ' ')"
  while IFS=$'\t' read -r name _ id; do
    [ -n "$id" ] && [ "$id" != null ] || continue
    if has "$(job_log "$id")" 'Packages: write'; then fail "job '$name' in run $run had packages: write"; fi
  done < <(jobs_of "$run")
done

pass "PR #$pr into dev and the push to dev @ ${dev_sha:0:7} never published or held packages: write"
