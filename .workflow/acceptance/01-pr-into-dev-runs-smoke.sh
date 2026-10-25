#!/usr/bin/env bash
# AT-01 — tracer bullet: a PR into dev triggers ci.yml, and job `smoke` is green: all five
# images built through compose, healthy, and the smoke test passed with four languages.
# Given: a PR into dev (PR=<number>, default: the newest one).
# Not checked here: the tally in the job summary (no public API exposes job summaries).
. "$(dirname "$0")/lib.sh"

read -r pr sha branch <<<"$(pick_pr dev)"
[ -n "${sha:-}" ] || fail "no PR into dev yet, so no CI run to observe"

run=$(ci_run "$sha" pull_request "$branch")
IFS=$'\t' read -r job conclusion <<<"$(job_named "$run" smoke)"
[ -n "${job:-}" ] || fail "run $run has no job named smoke"
[ "$conclusion" = success ] || fail "job smoke concluded $conclusion in run $run"

log=$(job_log "$job")
for svc in $SERVICES; do
  grep -Eq "(Image knock-knock-|[[:space:]])$svc[[:space:]]+Built" <<<"$log" || fail "no sign compose built $svc"
  grep -Eq "Container knock-knock-$svc-1[[:space:]]+Healthy" <<<"$log" || fail "no sign $svc came up healthy"
done
for lang in $BACKENDS; do
  grep -Eq "[[:space:]]$lang[[:space:]]+[0-9]+[[:space:]]*$" <<<"$log" || fail "the tally has no $lang line"
done
grep -Eq '[[:space:]]PASS[[:space:]]*$' <<<"$log" || fail "the smoke test didn't print PASS"

pass "PR into dev ran ci.yml (run $run): smoke green with four languages"
