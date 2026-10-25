#!/usr/bin/env bash
# AT-06 — anonymous pull (also covers E10, "a private package shows up before level 2"):
# with no registry credentials, the sha-<7> images pull, each backend answers /api/knock with
# "version":"sha-<7>" and its own lang, and on this Mac the pulled variant is native.
# A private package fails here with an authentication error; that is the visible failure E10 wants.
# Given: main's head on GitHub (SHA=<sha> to pick another published commit).
. "$(dirname "$0")/lib.sh"

sha=${SHA:-$(remote_commit refs/heads/main)}
tag=$(version_of "$sha")
anon=$(mktemp -d); trap 'rm -rf "$anon"; docker rm -f at06 >/dev/null 2>&1 || true' EXIT
export DOCKER_HOST=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}
native=$(docker version --format '{{.Server.Arch}}')

for svc in $SERVICES; do
  ref="$IMAGE-$svc:$tag"
  docker rmi -f "$ref" >/dev/null 2>&1 || true
  out=$(DOCKER_CONFIG=$anon docker pull -q "$ref" 2>&1) || fail "anonymous pull of $ref failed: $out"
  [ "$(docker image inspect "$ref" --format '{{.Architecture}}')" = "$native" ] || fail "$ref isn't $native on this host"
done
for svc in $BACKENDS; do
  docker rm -f at06 >/dev/null 2>&1 || true
  docker run -d --name at06 -p 18131:8080 "$IMAGE-$svc:$tag" >/dev/null
  body=""
  for _ in $(seq 50); do body=$(curl -fs localhost:18131/api/knock 2>/dev/null) && break; sleep 0.2; done
  [ "$(jq -r .version <<<"$body")" = "$tag" ] || fail "$svc answered version '$(jq -r .version <<<"$body")', not $tag"
  [ "$(jq -r .lang <<<"$body")" = "$svc" ] || fail "$IMAGE-$svc answered lang '$(jq -r .lang <<<"$body")'"
done

pass "all five $tag images pull anonymously ($native); the backends answer version $tag"
