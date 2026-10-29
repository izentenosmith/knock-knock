#!/usr/bin/env bash
# Runs the acceptance tests of every level so far (level 1: 01-08, e*, l*; level 2: c*, ce*).
# Usage: run.sh [pattern]  (e.g. run.sh 02, run.sh e0, run.sh c)
# ACT=1 lets the ACTS tests push throwaway branches, tags and PRs: ask the user first.
# The level-2 tests share one k3d cluster they create; it's deleted at the end (KEEP_CLUSTER=1 keeps it).
cd "$(dirname "$0")"
failed=0
[ -f observed.env ] && . ./observed.env
for t in [0-9el][0-9]*-*.sh c[0-9]*-*.sh ce[0-9]*-*.sh; do
  [ -f "$t" ] || continue
  case "$t" in "${1:-}"*) ;; *) continue ;; esac
  # Observed runs for the ACTS tests, unless the caller is acting or passed its own.
  p=$(tr '[:lower:]' '[:upper:]' <<<"${t%%-*}")
  inputs=()
  for k in RUN BEFORE OLD NEW SHA PR MAIN_PAIR; do
    v="${p}_$k"
    [ -n "${!v:-}" ] && [ -z "${ACT:-}" ] && inputs+=("$k=${!v}")
  done
  if out=$(env "${inputs[@]}" ./"$t" 2>&1); then echo "✅ $t"; else echo "❌ $t — $(grep -m1 '^FAIL' <<<"$out" || tail -1 <<<"$out")"; failed=$((failed + 1)); fi
done
[ -n "${KEEP_CLUSTER:-}" ] || ./cluster-down.sh
echo "$failed failing"
[ "$failed" -eq 0 ]
