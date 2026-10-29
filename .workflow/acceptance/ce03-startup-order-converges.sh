#!/usr/bin/env bash
# CE03 — startup order converges: when the frontend starts before the knock-api Service exists,
# its nginx can't resolve knock-api and exits; applying the rest of k8s/ then converges with
# nobody deleting a pod: the same frontend pod restarts, and smoke passes through the ingress.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

cluster
pin=$(pinned_tag)
# A failed run can leave a frontend whose nginx holds a dead knock-api address (it resolves once,
# at startup): never leave that behind for the next test to reuse.
trap 'status=$?
  if [ "$status" -ne 0 ]; then
    if [ -n "${KEEP_CLUSTER:-}" ]; then echo "KEEP_CLUSTER: kept the cluster, but it may be broken; delete it before the next run (./cluster-down.sh)" >&2
    else "$HERE/cluster-down.sh" >/dev/null; fi
  fi
  exit "$status"' EXIT

# Given an empty namespace, apply only the frontend Deployment (the one without pool: knock).
kc delete -f "$K8S" --wait=true >/dev/null 2>&1 || true
sleep 35 # CoreDNS caches answers for 30 s: let the old knock-api record expire first
front=$(manifests | jq -c '[.[] | select(.kind == "Deployment" and .spec.template.metadata.labels.pool != "knock")]')
[ "$(jq length <<<"$front")" -eq 1 ] || fail "expected exactly one non-backend Deployment (the frontend) in k8s/"
name=$(jq -r '.[0].metadata.name' <<<"$front")
jq -c '{apiVersion: "v1", kind: "List", items: .}' <<<"$front" | kc apply -f - >/dev/null
sel=$(jq -r '.[0].spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$front")

# Then nginx fails without knock-api: the pod restarts at least once.
pod="" restarts=0
for _ in $(seq 60); do
  read -r pod restarts <<<"$(kc get pods -l "$sel" -o json | jq -r '[.items[] | select(.metadata.deletionTimestamp == null)][0] // empty | "\(.metadata.name) \(.status.containerStatuses[0].restartCount // 0)"')"
  [ "${restarts:-0}" -ge 1 ] && break
  sleep 2
done
[ -n "$pod" ] || fail "the frontend pod never appeared"
[ "${restarts:-0}" -ge 1 ] || fail "the frontend ($pod) never failed without knock-api, so the order wasn't exercised"
# Why it failed: nginx's own words, from the crashed container (the current one while it waits in
# CrashLoopBackOff, or the previous one; containerd can drop either mid-churn, so retry briefly).
for _ in $(seq 15); do
  log=$( { kc logs "$pod"; kc logs "$pod" --previous; } 2>&1 || true)
  has "$log" 'host not found in upstream "knock-api' && break
  sleep 1
done
has "$log" 'host not found in upstream "knock-api' || fail "the frontend restarted, but not because knock-api was missing: $(tail -1 <<<"$log")"
uid=$(kc get pod "$pod" -o jsonpath='{.metadata.uid}')

# When the rest of k8s/ is applied, then it converges on its own: the restarts back off (up to
# 5 min) and CoreDNS may still serve the cached "no such host" for 30 s, so allow 6 minutes.
kc apply -f "$K8S" >/dev/null
up=""
for _ in $(seq 72); do
  curl -fsS --max-time 2 "$INGRESS/api/knock" >/dev/null 2>&1 && { up=1; break; }
  sleep 5
done
[ -n "$up" ] || { kc get pods -o wide >&2; fail "it didn't converge: the ingress never answered /api/knock within 6 minutes"; }
wait_ready
now=$(kc get pods -l "$sel" -o json | jq -r '[.items[] | select(.metadata.deletionTimestamp == null) | .metadata.uid] | join(" ")')
[ "$now" = "$uid" ] || fail "the frontend pod was replaced ($uid → $now), not restarted"
out=$(URL="$INGRESS/api/knock" EXPECT_VERSION="$pin" EXPECT_NODE_PREFIX=k3d-knock- "$ROOT/scripts/smoke.sh" 2>&1) \
  || fail "smoke failed after the late Service: $(grep -m1 '^FAIL' <<<"$out" || tail -1 <<<"$out")"

pass "$name started before knock-api, restarted $restarts+ times, and converged; smoke passed"
