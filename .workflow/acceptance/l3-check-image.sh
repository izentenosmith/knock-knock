#!/usr/bin/env bash
# L3 (F2) — scripts/check-image.sh <image> <lang> <version> starts the image and passes only if
# /api/knock answers with that lang and version; a wrong version or lang fails, naming it.
# Boundary: the script as a subprocess, on images built by compose (VERSION=dev by default).
. "$(dirname "$0")/lib.sh"
check="$ROOT/scripts/check-image.sh"
docker image inspect knock-knock-rust:latest knock-knock-python:latest >/dev/null 2>&1 \
  || (cd "$ROOT" && docker compose build -q rust python >/dev/null) || fail "setup: couldn't build the images"
set +e
out=$("$check" knock-knock-rust:latest rust dev 2>&1); code=$?
[ $code = 0 ] || fail "the right lang and version should pass (got $code '$out')"
out=$("$check" knock-knock-rust:latest rust sha-1234567 2>&1); code=$?
[ $code != 0 ] && grep -q version <<<"$out" || fail "a wrong version should fail naming version (got $code '$out')"
out=$("$check" knock-knock-python:latest rust dev 2>&1); code=$?
[ $code != 0 ] && grep -q lang <<<"$out" || fail "a wrong lang should fail naming lang (got $code '$out')"
printf 'FROM knock-knock-python:latest\nCMD ["python", "-c", "print(\\"boom-on-start\\", flush=True); raise SystemExit(3)"]\n' | docker build -q -t kk-crash - >/dev/null
out=$("$check" kk-crash python dev 2>&1); code=$?
[ $code != 0 ] && grep -q boom-on-start <<<"$out" || fail "a crashing image's check should fail and show its logs (got $code '$out')"
set -e
[ -z "$(docker ps -aq --filter label=knock-check)" ] || fail "check-image left a container running"
pass "check-image: passes the right image, fails a wrong version or lang"
