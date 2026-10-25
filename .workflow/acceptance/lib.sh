# Shared helpers for the level-01 acceptance tests (sourced, not run).
# Black box only: what GitHub, GHCR and the smoke CLI report from the outside.
# Needs: bash, git, gh (authenticated), docker (buildx), curl, jq.
set -euo pipefail

REPO=izentenosmith/knock-knock
IMAGE=ghcr.io/izentenosmith/knock-knock
SERVICES="go python rust ts frontend"
BACKENDS="go python rust ts"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
version_of() { printf 'sha-%s' "${1:0:7}"; }

# Tests marked ACTS push branches, tags or PRs, or re-run workflows on the public repo.
# They only act with ACT=1 (ask the user first); otherwise they observe RUN=<id> if given.
acts() { [ "${ACT:-}" = 1 ]; }

# Commit a remote ref points at (peels annotated tags). Empty when the ref doesn't exist.
remote_commit() {
  git ls-remote "https://github.com/$REPO" "$1" "$1^{}" | sort -k2 | awk '{c = $1} END {print c}'
}

# PR=<number> if given, else the newest PR (any state) into <base>, optionally from <head>,
# ignoring the throwaway acceptance/* PRs. Prints "<number> <head sha> <head branch>".
pick_pr() {
  if [ -n "${PR:-}" ]; then
    gh pr view -R "$REPO" "$PR" --json number,headRefOid,headRefName -q '"\(.number) \(.headRefOid) \(.headRefName)"'
  else
    gh pr list -R "$REPO" --base "$1" ${2:+--head "$2"} --state all --limit 30 --json number,headRefOid,headRefName \
      -q '[.[] | select(.headRefName | startswith("acceptance/") | not)][0] // empty | "\(.number) \(.headRefOid) \(.headRefName)"' 2>/dev/null || true
  fi
}

# A run is only evidence about the tree under test (TREE, default HEAD) if it ran the same
# workflows and scripts. HISTORY=1 marks a test that deliberately observes a past release.
fresh() {
  [ "${HISTORY:-}" = 1 ] && return 0
  local sha
  sha=$(gh run view -R "$REPO" "$1" --json headSha -q .headSha)
  git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || git -C "$ROOT" fetch -q origin "$sha"
  git -C "$ROOT" diff --quiet "$sha" "${TREE:-HEAD}" -- .github/workflows scripts \
    || fail "stale observation: run $1 ran the workflows/scripts of ${sha:0:7}, not ${TREE:-HEAD}'s (re-run with ACT=1)"
}

# Newest run of <workflow file> for <sha>, <event> and optional <head branch or tag>; it must have
# finished, and (unless HISTORY=1) have run the tree's workflows.
wf_run() {
  local runs id status
  runs=$(gh run list -R "$REPO" --workflow "$1" --commit "$2" --event "$3" ${4:+--branch "$4"} \
    --limit 1 --json databaseId,status 2>/dev/null) || fail "no $1 workflow in $REPO"
  id=$(jq -r '.[0].databaseId // empty' <<<"$runs")
  status=$(jq -r '.[0].status // empty' <<<"$runs")
  [ -n "$id" ] || fail "no $1 run for a $3 event on ${2:0:7}${4:+ ($4)}"
  [ "$status" = completed ] || fail "$1 run $id is still $status"
  fresh "$id"
  echo "$id"
}
ci_run() { wf_run ci.yml "$@"; }

# Wait for a run of ${WF:-ci.yml} for <sha>/<event> (and optional <head branch>) to appear and
# finish; prints its id. (ACT mode only.)
wait_run() {
  local id="" i
  for i in $(seq 60); do
    id=$(gh run list -R "$REPO" --workflow "${WF:-ci.yml}" --commit "$1" --event "$2" ${3:+--branch "$3"} --limit 1 \
      --json databaseId -q '.[0].databaseId // empty' 2>/dev/null || true)
    [ -n "$id" ] && break
    sleep 5
  done
  [ -n "$id" ] || fail "no ${WF:-ci.yml} run appeared for a $2 event on ${1:0:7}"
  gh run watch -R "$REPO" "$id" >/dev/null 2>&1 || true
  echo "$id"
}

# Jobs of a run as TSV: name, conclusion, id.
jobs_of() { gh run view -R "$REPO" "$1" --json jobs -q '.jobs[] | [.name, .conclusion, (.databaseId|tostring)] | @tsv'; }
# Id and conclusion of the job named exactly <name>.
job_named() { jobs_of "$1" | awk -F'\t' -v n="$2" '$1 == n {print $3 "\t" $2}' | head -1; }
# Jobs under a call to publish.yml: <caller> is `dry-run` or `publish` (default: both).
publish_jobs() {
  jobs_of "$1" | awk -F'\t' -v c="${2:-}" '{
    for (i = 0; i < 2; i++) { n = (c != "" ? c : (i ? "dry-run" : "publish")); if ($1 == n || index($1, n " / ") == 1) { print; next } }
  }'
}
# Logs are always captured whole before they are searched: `gh … | grep -q` under pipefail
# reports a SIGPIPE'd gh as failure, which hides exactly the match it was looking for.
job_log() { gh run view -R "$REPO" --job "$1" --log; }
# has <text> <pattern> [grep flags]: whether a captured text matches, without a pipe.
has() { grep -q ${3:-} -- "$2" <<<"$1"; }
# What a job printed: its log without the step scripts and env that GitHub echoes into each
# step's "Run …" header, so an assertion can't be satisfied by the script's own text.
job_output() {
  job_log "$1" | cut -f3- | sed -E 's/^[^ ]+Z //' \
    | awk '/##\[group\]Run / {skip = 1; next} skip && /##\[endgroup\]/ {skip = 0; next} !skip'
}

# Registry probes. Each fails red when the image or tag does not exist.
manifest() { docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>/dev/null || fail "$1 not found in GHCR"; }
digest() { manifest "$1" | jq -r .digest; }
platforms() { manifest "$1" | jq -r '[.manifests[].platform | "\(.os)/\(.architecture)"] | sort | join(" ")'; }
labels() { docker buildx imagetools inspect "$1" --format '{{json .Image}}' | jq -c --arg p "$2" '.[$p].config.Labels'; }
# Whether a tag exists, through the pipeline's own strict lookup: a registry error fails the test.
exists_in_ghcr() {
  local d
  d=$("$ROOT/scripts/image-digest.sh" "$1") || fail "can't tell whether $1 exists"
  [ -n "$d" ]
}
