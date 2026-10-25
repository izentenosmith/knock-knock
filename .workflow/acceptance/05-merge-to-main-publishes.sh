#!/usr/bin/env bash
# AT-05 — after a dev→main merge commit, the push to main publishes
# ghcr.io/izentenosmith/knock-knock-<svc>:sha-<7> for all five services, each a manifest list
# of exactly linux/amd64 + linux/arm64, with source, revision and version labels.
# Given: main's head on GitHub (SHA=<sha> to pick another published commit).
. "$(dirname "$0")/lib.sh"

sha=${SHA:-$(remote_commit refs/heads/main)}
tag=$(version_of "$sha")
[ "$(git -C "$ROOT" cat-file -p "$sha" 2>/dev/null | grep -c '^parent ')" = 2 ] || [ -n "${SHA:-}" ] \
  || fail "main's head ${sha:0:7} isn't a merge commit (fetch, or merge dev→main with a merge commit)"
run=$(ci_run "$sha" push main)
[ "$(gh run view -R "$REPO" "$run" --json conclusion -q .conclusion)" = success ] || fail "main run $run isn't green"

for svc in $SERVICES; do
  ref="$IMAGE-$svc:$tag"
  [ "$(platforms "$ref")" = "linux/amd64 linux/arm64" ] || fail "$ref platforms are '$(platforms "$ref")'"
  for p in linux/amd64 linux/arm64; do
    l=$(labels "$ref" "$p")
    [ "$(jq -r '."org.opencontainers.image.source"' <<<"$l")" = "https://github.com/$REPO" ] || fail "$ref ($p) source label: $l"
    [ "$(jq -r '."org.opencontainers.image.revision"' <<<"$l")" = "$sha" ] || fail "$ref ($p) revision label: $l"
    [ "$(jq -r '."org.opencontainers.image.version"' <<<"$l")" = "$tag" ] || fail "$ref ($p) version label: $l"
  done
done

pass "main @ ${sha:0:7} published $tag for all five services, amd64 + arm64, labelled"
