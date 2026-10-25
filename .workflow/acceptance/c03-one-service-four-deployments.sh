#!/usr/bin/env bash
# C03 — one Service over four Deployments: in the running cluster, knock-api selects exactly
# `pool: knock` on port 8080, no other Service selects a backend pod, and knock-api's endpoints
# are four ready pods, one from each of knock-go, knock-python, knock-rust and knock-ts. The
# frontend pod isn't among them.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

cluster

svc=$(kc get service knock-api -o json 2>/dev/null) || fail "there's no Service knock-api"
jq -e '.spec.selector == {"pool": "knock"}' <<<"$svc" >/dev/null \
  || fail "knock-api selects $(jq -c .spec.selector <<<"$svc"), expected exactly {\"pool\":\"knock\"}"
jq -e '(.spec.ports | length == 1) and (.spec.ports[0] | .port == 8080 and (.targetPort == 8080 or .targetPort == "8080"))' <<<"$svc" >/dev/null \
  || fail "knock-api doesn't serve exactly port 8080 → 8080: $(jq -c .spec.ports <<<"$svc")"

pods=$(kc get pods -o json)
services=$(kc get services -o json)
# Which Deployment owns each pod (pod → ReplicaSet → Deployment).
rs=$(kc get replicasets -o json)
deployment_of() {
  local owner
  owner=$(jq -r --arg p "$1" '.items[] | select(.metadata.name == $p) | .metadata.ownerReferences[0].name // empty' <<<"$pods")
  jq -r --arg r "$owner" '.items[] | select(.metadata.name == $r) | .metadata.ownerReferences[0].name // empty' <<<"$rs"
}

# Only knock-api is in front of the backends: no other Service's selector matches a pool pod.
others=$(jq -r --argjson pods "$pods" '
  [.items[] | select(.metadata.name != "knock-api" and (.spec.selector // {}) != {}) | . as $s
   | select(any($pods.items[] | select(.metadata.labels.pool == "knock");
       .metadata.labels as $l | all($s.spec.selector | to_entries[]; $l[.key] == .value)))
   | .metadata.name] | join(" ")' <<<"$services")
[ -z "$others" ] || fail "other Services also select backend pods: $others"

# knock-api's ready endpoints: one pod from each backend Deployment, nothing else.
eps=$(kc get endpointslices -l kubernetes.io/service-name=knock-api -o json \
  | jq -r '[.items[].endpoints[] | select(.conditions.ready) | .targetRef.name] | sort | .[]')
[ "$(wc -l <<<"$eps" | tr -d ' ')" -eq 4 ] || fail "knock-api has $(grep -c . <<<"$eps") ready endpoints, expected 4: $(tr '\n' ' ' <<<"$eps")"
owners=$(for p in $eps; do deployment_of "$p"; done | sort | tr '\n' ' ')
[ "$owners" = "knock-go knock-python knock-rust knock-ts " ] || fail "knock-api's endpoints come from '$owners'"

pass "knock-api (pool: knock) is the one Service over knock-go, knock-python, knock-rust and knock-ts"
