#!/usr/bin/env bash
# Runs the level-01 acceptance tests. Usage: run.sh [pattern]  (e.g. run.sh 02, run.sh e0)
# ACT=1 lets the ACTS tests push throwaway branches, tags and PRs: ask the user first.
cd "$(dirname "$0")"
failed=0
[ -f observed.env ] && . ./observed.env
for t in [0-9el][0-9]*-*.sh; do
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
echo "$failed failing"
[ "$failed" -eq 0 ]
