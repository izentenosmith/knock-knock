#!/usr/bin/env bash
# E10 (F22) — with every container healthy, a contract failure inside scripts/smoke.sh turns the
# smoke job red at the smoke step (so `smoke.sh | tee` can't hide it), and its FAIL line is output.
# ACTS: pushes branch acceptance/wrong-lang (the python backend answers lang "py"), opens a draft
# PR into dev, waits for CI, then closes it and deletes the branch. Observe only: RUN=<id>.
. "$(dirname "$0")/lib.sh"

branch=acceptance/wrong-lang
if acts; then
  work=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  git -C "$ROOT" fetch -q origin dev
  git -C "$ROOT" worktree add -q --detach "$work" origin/dev
  sed -i.bak 's/"lang": "python"/"lang": "py"/' "$work/backends/python/main.py" && rm "$work/backends/python/main.py.bak"
  grep -q '"lang": "py"' "$work/backends/python/main.py" || fail "setup: couldn't change python's lang"
  git -C "$work" commit -qam "test: python answers the wrong lang (acceptance E10, never merge)"
  git -C "$work" push -q -f origin "HEAD:refs/heads/$branch"
  sha=$(git -C "$work" rev-parse HEAD)
  gh pr create -R "$REPO" --base dev --head "$branch" --draft --title "acceptance E10: wrong lang (do not merge)" --body "Throwaway PR for acceptance test E10." >/dev/null
  RUN=$(wait_run "$sha" pull_request)
  gh pr close -R "$REPO" "$branch" --delete-branch >/dev/null
fi
[ -n "${RUN:-}" ] || fail "not observed yet: run with ACT=1 (pushes a throwaway PR, ask first) or set RUN=<id>"

fresh "$RUN"
IFS=$'\t' read -r job conclusion <<<"$(job_named "$RUN" smoke)"
[ "${conclusion:-}" = failure ] || fail "smoke concluded ${conclusion:-missing} in run $RUN, expected failure"
steps=$(gh run view -R "$REPO" "$RUN" --json jobs -q '.jobs[] | select(.name == "smoke") | .steps[] | "\(.name)\t\(.conclusion)"')
grep -q $'^Run docker compose up --build --wait -d\tsuccess$' <<<"$steps" || fail "compose didn't come up healthy, so this isn't a smoke.sh failure"
grep -Eq $'^Run scripts/smoke.sh.*\tfailure$' <<<"$steps" || fail "the smoke.sh step didn't fail: $(tr '\n' ' ' <<<"$steps")"
has "$(job_output "$job")" "^FAIL: expected answers from 'go python rust ts'" || fail "the FAIL line isn't in the output"

pass "a healthy stack with a wrong lang failed at the smoke.sh step (run $RUN)"
