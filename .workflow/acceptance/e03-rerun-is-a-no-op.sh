#!/usr/bin/env bash
# E03 — re-running a successful main run skips every service ("already exists"), pushes nothing,
# and every sha-<7> digest is the same before and after.
# ACTS: re-runs main's latest ci.yml run (gh run rerun) and waits for it.
# Observe only: RUN=<id of a re-run main run> BEFORE="<svc>=<digest> ..." recorded beforehand.
. "$(dirname "$0")/lib.sh"

sha=${SHA:-$(remote_commit refs/heads/main)}
tag=$(version_of "$sha")
snapshot() { for svc in $SERVICES; do printf '%s=%s ' "$svc" "$(digest "$IMAGE-$svc:$tag")"; done; }
if acts; then
  RUN=$(ci_run "$sha" push main)
  BEFORE=$(snapshot)
  gh run rerun -R "$REPO" "$RUN"
  sleep 10
  gh run watch -R "$REPO" "$RUN" >/dev/null 2>&1 || true
fi
[ -n "${RUN:-}" ] && [ -n "${BEFORE:-}" ] || fail "not observed yet: run with ACT=1 (re-runs main's CI, ask first) or set RUN and BEFORE"

fresh "$RUN"
[ "$(gh run view -R "$REPO" "$RUN" --json attempt -q .attempt)" -ge 2 ] || fail "run $RUN was never re-run"
[ "$(gh run view -R "$REPO" "$RUN" --json conclusion -q .conclusion)" = success ] || fail "the re-run of $RUN isn't green"
for svc in $SERVICES; do
  id=$(publish_jobs "$RUN" publish | awk -F'\t' -v s="publish / build ($svc," 'index($1, s) == 1 {print $3}')
  [ -n "$id" ] || fail "run $RUN has no build job for $svc"
  has "$(job_output "$id")" "^$IMAGE-$svc:$tag already exists" || fail "the re-run didn't skip $svc as already existing"
done
[ "$(snapshot)" = "$BEFORE" ] || fail "digests changed: before '$BEFORE', after '$(snapshot)'"

pass "re-running main run $RUN skipped all five services; digests unchanged"
