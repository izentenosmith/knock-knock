#!/usr/bin/env bash
# AT-03 — CI proves the version plumbing: on a push run, `smoke` builds with
# VERSION=sha-<first 7 of the commit> and passes with EXPECT_VERSION set to the same value.
# Given: a pushed commit on dev (SHA=<sha>, default: dev's head on GitHub).
. "$(dirname "$0")/lib.sh"

sha=${SHA:-$(remote_commit refs/heads/dev)}
want=$(version_of "$sha")
run=$(ci_run "$sha" push)
IFS=$'\t' read -r job conclusion <<<"$(job_named "$run" smoke)"
[ -n "${job:-}" ] || fail "run $run has no job named smoke"
[ "$conclusion" = success ] || fail "job smoke concluded $conclusion in run $run"

out=$(job_output "$job")
has "$out" "^version $want in every answer$" || fail "smoke didn't check every answer for version $want"
has "$out" '^PASS$' || fail "smoke didn't pass"

pass "push to dev @ ${sha:0:7}: built and smoke-tested as $want"
