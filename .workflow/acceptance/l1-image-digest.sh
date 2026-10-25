#!/usr/bin/env bash
# L1 (F8, F25) — scripts/image-digest.sh says "absent" only for the registry's own answer for a
# missing tag or package; every other failure exits non-zero, even when the reference contains
# "denied" or "not found". With --revision <sha>, an existing image whose revision label differs fails.
# Boundary: the script as a subprocess, against a real registry (registry:2 on localhost).
. "$(dirname "$0")/lib.sh"; . "$HERE/lib-registry.sh"
digest="$ROOT/scripts/image-digest.sh"
registry_up
seed knock-knock-rust:latest kk-rust:sha-1111111 org.opencontainers.image.revision=1111111aaaa

run() { out=$("$digest" "$@" 2>&1); code=$?; }
set +e
run "$REG/kk-rust:sha-1111111"; [ $code = 0 ] && [[ $out == sha256:* ]] || fail "an existing tag should print its digest (got $code '$out')"
run "$REG/kk-rust:sha-2222222"; [ $code = 0 ] && [ -z "$out" ] || fail "a missing tag should be absent (got $code '$out')"
run "$REG/never-pushed:x"; [ $code = 0 ] && [ -z "$out" ] || fail "a missing repository should be absent (got $code '$out')"
for ref in registry.invalid/denied:x registry.invalid/x:level-05-denied-routes registry.invalid/not-found:x 127.0.0.1:1/x:not-found; do
  run "$ref"; [ $code != 0 ] || fail "an unreachable registry must not read as absent: $ref"
done
run --revision 1111111aaaa "$REG/kk-rust:sha-1111111"; [ $code = 0 ] && [[ $out == sha256:* ]] || fail "a matching revision should pass (got $code '$out')"
run --revision 9999999bbbb "$REG/kk-rust:sha-1111111"; [ $code != 0 ] && grep -q revision <<<"$out" || fail "a different revision must fail and say so (got $code '$out')"
run --revision 9999999bbbb "$REG/kk-rust:sha-2222222"; [ $code = 0 ] && [ -z "$out" ] || fail "--revision on a missing tag is still absent (got $code '$out')"
run --revision 9999999bbbb "$REG/kk-rust:sha-1111111"; [ $code = 2 ] || fail "a revision mismatch should exit 2, apart from registry errors (got $code)"

# GHCR's own answer for a package that doesn't exist (403 on the anonymous token) is absent.
run "ghcr.io/izentenosmith/no-such-package-$RANDOM:x"; [ $code = 0 ] && [ -z "$out" ] || fail "GHCR's 403 for a missing package should be absent (got $code '$out')"

# Only the registry's exact answer counts: other text that merely contains "not found" is an error.
stub=$(mktemp -d); trap 'rm -rf "$stub"' EXIT
printf '#!/bin/sh\necho "ERROR: failed to do request: proxy said: page not found" >&2\nexit 1\n' >"$stub/docker"; chmod +x "$stub/docker"
out=$(PATH="$stub:$PATH" "$digest" "$REG/kk-rust:sha-3333333" 2>&1); code=$?
[ $code != 0 ] || fail "a non-exact 'not found' must not read as absent (got $code '$out')"

# A multi-platform index (the only shape CI publishes): every platform's revision is checked.
docker buildx imagetools create -t "$REG/kk-multi:sha-ddb0365" ghcr.io/izentenosmith/knock-knock-go:sha-ddb0365 >/dev/null 2>&1 || fail "setup: couldn't copy a multi-platform image"
rev=$(git -C "$ROOT" rev-parse ddb0365)
run --revision "$rev" "$REG/kk-multi:sha-ddb0365"; [ $code = 0 ] && [[ $out == sha256:* ]] || fail "a multi-platform image with the right revision should pass (got $code '$out')"
run --revision 0000000000 "$REG/kk-multi:sha-ddb0365"; [ $code = 2 ] || fail "a multi-platform image with another revision should exit 2 (got $code '$out')"
set -e
pass "image-digest: absent only on the registry's answer; errors fail; revision mismatches fail"
