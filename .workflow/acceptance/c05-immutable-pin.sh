#!/usr/bin/env bash
# C05 — immutable pin: the five Deployments in k8s/ run exactly the five published images,
# ghcr.io/izentenosmith/knock-knock-<svc>, all on one sha-<7> tag (no latest, no digest-only
# ref), and that tag exists on GHCR for every service. (That the running backends report it as
# `version` is C01's smoke check, EXPECT_VERSION=<the pin>.)
# Statically against k8s/ plus a registry lookup; no cluster.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

images=$(manifests | jq -r '.[] | select(.kind == "Deployment") | .spec.template.spec.containers[].image' | sort)
[ -n "$images" ] || fail "no Deployment images in k8s/"
tag=$(pinned_tag)
[[ "$tag" =~ ^sha-[0-9a-f]{7}$ ]] || fail "the images are pinned to '$tag', not a sha-<7> tag"

want=$(for svc in $SERVICES; do echo "$IMAGE-$svc:$tag"; done | sort)
[ "$images" = "$want" ] || fail "k8s/ runs $(tr '\n' ' ' <<<"$images"), expected $(tr '\n' ' ' <<<"$want")"

for svc in $SERVICES; do
  exists_in_ghcr "$IMAGE-$svc:$tag" || fail "$IMAGE-$svc:$tag isn't published"
done

pass "all five images are pinned to $tag, and GHCR has it for every service"
