#!/usr/bin/env bash
# L2 (F1, F24, F29, F4) — scripts/promote.sh <image> <version> <level-tag> <revision>, against a real
# registry: a malformed level tag fails before anything is written; a source that never appears
# fails "never published from main" (after a bounded wait) and writes nothing; a source that
# appears during the wait is promoted; an absent level tag is created at exactly the source
# digest; a level tag already there is a no-op; one at another digest fails as immutable and is
# left alone; a source built from another revision fails.
. "$(dirname "$0")/lib.sh"; . "$HERE/lib-registry.sh"
promote="$ROOT/scripts/promote.sh"
registry_up
id=$RANDOM; img="$REG/kk-promote-$id"; rev=abc1234def
seed knock-knock-rust:latest "kk-promote-$id:sha-abc1234" org.opencontainers.image.revision=$rev
seed knock-knock-go:latest "kk-promote-$id:sha-0ther00" org.opencontainers.image.revision=0ther00xyz
d() { "$ROOT/scripts/image-digest.sh" "$1"; }
export PROMOTE_WAIT_SECONDS=0 PROMOTE_POLL_SECONDS=1
set +e

out=$("$promote" "$img" sha-abc1234 level-1-bad "$rev" 2>&1); code=$?
[ $code != 0 ] && grep -q 'level-NN-' <<<"$out" || fail "a malformed level tag should fail naming the format (got $code '$out')"
[ -z "$(d "$img:level-1-bad")" ] || fail "a malformed level tag was written"

out=$("$promote" "$img" sha-fffffff level-98-never ffffffffff 2>&1); code=$?
[ $code != 0 ] && grep -q 'never published from main' <<<"$out" || fail "an absent source should fail 'never published from main' (got $code '$out')"
[ -z "$(d "$img:level-98-never")" ] || fail "a level tag was written for an absent source"

out=$("$promote" "$img" sha-abc1234 level-97-wrong-rev 0000000000 2>&1); code=$?
[ $code != 0 ] && grep -q revision <<<"$out" || fail "a source from another revision should fail (got $code '$out')"

out=$("$promote" "$img" sha-abc1234 level-01-pipeline "$rev" 2>&1); code=$?
[ $code = 0 ] && grep -q '^promoted ' <<<"$out" || fail "an absent level tag should be promoted (got $code '$out')"
[ "$(d "$img:level-01-pipeline")" = "$(d "$img:sha-abc1234")" ] || fail "the level tag isn't at the source digest"

out=$("$promote" "$img" sha-abc1234 level-01-pipeline "$rev" 2>&1); code=$?
[ $code = 0 ] && grep -q 'no-op' <<<"$out" || fail "re-promoting should be a no-op (got $code '$out')"

docker buildx imagetools create -t "$img:level-02-taken" "$img:sha-0ther00" >/dev/null 2>&1 || fail "setup: couldn't create level-02-taken"
before=$(d "$img:level-02-taken")
out=$("$promote" "$img" sha-abc1234 level-02-taken "$rev" 2>&1); code=$?
[ $code != 0 ] && grep -q immutable <<<"$out" || fail "a level tag at another digest should fail as immutable (got $code '$out')"
[ "$(d "$img:level-02-taken")" = "$before" ] || fail "the existing level tag was moved"

PROMOTE_WAIT_SECONDS=20 "$promote" "$img" sha-1ate000 level-03-late 1ate000rev >"$HERE/.l2-late.out" 2>&1 & pid=$!
sleep 3; seed knock-knock-ts:latest "kk-promote-$id:sha-1ate000" org.opencontainers.image.revision=1ate000rev
wait $pid; code=$?
[ $code = 0 ] && [ "$(d "$img:level-03-late")" = "$(d "$img:sha-1ate000")" ] || fail "a source published during the wait wasn't promoted (got $code '$(cat "$HERE/.l2-late.out")')"
rm -f "$HERE/.l2-late.out"

long="level-04-$(printf 'x%.0s' $(seq 130))"
out=$("$promote" "$img" sha-abc1234 "$long" "$rev" 2>&1); code=$?
[ $code != 0 ] && grep -q 'level-NN-' <<<"$out" || fail "a level tag over 128 characters should fail the format check (got $code)"

# A docker whose `imagetools create` silently does nothing: the read-back must catch it.
stub=$(mktemp -d); trap 'rm -rf "$stub"' EXIT; real=$(command -v docker)
printf '#!/bin/bash\nif [ "$1 $2 $3" = "buildx imagetools create" ]; then exit 0; fi\nexec %s "$@"\n' "$real" >"$stub/docker"; chmod +x "$stub/docker"
out=$(PATH="$stub:$PATH" "$promote" "$img" sha-abc1234 level-05-noop-create "$rev" 2>&1); code=$?
[ $code != 0 ] || fail "a create that didn't happen must fail the read-back (got $code '$out')"

# Two transient registry errors during the wait are retried, then the source is promoted.
printf '#!/bin/bash\nn=$(cat %s/count 2>/dev/null || echo 0); echo $((n+1)) >%s/count\nif [ "$1 $2 $3" = "buildx imagetools inspect" ] && [ $n -lt 2 ]; then echo "ERROR: unexpected status 502 Bad Gateway" >&2; exit 1; fi\nexec %s "$@"\n' "$stub" "$stub" "$real" >"$stub/docker"
out=$(PATH="$stub:$PATH" PROMOTE_WAIT_SECONDS=10 "$promote" "$img" sha-abc1234 level-06-flaky "$rev" 2>&1); code=$?
[ $code = 0 ] && [ "$(d "$img:level-06-flaky")" = "$(d "$img:sha-abc1234")" ] || fail "transient registry errors during the wait should be retried (got $code '$out')"
set -e
pass "promote: validates, waits, promotes at the same digest, no-ops, refuses to move or mismatch"
