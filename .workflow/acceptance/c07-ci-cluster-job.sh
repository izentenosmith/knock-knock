#!/usr/bin/env bash
# C07 — a PR into dev runs ci.yml's job `cluster` green: it installs k3d v5.9.0, creates the
# cluster with the README's flags, applies k8s/, and passes the smoke test through the ingress
# with EXPECT_VERSION = the tag k8s/ pins and EXPECT_NODE_PREFIX=k3d-knock-, four languages
# answering. Its token holds contents: read and nothing that writes.
# Given: a PR into dev (PR=<number>, default: the newest one) whose head carries k8s/.
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh" # for images

read -r pr sha branch <<<"$(pick_pr dev)"
[ -n "${sha:-}" ] || fail "no PR into dev yet, so no CI run to observe"
git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || git -C "$ROOT" fetch -q origin "$sha"
pin=$( (git -C "$ROOT" grep -h -o -E 'knock-knock-[a-z]+:sha-[0-9a-f]{7}' "$sha" -- k8s 2>/dev/null || true) | sed 's/.*://' | sort -u)
[ -n "$pin" ] || fail "PR #$pr's head (${sha:0:7}) has no pinned images in k8s/"
[ "$(wc -w <<<"$pin")" -eq 1 ] || fail "PR #$pr's k8s/ pins more than one tag: $pin"
git -C "$ROOT" diff --quiet "$sha" "${TREE:-HEAD}" -- k8s \
  || fail "stale observation: PR #$pr's head (${sha:0:7}) has a different k8s/ from ${TREE:-HEAD}'s"

run=$(ci_run "$sha" pull_request "$branch")
IFS=$'\t' read -r job conclusion <<<"$(job_named "$run" cluster)"
[ -n "${job:-}" ] || fail "run $run has no job named cluster"
[ "$conclusion" = success ] || fail "job cluster concluded $conclusion in run $run"

out=$(job_output "$job")
[ -n "$out" ] || fail "can't read job cluster's output"
has "$out" 'k3d version v5\.9\.0' || fail "job cluster didn't run k3d v5.9.0"
nodes=$(grep -oE "Creating node '[^']+'" <<<"$out" | sort | tr '\n' ' ' || true)
[ "$nodes" = "Creating node 'k3d-knock-agent-0' Creating node 'k3d-knock-agent-1' Creating node 'k3d-knock-server-0' " ] \
  || fail "job cluster's k3d created '$nodes', expected one server and two agents"
has "$out" "portmapping '8080:80' targets the loadbalancer" || fail "job cluster didn't map 8080 to the loadbalancer"
# The images the run itself read from k8s/ are the tree's (the run checked out a merge ref).
ran=$(awk '/k8s\/ runs:$/ {on = 1; next} on && !done && /^  ghcr\.io\// {print $1; next} on {done = 1}' <<<"$out" | sort -u)
want=$(images | sort -u)
[ -n "$ran" ] || fail "job cluster didn't print the images it read from k8s/"
[ "$ran" = "$want" ] || fail "job cluster ran $(tr '\n' ' ' <<<"$ran"), the tree's k8s/ has $(tr '\n' ' ' <<<"$want")"
has "$out" '^[0-9]+ knocks on http://localhost:8080/api/knock$' -E || fail "job cluster's smoke didn't knock on the ingress (localhost:8080)"
has "$out" "version $pin in every answer" || fail "job cluster's smoke didn't check version $pin"
has "$out" 'node prefix k3d-knock- in every answer' || fail "job cluster's smoke didn't check the node prefix"
for lang in $BACKENDS; do
  grep -Eq "^[[:space:]]+$lang[[:space:]]+[0-9]+[[:space:]]*$" <<<"$out" || fail "the tally has no $lang line"
done
grep -Eq '^PASS[[:space:]]*$' <<<"$out" || fail "the smoke test didn't print PASS"

log=$(job_log "$job")
perms=$(awk -F'\t' '{print $3}' <<<"$log" | sed -E 's/^[^ ]+Z //' \
  | awk '/GITHUB_TOKEN Permissions/ {on = 1; next} on && /##\[endgroup\]/ {on = 0; done = 1} on && !done')
[ -n "$perms" ] || fail "no GITHUB_TOKEN Permissions section in job cluster's log"
writes=$(grep -i ': write' <<<"$perms" || true)
[ -z "$writes" ] || fail "job cluster's token can write: $(tr '\n' ' ' <<<"$writes")"
has "$perms" 'Contents: read' || fail "job cluster's token can't read contents"

pass "PR #$pr into dev ran cluster green (run $run): k3d v5.9.0, smoke through the ingress with $pin"
