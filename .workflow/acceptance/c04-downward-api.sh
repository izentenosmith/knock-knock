#!/usr/bin/env bash
# C04 — Downward API: every backend container's POD_NAME comes from metadata.name and NODE_NAME
# from spec.nodeName, and through the ingress each answer's `node` is the node its `pod` is
# scheduled on. (The `pod` value alone can't prove POD_NAME: a pod's hostname is its name, which
# is also the fallback. The spec is where that proof lives.)
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

cluster

pods=$(kc get pods -l pool=knock -o json)
[ "$(jq '.items | length' <<<"$pods")" -ge 4 ] || fail "fewer than four backend pods are running"
bad=$(jq -r '.items[] | .metadata.name as $p | .spec.containers[] |
  ((.env // []) | map({(.name): (.valueFrom.fieldRef.fieldPath // "")}) | add // {}) as $e |
  select($e.POD_NAME != "metadata.name" or $e.NODE_NAME != "spec.nodeName") | $p' <<<"$pods")
[ -z "$bad" ] || fail "these pods don't take POD_NAME/NODE_NAME from the Downward API: $(tr '\n' ' ' <<<"$bad")"

# Every answer's node is where its pod runs.
nodes=$(jq -c '[.items[] | {(.metadata.name): .spec.nodeName}] | add' <<<"$pods")
answers=$(mktemp); trap 'rm -f "$answers"' EXIT
for i in $(seq 40); do
  curl -fsS --max-time 5 "$INGRESS/api/knock" >>"$answers" || fail "knock $i got no answer"
  echo >>"$answers"
done
wrong=$(jq -rs --argjson n "$nodes" '.[] | select($n[.pod] == null or .node == null or $n[.pod] != .node) | "\(.pod) said \(.node), runs on \($n[.pod] // "no such pod")"' "$answers")
[ -z "$wrong" ] || fail "answers name the wrong node: $(head -1 <<<"$wrong")"

pass "POD_NAME and NODE_NAME come from the Downward API; 40 answers named their own pod's node"
