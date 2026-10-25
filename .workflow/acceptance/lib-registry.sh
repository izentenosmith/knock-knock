# A real registry at the boundary for the local tests: registry:2 on localhost:5055.
# Sourced after lib.sh. Seeds images from the locally built compose images.
REG=localhost:5055
registry_up() {
  docker inspect kk-registry >/dev/null 2>&1 || docker run -d --name kk-registry -p 5055:5000 registry:2 >/dev/null
  for _ in $(seq 50); do curl -fs "http://$REG/v2/" >/dev/null && return; sleep 0.1; done
  fail "local registry didn't start"
}
# seed <local image> <repo:tag> [label=value ...]: push an image (optionally relabelled) to the local registry
seed() {
  local src=$1 dst=$2; shift 2
  if [ $# -gt 0 ]; then
    printf 'FROM %s\n' "$src" | docker build -q $(printf -- '--label %s ' "$@") -t "$REG/$dst" - >/dev/null
  else
    docker tag "$src" "$REG/$dst"
  fi
  docker push -q "$REG/$dst" >/dev/null
}
