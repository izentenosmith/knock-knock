#!/usr/bin/env bash
# CE05 — the cluster job never publishes: in ci.yml as it stands in the tree, `cluster` exists,
# neither it nor the workflow's top level grants packages: write, `cluster` doesn't call
# publish.yml, and `publish` still needs only `smoke` (it doesn't wait for, or depend on,
# `cluster`). The runtime half (cluster's token holds no write scope) is C07's.
# Statically, against the workflow (GitHub's own reading of it is what C07 observes).
. "$(dirname "$0")/lib.sh"

wf=$(ruby -ryaml -rjson -e 'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))' \
  "$ROOT/.github/workflows/ci.yml") || fail "can't read ci.yml"

jq -e '.jobs.cluster' <<<"$wf" >/dev/null || fail "ci.yml has no job named cluster"
jq -e '(.jobs.cluster.uses // "") == ""' <<<"$wf" >/dev/null || fail "cluster calls a reusable workflow"
for scope in '.permissions' '.jobs.cluster.permissions'; do
  if jq -e "($scope // {}) | (type == \"string\" and test(\"write\")) or (type == \"object\" and .packages == \"write\")" <<<"$wf" >/dev/null; then
    fail "ci.yml grants packages: write at $scope"
  fi
done
# Nor can it push some other way: no secret, no registry login, no push, no pushing action.
pushes=$(jq -r '.jobs.cluster | tostring | [scan("secrets\\.[A-Za-z_]+|docker (?:login|push)|build-push-action|--push|imagetools create")] | unique | join(", ")' <<<"$wf")
[ -z "$pushes" ] || fail "the cluster job can push: $pushes"
needs=$(jq -c '.jobs.publish.needs | if type == "string" then [.] else . end' <<<"$wf")
[ "$needs" = '["smoke"]' ] || fail "publish needs $needs, expected only smoke"

pass "cluster holds no write scope and publish still needs only smoke"
