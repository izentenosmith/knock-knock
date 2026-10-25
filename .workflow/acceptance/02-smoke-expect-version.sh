#!/usr/bin/env bash
# AT-02 — EXPECT_VERSION: with EXPECT_VERSION=sha-abc1234 the smoke test passes against
# answers carrying that version and fails, naming `version`, against answers carrying `dev`.
# With EXPECT_VERSION unset it behaves exactly as today.
# Boundary: scripts/smoke.sh as a subprocess; the stack behind it is faked (fixtures/fake_api.py).
. "$(dirname "$0")/lib.sh"

smoke="$ROOT/scripts/smoke.sh"
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
serve() { python3 -I "$HERE/fixtures/fake_api.py" "$1" "$2" & pids+=($!); }
serve 18121 sha-abc1234
serve 18122 dev
serve 18123 sha-abc1234,sha-abc1234,sha-abc1234,dev
for port in 18121 18122 18123; do
  up=""
  for _ in $(seq 50); do curl -fs "localhost:$port/api/knock" >/dev/null 2>&1 && { up=1; break; }; sleep 0.1; done
  [ -n "$up" ] || fail "setup: the fake API on $port didn't start"
done

# Given answers with version sha-abc1234, when EXPECT_VERSION matches, then it passes.
out=$(URL=http://localhost:18121/api/knock EXPECT_VERSION=sha-abc1234 "$smoke" 8 2>&1) \
  || fail "smoke should pass when every version equals EXPECT_VERSION"
grep -qx 'version sha-abc1234 in every answer' <<<"$out" || fail "smoke didn't report the version it checked"

# Given answers with version dev, when EXPECT_VERSION=sha-abc1234, then it fails and names version.
if out=$(URL=http://localhost:18122/api/knock EXPECT_VERSION=sha-abc1234 "$smoke" 8 2>&1); then
  fail "smoke passed although every answer had version dev, not sha-abc1234"
fi
grep -q '^FAIL: .*version' <<<"$out" || fail "the failure doesn't name version: $(tail -1 <<<"$out")"

# Given one backend in four answering dev, when EXPECT_VERSION=sha-abc1234, then it fails.
if out=$(URL=http://localhost:18123/api/knock EXPECT_VERSION=sha-abc1234 "$smoke" 8 2>&1); then
  fail "smoke passed although one backend answered dev"
fi
grep -q '^FAIL: .*version' <<<"$out" || fail "the mixed-version failure doesn't name version: $(tail -1 <<<"$out")"

# Given EXPECT_VERSION set but empty (a CI typo), then it fails instead of skipping the check.
if out=$(URL=http://localhost:18121/api/knock EXPECT_VERSION= "$smoke" 8 2>&1); then
  fail "smoke passed with EXPECT_VERSION set but empty"
fi
grep -q '^FAIL: EXPECT_VERSION is set but empty' <<<"$out" || fail "the empty-version failure doesn't say so: $(tail -1 <<<"$out")"

# Given answers with version dev, when EXPECT_VERSION is unset, then it passes as it does today.
out=$(URL=http://localhost:18122/api/knock "$smoke" 8 2>&1) || fail "smoke without EXPECT_VERSION should still pass"
[ "$(tail -1 <<<"$out")" = PASS ] || fail "smoke without EXPECT_VERSION no longer ends in PASS"

pass "EXPECT_VERSION is enforced when set and ignored when unset"
