# Shared helpers for the level-02 cluster tests (sourced after lib.sh, not run).
# The harness owns at most one k3d cluster, `knock`, created with the README's exact commands.
# It refuses to touch a `knock` cluster it didn't create, and refuses to start while something
# else holds port 8080 (compose, say). Needs: k3d, kubectl, docker, curl, jq, nc, ruby (YAML).

CLUSTER=knock
K8S="$ROOT/k8s"
INGRESS=http://localhost:8080
OWNED="$HERE/.cluster-owned" # gitignored: id of the k3d server container this harness created

# Only ever the harness's cluster, whatever the current kubectl context is.
kc() { kubectl --context "k3d-$CLUSTER" "$@"; }

# Every object in k8s/ as one JSON array (read as YAML, the way kubectl reads the directory).
manifests() {
  local files=() f
  for f in "$K8S"/*.yaml "$K8S"/*.yml "$K8S"/*.json; do [ -f "$f" ] && files+=("$f"); done
  [ "${#files[@]}" -gt 0 ] || fail "no manifests in k8s/"
  ruby -ryaml -rjson -e 'puts JSON.generate(ARGV.flat_map { |f| YAML.load_stream(File.read(f)) }.compact)' "${files[@]}"
}

# Every image the Deployments in k8s/ run, init containers included.
images() { manifests | jq -r '.[] | select(.kind == "Deployment") | .spec.template.spec | (.initContainers // []) + .containers | .[].image'; }

# The one tag all five images in k8s/ share; fails if they don't share exactly one.
pinned_tag() {
  local tags
  tags=$(images | sed -E 's/^[^:]*://' | sort -u | tr '\n' ' ' | sed 's/ $//')
  [ -n "$tags" ] || fail "no images in k8s/"
  [ "$(wc -w <<<"$tags")" -eq 1 ] || fail "the images in k8s/ don't share one tag: $tags"
  echo "$tags"
}

server_id() { docker inspect -f '{{.Id}}' "k3d-$CLUSTER-server-0" 2>/dev/null || true; }
exists() { k3d cluster get "$CLUSTER" >/dev/null 2>&1; }
owned() { [ -f "$OWNED" ] && [ -n "$(server_id)" ] && [ "$(server_id)" = "$(cat "$OWNED")" ]; }

# Waiting is the environment's job, never the smoke test's: every Deployment rolled out, then
# the ingress answering a knock.
wait_ready() {
  local d
  for d in $(kc get deployments -o name); do
    kc rollout status "$d" --timeout="${1:-180}s" >/dev/null \
      || { kc get pods -o wide >&2; fail "$d didn't roll out"; }
  done
  local i
  for i in $(seq 60); do
    curl -fsS --max-time 2 "$INGRESS/api/knock" >/dev/null 2>&1 && return 0
    sleep 2
  done
  kc get pods -o wide >&2
  fail "the ingress never answered /api/knock"
}

# A new cluster from scratch, exactly as the README says, with k8s/ applied and ready.
fresh_cluster() {
  manifests >/dev/null
  if exists; then
    owned || fail "refusing: a k3d cluster '$CLUSTER' exists that this harness didn't create (delete it yourself: k3d cluster delete $CLUSTER)"
    k3d cluster delete "$CLUSTER" >/dev/null 2>&1
  fi
  rm -f "$OWNED"
  command -v nc >/dev/null || fail "setup: nc is needed to check that port 8080 is free"
  ! nc -z localhost 8080 2>/dev/null || fail "refusing: port 8080 is taken (docker compose down first?)"
  k3d cluster create knock --agents 2 -p "8080:80@loadbalancer" >/dev/null 2>&1 || fail "k3d cluster create failed"
  server_id >"$OWNED"
  kubectl --context "k3d-$CLUSTER" apply -f "$K8S" >/dev/null || fail "kubectl apply -f k8s/ failed"
  wait_ready
}

# The harness's cluster: reused if it's already up (holding exactly k8s/'s objects: whatever
# a previous tree applied and k8s/ no longer has is pruned), created from scratch otherwise.
cluster() {
  if owned; then
    manifests >/dev/null
    kc apply --prune --all -f "$K8S" >/dev/null || fail "kubectl apply --prune -f k8s/ failed"
    wait_ready
  else
    fresh_cluster
  fi
}

# Conclusion of each step of a GitHub job, as TSV: name, conclusion.
steps_of() { gh api "repos/$REPO/actions/jobs/$1" -q '.steps[] | [.name, .conclusion] | @tsv'; }
# step <job> <name> → that step's conclusion (empty if there's no such step).
step() { steps_of "$1" | awk -F'\t' -v n="$2" '$1 == n {print $2}' | head -1; }
