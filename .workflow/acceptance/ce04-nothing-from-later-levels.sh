#!/usr/bin/env bash
# CE04 — nothing from later levels: k8s/ holds only Deployments, Services and Ingresses in the
# default namespace, with no probes (4), rollout tuning (5), replicas other than 1 or HPA (6),
# resources (7), topology spread / affinity / nodeSelector / nodeName / priority (8), ConfigMap,
# envFrom, secrets, volumes or DELAY_MS (9), kustomization (10), LoadBalancer or NodePort
# Service, external IPs, host ports or host network (3), init containers; and nothing in the
# backends, the frontend or k8s/ wires up CORS (3).
# Statically against k8s/ and the sources; no cluster.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

m=$(manifests)
# present: set to something (an empty list, an empty map, 0 or false count as absent).
check() { # <description> <jq filter selecting offending objects' names>
  local bad
  bad=$(jq -r 'def present: . != null and . != [] and . != {} and . != 0 and . != false; '"$2" <<<"$m" | tr '\n' ' ')
  [ -z "${bad// /}" ] || fail "$1: $bad"
}

kinds=$(jq -r '[.[].kind] | unique | join(" ")' <<<"$m")
[ "$kinds" = "Deployment Ingress Service" ] || fail "k8s/ holds kinds '$kinds', expected exactly Deployment Ingress Service"
check "objects outside the default namespace" '.[] | select((.metadata.namespace // "default") != "default") | .metadata.name'
check "replicas other than 1 (level 6)" '.[] | select(.kind == "Deployment" and (.spec.replicas // 1) != 1) | .metadata.name'
check "rollout tuning (level 5)" '.[] | select(.kind == "Deployment" and (.spec | (.strategy | present) or (.minReadySeconds | present) or (.progressDeadlineSeconds | present))) | .metadata.name'
pod='.[] | select(.kind == "Deployment") | .metadata.name as $n | .spec.template.spec'
check "probes (level 4)" "$pod | select(any(.containers[]; (.livenessProbe | present) or (.readinessProbe | present) or (.startupProbe | present))) | \$n"
check "requests/limits (level 7)" "$pod | select(any(.containers[]; .resources | present)) | \$n"
check "scheduling constraints (level 8)" "$pod | select([.topologySpreadConstraints, .affinity, .nodeSelector, .tolerations, .nodeName, .priorityClassName, .schedulerName] | any(present)) | \$n"
check "init containers (not part of level 2)" "$pod | select(.initContainers | present) | \$n"
check "volumes (not part of level 2; config from ConfigMaps and Secrets is level 9)" "$pod | select(.volumes | present) | \$n"
check "host ports or host network (level 3)" "$pod | select((.hostNetwork | present) or any(.containers[]; any(.ports[]?; .hostPort | present))) | \$n"
check "config from outside the pod (level 9)" "$pod | select(any(.containers[]; (.envFrom | present) or any(.env[]?; .name == \"DELAY_MS\" or (.valueFrom.configMapKeyRef | present) or (.valueFrom.secretKeyRef | present)) or ((.args // []) + (.command // []) | any(test(\"DELAY_MS\"))))) | \$n"
check "L4 exposure (level 3)" '.[] | select(.kind == "Service" and (((.spec.type // "ClusterIP") != "ClusterIP") or (.spec.externalIPs | present))) | .metadata.name'
ls "$K8S" | grep -qi '^kustomization' && fail "k8s/ has a kustomization (level 10)"

# CORS, however it's wired: a header, a library, an annotation. Every scanned place must exist,
# or the scan would pass on nothing.
for d in backends frontend k8s; do [ -d "$ROOT/$d" ] || fail "setup: $d/ is gone; point the CORS scan at its replacement"; done
cors=$(grep -rliE 'cors|access-control-allow' \
  --exclude-dir=node_modules --exclude-dir=target --exclude-dir=.venv --exclude-dir=venv \
  --exclude-dir=__pycache__ --exclude-dir=dist "$ROOT/backends" "$ROOT/frontend" "$ROOT/k8s") \
  && fail "something wires up CORS (level 3): $(tr '\n' ' ' <<<"$cors")"
[ $? -eq 1 ] || fail "the CORS scan failed"

pass "k8s/ is Deployments, Services and an Ingress, with nothing from levels 3–10"
