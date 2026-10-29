# Shared helpers for the level-02 cluster tests (sourced after lib.sh, not run).
# The harness owns at most one k3d cluster, `knock`, created with the README's exact commands.
# It refuses to touch a `knock` cluster it didn't create, and refuses to start while something
# else holds port 8080 (compose, say). Needs: k3d, kubectl, docker, curl, jq, nc, ruby (YAML).

CLUSTER=knock
K8S="$ROOT/k8s"
INGRESS=http://localhost:8080
OWNED="$HERE/.cluster-owned"     # gitignored: id of the k3d server container this harness created
KUBECFG="$HERE/.cluster-kubeconfig" # gitignored: that cluster's kubeconfig, from k3d itself

# Only ever the harness's cluster: its own kubeconfig, written by k3d for the cluster it created,
# never the user's (whose k3d-knock context could point at another runtime's cluster).
kc() { kubectl --kubeconfig "$KUBECFG" --context "k3d-$CLUSTER" "$@"; }

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
owned() { [ -f "$OWNED" ] && [ -s "$KUBECFG" ] && [ -n "$(server_id)" ] && [ "$(server_id)" = "$(cat "$OWNED")" ]; }

# Waiting is the environment's job, never the smoke test's: every Deployment rolled out, then
# the ingress answering a knock.
wait_ready() {
  local d deployments
  deployments=$(kc get deployments -o name) || fail "can't list the Deployments"
  [ -n "$deployments" ] || fail "there are no Deployments to wait for"
  for d in $deployments; do
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
  rm -f "$OWNED" "$KUBECFG"
  command -v nc >/dev/null || fail "setup: nc is needed to check that port 8080 is free"
  ! nc -z localhost 8080 2>/dev/null || fail "refusing: port 8080 is taken (docker compose down first?)"
  k3d cluster create knock --agents 2 -p "8080:80@loadbalancer" >/dev/null 2>&1 || fail "k3d cluster create failed"
  server_id >"$OWNED"
  k3d kubeconfig get "$CLUSTER" >"$KUBECFG" || fail "can't get the new cluster's kubeconfig"
  kc apply -f "$K8S" >/dev/null || fail "kubectl apply -f k8s/ failed"
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
# A PR's merge state once GitHub has computed it (UNKNOWN for a while after a change).
merge_state() {
  local state="" i
  for i in $(seq 30); do
    state=$(gh pr view -R "$REPO" "$1" --json mergeStateStatus -q .mergeStateStatus)
    [ "$state" != UNKNOWN ] && break
    sleep 2
  done
  echo "$state"
}
# bind_run <run> <branch>: fails unless the run is a pull_request run of <branch> at the head of a
# PR from <branch> into dev (the throwaway scenario's own run, not any red run).
bind_run() {
  local event head_branch head_sha heads
  read -r event head_branch head_sha <<<"$(gh run view -R "$REPO" "$1" --json event,headBranch,headSha -q '"\(.event) \(.headBranch) \(.headSha)"')"
  [ -n "${head_sha:-}" ] || fail "can't read run $1"
  [ "$event $head_branch" = "pull_request $2" ] || fail "run $1 is a $event run of $head_branch, not this scenario's PR from $2"
  heads=$(gh pr list -R "$REPO" --head "$2" --base dev --state all --json headRefOid -q '.[].headRefOid')
  [ -n "$heads" ] || fail "there's no PR from $2 into dev"
  grep -qx "$head_sha" <<<"$heads" || fail "run $1's commit ${head_sha:0:7} isn't the head of a PR from $2 into dev"
}
# step <job> <name> → that step's conclusion (empty if there's no such step).
step() { steps_of "$1" | awk -F'\t' -v n="$2" '$1 == n {print $2}' | head -1; }
