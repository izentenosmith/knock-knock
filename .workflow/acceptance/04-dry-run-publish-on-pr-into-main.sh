#!/usr/bin/env bash
# AT-04 — a PR from dev into main runs smoke (ci.yml), only-dev-to-main, and a dry run (dry-run.yml)
# that builds all five services for linux/amd64 and linux/arm64 at the version smoke tested and
# checks every backend, with no login and no push, release-ready green, and no job holding
# packages: write. Assertions read job *output*.
# Given: a PR from dev into main (PR=<number>, default: the newest one).
. "$(dirname "$0")/lib.sh"

read -r pr sha branch <<<"$(pick_pr main dev)"
[ -n "${sha:-}" ] || fail "no PR from dev into main yet, so no dry run to observe"

ci=$(ci_run "$sha" pull_request dev)
IFS=$'\t' read -r smoke conclusion <<<"$(job_named "$ci" smoke)"
[ "${conclusion:-}" = success ] || fail "smoke concluded ${conclusion:-missing} in run $ci"
tested=$(grep -Eo '^version sha-[0-9a-f]{7} in every answer$' <<<"$(job_output "$smoke")" | grep -Eo 'sha-[0-9a-f]{7}' || true)
[ -n "$tested" ] || fail "smoke in run $ci didn't report the version it tested"
run=$(wf_run dry-run.yml "$sha" pull_request dev)
IFS=$'\t' read -r _ conclusion <<<"$(job_named "$run" release-ready)"
[ "${conclusion:-}" = success ] || fail "release-ready concluded ${conclusion:-missing} in run $run"
rule=$(wf_run only-dev-to-main.yml "$sha" pull_request dev)
IFS=$'\t' read -r _ conclusion <<<"$(job_named "$rule" only-dev-to-main)"
[ "${conclusion:-}" = success ] || fail "only-dev-to-main concluded ${conclusion:-missing} in run $rule"

dry=$(publish_jobs "$run" dry-run)
[ -n "$dry" ] || fail "run $run has no dry-run jobs"
bad=$(awk -F'\t' '$2 != "success" && $2 != "skipped"' <<<"$dry")
[ -z "$bad" ] || fail "dry-run jobs not green: $(cut -f1,2 <<<"$bad" | tr '\n' ' ')"
[ -z "$(publish_jobs "$ci" publish | awk -F'\t' '$2 != "skipped"')" ] || fail "run $ci also ran the real publish"

for svc in $SERVICES; do
  id=$(awk -F'\t' -v s="dry-run / build ($svc," 'index($1, s) == 1 && $2 == "success" {print $3}' <<<"$dry")
  [ -n "$id" ] || fail "no green dry-run build for $svc"
  out=$(job_output "$id")
  version=$(grep -Eo "^dry run: built $IMAGE-$svc:sha-[0-9a-f]{7}" <<<"$out" | grep -Eo 'sha-[0-9a-f]{7}$' || true)
  [ -n "$version" ] || fail "$svc's dry run didn't report what it built"
  [ "$version" = "$tested" ] || fail "$svc's dry run built $version, but smoke tested $tested"
  for p in linux/amd64 linux/arm64; do
    grep -q "\[$p " <<<"$out" || fail "buildx didn't build $svc for $p"
  done
  if [ "$svc" != frontend ]; then
    grep -q "answers as $svc, $version$" <<<"$out" || fail "$svc's image wasn't started and checked"
  fi
  if has "$out" 'Login Succeeded|pushing manifest for ghcr\.io' -E; then fail "$svc's dry run logged in to or pushed to GHCR"; fi
  has "$out" "^dry run: built $IMAGE-$svc:$version for linux/amd64 and linux/arm64 and checked it, pushed nothing$" || fail "$svc's dry run didn't confirm it pushed nothing"
  if exists_in_ghcr "$IMAGE-$svc:$version"; then fail "the dry run left $svc:$version in GHCR"; fi
done

while IFS=$'\t' read -r name _ id; do
  [ -n "$id" ] && [ "$id" != null ] || continue
  if has "$(job_log "$id")" 'Packages: write'; then fail "job '$name' in the dry-run run held packages: write"; fi
done < <(jobs_of "$run"; jobs_of "$ci")

pass "PR #$pr dev→main: smoke, only-dev-to-main, release-ready, a checked multi-arch dry run, nothing pushed, no write token"
