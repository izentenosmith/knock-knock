#!/usr/bin/env bash
# C01 — tracer bullet: from scratch, the README's exact commands (k3d cluster create knock
# --agents 2 -p "8080:80@loadbalancer", kubectl apply -f k8s/, then a wait) give a cluster whose
# ingress on localhost:8080 serves the UI, and scripts/smoke.sh passes through it with the pinned
# version and the k3d node prefix, four languages answering. On an arm64 host the nodes are
# arm64, and the images were pulled with no credentials (no imagePullSecrets anywhere).
# Owns the `knock` cluster: refuses if one exists that it didn't create, or if :8080 is taken.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

pin=$(pinned_tag)
fresh_cluster

# The UI, through the ingress.
html=$(curl -fsS --max-time 5 "$INGRESS/") || fail "GET / through the ingress failed"
has "$html" '<div id="root"></div>' || fail "GET / through the ingress isn't the frontend's page"

# The same smoke test, through the ingress.
out=$(EXPECT_VERSION="$pin" EXPECT_NODE_PREFIX=k3d-knock- "$ROOT/scripts/smoke.sh" 2>&1) \
  || fail "smoke through the ingress failed: $(grep -m1 '^FAIL' <<<"$out" || tail -1 <<<"$out")"
[ "$(tail -1 <<<"$out")" = PASS ] || fail "smoke didn't end in PASS"
grep -qx "version $pin in every answer" <<<"$out" || fail "smoke didn't check version $pin"
grep -qx "node prefix k3d-knock- in every answer" <<<"$out" || fail "smoke didn't check the node prefix"

# Native nodes and anonymous pulls.
if [ "$(uname -m)" = arm64 ]; then
  archs=$(kc get nodes -o json | jq -r '[.items[].metadata.labels["kubernetes.io/arch"]] | unique | join(" ")')
  [ "$archs" = arm64 ] || fail "the nodes are '$archs', expected arm64"
fi
secrets=$(kc get pods -o json | jq '[.items[] | select((.spec.imagePullSecrets // []) != [])] | length')
[ "$secrets" -eq 0 ] || fail "$secrets pods pull with imagePullSecrets"

pass "k3d + kubectl apply -f k8s/ serve the UI at $INGRESS; smoke passed with $pin on k3d nodes"
