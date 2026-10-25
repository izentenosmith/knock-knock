#!/usr/bin/env bash
# CE04 — nothing from later levels: k8s/ holds only Deployments, Services and Ingresses in the
# default namespace, with no probes (4), rollout strategy (5), replicas other than 1 or HPA (6),
# resources (7), topology spread / affinity / nodeSelector / nodeName / priority (8), ConfigMap,
# envFrom, secrets or DELAY_MS (9), kustomization (10), LoadBalancer or NodePort Service, host
# ports or host network (3), init containers; and nothing sends CORS (3).
# Statically against k8s/ and the backends' sources; no cluster.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

m=$(manifests)
check() { # <description> <jq filter selecting offending objects' names>
  local bad
  bad=$(jq -r "$2" <<<"$m" | tr '\n' ' ')
  [ -z "${bad// /}" ] || fail "$1: $bad"
}

kinds=$(jq -r '[.[].kind] | unique | join(" ")' <<<"$m")
[ "$kinds" = "Deployment Ingress Service" ] || fail "k8s/ holds kinds '$kinds', expected exactly Deployment Ingress Service"
check "objects outside the default namespace" '.[] | select((.metadata.namespace // "default") != "default") | .metadata.name'
check "replicas other than 1 (level 6)" '.[] | select(.kind == "Deployment" and (.spec.replicas // 1) != 1) | .metadata.name'
check "rollout tuning (level 5)" '.[] | select(.kind == "Deployment" and (.spec.strategy or .spec.minReadySeconds or .spec.progressDeadlineSeconds)) | .metadata.name'
pod='.[] | select(.kind == "Deployment") | .metadata.name as $n | .spec.template.spec'
check "probes (level 4)" "$pod | select(any(.containers[]; .livenessProbe or .readinessProbe or .startupProbe)) | \$n"
check "requests/limits (level 7)" "$pod | select(any(.containers[]; .resources != null)) | \$n"
check "scheduling constraints (level 8)" "$pod | select(.topologySpreadConstraints or .affinity or .nodeSelector or .tolerations or .nodeName or .priorityClassName or .schedulerName) | \$n"
check "init containers (not part of level 2)" "$pod | select(.initContainers) | \$n"
check "host ports or host network (level 3)" "$pod | select(.hostNetwork or any(.containers[]; any(.ports[]?; .hostPort))) | \$n"
check "config from outside the pod (level 9)" "$pod | select(any(.containers[]; .envFrom or any(.env[]?; .name == \"DELAY_MS\" or .valueFrom.configMapKeyRef or .valueFrom.secretKeyRef) or ((.args // []) + (.command // []) | any(test(\"DELAY_MS\"))))) | \$n"
check "L4 exposure (level 3)" '.[] | select(.kind == "Service" and (((.spec.type // "ClusterIP") != "ClusterIP") or .spec.externalIPs)) | .metadata.name'
ls "$K8S" | grep -qi '^kustomization' && fail "k8s/ has a kustomization (level 10)"
[ -f "$ROOT/frontend/nginx.conf" ] || fail "setup: frontend/nginx.conf is gone; point the CORS check at the frontend's config"
cors=$(grep -rliE 'cors|access-control-allow' --exclude-dir=node_modules --exclude-dir=target --exclude-dir=.venv \
  "$ROOT/backends" "$ROOT/frontend/nginx.conf" || true)
[ -z "$cors" ] || fail "something wires up CORS (level 3): $(tr '\n' ' ' <<<"$cors")"

pass "k8s/ is Deployments, Services and an Ingress, with nothing from levels 3–10"
