#!/usr/bin/env bash
# C06 — the Ingress routes `/` (prefix) to the frontend Service, and nothing routes to knock-api:
# /api/knock reaches a backend only through the frontend's nginx. Through the ingress, GET /
# returns the frontend's page and a client-side route falls back to it too.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

cluster

ing=$(kc get ingress -o json)
[ "$(jq '.items | length' <<<"$ing")" -ge 1 ] || fail "there's no Ingress"
# The Service(s) the Ingress sends traffic to, and the path(s) it matches.
backends=$(jq -r '[.items[] | (.spec.defaultBackend.service.name // empty), (.spec.rules[]?.http.paths[]?.backend.service.name)] | unique | join(" ")' <<<"$ing")
root=$(jq -r '[.items[].spec.rules[]?.http.paths[]? | select(.path == "/" and .pathType == "Prefix") | .backend.service.name] | unique | join(" ")' <<<"$ing")
[ -n "$root" ] || fail "no Ingress rule routes path / (Prefix)"
[[ " $backends " != *" knock-api "* ]] || fail "the Ingress routes straight to knock-api"
[ "$backends" = "$root" ] || fail "the Ingress routes to '$backends', expected only the frontend ($root)"

# The Service at / is the frontend's: it selects the pod running the frontend image.
sel=$(kc get service "$root" -o json | jq -c '.spec.selector // {}')
images=$(kc get pods -o json | jq -r --argjson s "$sel" '.items[] | select(.metadata.labels as $l | $s != {} and all($s | to_entries[]; $l[.key] == .value)) | .spec.containers[].image' | sort -u)
[[ "$images" == "$IMAGE-frontend:"* ]] && [ "$(wc -l <<<"$images" | tr -d ' ')" -eq 1 ] \
  || fail "Service $root (behind /) runs '$(tr '\n' ' ' <<<"$images")', not the frontend"

for path in / /some/client/route; do
  html=$(curl -fsS --max-time 5 "$INGRESS$path") || fail "GET $path through the ingress failed"
  has "$html" '<title>knock-knock</title>' || fail "GET $path through the ingress isn't the frontend's page"
done
answer=$(curl -fsS --max-time 5 "$INGRESS/api/knock") || fail "GET /api/knock through the ingress failed"
jq -e '.lang' <<<"$answer" >/dev/null || fail "/api/knock through the ingress isn't a signature"

pass "the Ingress sends / to $root (the frontend), and /api/ goes on through nginx"
