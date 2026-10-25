#!/usr/bin/env bash
# C02 — EXPECT_NODE_PREFIX: set to k3d-knock-, the smoke test passes when every answer's `node`
# starts with it and fails, naming `node`, when any answer says `local` or another prefix (a
# literal prefix: not a substring, not a regex). Set but empty fails. Unset, its output is
# byte-for-byte the smoke test level 2 started from (04f74b3) (with and without EXPECT_VERSION).
# Boundary: scripts/smoke.sh as a subprocess; the stack behind it is faked (fixtures/fake_api.py).
. "$(dirname "$0")/lib.sh"

smoke="$ROOT/scripts/smoke.sh"
before=$(mktemp)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true; rm -f "$before"' EXIT
git -C "$ROOT" show 04f74b3:scripts/smoke.sh >"$before" # level 2's base: the newest level-1 release

serve() { python3 -I "$HERE/fixtures/fake_api.py" "$@" & pids+=($!); }
serve 18221 sha-abc1234 k3d-knock-agent-0,k3d-knock-agent-1,k3d-knock-server-0
serve 18222 sha-abc1234 k3d-knock-agent-0,k3d-knock-agent-1,local
serve 18223 sha-abc1234 k3d-other-agent-0
serve 18224 sha-abc1234 x-k3d-knock-agent-0
serve 18225 sha-abc1234 k3d-knock-agent-0
for port in 18221 18222 18223 18224 18225; do
  up=""
  for _ in $(seq 50); do curl -fs "localhost:$port/api/knock" >/dev/null 2>&1 && { up=1; break; }; sleep 0.1; done
  [ -n "$up" ] || fail "setup: the fake API on $port didn't start"
done
url() { echo "http://localhost:$1/api/knock"; }

# Given every node on k3d-knock-*, when EXPECT_NODE_PREFIX=k3d-knock-, then it passes and says so.
out=$(URL=$(url 18221) EXPECT_NODE_PREFIX=k3d-knock- "$smoke" 8 2>&1) \
  || fail "smoke should pass when every node starts with EXPECT_NODE_PREFIX: $(tail -1 <<<"$out")"
grep -qx 'node prefix k3d-knock- in every answer' <<<"$out" || fail "smoke didn't report the node prefix it checked"

# Given one backend answering node `local` (NODE_NAME not wired), then it fails and names node.
for port in 18222 18223 18224; do
  if out=$(URL=$(url $port) EXPECT_NODE_PREFIX=k3d-knock- "$smoke" 8 2>&1); then
    fail "smoke passed although the nodes on $port don't all start with k3d-knock-"
  fi
  grep -q '^FAIL: .*node' <<<"$out" || fail "the failure on $port doesn't name node: $(tail -1 <<<"$out")"
done

# The prefix is literal: a regex-looking prefix doesn't match by accident.
if out=$(URL=$(url 18225) EXPECT_NODE_PREFIX=k3d.knock "$smoke" 8 2>&1); then
  fail "EXPECT_NODE_PREFIX=k3d.knock matched k3d-knock-agent-0 (read as a regex)"
fi

# Given EXPECT_NODE_PREFIX set but empty (a CI typo), then it fails instead of skipping the check.
if out=$(URL=$(url 18221) EXPECT_NODE_PREFIX= "$smoke" 8 2>&1); then
  fail "smoke passed with EXPECT_NODE_PREFIX set but empty"
fi
grep -q '^FAIL: EXPECT_NODE_PREFIX is set but empty' <<<"$out" || fail "the empty-prefix failure doesn't say so: $(tail -1 <<<"$out")"

# Unset, the output is the level-1 smoke test's, byte for byte, with and without EXPECT_VERSION.
for port in 18221 18222; do
  for ev in unset sha-abc1234; do
    if [ "$ev" = unset ]; then
      now=$(URL=$(url $port) "$smoke" 8 2>&1) || fail "smoke without EXPECT_NODE_PREFIX should pass on $port"
      was=$(URL=$(url $port) bash "$before" 8 2>&1) || fail "setup: the level-1 smoke failed on $port"
    else
      now=$(URL=$(url $port) EXPECT_VERSION=$ev "$smoke" 8 2>&1) || fail "smoke with only EXPECT_VERSION should pass on $port"
      was=$(URL=$(url $port) EXPECT_VERSION=$ev bash "$before" 8 2>&1) || fail "setup: the level-1 smoke failed on $port"
    fi
    [ "$now" = "$was" ] || fail "unset EXPECT_NODE_PREFIX changed the output (port $port, EXPECT_VERSION $ev): $(diff <(echo "$was") <(echo "$now") | head -3)"
  done
done

pass "EXPECT_NODE_PREFIX is enforced as a literal prefix when set and invisible when unset"
