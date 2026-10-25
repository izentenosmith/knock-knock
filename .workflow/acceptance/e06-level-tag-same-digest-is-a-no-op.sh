#!/usr/bin/env bash
# E06 — promotion is a no-op when the level tag already sits at the sha-<7> digest: re-running
# the level tag's run is green, says no-op, and changes no digest.
# The other half (a level tag at a *different* digest fails) needs a forged tag in a public
# package and a PAT with packages: write, which the design forbids; it is left to tdd.
# ACTS: re-runs the level tag's ci.yml run. Observe only: RUN=<id of that re-run>.
. "$(dirname "$0")/lib.sh"
# Release history: this observes the level-01-pipeline release as it ran (workflows at 52dd932).
# The current promotion code is covered by l2 until the next level's tag runs it on GitHub.
HISTORY=1

level=${LEVEL_TAG:-level-01-pipeline}
sha=$(remote_commit "refs/tags/$level")
[ -n "$sha" ] || fail "tag $level isn't on GitHub yet"
snapshot() { for svc in $SERVICES; do printf '%s=%s ' "$svc" "$(digest "$IMAGE-$svc:$1")"; done; }
source=$(snapshot "$(version_of "$sha")") # what every level tag must stay on, whenever this runs
if acts; then
  RUN=$(ci_run "$sha" push "$level")
  gh run rerun -R "$REPO" "$RUN"; sleep 10
  gh run watch -R "$REPO" "$RUN" >/dev/null 2>&1 || true
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (re-runs the $level CI run, ask first) or set RUN=<id>"

[ "$(gh run view -R "$REPO" "$RUN" --json attempt -q .attempt)" -ge 2 ] || fail "run $RUN was never re-run"
[ "$(gh run view -R "$REPO" "$RUN" --json conclusion -q .conclusion)" = success ] || fail "the re-run of $RUN isn't green"
pub=$(publish_jobs "$RUN" publish | awk -F'\t' 'index($1, "publish / promote") == 1')
[ "$(wc -l <<<"$pub" | tr -d ' ')" = 5 ] || fail "run $RUN doesn't have 5 promote jobs"
while IFS=$'\t' read -r name _ id; do
  has "$(job_output "$id")" ': no-op$' || fail "$name didn't report a no-op"
done <<<"$pub"
[ "$(snapshot "$level")" = "$source" ] || fail "level tags moved off the source digests: '$(snapshot "$level")' vs '$source'"

pass "(history, level-01 release) re-promoting $level (run $RUN) was a no-op"
