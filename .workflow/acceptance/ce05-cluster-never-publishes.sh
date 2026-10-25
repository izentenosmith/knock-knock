#!/usr/bin/env bash
# CE05 — the cluster job never publishes: in ci.yml as it stands in the tree, `cluster` exists,
# neither it nor the workflow's top level grants packages: write, `cluster` doesn't call
# publish.yml and never mentions a secret, a login or a push, and `publish` still needs only
# `smoke`. Also the static half of CE06: nothing in `cluster` tolerates a red smoke test. The
# runtime halves are C07's (no write scope) and CE06's (a red smoke turns cluster red).
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
# Nor can it push some other way: the job never mentions a secret, a login or a push at all.
pushes=$(jq -r '.jobs.cluster | tostring | [scan("(?i)secrets|login|push")] | unique | join(", ")' <<<"$wf")
[ -z "$pushes" ] || fail "the cluster job mentions: $pushes"
# And a red smoke test always fails it: nothing tolerates a failure, and steps run in bash with
# pipefail (the workflow default), so `smoke.sh | tee` can't hide one.
jq -e '[.jobs.cluster | .. | objects | select(has("continue-on-error"))] | length == 0' <<<"$wf" >/dev/null \
  || fail "the cluster job tolerates a failure (continue-on-error)"
jq -e '.defaults.run.shell == "bash" and (.jobs.cluster.defaults.run.shell // "bash") == "bash" and ([.jobs.cluster.steps[] | .shell // "bash"] | all(. == "bash"))' <<<"$wf" >/dev/null \
  || fail "the cluster job doesn't run its steps in bash (pipefail)"
smoke_step=$(jq -r '.jobs.cluster.steps[] | select(.name == "Smoke test through the ingress") | .run' <<<"$wf")
[ -n "$smoke_step" ] || fail "the cluster job has no step 'Smoke test through the ingress'"
if grep -qE '\|\||; *true|exit 0' <<<"$smoke_step"; then fail "the smoke step swallows a failure: $smoke_step"; fi
needs=$(jq -c '.jobs.publish.needs | if type == "string" then [.] else . end' <<<"$wf")
[ "$needs" = '["smoke"]' ] || fail "publish needs $needs, expected only smoke"

pass "cluster can't publish, fails on a red smoke test, and publish still needs only smoke"
