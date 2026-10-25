#!/usr/bin/env bash
# CE03 — startup order converges: when the frontend starts before the knock-api Service exists,
# its nginx can't resolve knock-api and exits; applying the rest of k8s/ then converges with
# nobody deleting a pod: the same frontend pod restarts, and smoke passes through the ingress.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

cluster
pin=$(pinned_tag)

# Given an empty namespace, apply only the frontend Deployment (the one without pool: knock).
kc delete -f "$K8S" --wait=true >/dev/null 2>&1 || true
front=$(manifests | jq -c '[.[] | select(.kind == "Deployment" and .spec.template.metadata.labels.pool != "knock")]')
[ "$(jq length <<<"$front")" -eq 1 ] || fail "expected exactly one non-backend Deployment (the frontend) in k8s/"
name=$(jq -r '.[0].metadata.name' <<<"$front")
jq -c '{apiVersion: "v1", kind: "List", items: .}' <<<"$front" | kc apply -f - >/dev/null
sel=$(jq -r '.[0].spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$front")

# Then nginx fails without knock-api: the pod restarts at least once.
pod="" restarts=0
for _ in $(seq 60); do
  read -r pod restarts <<<"$(kc get pods -l "$sel" -o json | jq -r '.items[0] // empty | "\(.metadata.name) \(.status.containerStatuses[0].restartCount // 0)"')"
  [ "${restarts:-0}" -ge 1 ] && break
  sleep 2
done
[ -n "$pod" ] || fail "the frontend pod never appeared"
[ "${restarts:-0}" -ge 1 ] || fail "the frontend ($pod) never failed without knock-api, so the order wasn't exercised"
uid=$(kc get pod "$pod" -o jsonpath='{.metadata.uid}')

# When the rest of k8s/ is applied, then it converges on its own.
kc apply -f "$K8S" >/dev/null
wait_ready 240
now=$(kc get pods -l "$sel" -o jsonpath='{.items[*].metadata.uid}')
[ "$now" = "$uid" ] || fail "the frontend pod was replaced ($uid → $now), not restarted"
out=$(EXPECT_VERSION="$pin" EXPECT_NODE_PREFIX=k3d-knock- "$ROOT/scripts/smoke.sh" 2>&1) \
  || fail "smoke failed after the late Service: $(grep -m1 '^FAIL' <<<"$out" || tail -1 <<<"$out")"

pass "$name started before knock-api, restarted $restarts+ times, and converged; smoke passed"
