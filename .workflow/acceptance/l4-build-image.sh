#!/usr/bin/env bash
# L4 (F43) — scripts/build-image.sh builds both platforms once into a staging registry, starts the
# amd64 image from there (backends), and only then copies that exact index to the destination:
# the pushed digest is the staged digest. A dry run pushes nothing. A failed check pushes nothing.
# Boundary: the script as a subprocess; staging and destination are real local registries,
# with a buildx builder on the host network (as in CI).
. "$(dirname "$0")/lib.sh"; . "$HERE/lib-registry.sh"
build="$ROOT/scripts/build-image.sh"
registry_up
docker inspect kk-staging >/dev/null 2>&1 || docker run -d --name kk-staging -p 5056:5000 registry:2 >/dev/null
if ! docker buildx inspect kk-l4 >/dev/null 2>&1; then
  printf '[registry."localhost:5056"]\n  http = true\n' >"$HERE/.bk.toml"
  docker buildx create --name kk-l4 --driver docker-container --driver-opt network=host --buildkitd-config "$HERE/.bk.toml" >/dev/null
fi
export STAGING=localhost:5056 BUILDER=kk-l4
id=$RANDOM; dest="$REG/kk-l4-$id"; rev=4444444abcdef
set +e

out=$("$build" go "$ROOT/backends/go" "$dest-go" sha-4444444 "$rev" 2>&1); code=$?
[ $code = 0 ] && grep -q "^dry run: built $dest-go:sha-4444444 for linux/amd64 and linux/arm64" <<<"$out" || fail "a dry run should build and report (got $code '$(tail -3 <<<"$out")')"
grep -q "answers as go, sha-4444444" <<<"$out" || fail "the dry run didn't start and check the image"
[ -z "$("$ROOT/scripts/image-digest.sh" "$dest-go:sha-4444444")" ] || fail "the dry run pushed"

out=$("$build" go "$ROOT/backends/go" "$dest-go" sha-4444444 "$rev" --push 2>&1); code=$?
[ $code = 0 ] || fail "a push should succeed (got $code '$(tail -3 <<<"$out")')"
pushed=$("$ROOT/scripts/image-digest.sh" --revision "$rev" "$dest-go:sha-4444444")
staged=$("$ROOT/scripts/image-digest.sh" "$STAGING/go:sha-4444444")
[ -n "$pushed" ] && [ "$pushed" = "$staged" ] || fail "the pushed digest ($pushed) isn't the staged, checked one ($staged)"
[ "$(platforms "$dest-go:sha-4444444")" = "linux/amd64 linux/arm64" ] || fail "the pushed image isn't exactly amd64 + arm64"

bad=$(mktemp -d); cp -R "$ROOT/backends/go/." "$bad/"; echo 'ENV VERSION=dev' >>"$bad/Dockerfile"
out=$("$build" go "$bad" "$dest-bad" sha-5555555 "$rev" --push 2>&1); code=$?
[ $code != 0 ] && grep -q "answered version 'dev'" <<<"$out" || fail "an image that fails its check should stop the push (got $code)"
[ -z "$("$ROOT/scripts/image-digest.sh" "$dest-bad:sha-5555555")" ] || fail "an image that failed its check was pushed"
rm -rf "$bad"
set -e
pass "build-image: one build, checked from staging, the same digest pushed; a failed check pushes nothing"
