#!/usr/bin/env bash
# AT-07 — the annotated level tag, on a commit main has, runs CI on the tag; publish promotes (its
# build job is skipped) and every service's level tag is exactly the digest of its sha-<7>.
# Given: LEVEL_TAG (default level-01-pipeline) pushed to GitHub.
. "$(dirname "$0")/lib.sh"
# Release history: this observes the level-01-pipeline release as it ran (workflows at 52dd932).
# The current promotion code is covered by l2 until the next level's tag runs it on GitHub.
HISTORY=1

level=${LEVEL_TAG:-level-01-pipeline}
refs=$(git ls-remote "https://github.com/$REPO" "refs/tags/$level" "refs/tags/$level^{}")
sha=$(remote_commit "refs/tags/$level")
[ -n "$sha" ] || fail "tag $level isn't on GitHub yet"
grep -q '\^{}$' <<<"$refs" || fail "$level isn't an annotated tag on GitHub"
git -C "$ROOT" fetch -q origin main
git -C "$ROOT" merge-base --is-ancestor "$sha" origin/main || fail "$level is on ${sha:0:7}, which isn't on main"

run=$(ci_run "$sha" push "$level")
[ "$(gh run view -R "$REPO" "$run" --json conclusion -q .conclusion)" = success ] || fail "the $level run $run isn't green"
jobs=$(publish_jobs "$run" publish)
promoted=$(awk -F'\t' 'index($1, "publish / promote") == 1 && $2 == "success"' <<<"$jobs" | wc -l | tr -d ' ')
[ "$promoted" = 5 ] || fail "expected 5 green promote jobs in run $run, got $promoted"
built=$(awk -F'\t' 'index($1, "publish / build") == 1 && $2 != "skipped"' <<<"$jobs")
[ -z "$built" ] || fail "the tag run built images: $(cut -f1 <<<"$built" | tr '\n' ' ')"

for svc in $SERVICES; do
  a=$(digest "$IMAGE-$svc:$level"); b=$(digest "$IMAGE-$svc:$(version_of "$sha")")
  [ "$a" = "$b" ] || fail "$svc: $level is $a but $(version_of "$sha") is $b"
done

pass "(history, level-01 release) $level (annotated, on main) promotes $(version_of "$sha") for all five services without building, same digests"
