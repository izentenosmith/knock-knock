# Ledger: level-01-pipeline

Append-only. Finding and smell ids are stable across iterations.

## Iteration 1

### Smells
- **B1** Dispensables / Duplicate Code at `publish.yml`: the GHCR digest lookup was
  pasted into the guard and the promotion, with a third ad-hoc inspect after the push.
  Blocking: these copies decide whether a tag exists, and divergence would make the guard
  and the promotion disagree about immutability. Fixed: Extract Function into
  `scripts/image-digest.sh` (PR #9, released in #10 as `3b78dd7`).
- **W1** Change Preventers / Shotgun Surgery at `publish.yml`: the five images were listed
  twice (the build `include` and the promote `service` list). Fixed: one list shared
  through the YAML anchor `&images` (PR #9).
- **W2** Dispensables / Duplicate Code at `ci.yml`, in the version step:
  `sha-${GITHUB_SHA::7}` was computed twice. Fixed: local variable (PR #9).
- **N1** Dispensables / Duplicate Code at `publish.yml`: the one-line `docker login` step
  appears in both `build` and `promote`. Noted: one line, and a composite action would
  cost more than it saves.
  - **Promote if:** a third job needs to log in, or the login changes (an action, another
    registry).
- **N2** Bloaters / Long Method (mild) at `publish.yml`, in the build step: it branches
  on `PUSH` twice (output flag, summary line). Noted: two modes, readable as written.
  - **Promote if:** a third build mode appears, or the step grows beyond the build and
    its summary.
- **N3** Dispensables / Duplicate Code: the service list lives in both `compose.yaml` and
  `publish.yml`. Noted: accepted by the architect (Q2), true duplication that can't be
  unified without parsing compose in YAML.
  - **Promote if:** a service is added and one of the two lists is forgotten, or at level 10.

### Verification
- Pre-refactor: acceptance suite 16/16 green.
- Post-refactor: acceptance suite 16/16 green. The refactored paths were exercised by:
  - PR #9 into `dev`: `smoke`;
  - PR #10 from `dev` into `main`: the dry run with the anchored list;
  - the `main` push run 40139376235: the guard's "absent" branch and the post-push
    digest;
  - its re-run (attempt 2): the guard's "exists" branch, with every digest unchanged.
- **Not exercised:** the refactored `promote` job (now with checkout plus
  `scripts/image-digest.sh`). A re-run uses the workflow at its own commit, and
  `level-01-pipeline` sits on `52dd932`, before the refactor. The next `level-*` tag is
  the first run of it.

### Findings (unadjudicated)
Four read-only delegates, one per surface: acceptance-test integrity (A), workflow edge
cases (W), security (S), contracts/docs (D). Duplicates are merged; sources are given as
delegate+number. Ranked most severe first.

#### F1
- **Target:** promotion (AT-07, e05, e06) after the refactor
- **Claim challenged:** level tags promote at the same digest, refuse unpublished commits and re-run as a no-op
- **Evidence:** The refactor rewrote `promote` (added checkout, `scripts/image-digest.sh`, `include: *images`). `level-01-pipeline` sits on `52dd932`, before the refactor. A re-run uses the workflow from its own commit, and e05/e06/07 observe runs and registry state that the old code produced. With immutable tags and fixed run ids, those tests stay green whatever the current promote does. (A1, W14)
- **Breaking case:** delete the new checkout from `promote` → `scripts/image-digest.sh` is missing (exit 127) on the next level tag; 07, e05 and e06 all stay green
- **Confidence:** proven for 07/e06; unproven whether e05/e01/e08/e09 ran pre-refactor
- **Would be settled by:** `gh run view <id> --json headSha` for the e05/e01/e08/e09 runs, then `git merge-base --is-ancestor dc44a0d <sha>`
- **Severity hint:** blocker

#### F2
- **Target:** "only smoke-tested images are published"
- **Claim challenged:** the image pushed as `sha-<7>` is the image that passed smoke
- **Evidence:** smoke tests compose-built amd64 images on one runner. Publish rebuilds from scratch with buildx (amd64 and arm64) in another job, from floating base tags. No digest or artifact ties the two together. Tag runs rebuild in smoke, then promote other bytes. (W1, W11, S8, D5)
- **Breaking case:** delete `--build-arg VERSION="$VERSION"` from publish's build → smoke, guard and push all green; every published backend answers `"version":"dev"`, and no check in the pipeline fails
- **Confidence:** proven (the mutation survives the pipeline; AT-06 would catch it after the fact)
- **Severity hint:** major

#### F3
- **Target:** README Pipeline step 5 (the release command)
- **Claim challenged:** the shown `git tag -a level-NN-… && git push` promotes the release
- **Evidence:** the command tags HEAD. Nothing says to check out an up-to-date `main` merge commit. On `dev`, or on a stale local `main`, the tag lands on an unpublished commit, promote fails "never published from main", and the ruleset makes the tag unfixable forever. (D1)
- **Breaking case:** on `dev` (73b1c6d), run the command with `level-02-cluster` → promote fails for all 5 → the level name is permanently stuck on a commit with no images
- **Confidence:** proven
- **Severity hint:** major

#### F4
- **Target:** ordering of the main publish and the tag promotion
- **Claim challenged:** pushing the tag after the merge promotes the images
- **Evidence:** the main run and the tag run are in different concurrency groups. Promote only waits for its own smoke, and the docs never say to wait for main to go green. (D2, W5)
- **Breaking case:** merge, then push the tag right away → the tag's promote runs while main is still building rust/go under QEMU → those services fail "never published from main"; the level is split across services until someone re-runs the failed jobs
- **Confidence:** proven (traced; timing is the variable)
- **Severity hint:** major

#### F5
- **Target:** the `dev`→`main` gate
- **Claim challenged:** the dry-run publish gates the merge into main
- **Evidence:** `main` requires only `smoke` and `only-dev-to-main`. The `publish / build (…)` checks aren't required, so a red arm64 dry run is still mergeable, and the real publish then fails after the merge. (D3)
- **Breaking case:** a Dockerfile that builds on amd64 but fails under QEMU arm64 → PR mergeable → `main` publish red → a release commit with no images
- **Confidence:** proven
- **Severity hint:** major

#### F6
- **Target:** concurrency on `main`
- **Claim challenged:** main runs are never cancelled, so every merge to main is published
- **Evidence:** `cancel-in-progress: false` only protects the running run. GitHub keeps one pending run per group, and a newer queued run cancels the pending one. (W2, D6)
- **Breaking case:** merges A, B and C in quick succession → B cancelled while pending → `sha-<B>` never exists; a later level tag on B fails permanently
- **Confidence:** proven (documented platform semantics)
- **Severity hint:** major

#### F7
- **Target:** promotion on a tag *deletion* push
- **Claim challenged:** a level tag only ever receives its own commit's `sha-<7>`
- **Evidence:** nothing checks `github.event.deleted`. For a push that deletes a ref, `GITHUB_SHA` reverts to the default-branch tip. (W3)
- **Breaking case:** a level tag lands on the wrong commit and the user deletes it (possible before the ruleset, or with a bypass) → the deletion run promotes the main tip under that name → re-pushing the right commit fails "immutable"
- **Confidence:** unproven (with the ruleset active, deletion is blocked)
- **Would be settled by:** check whether a delete push of a `level-*` tag triggers ci.yml (GitHub docs on push events for deleted tags), or push and delete a throwaway tag that matches the trigger
- **Severity hint:** major

#### F8
- **Target:** `scripts/image-digest.sh` classification
- **Claim challenged:** "a flaky registry never reads as absent"
- **Evidence:** `grep -Eqi 'not found|403 Forbidden|denied'` runs over the whole combined output, including the request URL (which contains the tag) and local errors (`permission denied`, `command not found`). In the guard, "absent" means rebuild and push; in promote's `dst` lookup it means overwrite. Separately, every lookup in CI runs after `docker login` (authenticated), but the 403 branch was reasoned from an anonymous probe. (W4, S9, W13)
- **Breaking case:** a level tag named `level-05-denied-routes` plus a transient 5xx on the `dst` lookup → the output contains "denied" via the URL → read as absent → `imagetools create` overwrites the level tag
- **Confidence:** unproven (the error text is assumed)
- **Would be settled by:** run image-digest.sh against an unreachable or 5xx registry with a ref containing "denied" (expect exit 1, get exit 0); inspect an authenticated lookup of a missing GHCR package
- **Severity hint:** major

#### F9
- **Target:** `only-dev-to-main`
- **Claim challenged:** only this repo's `dev` can open a mergeable PR into main
- **Evidence:** the job compares only `github.head_ref` (the bare branch name), never the head repo. A fork's branch called `dev` passes. (S1, D11)
- **Breaking case:** PR `forker:dev → main` → `only-dev-to-main` green
- **Confidence:** proven
- **Severity hint:** major

#### F10
- **Target:** `only-dev-to-main` after the PR's base is changed
- **Claim challenged:** a feature PR into main is always blocked
- **Evidence:** `pull_request` uses the default activity types (no `edited`). On a PR into dev the job is skipped, which counts as success on the head SHA. Changing the base to main starts no new run. (S2)
- **Breaking case:** open `feature → dev`, let the checks pass, change the base to `main` → both required checks already green on that SHA → mergeable
- **Confidence:** unproven
- **Would be settled by:** open a throwaway PR into dev, change its base to main, and check whether the merge is allowed and whether a run starts
- **Severity hint:** major

#### F11
- **Target:** required checks as an integrity gate
- **Claim challenged:** a green `smoke`/`only-dev-to-main` means the repo's pipeline passed
- **Evidence:** `pull_request` runs the PR's own `ci.yml`. A PR can rewrite both jobs to `exit 0`, and binding them to the Actions app doesn't prevent that. (S3)
- **Breaking case:** a PR whose `ci.yml` makes both jobs `exit 0` → both required checks green
- **Confidence:** proven (documented behaviour)
- **Severity hint:** major

#### F12
- **Target:** registry-side immutability
- **Claim challenged:** "images are never overwritten"; "level tags can't be moved"
- **Evidence:** the ruleset protects git refs only. Any workflow run in the repo (an unprotected branch with its own workflow file, a same-repo PR, a tag on any commit) can request `packages: write` on the linked packages and push or retag anything. GHCR tags can also be changed or deleted from the UI. The checks in `publish.yml` bind only the official path. (S4, S5)
- **Breaking case:** push branch `x` with a workflow that pushes `knock-knock-rust:level-02-cluster` ahead of time → the real promotion later fails "immutable" while the planted image is what users pull
- **Confidence:** proven (needs write access)
- **Severity hint:** major

#### F13
- **Target:** the tag ruleset
- **Claim challenged:** level tags are controlled
- **Evidence:** the rules are deletion and update only; creating a tag on any commit, including one on an unprotected branch with its own workflow, is unrestricted. (S6)
- **Breaking case:** `git tag level-99-x <commit on branch y>` and push it → branch y's ci.yml runs with whatever permissions it declares
- **Confidence:** proven
- **Severity hint:** major

#### F14
- **Target:** test e06
- **Claim challenged:** e06 proves the re-run was a no-op
- **Evidence:** in observe mode `before` is taken just before the comparison, so the digest check is vacuous. `grep no-op` matches the script text GitHub echoes in every step header. (A2)
- **Breaking case:** remove the `dst = src` branch (always `imagetools create`) → e06 still passes
- **Confidence:** proven
- **Severity hint:** major

#### F15
- **Target:** test e05
- **Claim challenged:** e05 proves the failure says "never published from main"
- **Evidence:** the grep matches the echoed script in the step header, and any failed publish job counts. (A3)
- **Breaking case:** make promote fail for any other reason (missing script) → e05 passes
- **Confidence:** proven
- **Severity hint:** major

#### F16
- **Target:** test e03
- **Claim challenged:** e03 proves every service was skipped as "already exists"
- **Evidence:** gh prefixes each log line with the job name, and the echoed guard script contains "already exists", so the grep matches on every run. Only the digest comparison is real. (A4)
- **Breaking case:** the guard never sets `skip` but the rebuild happens to be digest-identical → still passes
- **Confidence:** proven
- **Severity hint:** major

#### F17
- **Target:** test e01
- **Claim challenged:** e01 proves a red smoke blocks publish
- **Evidence:** its broken PR targets dev, where `publish` is skipped by its `if:` whatever smoke does. (A5)
- **Breaking case:** remove `needs: smoke` → e01 unchanged, passes
- **Confidence:** proven
- **Severity hint:** major

#### F18
- **Target:** AT-04 "GHCR unchanged"
- **Claim challenged:** AT-04 proves the dry run pushed nothing
- **Evidence:** it probes `sha-<PR head 7>`, but on `pull_request` the version comes from the merge commit `refs/pull/N/merge`. (A6)
- **Breaking case:** the dry run pushes `sha-<merge7>` → the probe on `sha-<head7>` finds nothing → passes
- **Confidence:** proven
- **Severity hint:** major

#### F19
- **Target:** AT-04 "built for both platforms"
- **Claim challenged:** AT-04 proves every service was built for amd64 and arm64
- **Evidence:** `knock-knock-<svc>` is printed in the env block of every step header, and "linux/amd64 and linux/arm64" is printed by the hard-coded dry-run echo. (A7)
- **Breaking case:** `--platform linux/amd64` only → the echo still names both → passes
- **Confidence:** proven
- **Severity hint:** major

#### F20
- **Target:** test e08 (injection)
- **Claim challenged:** no `uid=` in the log means the branch name was not executed
- **Evidence:** an inlined `$(id)` would expand inside the `[ … ]` argument and never be printed. (A8)
- **Breaking case:** inline `${{ github.head_ref }}` into the run script → `id` executes → e08 passes
- **Confidence:** proven
- **Severity hint:** major

#### F21
- **Target:** e09, half 1
- **Claim challenged:** "main and tag runs are never cancelled" is verified
- **Evidence:** it only scans history, and no overlapping main or tag runs were ever produced. (A9)
- **Breaking case:** `cancel-in-progress: true` everywhere → passes
- **Confidence:** proven
- **Severity hint:** major

#### F22
- **Target:** the `smoke.sh | tee` pipefail fix
- **Claim challenged:** a failing smoke.sh turns the job red
- **Evidence:** no test makes smoke.sh itself fail in CI. e01's failure probably comes from `compose up --wait`. (A10)
- **Breaking case:** remove `defaults.run.shell: bash` → no test goes red
- **Confidence:** unproven
- **Would be settled by:** check which step failed in run 40103856608
- **Severity hint:** major

#### F23
- **Target:** least privilege of the dry run
- **Claim challenged:** PR runs never hold registry write
- **Evidence:** the dry-run `build` gets `packages: write` and `publish` doesn't depend on `only-dev-to-main`, so a same-repo PR from any branch into main gets a write token. `actions/checkout` keeps that token in `.git/config` by default. (S7, W12)
- **Breaking case:** a same-repo `feature → main` PR → the build job holds a write token stored on disk
- **Confidence:** proven
- **Severity hint:** minor

#### F24
- **Target:** post-push and post-promote verification; how faithful the refactor was
- **Claim challenged:** the summaries report verified digests, and the refactor kept behaviour
- **Evidence:** the post-push lookup now goes through image-digest.sh, which exits 0 with empty output on "not found" (before the refactor, inspect failing failed the step). After `imagetools create`, `dst` is never re-read. (D4, W8, D8)
- **Breaking case:** the post-push read says "not found" (lag) → step green with `pushed … @ ` and no digest
- **Confidence:** proven (the behaviour change); unproven (re-encoding by imagetools)
- **Would be settled by:** compare the `:level-01-pipeline` and `:sha-52dd932` digests for all five
- **Severity hint:** minor

#### F25
- **Target:** guard and promote trust a 7-character tag
- **Claim challenged:** if `sha-<7>` exists, it is this commit's image
- **Evidence:** neither compares the `revision` label with `GITHUB_SHA`; 7 hex characters can collide or be planted (F12). (S10, W7)
- **Breaking case:** a colliding or planted `sha-<7>` → main skips the build → the level tag promotes foreign bytes
- **Confidence:** proven (low probability)
- **Severity hint:** minor

#### F26
- **Target:** credentials on the runner
- **Claim challenged:** the token is only exposed to the login step
- **Evidence:** `docker login` writes `~/.docker/config.json` and checkout writes `.git/config`; both are readable by every later step, including third-party actions. (S11)
- **Breaking case:** a compromised step in build or promote reads a `packages: write` token
- **Confidence:** proven
- **Severity hint:** minor

#### F27
- **Target:** reach of `enforce_admins` and "no bypass"
- **Claim challenged:** the protections bind the owner
- **Evidence:** an admin can edit or disable both at will. (S12)
- **Breaking case:** a stolen owner session disables protection, pushes, and re-enables it
- **Confidence:** proven
- **Severity hint:** minor

#### F28
- **Target:** tag pushes
- **Claim challenged:** pushing a level tag always triggers promotion
- **Evidence:** GitHub creates no push events when more than 3 tags are pushed at once. (W6)
- **Breaking case:** `git push --tags` with 4 or more new tags → no runs, nothing promoted, silently
- **Confidence:** proven (documented)
- **Severity hint:** minor

#### F29
- **Target:** level tag name validation
- **Claim challenged:** every `level-*` git tag is a valid `level-NN-<slug>` image tag
- **Evidence:** nothing checks the format. `level-2-x` publishes a permanent tag in the wrong format; `level-x@sha256:…` becomes a digest reference with spurious results. (D7, W15)
- **Breaking case:** `level-2-cluster` → a permanent, mis-sorted tag that can't be removed
- **Confidence:** proven
- **Severity hint:** minor

#### F30
- **Target:** EXPECT_VERSION in CI
- **Claim challenged:** CI proves every backend reports `sha-<7>`
- **Evidence:** the check is skipped silently when the variable is empty (for example, a renamed step id makes `env.VERSION` empty). (W9)
- **Breaking case:** drop the step's `EXPECT_VERSION` env → smoke prints PASS
- **Confidence:** proven
- **Severity hint:** minor

#### F31
- **Target:** CI readiness
- **Claim challenged:** `compose up --wait` means the API is ready
- **Evidence:** the frontend has no healthcheck, so `--wait` returns once nginx is merely running, and smoke's first curl has no retry. (D13, W10)
- **Breaking case:** nginx binds slowly → "knock 1 of 40 got no answer" → red required check, flaky
- **Confidence:** unproven
- **Would be settled by:** repeated CI or local `up --wait && smoke.sh` runs
- **Severity hint:** minor

#### F32
- **Target:** smoke job summary
- **Claim challenged:** the summary shows the smoke result
- **Evidence:** on failure, pipefail stops the step before the summary is written, and FAIL goes to stderr, not to `smoke.txt`. (W16)
- **Breaking case:** a failing smoke → empty summary
- **Confidence:** proven
- **Severity hint:** minor

#### F33
- **Target:** build volume
- **Claim challenged:** each commit is built a sensible number of times
- **Evidence:** dev push plus PR sync builds the same SHA twice; one release is at least 4 compose builds and 2 QEMU sets. (W17)
- **Breaking case:** n/a (cost)
- **Confidence:** proven
- **Severity hint:** minor

#### F34
- **Target:** PLAN §1/§2 accuracy
- **Claim challenged:** "every Dockerfile multi-stage, passes VERSION"; "8–150 MB"; `scripts/` lists only smoke.sh
- **Evidence:** python and ts are single-stage, the frontend has no `ARG VERSION`, sizes go up to 237 MB, and `image-digest.sh` isn't listed. Publish passes `--build-arg VERSION` to the frontend, which never consumes it. (D9, D10)
- **Breaking case:** n/a (docs contradict the files)
- **Confidence:** proven
- **Severity hint:** minor

#### F35
- **Target:** README/PLAN "VERSION = sha-<7>", and the EXPECT_VERSION example
- **Claim challenged:** the version is the commit's SHA; the README example works
- **Evidence:** on PRs the version comes from the merge commit's SHA. `EXPECT_VERSION=sha-3f9c2a1 scripts/smoke.sh` against the quickstart always fails (compose defaults to `dev`), and the README doesn't say to use `VERSION=… docker compose up --build`. (D12)
- **Breaking case:** follow the README example → FAIL
- **Confidence:** proven
- **Severity hint:** minor

#### F36
- **Target:** README/PLAN wording
- **Claim challenged:** "One job, `smoke`"; the replay example; Requirements
- **Evidence:** ci.yml has 3 jobs. `git checkout level-03-load-balancing` names a tag that doesn't exist (this predates level 1). Requirements lists k3d/kubectl but not curl/jq. (D14)
- **Breaking case:** run the replay example → error
- **Confidence:** proven
- **Severity hint:** minor

#### F37
- **Target:** AT-02
- **Claim challenged:** AT-02 proves EXPECT_VERSION is checked on every answer
- **Evidence:** the fake gives every answer the same version, so mixed versions are never tested. (A11)
- **Breaking case:** check only the first answer → AT-02 passes
- **Confidence:** proven
- **Severity hint:** minor

#### F38
- **Target:** AT-03
- **Claim challenged:** AT-03 proves the images were built with VERSION
- **Evidence:** its `VERSION.*$want` grep is satisfied by the EXPECT_VERSION line it already required. (A12)
- **Breaking case:** n/a (redundant assertion)
- **Confidence:** proven
- **Severity hint:** minor

#### F39
- **Target:** `exists_in_ghcr` in the test lib
- **Claim challenged:** "this tag is absent from GHCR"
- **Evidence:** any inspect error reads as absent. (A13)
- **Breaking case:** registry unreachable → the "nothing pushed" checks pass
- **Confidence:** proven
- **Severity hint:** minor

#### F40
- **Target:** AT-07
- **Claim challenged:** AT-07 proves the tag is on main's merge commit and promote (not build) ran
- **Evidence:** it checks neither; equal digests can't tell the two apart; the annotated check uses the local tag. (A14)
- **Breaking case:** a tag run that builds and is skipped by the guard → passes
- **Confidence:** proven
- **Severity hint:** minor

#### F41
- **Target:** how the test lib selects runs
- **Claim challenged:** the tests observe the criterion's run
- **Evidence:** `pick_pr` takes the newest PR in any state (it can be a throwaway); `ci_run` filters by SHA and event only (e08's PR into main shares dev's head SHA). These produce false failures, not false passes. (A15)
- **Breaking case:** a throwaway PR is newest → AT-01 fails falsely
- **Confidence:** proven
- **Severity hint:** minor

### Surfaces
- **Swept:** script injection (all untrusted values go through env; `${{ }}` never appears inside a `run:` body); fork token scope; event/ref routing of `publish`; reusable-workflow permission narrowing; secrets in logs; build-context leaks; cache poisoning (none); shell semantics under `-eo pipefail`; expression typing and outputs; failure propagation and `fail-fast: false` convergence; image names and labels; required-check names stable (no `name:` overrides); backend VERSION contract; smoke.sh and compose back-compat; the README `docker run` port. All held.
- **Swept:** AT-01, AT-05, AT-06, AT-08, e02 and e07 would each fail if their criterion broke.
- **Unattacked:** Actions settings for fork-run approval and allowed actions (needs `gh api`); what `GITHUB_TOKEN` with `packages: write` can do to package settings; whether the refactored promote and anchors work on a tag run (covered by F1); whether cancelled main runs are visible to the operator; QEMU time limits (deferred cache / arm64 smoke).

### Verdicts
Reproductions run for this adjudication (2026-10-24):
- F1: run headShas checked against `dc44a0d`.
- F7: run history checked for the earlier deletion of `level-99-acceptance-unpublished`.
- F8: `scripts/image-digest.sh` run locally on unreachable refs containing "denied".
- F10: throwaway PR #11 opened into `dev`, then its base switched to `main`.
- F22: step conclusions of run 40103856608.
- F31: 15 cold local `compose up --wait` + smoke cycles.

#### F1 — CONFIRMED major
- **Reason:** Every promote observation comes from before the refactor. Runs 40107587653, 40110298668, 40103856608, 40104092981 and 40103984571 all have headShas that don't contain `dc44a0d`, and 07/e05/e06 can't see the current `promote`. The behaviour isn't shown to be broken (so not a blocker), but a core path has no test that would go red.

#### F2 — CONFIRMED major
- **Reason:** Traced. The published images come from a second, untested build. The named mutation (dropping `--build-arg VERSION` in publish) leaves every pipeline check green and ships backends that answer `dev`. AT-06 only catches it by hand, after the fact.

#### F3 — CONFIRMED major
- **Reason:** The README command tags HEAD. On `dev` or on a stale `main`, the tag lands on an unpublished commit, and the ruleset (no bypass) makes that permanent.

#### F4 — CONFIRMED major
- **Reason:** The tag run and the `main` run are in separate concurrency groups, and promote doesn't wait for the `main` publish. The documented flow (merge, then tag) races it.

#### F5 — CONFIRMED major
- **Reason:** `main` requires only `smoke` and `only-dev-to-main`. A red dry run doesn't block the merge (protection read back in AT-08).

#### F6 — CONFIRMED major
- **Reason:** Documented GitHub concurrency semantics: a newer queued run cancels the pending one in the same group, and `cancel-in-progress: false` protects only the running run. A merge to `main` can therefore go unpublished.

#### F7 — REFUTED
- **Reason:** When `level-99-acceptance-unpublished` was deleted (e05), no run started. That tag has exactly one run (40107587653), from its creation. Tag deletions don't trigger ci.yml, and the ruleset now blocks deleting `level-*` tags anyway.
- **Reopens only if:** a deletion of a `level-*` tag is shown to start a ci.yml run.

#### F8 — CONFIRMED major
- **Reason:** Reproduced. `scripts/image-digest.sh registry.invalid/denied:x` and `registry.invalid/x:level-05-denied-routes` exit 0 as "absent" on a DNS failure. Any error text containing those words (including the ref itself) reads as absent, which in the guard means a re-push and in promote means an overwrite.

#### F9 — CONFIRMED major
- **Reason:** `only-dev-to-main` compares only the branch name, so a fork's `dev` passes the rule `main` relies on.

#### F10 — CONFIRMED major
- **Reason:** Reproduced on PR #11. A feature PR into `dev` passed, its base was switched to `main`, no run started, and GitHub reported it CLEAN/MERGEABLE into `main`. The skipped `only-dev-to-main` from the PR-into-dev run satisfied the required check.

#### F11 — REFUTED
- **Reason:** A PR running its own workflow is how `pull_request` works on every GitHub repo. The brief never claims that required checks prove the base branch's workflow ran. The only person who can merge is the owner, who sees any ci.yml change in the diff. First-time fork runs need approval. Not a defect against the agreed contract.
- **Reopens only if:** the repo gains collaborators with merge rights, or "require workflows" rulesets become available for this account.

#### F12 — CONFIRMED minor
- **Reason:** The attack needs write access, which only the owner has, so it's out of the threat model. But the README's absolute "images are never overwritten" overclaims: only the pipeline never overwrites. Docs defect.

#### F13 — REFUTED
- **Reason:** Anyone who can create tags can already push branches with arbitrary workflows, so restricting tag creation adds nothing in this threat model. The official promote path refuses commits with no `sha-<7>` (e05).
- **Reopens only if:** an official-path promotion of a commit that isn't on `main` is shown to succeed.

#### F14 — CONFIRMED major
- **Reason:** In observe mode e06 snapshots `before` right before comparing, and its `no-op` grep matches the step script GitHub echoes into every log. It passes with the no-op branch removed.

#### F15 — CONFIRMED major
- **Reason:** e05's message grep matches the echoed script, and it accepts a failure from any cause.

#### F16 — CONFIRMED major
- **Reason:** e03's "already exists" grep matches the echoed guard script on every run. Only its digest check is real.

#### F17 — CONFIRMED major
- **Reason:** e01's broken PR targets `dev`, where `publish` is skipped by its own `if:`. The `needs: smoke` gate is never exercised.

#### F18 — CONFIRMED major
- **Reason:** The dry run tags with the version of the `refs/pull/N/merge` commit, while AT-04 probes the PR head's version, so a push by the dry run would go unseen.

#### F19 — CONFIRMED major
- **Reason:** The service and platform greps are satisfied by the echoed env block and the hard-coded dry-run echo. `--platform linux/amd64` alone would pass.

#### F20 — CONFIRMED major
- **Reason:** With `$(id)`, an executed substitution leaves nothing in the log, so e08 can't tell whether injection happened.

#### F21 — CONFIRMED minor
- **Reason:** e09's `main`/tag half only scans history in which no overlapping `main` runs ever happened, so it is vacuous. Minor because it is test coverage of a behaviour that F6 changes anyway.

#### F22 — CONFIRMED major
- **Reason:** In run 40103856608 the failing step was `docker compose up`, and `scripts/smoke.sh | tee` was skipped. No run shows a failing smoke.sh turning the job red, so the pipefail fix is unverified.

#### F23 — CONFIRMED minor
- **Reason:** The dry run never logs in or pushes, but it holds `packages: write`, including on a same-repo PR into `main` from a branch other than `dev`. Least privilege isn't met.

#### F24 — CONFIRMED minor
- **Reason:** Traced from the diff. The refactor made a failed post-push read return an empty digest and a green step, where before the step failed. After `imagetools create`, the level tag's digest is never re-read. The digests are equal today (AT-07); the gap is that nothing checks them.

#### F25 — CONFIRMED minor
- **Reason:** The guard and promote trust a 7-character tag name without comparing the image's `revision` label to `GITHUB_SHA`. Low probability, cheap to check.

#### F26 — CONFIRMED minor
- **Reason:** `actions/checkout` keeps the token in `.git/config` in the publish jobs, which never use git credentials.

#### F27 — REFUTED
- **Reason:** An admin can always change their own repo's settings; the owner is the root of trust. Nothing in the design claims otherwise.
- **Reopens only if:** the repo moves to an org with admins other than the owner.

#### F28 — REFUTED
- **Reason:** The documented flow pushes a single tag by name (`git push origin level-NN-<slug>`), never `--tags`, so the limit of 3 tags per push is never reached.
- **Reopens only if:** the docs or tooling start pushing several tags at once.

#### F29 — CONFIRMED minor
- **Reason:** Nothing checks the `level-NN-<slug>` format before a permanent GHCR tag is written.

#### F30 — CONFIRMED minor
- **Reason:** If `env.VERSION` came out empty, CI's EXPECT_VERSION check would be skipped silently.

#### F31 — REFUTED
- **Reason:** 0 failures in 15 cold local `compose up --wait` + smoke cycles, and every CI smoke run so far failed only where it was broken on purpose. nginx is listening long before the first knock.
- **Reopens only if:** a CI or local run fails with "knock 1 of N got no answer" on a healthy stack.

#### F32 — CONFIRMED minor
- **Reason:** When smoke fails, its result never reaches the job summary (pipefail stops the step, and FAIL goes to stderr). Cosmetic.

#### F33 — REFUTED
- **Reason:** The duplicate runs were accepted in Q4, and build cost belongs to the deferred cache decision (Q9), whose signal hasn't fired (CI about 40 s, publish about 4 min).
- **Reopens only if:** CI exceeds about 5 min or publish about 10 min, sustained.

#### F34 — CONFIRMED minor
- **Reason:** PLAN §1/§2 claim things the files contradict: every Dockerfile multi-stage, `VERSION` passed everywhere, 8–150 MB, and a `scripts/` layout that doesn't list `image-digest.sh`.

#### F35 — CONFIRMED minor
- **Reason:** The README's `EXPECT_VERSION` example fails against the quickstart (compose defaults to `dev`). The PR-run version comes from the merge commit, and that isn't documented.

#### F36 — CONFIRMED minor
- **Reason:** PLAN says "One job, `smoke`" (there are three), and Requirements omit curl/jq. The replay example naming a future tag predates level 1, is illustrative, and isn't part of this.

#### F37 — CONFIRMED minor
- **Reason:** AT-02's fixture never mixes versions, so "first answer only" would pass.

#### F38 — REFUTED
- **Reason:** AT-03's extra grep is redundant but creates no false pass. The real proof (smoke passing with EXPECT_VERSION set) is checked, and its weakness is F37's.
- **Reopens only if:** F37's fix leaves AT-03 unable to detect a backend that ignores VERSION.

#### F39 — CONFIRMED minor
- **Reason:** `exists_in_ghcr` treats every inspect error as absent, the same flaw as F8 but in the test lib.

#### F40 — CONFIRMED minor
- **Reason:** AT-07 checks neither that the tag's commit is on `main` nor that promote (not build) ran. Its annotated-tag check uses the local tag.

#### F41 — CONFIRMED minor
- **Reason:** Run and PR selection can pick a throwaway PR or another PR's run. These produce false reds, not false greens.

### Carried smells
Shipping would carry N1, N2 and N3. Cross-check:
- N2 (the build step branching on `PUSH`) is the code that F2, F23 and F24 change. If the dry run becomes its own caller job (F23), the branching may go, so re-read N2 next pass.
- N1 (login in both jobs) is touched by F26.
- No noted smell caused a confirmed blocker.

### Remediation slices
- [ ] [major] F1 — The promotion decision (absent source → fail saying the commit was never published from main; level tag at the same digest → no-op; at a different digest → fail as immutable; absent level tag → create it, and it then resolves to the source digest) is verified against a real registry without GitHub, and the next level tag's run uses that same code.
- [ ] [major] F2 — After a real publish, each backend's pushed `sha-<7>` image, run as pulled from the registry, answers `/api/knock` with `"version":"sha-<7>"` and its own `lang`. The publish job fails otherwise, so dropping the VERSION build arg turns the run red.
- [ ] [major] F3 — The README release step names the commit to tag explicitly (`main`'s merge commit after a fetch) and says to wait for `main`'s run to be green first. Following it from `dev` or from a stale `main` can't tag the wrong commit.
- [ ] [major] F4 — A level tag pushed while `main`'s publish of that commit is still running is promoted once the publish finishes, within a bounded wait, instead of failing with "never published from main". A tag on a commit that isn't on `main` fails at once, saying so.
- [ ] [major] F5 — A PR into `main` whose dry-run build fails for any service can't be merged, because a required check is red.
- [ ] [major] F6 — Two or more pushes to `main` in quick succession each publish their own `sha-<7>`. None is cancelled while pending.
- [ ] [major] F8 — `scripts/image-digest.sh` reports "absent" only for the registry's own answer for a missing tag or a missing package. Any other failure (DNS, connection, 5xx, local errors) exits non-zero, even when the reference contains "denied" or "not found".
- [ ] [major] F9 — A PR into `main` whose head is a branch named `dev` in a fork fails `only-dev-to-main`.
- [ ] [major] F10 — Changing an open PR's base to `main` re-runs `only-dev-to-main`, and the PR can't be merged unless its head is this repo's `dev`.
- [ ] [major] F14 — e06 fails if a re-promotion rewrites the level tag or doesn't report a no-op. Its assertions come from output lines (not the echoed script) and from digests recorded when it acted.
- [ ] [major] F15 — e05 fails unless the publish failure's output line (not the echoed script) says the commit was never published from main.
- [ ] [major] F16 — e03 fails unless each service's guard output (not the echoed script) reports "already exists".
- [ ] [major] F17 — A red smoke on a PR into `main` leaves the publish/dry-run jobs skipped, and e01 observes that on a PR into `main`.
- [ ] [major] F18 — AT-04 probes GHCR for the version the dry run actually used (the merge commit's) and fails if any registry error stops it from proving absence.
- [ ] [major] F19 — AT-04 fails unless buildx output (not echoes or env) shows each of the five services built for `linux/amd64` and `linux/arm64`.
- [ ] [major] F20 — e08's branch name carries a payload whose execution would leave a distinct mark in the log, and e08 fails if that mark appears.
- [ ] [major] F22 — A CI run in which every container is healthy but smoke.sh fails the contract turns `smoke` red, and a test observes that run.
- [ ] [minor] F12 — The README says the pipeline never overwrites a published tag, instead of claiming that images can never be overwritten.
- [ ] [minor] F21 — e09 produces two overlapping `main`-ref runs and fails if either is cancelled.
- [ ] [minor] F23 — The dry run runs with no `packages: write` permission.
- [ ] [minor] F24 — After a push, the publish step fails if the pushed tag's digest can't be read back. After promoting, it fails unless the level tag resolves to the source digest.
- [ ] [minor] F25 — The guard fails, rather than skipping, if an existing `sha-<7>` carries a `revision` label other than the commit being published.
- [ ] [minor] F26 — The publish jobs' checkout doesn't keep git credentials.
- [ ] [minor] F29 — A `level-*` tag not matching `level-NN-<slug>` (two digits, a lowercase slug) fails before any image tag is written, saying so.
- [ ] [minor] F30 — CI fails if the version it would test against is empty, instead of silently skipping the check.
- [ ] [minor] F32 — A failing smoke test's output, including the FAIL line, appears in the job summary.
- [ ] [minor] F34 — PLAN §1/§2 match the files: which Dockerfiles are multi-stage, where VERSION applies, the image-size range, and the `scripts/` layout.
- [ ] [minor] F35 — The README's EXPECT_VERSION example works as written (with `VERSION=… docker compose up --build`), and the docs say PR runs use the merge commit's SHA.
- [ ] [minor] F36 — PLAN's level-01 note names the three CI jobs correctly, and the README Requirements list curl and jq.
- [ ] [minor] F37 — AT-02 fails if EXPECT_VERSION is checked against only some answers (a fixture with mixed versions must fail).
- [ ] [minor] F39 — The test lib's absence check fails on registry errors instead of reading them as absent.
- [ ] [minor] F40 — AT-07 fails unless the level tag's commit is on `main` (checked on the remote) and the tag run promoted without building.
- [ ] [minor] F41 — The acceptance tests ignore throwaway `acceptance/*` PRs and pick runs by event and head branch, so a newer throwaway PR can't make them fail.

### Verdict: NO-GO
- **Reason:** 17 confirmed majors (F1–F6, F8–F10, F14–F20, F22) and 16 confirmed minors remain open, and nothing is INCONCLUSIVE. 8 findings refuted (F7, F11, F13, F27, F28, F31, F33, F38). This is iteration 1 of at most 3.

## Iteration 2

### Closed slices
- [x] F1 — verified by `l2-promote.sh` (promotion decision against a real registry); the
  level-tag run calls `scripts/promote.sh`, so the next level tag runs the tested code
- [x] F2 — verified by `l3-check-image.sh` and `04-dry-run-publish-on-pr-into-main.sh`
  (the dry run's "answers as <svc>, sha-<7>" line per backend, run 40142663865); the
  publish run 40143010258 checked each backend before pushing
- [x] F3 — verified by review: README step 5 tags `origin/main` by name after its run is
  green; `07-level-tag-promotes.sh` fails a level tag not on `main`
- [x] F4 — verified by `l2-promote.sh` (a source published during the wait is promoted)
  and by the promote job's `merge-base --is-ancestor` check on `origin/main`
- [x] F5 — verified by `08-branch-protection.sh` (`release-ready` required on `main`) and
  `e01-failed-smoke-blocks-publish.sh` (red `release-ready`, PR BLOCKED, run 40142547360)
- [x] F6 — verified by `e09-concurrency-never-cuts-a-publish.sh` (main runs 40143010258:1
  and 40139376235:3, of different commits, overlapped and both finished green)
- [x] F8 — verified by `l1-image-digest.sh`
- [x] F9 — verified by review (the rule compares the head repository); not
  acceptance-testable (a fork's `dev` needs a second account); `04` (dev passes), `e08`
  and `e11` (others fail) cover the rule's other branches
- [x] F10 — verified by `e11-base-switch-to-main-is-blocked.sh` (run 40142498014, BLOCKED)
- [x] F14 — verified by `e06-level-tag-same-digest-is-a-no-op.sh` (per-job `: no-op` output
  lines; digests compared to the immutable source)
- [x] F15 — verified by `e05-level-tag-on-unpublished-commit-fails.sh` (per-job output)
- [x] F16 — verified by `e03-rerun-is-a-no-op.sh` (per-service "already exists" output, run 40143010258)
- [x] F17 — verified by `e01-failed-smoke-blocks-publish.sh` (a PR into `main`: dry run skipped after a red smoke)
- [x] F18 — verified by `04-dry-run-publish-on-pr-into-main.sh` (probes the version the dry run reported)
- [x] F19 — verified by `04-dry-run-publish-on-pr-into-main.sh` (buildx `[linux/amd64 …]` and `[linux/arm64 …]` lines per service)
- [x] F20 — verified by `e08-only-dev-into-main.sh` (the payload prints `beef` if executed; run 40142524701)
- [x] F22 — verified by `e10-failing-smoke-script-fails-the-job.sh` (compose healthy, the smoke.sh step failed, run 40142355972)
- [x] F12 — verified by review: the README scopes "never overwrites" to the pipeline
- [x] F21 — verified by `e09-concurrency-never-cuts-a-publish.sh` (the overlapping pair above)
- [x] F23 — verified by `04-dry-run-publish-on-pr-into-main.sh` (no job in the dry-run run holds `packages: write`)
- [x] F24 — verified by `l2-promote.sh` (the level tag is re-read and must equal the source); the publish step fails on an empty read-back
- [x] F25 — verified by `l1-image-digest.sh` (`--revision` mismatch fails); the guard uses it
- [x] F26 — verified by review (`persist-credentials: false` on both publish checkouts); not acceptance-testable
- [x] F29 — verified by `l2-promote.sh` (a malformed level tag fails before anything is written)
- [x] F30 — verified by `02-smoke-expect-version.sh` (EXPECT_VERSION set but empty fails)
- [x] F32 — verified by review (the smoke output, including FAIL lines, goes to the summary in an `always()` step); job summaries have no public API
- [x] F34 — verified by review of PLAN §1/§2
- [x] F35 — verified by review of the README quickstart
- [x] F36 — verified by review of PLAN's level-01 note and README Requirements
- [x] F37 — verified by `02-smoke-expect-version.sh` (a mixed-version fixture must fail)
- [x] F39 — verified by `04`/`e05` (`exists_in_ghcr` goes through `scripts/image-digest.sh`, so a registry error fails)
- [x] F40 — verified by `07-level-tag-promotes.sh` (annotated on the remote, on `main`, promote ran and build was skipped)
- [x] F41 — verified by `01`/`04`/`e02` (`pick_pr` skips `acceptance/*`, and runs are picked by head branch)

### Smells
- **N1** — left: condition not met (no third job logs in; the login is unchanged)
- **N2** — left: condition not met (still two build modes; the read-back belongs to the summary branch)
- **N3** — left: condition not met (no service added)
- **B2** Dispensables / Duplicate Code at `publish.yml`, in the build job: the checked amd64
  build and the pushed multi-arch build each spelled out their own `docker buildx build …
  --build-arg VERSION`. Blocking: if the two drift apart, the check tests an image that
  isn't the one shipped (F2 again). Fixed: one step, one `build=(…)` argument array (PR #18,
  released in #19).
- **N4** Dispensables / Duplicate Code at `ci.yml`: the jobs `dry-run` and `release-ready`
  repeat the "PR into main" predicate. Noted: two copies next to each other. If they
  diverged, `release-ready` would see `skipped` and fail closed.
  - **Promote if:** a third job needs the predicate, or the predicate changes.

### Findings (unadjudicated)
Iteration 2: three read-only delegates, one per surface: test integrity (T), workflow and
scripts (W), security/contracts/docs (S). F7, F11, F13, F27, F28, F31, F33 and F38 are
refuted and were not revisited. Sources are given as delegate+number. Ranked most severe first.

#### F42
- **Target:** `release-ready` as the required gate on `main`
- **Claim challenged:** a PR into `main` can't merge unless its dry run passed
- **Evidence:** every push to `dev` (and `main`) runs ci.yml, where `release-ready` is skipped by its `if`, and that skipped check attaches to the pushed SHA, which is also the `dev`→`main` PR's head. A skipped required check counts as passing. ci.yml's `pull_request` has no `edited` type. (S1, W1, T6)
- **Breaking case:** (a) open a PR from `dev` into a third branch (ci.yml doesn't run), then switch its base to `main` → only `only-dev-to-main` runs → smoke=success and release-ready=skipped from the push run → mergeable without a dry run. (b) During a normal `dev`→`main` PR, before the PR run's `release-ready` exists, the push run's skipped one may stand in for it.
- **Confidence:** unproven (depends on GitHub's resolution of same-named check runs)
- **Would be settled by:** reproduce (a) with throwaway branches and read `mergeStateStatus`; for (b), read the head SHA's `release-ready` check runs while the dry run is in progress
- **Severity hint:** blocker

#### F59
- **Target:** observe mode (`run.sh` plus `observed.env`) for the ACTS tests
- **Claim challenged:** a green suite means the current code meets the criteria
- **Evidence:** observe mode replays recorded runs and never compares the run's head SHA (or the workflow files at that commit) with the current tree. The e09 feature pair (40103959266/40103984571) predates the concurrency rewrite in 5441709. (T1)
- **Breaking case:** remove `always()` from `release-ready`, or `edited` from only-dev-to-main, or `shell: bash`, or set main to `cancel-in-progress: true` → the suite stays green on recorded runs
- **Confidence:** proven (mechanism)
- **Severity hint:** blocker

#### F60
- **Target:** `grep -q` on piped `gh` logs under pipefail (04, e02, e01, e03, e05, e06, e10)
- **Claim challenged:** `if job_log … | grep -q X; then fail` catches X, and `job_output … | grep -q X || fail` passes when X is present
- **Evidence:** `grep -q` exits at the first match, so `gh` gets SIGPIPE and pipefail makes the pipeline return 141. A negative check can then never fail exactly when its target is present, and a positive check can flake red when the match is followed by lots of output. (T2, T12)
- **Breaking case:** give `dry-run` `packages: write` → "Packages: write" sits near the top of a large log → the pipeline exits 141 → `if` is false → 04 passes
- **Confidence:** proven (bash semantics, checked with `seq | grep -q`)
- **Severity hint:** major

#### F43
- **Target:** "what ships is what was checked"
- **Claim challenged:** the pushed amd64 image is the one check-image started
- **Evidence:** these are two separate buildx builds, each re-resolving floating `FROM` tags, and nothing compares the checked image's layers with the pushed amd64 manifest. arm64 is never started. 04 never runs the shipped multi-arch build. (S5, W2, T9)
- **Breaking case:** a base tag republished between the two builds → different amd64 layers ship and the job stays green; or dropping `--build-arg VERSION` from the second call only → 04 passes
- **Confidence:** unproven
- **Would be settled by:** in a publish run, compare `check/<svc>` RootFS layers with the pushed amd64 config's diff_ids
- **Severity hint:** major

#### F51
- **Target:** image-digest.sh's 403 branch
- **Claim challenged:** a 403 on the token request means the package doesn't exist
- **Evidence:** the authenticated path in CI (an oauth token, 403) is also GHCR's answer for an existing package the token can't read (unlinked, or Actions access removed). The authenticated answer for a not-yet-created package is still unobserved. (W4)
- **Breaking case:** an existing tag in an unlinked package → read as absent → a full build and a push that fails later, or promote waiting 20 min, then "never published"
- **Confidence:** unproven
- **Would be settled by:** an authenticated inspect of a missing package, and of an existing package the token can't read
- **Severity hint:** major

#### F61
- **Target:** observation identity in e08 and e11, and the `STATE` inputs of e01 and e11
- **Claim challenged:** the recorded runs are the payload PR's run and the base-switch run, and the PR was BLOCKED
- **Evidence:** e08 never checks the run's head branch, and e11 never checks that the run came from an `edited` event, so `E11_RUN` and `E08_RUN` are interchangeable. `STATE` is a literal `BLOCKED` in observed.env that the tests compare with itself. (T3)
- **Breaking case:** `E11_RUN=40142524701` (the e08 run) → e11 passes
- **Confidence:** proven
- **Severity hint:** major

#### F62
- **Target:** e08's injection check
- **Claim challenged:** the branch-name payload isn't executed anywhere in the pipeline
- **Evidence:** only the `only-dev-to-main` job's output is read; the same PR's ci.yml jobs aren't inspected. (T4)
- **Breaking case:** add `run: echo "${{ github.head_ref }}"` to smoke → "beef" lands in ci.yml's log → e08 passes
- **Confidence:** proven
- **Severity hint:** major

#### F63
- **Target:** e09's `main` half
- **Claim challenged:** overlapping green `main` runs show that no publish is cancelled or left pending
- **Evidence:** attempt-level `run_started_at` can fall inside the other run even when the two are serialized by a shared group. The recorded pair includes a re-run that only skips, and "never cancelled" scans only the last 200 runs. (T5)
- **Breaking case:** revert to a shared group with cancel false → the runs serialize but may still count as overlapping
- **Confidence:** unproven
- **Would be settled by:** comparing the job-level `started_at`/`completed_at` of the pair
- **Severity hint:** major

#### F44
- **Target:** promote's "on main" guard
- **Claim challenged:** a tag on a commit `main` never published fails at once
- **Evidence:** `merge-base --is-ancestor` accepts any commit reachable through second parents, which includes every `dev`/feature commit and pre-pipeline first-parent commits. Only first-parent commits from the pipeline on have `sha-<7>`. (S2, W3)
- **Breaking case:** tag `00578d2` → passes the guard → 5 jobs wait 20 min → "never published from main" (misleading); the name is burned for good
- **Confidence:** proven
- **Severity hint:** minor

#### F45
- **Target:** the promotion guarantees in README/PLAN for tags on older `main` commits
- **Claim challenged:** every level-tag promotion enforces the name, the ancestry and the revision
- **Evidence:** a tag push runs the workflows of the tagged commit. At 3b78dd7, c063e45 and 52dd932, promote has no regex, no ancestry check and the old lookup. (S3)
- **Breaking case:** `git tag -a level-2-oops 3b78dd7` → the old workflow promotes it on all five packages
- **Confidence:** proven
- **Severity hint:** minor

#### F46
- **Target:** PLAN "each backend … checked before anything is pushed"; partial releases
- **Claim challenged:** nothing is pushed until every backend is checked; a level tag gives "the same images"
- **Evidence:** each matrix leg (`fail-fast: false`) checks and pushes only its own image, and the frontend pushes immediately. If `main` publishes 4 of 5, promotion is applied to 4 and waits 20 min to fail the fifth. (S4, W6)
- **Breaking case:** rust's check fails on `main` → the 4 others are published → `level-NN` is applied to 4 images
- **Confidence:** proven
- **Severity hint:** minor

#### F52
- **Target:** promote.sh's wait
- **Claim challenged:** a source still publishing is waited for
- **Evidence:** any transient error during polling (429, 5xx, timeout) aborts the wait at once under `set -e`, with no retry. (W5)
- **Breaking case:** one 502 at minute 12 → the job fails
- **Confidence:** proven
- **Severity hint:** minor

#### F53
- **Target:** the publish read-back
- **Claim challenged:** an empty read-back means the push failed
- **Evidence:** GHCR's read-after-push consistency is unknown; a brief "not found" fails a successful push. (W7)
- **Breaking case:** a lagging tag → a red job; a re-run recovers
- **Confidence:** unproven
- **Would be settled by:** search the publish logs for "can't read it back"
- **Severity hint:** minor

#### F54
- **Target:** check-image.sh diagnostics
- **Claim challenged:** a failed check is diagnosable
- **Evidence:** `--rm` deletes a crashed container's logs; if the container exits before `docker port`, the error is raw; readiness is about 10 s; the `knock-check` label is unused. (W8)
- **Breaking case:** a container that crashes on start → "no answer" with no logs
- **Confidence:** proven (lost logs); unproven (timing)
- **Would be settled by:** check-image against an image that sleeps 12 s before listening
- **Severity hint:** minor

#### F55
- **Target:** job time bounds
- **Claim challenged:** the pipeline's waits are bounded
- **Evidence:** no job sets `timeout-minutes`; a hung QEMU build runs to the 6 h default. (W9)
- **Breaking case:** a hung arm64 `npm ci` → 6 h
- **Confidence:** proven (absence)
- **Severity hint:** minor

#### F56
- **Target:** `release-ready` with `always()` in cancelled runs
- **Claim challenged:** `release-ready` reflects the current head's dry run
- **Evidence:** a cancelled, superseded run posts `release-ready=failure`. (W10)
- **Breaking case:** close/reopen on the same SHA → a stale failure next to the pending check
- **Confidence:** proven
- **Severity hint:** minor

#### F57
- **Target:** image-digest.sh `--revision`
- **Claim challenged:** a foreign revision is always refused, with a clear message
- **Evidence:** only the first platform's label is compared; a config without `config` makes jq fail with no `::error::`; a 7-character collision blocks a commit for good. (W11)
- **Breaking case:** an arm64 config with another revision → accepted
- **Confidence:** proven
- **Severity hint:** minor

#### F58
- **Target:** promote's format regex; the frontend's build arg
- **Claim challenged:** malformed names are refused before any work
- **Evidence:** the regex has no length bound (Docker tags are limited to 128 characters); `--build-arg VERSION` goes to a frontend that never declares it. (W12)
- **Breaking case:** a 200-character level tag → passes, waits, then fails in `imagetools create`
- **Confidence:** proven
- **Severity hint:** minor

#### F47
- **Target:** credentials on the runner
- **Claim challenged:** no job persists the token
- **Evidence:** ci.yml's smoke checkout persists a `contents: read` token (an inconsistency, read-only). (S6)
- **Breaking case:** the token stays on disk during the smoke job
- **Confidence:** proven
- **Severity hint:** minor

#### F48
- **Target:** README Quickstart
- **Claim challenged:** "rotate go → python → rust → ts, perfectly"; `VERSION=… up --build -d` followed by EXPECT_VERSION smoke works
- **Evidence:** the round-robin order follows Docker DNS order, which nothing fixes; the README uses `-d` without `--wait`, so smoke can race a backend that isn't healthy yet. (S7)
- **Breaking case:** rotation rust → go → …; the first smoke run fails after `up -d`
- **Confidence:** unproven
- **Would be settled by:** several `down`/`up -d` cycles, recording the order and smoking immediately
- **Severity hint:** minor

#### F49
- **Target:** PLAN §2 layout
- **Claim challenged:** the layout lists the tracked files
- **Evidence:** `backends/rust/Cargo.lock` (required: `--locked`), `LICENSE` and `.gitignore` are missing. (S8)
- **Breaking case:** a rebuild from the layout omits Cargo.lock → the rust build fails
- **Confidence:** proven
- **Severity hint:** minor

#### F50
- **Target:** the merge-commit convention
- **Claim challenged:** "merge it with a merge commit, so `main` always contains `dev`" is enforced
- **Evidence:** nothing restricts the merge method; a squash or rebase into `main` breaks the containment. (S9)
- **Breaking case:** a squash merge into `main` → `dev` diverges
- **Confidence:** unproven
- **Would be settled by:** `gh api repos/izentenosmith/knock-knock --jq '{allow_squash_merge,allow_rebase_merge}'`
- **Severity hint:** minor

#### F64
- **Target:** e01 "PR BLOCKED"
- **Claim challenged:** BLOCKED shows the release-ready gate
- **Evidence:** the PR also fails `only-dev-to-main` and `smoke`, so BLOCKED would happen regardless. (T7)
- **Breaking case:** n/a (BLOCKED adds nothing beyond release-ready's own conclusion)
- **Confidence:** proven
- **Severity hint:** minor

#### F65
- **Target:** 04's dry-run version
- **Claim challenged:** the dry run checks the commit's `sha-<7>`
- **Evidence:** the version comes from the job's own line and is never compared with smoke's. (T8)
- **Breaking case:** `version: sha-deadbee` in the dry-run call → 04 passes
- **Confidence:** proven
- **Severity hint:** minor

#### F66
- **Target:** l1's fidelity
- **Claim challenged:** l1 covers the script's classification
- **Evidence:** the 403 branch is never exercised; a substring "not found" match would survive; the platform-map branch may not be covered locally. (T10)
- **Breaking case:** delete the 403 branch → l1 passes
- **Confidence:** proven (403, substring); unproven (map)
- **Would be settled by:** `imagetools inspect localhost:5055/kk-rust:sha-1111111 --format '{{json .Image}}' | jq 'has("config")'`
- **Severity hint:** minor

#### F67
- **Target:** l2
- **Claim challenged:** l2 catches promote regressions
- **Evidence:** deleting the post-create read-back, or dropping the `@$src` pin, survives. (T11)
- **Breaking case:** delete the read-back → l2 passes
- **Confidence:** proven
- **Severity hint:** minor

#### F68
- **Target:** 02's negative cases
- **Claim challenged:** they fail for the right reason
- **Evidence:** they assert only a non-zero exit; a fake that never starts makes them pass vacuously. (T13)
- **Breaking case:** port 18123 never listens → "got no answer" → passes
- **Confidence:** proven
- **Severity hint:** minor

#### F69
- **Target:** e08's run selection in ACT mode
- **Claim challenged:** e08 observes its own PR's run
- **Evidence:** it pushes dev's existing SHA and takes the newest `only-dev-to-main` run for that SHA with no branch filter. (T14)
- **Breaking case:** the real `dev`→`main` PR's run is picked → a false red (or a stale earlier e08 run)
- **Confidence:** proven
- **Severity hint:** minor

#### F70
- **Target:** 03
- **Claim challenged:** 03 proves the version plumbing from output
- **Evidence:** it greps the raw log, where the env blocks echoed in "Run" headers satisfy it whatever ran. (T15)
- **Breaking case:** n/a beyond the job conclusion and 02
- **Confidence:** proven
- **Severity hint:** minor

### Surfaces
- **Swept:** `job_output` header stripping (anchored positive greps; negative greps paired with a positive one); `publish_jobs` matching; `pick_pr` exclusion; `wf_run --branch dev`; e10 step assertions; e01 in ACT mode; l2 format/revision/no-op/immutable/wait; l3; 02 head/tail-only comparisons; permissions (only `publish` writes; the dry run is read-only; only-dev-to-main has `{}`); injection (all untrusted values through env; no workflow-command injection via refnames); only-dev-to-main (head repo + branch, close/reopen/synchronize/base switch away and back); check-name stability; image contract and labels; the level regex matches all 14 planned tags; README step 5 commands; the concurrency expression on every ref kind; `release-ready` when smoke fails, the dry run fails or is cancelled; image-digest's exact comparison and its 401/429/network handling; promote's deadline and branches; check-image ports and entrypoints. All held.
- **Unattacked:** live GitHub behaviour (resolution of same-named check runs, see F42; authenticated GHCR answers, see F51; read-after-push consistency, see F53); 05, 06, 07, 08 and e07 beyond a skim; nginx/app internals; QEMU durations against the 20-min wait.

### Verdicts
Iteration 2. 33 slices closed this iteration; F7, F11, F13, F27, F28, F31, F33 and F38 are
still refuted. Reproductions run:
- F42: check runs on dev's tip `00578d2`;
- F60: `PIPESTATUS` of a `gh … --log | grep -q` on a dry-run job;
- F50: the repo's merge settings;
- F53: "can't read it back" across the last publish runs;
- F63: job-level times of the recorded pair;
- F66: the local image's `.Image` shape.

#### F42 — CONFIRMED blocker
- **Reason:** On `00578d2` (PR #19's head), the push run's `release-ready` was **skipped** at 23:49:35, and the PR run's real `release-ready` only appeared at 23:53:44. For four minutes the only `release-ready` check on the head was a skipped one. A skipped required check counts as passing. That's the mechanism already reproduced live for `only-dev-to-main` in iteration 1 (F10, PR #11). The base-switch route (a) has no timing at all. The required gate on `main` can be satisfied without a dry run.

#### F59 — CONFIRMED major
- **Reason:** Observe mode replays recorded runs without checking that they ran the current workflows. Mutating `ci.yml` (dropping `always()`, `edited`, `shell: bash`) leaves the suite green. A green suite doesn't prove the tree. The behaviour itself isn't shown broken, so this is a major, not a blocker.

#### F60 — CONFIRMED major
- **Reason:** Reproduced. `gh … --log | grep -q 'Contents: read'` gives `PIPESTATUS=141 0`, and the `if` takes the else branch. Every "no job holds `packages: write`" check (04, e02) can never fire, and the positive `grep -q … || fail` checks can flake red.

#### F61 — CONFIRMED major
- **Reason:** e08 and e11 accept any failed `only-dev-to-main` run (no head-branch or event check), and `STATE` is a literal compared with itself in observe mode.

#### F43 — CONFIRMED minor
- **Reason:** Proven structurally: two builds, and nothing ties the pushed amd64 bytes to the checked ones. Actual drift needs a base republish or a cache miss in a few minutes, which is unproven. The "what ships is what was checked" comment overclaims.

#### F44 — CONFIRMED minor
- **Reason:** `--is-ancestor` accepts commits reached through second parents (`dev`/feature commits), which are never published, so the "isn't on main" fast failure doesn't fire and the run waits 20 min with a misleading message.

#### F45 — CONFIRMED minor
- **Reason:** Tag runs use the tagged commit's workflows. On 3b78dd7, c063e45 and 52dd932, promotion has none of the new checks, so the docs' unqualified guarantee overclaims.

#### F46 — CONFIRMED minor
- **Reason:** PLAN says nothing is pushed until each backend is checked, but each matrix leg pushes its own image after its own check. README's wording ("each backend … before it is pushed") is the accurate one. The partial-release convergence is by design (`fail-fast: false` plus re-run).

#### F47 — CONFIRMED minor
- **Reason:** smoke's checkout persists a read-only token, inconsistent with the hardened publish jobs. Trivial.

#### F48 — CONFIRMED minor
- **Reason:** Level 0's own verification showed the rotation `rust python go ts`, not "go → python → rust → ts". The README's `up --build -d` example lacks `--wait`.

#### F49 — CONFIRMED minor
- **Reason:** PLAN §2 omits `backends/rust/Cargo.lock` (required by `--locked`), `LICENSE` and `.gitignore`.

#### F50 — REFUTED
- **Reason:** Squash and rebase are allowed on purpose. Q6 resolved that GitHub can't restrict the merge method per base branch, kept squash for feature→`dev`, and accepted merge commits for `dev`→`main` as a documented convention.
- **Reopens only if:** a squash or rebase merge into `main` happens, or the design moves to "enforced".

#### F51 — REFUTED
- **Reason:** Even if GHCR answered 403 for an existing package the token can't read, reading it as "absent" fails closed: the guard's push and promote's create need the same access and would be denied, so nothing can be overwritten. The cost is a slower, misleading failure, which no contract covers.
- **Reopens only if:** a 403 read as absent is shown to lead to a write that succeeds.

#### F52 — CONFIRMED minor
- **Reason:** Any transient registry error during promote's wait aborts it at once, without a retry.

#### F53 — REFUTED
- **Reason:** No "can't read it back" in any of the last 5 publish runs; GHCR served every pushed tag immediately. A lag would fail loudly and a re-run recovers (the guard skips).
- **Reopens only if:** a publish run fails "can't read it back" for a tag that exists.

#### F54 — CONFIRMED minor
- **Reason:** `--rm` discards a failed container's logs, so a failed check says only "no answer".

#### F55 — CONFIRMED minor
- **Reason:** No job sets `timeout-minutes`.

#### F56 — REFUTED
- **Reason:** A cancelled, superseded run posting `release-ready=failure` fails closed and is replaced by the next run's result. No gate is weakened.
- **Reopens only if:** a stale failure is shown to block a PR whose newest run passed, or (with F42) a stale *success* is shown to stand in for one.

#### F57 — CONFIRMED minor
- **Reason:** `--revision` compares only the first platform's label, and an unexpected `.image` shape makes jq fail with no `::error::`.

#### F58 — CONFIRMED minor
- **Reason:** The level-tag regex has no length bound (Docker tags are limited to 128 characters). The frontend's unused `VERSION` build arg is only a warning and is not part of this finding.

#### F62 — CONFIRMED minor
- **Reason:** e08 reads only `only-dev-to-main`'s output. ci.yml doesn't use `head_ref` today (read), so this is a coverage gap, not a defect.

#### F63 — CONFIRMED minor
- **Reason:** The recorded pair overlaps at job level too (40139376235:3's jobs ran 23:30:43–23:31:29, inside 40143010258:1's 23:30:28–23:35:27), so the evidence holds. The test should compare job-level times, though, and it scans only the last 200 runs.

#### F64 — REFUTED
- **Reason:** e01 asserts `release-ready`'s own conclusion directly; BLOCKED is a supplementary observation, not the proof.
- **Reopens only if:** that direct assertion is removed or weakened.

#### F65 — CONFIRMED minor
- **Reason:** 04 never compares the dry run's version with the one smoke tested.

#### F66 — CONFIRMED minor
- **Reason:** l1 never exercises the GHCR 403 branch or a non-exact "not found" text. The seeded local image is single-platform (`has("config") == true`), so the platform-map branch is covered only by CI.

#### F67 — CONFIRMED minor
- **Reason:** Deleting promote's post-create read-back survives l2.

#### F68 — CONFIRMED minor
- **Reason:** 02's negative cases accept any failure (a fake that never started passes them).

#### F69 — CONFIRMED minor
- **Reason:** e08's `wait_run` picks runs for its SHA with no head-branch filter.

#### F70 — CONFIRMED minor
- **Reason:** 03's greps match the env blocks echoed into later steps' headers.

### Carried smells
Shipping would carry N1–N4. Cross-check: N4 (the "PR into main" predicate repeated in `dry-run` and `release-ready`) sits in the code F42 has to change. The fix moves both jobs out of ci.yml, which retires N4's duplication rather than patching it.

### Remediation slices
- [ ] [blocker] F42 — No run that isn't a PR into `main` ever produces a `release-ready` check, so `main`'s required `release-ready` exists on a PR's head only after that PR's own dry run, including after a base switch to `main` (which starts the dry run). A PR from `dev` switched to `main` is BLOCKED until its dry run passes.
- [ ] [major] F59 — Observe mode fails ("stale observation") unless the observed run's commit has the same `.github/workflows` and `scripts` as the tree under test.
- [ ] [major] F60 — The suite's log checks don't depend on pipe exit status: a negative check fails when the text is present, and a positive check passes when it is present, whatever the log's size.
- [ ] [major] F61 — e08 and e11 fail unless the observed run is the throwaway PR's (head branch) and, for e11, an `edited` event. Neither asserts a merge state in observe mode that it didn't read itself.
- [ ] [minor] F43 — The pushed `linux/amd64` image is the very image that was started and checked: same manifest digest, nothing rebuilt in between.
- [ ] [minor] F44 — A level tag on a commit that isn't on `main`'s first-parent line fails at once, saying so, without waiting.
- [ ] [minor] F45 — README and PLAN say the promotion checks apply to commits released with this pipeline, and that step 5 tags `origin/main`'s newest merge commit.
- [ ] [minor] F46 — PLAN says each backend's image is checked before *it* is pushed.
- [ ] [minor] F47 — smoke's checkout doesn't keep git credentials.
- [ ] [minor] F48 — The README states the rotation without claiming a fixed order, and its versioned quickstart waits for health (`--wait`).
- [ ] [minor] F49 — PLAN §2 lists `Cargo.lock`, `LICENSE` and `.gitignore`.
- [ ] [minor] F52 — During its wait, promotion retries transient registry errors until the deadline, and still fails at once on a foreign revision.
- [ ] [minor] F54 — A failed image check prints the container's logs.
- [ ] [minor] F55 — Every job has a `timeout-minutes` longer than its normal run (promote's longer than its wait).
- [ ] [minor] F57 — `--revision` checks every platform's label, and an unreadable label fails with an `::error::` message.
- [ ] [minor] F58 — A level tag longer than 128 characters fails the format check.
- [ ] [minor] F62 — e08 fails if the payload's mark appears in any job of any workflow run for the throwaway PR.
- [ ] [minor] F63 — e09's `main` half compares job-level times.
- [ ] [minor] F65 — 04 fails unless the dry run's version equals the one its run's smoke tested.
- [ ] [minor] F66 — l1 covers GHCR's 403 answer for a missing package and fails a non-exact "not found" text.
- [ ] [minor] F67 — l2 fails if the level tag doesn't read back at the source digest after creation.
- [ ] [minor] F68 — 02's negative cases require the FAIL message they expect (`version`, or `set but empty`).
- [ ] [minor] F69 — e08 waits for its own PR's run (by head branch).
- [ ] [minor] F70 — 03 reads the version from smoke's output, not from echoed env blocks.

### Verdict: NO-GO
- **Reason:** 1 confirmed blocker (F42) and 3 confirmed majors (F59, F60, F61) are open, plus 20 confirmed minors. 5 refuted (F50, F51, F53, F56, F64). Progress this iteration: 33 slices closed. This is iteration 2 of at most 3, so the next adjudication is the last; anything left open then escalates to you.

## Iteration 3

### Closed slices
- [x] F42 — verified by `e12-dev-switched-to-main-waits-for-its-dry-run.sh` (dev's tip
  `a132243` carried 0 `release-ready` checks after its push run; switched PR #21 was
  BLOCKED until its dry run 40146914977 passed, then CLEAN) and `04` (the release-ready
  that gated PR #27 came from `dry-run.yml`)
- [x] F59 — verified by `fresh` in lib (`TREE=00578d2` makes e10 fail "stale observation";
  07/e05/e06 are explicit release-history checks)
- [x] F60 — verified by `has()` in lib (a match in a 300000-line text is found; no
  `gh … | grep` remains in the suite)
- [x] F61 — verified by `e08` (run 40147408856 must be the payload branch's) and `e11`
  (run 40147379333 must be `acceptance/base-switch`'s, and PR #23 must have a
  `base_ref_changed` event); merge states are asserted only when read live
- [x] F43 — verified by `l4-build-image.sh` (pushed digest == staged, checked digest; a
  failed check pushes nothing) and the main run 40148450199 ("pushed … (the image that
  was checked)" for all five)
- [x] F44 — verified by review (promote requires a `git rev-list --first-parent origin/main`
  commit); `e05` history covers the failure path
- [x] F45 — verified by review of the README step 5 and PLAN qualifiers
- [x] F46 — verified by review of PLAN's level-01 note
- [x] F47 — verified by review (smoke's checkout: `persist-credentials: false`)
- [x] F48 — verified by review (rotation order not claimed; `--wait` in the versioned quickstart)
- [x] F49 — verified by review of PLAN §2
- [x] F52 — verified by `l2-promote.sh` (two 502s during the wait are retried, then promoted)
- [x] F54 — verified by `l3-check-image.sh` (a crashing image's check shows its logs)
- [x] F55 — verified by review (`timeout-minutes` on every job; promote 30 > the 20-min wait)
- [x] F57 — verified by `l1-image-digest.sh` (a multi-platform index: every platform's label checked; mismatch exits 2)
- [x] F58 — verified by `l2-promote.sh` (a level tag over 128 characters fails the format check)
- [x] F62 — verified by `e08-only-dev-into-main.sh` (no job in any of the payload branch's 3 runs printed the mark)
- [x] F63 — verified by `e09-concurrency-never-cuts-a-publish.sh` (job-level windows; pair
  40149148487:1 and 40148450199:2, both fresh, overlapped and finished green)
- [x] F65 — verified by `04-dry-run-publish-on-pr-into-main.sh` (each build's version equals smoke's)
- [x] F66 — verified by `l1-image-digest.sh` (GHCR's real 403 for a missing package; a non-exact "not found" fails)
- [x] F67 — verified by `l2-promote.sh` (a create that didn't happen fails the read-back)
- [x] F68 — verified by `02-smoke-expect-version.sh` (negative cases require their FAIL messages; the fake must start)
- [x] F69 — verified by `e08` (waits by head branch)
- [x] F70 — verified by `03-ci-proves-version.sh` (smoke's "version sha-<7> in every answer" output line)

### Smells
- **N1** — left: condition not met (two jobs still log in, one line each; the login is unchanged)
- **N2** — retired: the build step no longer branches on `PUSH`. It passes `--push` to
  `scripts/build-image.sh`, whose dry run is a single guard clause.
- **N3** — left: condition not met (no service added)
- **N4** — retired: `dry-run` and `release-ready` moved to `dry-run.yml`, whose trigger
  filter replaces the repeated "PR into main" predicate.
- **N5** Dispensables / Duplicate Code at `ci.yml` (smoke's version step) and
  `dry-run.yml` (the `version` job): both compute `sha-${GITHUB_SHA::7}`. Noted: two
  one-liners in two workflows, and AT-04 fails if the dry run's version ever differs from
  smoke's (F65).
  - **Promote if:** a third place computes the version, or its format changes.

### Findings (unadjudicated)
Iteration 3: three read-only delegates, one per surface: gate and workflows (G), scripts and publishing (P), test integrity (T). Refuted findings F7, F11, F13, F27, F28, F31, F33, F38, F50, F51, F53, F56 and F64 were not revisited. Sources are given as delegate+letter or number. Ranked most severe first.

#### F71
- **Target:** fresh()
- **Claim challenged:** a mutated tree turns replayed tests red
- **Evidence:** fresh compares only .github/workflows and scripts; build inputs (compose.yaml VERSION args, Dockerfiles' ARG/ENV VERSION) are outside it, and no local test builds them all. (T1)
- **Breaking case:** drop python's VERSION arg in compose.yaml → replayed 01/03/04/e01/e10/e13 stay green
- **Confidence:** proven
- **Severity hint:** major

#### F72
- **Target:** fresh() inputs and run.sh environment
- **Claim challenged:** the replay can't be fooled by the environment
- **Evidence:** uncommitted edits are invisible (commit-to-commit diff); an exported HISTORY=1 or TREE disables or re-anchors freshness; caller RUN/PR/SHA leak into tests with no recorded entry; keys like 01_RUN are invalid, so 01–08 never get recorded inputs. (T3)
- **Breaking case:** edit ci.yml without committing → e10 replays green
- **Confidence:** proven
- **Severity hint:** major

#### F73
- **Target:** negative log assertions (e02, 04, e08)
- **Claim challenged:** 'no job held packages: write' / 'no GHCR push' / 'no beef'
- **Evidence:** `if has "$(job_log …)" pat; then fail`: a failed log fetch (expired, 404, rate limit, job still running) yields an empty text and the negative check passes; e02 has no positive log assertion at all. (T4)
- **Breaking case:** logs expired → every job_log is empty → e02 passes with a write token everywhere
- **Confidence:** proven
- **Severity hint:** major

#### F74
- **Target:** e01's 'a red smoke publishes nothing'
- **Claim challenged:** e01 would fail if a red smoke could publish
- **Evidence:** on any PR, publish is skipped by its event clause regardless of smoke, so e01 can't see the gate; no test has a red smoke on a push to main, where `needs: smoke` matters. (T5)
- **Breaking case:** `if: always() && push && …` on publish → e01, 05, e03, e09 all green
- **Confidence:** proven
- **Severity hint:** major

#### F75
- **Target:** e12 replay binding
- **Claim challenged:** E12_RUN/E12_PR prove the switched PR's own dry run produced its release-ready
- **Evidence:** the run isn't tied to PR #21 (no pull_requests / head match / after-the-switch check); the stray scan reads check runs, not commit statuses. (T6)
- **Breaking case:** E12_RUN = any dev→main release PR's dry run → green
- **Confidence:** proven
- **Severity hint:** major

#### F76
- **Target:** e09 feature half replay
- **Claim challenged:** the older run was cancelled by the newer one
- **Evidence:** only conclusions are checked (cancelled / success): no shared branch or ref, no ordering, NEW not checked for freshness. (T7)
- **Breaking case:** OLD = a hand-cancelled run, NEW = any green run → passes
- **Confidence:** proven
- **Severity hint:** major

#### F77
- **Target:** fresh() on pull_request runs
- **Claim challenged:** a PR run's headSha carries the workflows that ran
- **Evidence:** pull_request runs execute refs/pull/N/merge (head + base); fresh compares the head only. Not live today (`git diff bb2ec78 9f804c8` is empty). (T2)
- **Breaking case:** dev gains a ci.yml change after a feature branched → its PR run executes dev's ci.yml, fresh passes
- **Confidence:** proven (mechanism)
- **Severity hint:** major

#### F78
- **Target:** build-image.sh's frontend path
- **Claim challenged:** every published image was started and checked
- **Evidence:** the frontend is never started, yet build-image prints 'built … and checked it' / '(the image that was checked)', and publish.yml's comment says what ships is what was checked. (P-A)
- **Breaking case:** an nginx:alpine drift that won't start → frontend published, summary says checked
- **Confidence:** proven
- **Severity hint:** major

#### F79
- **Target:** where the script tests live
- **Claim challenged:** classification, promote, check-image and build-image are covered by tests
- **Evidence:** l1–l4 (and the whole suite) live in untracked .workflow/; nothing in the repo or CI runs them, so the coverage can't be reproduced and can regress unseen. (P-B)
- **Breaking case:** change image-digest.sh's matcher in a PR → CI green, nothing runs l1
- **Confidence:** proven
- **Severity hint:** major

#### F80
- **Target:** release-ready per commit
- **Claim challenged:** release-ready can only come from this PR's own dry run
- **Evidence:** checks attach to the SHA; a dev→main PR closed after a green dry run leaves release-ready=success on H, which a new PR at the same H shows before its own dry run reports. (G1)
- **Breaking case:** close #A (green), open #B at the same H → CLEAN during #B's dry run
- **Confidence:** unproven
- **Would be settled by:** close a green dev→main PR, open another at the same SHA, read mergeStateStatus during its dry run
- **Severity hint:** major

#### F81
- **Target:** re-running a single job
- **Claim challenged:** a failed newest dry run keeps main blocked
- **Evidence:** re-running release-ready alone in an older successful run on the same SHA posts a newer success. (G2)
- **Breaking case:** R1 green, R2 red after a title edit → re-run R1's release-ready → CLEAN
- **Confidence:** unproven
- **Would be settled by:** make R2 fail, re-run R1's release-ready, read mergeStateStatus
- **Severity hint:** major

#### F82
- **Target:** smoke on main's gate
- **Claim challenged:** the smoke that gates main is the PR's own run
- **Evidence:** the dev push run's smoke on the same SHA satisfies the required check, and a base-switched PR never gets a PR smoke. (G4)
- **Breaking case:** the PR's merge-commit smoke red, the push smoke green → mergeable
- **Confidence:** proven (base switch)
- **Severity hint:** minor

#### F83
- **Target:** edited events on closed PRs
- **Claim challenged:** an edit can't affect another PR's checks
- **Evidence:** editing a closed dev→main PR's title starts a dry run for its frozen head, which may be an open PR's head too. (G3)
- **Breaking case:** closed #A and open #B at H → #A's run posts a newer release-ready
- **Confidence:** unproven
- **Would be settled by:** edit a closed PR whose head equals an open PR's head
- **Severity hint:** minor

#### F84
- **Target:** only-dev-to-main per commit
- **Claim challenged:** a PR into main not headed by dev always fails the rule
- **Evidence:** a fork PR at dev's tip SHA (runs awaiting approval) shows H's earlier only-dev-to-main=success. (G5)
- **Breaking case:** fork PR at H → all three checks green
- **Confidence:** unproven
- **Would be settled by:** open a fork PR at H without approving its runs
- **Severity hint:** minor

#### F85
- **Target:** edits during a dry run
- **Claim challenged:** a dev→main PR reaches a stable green release-ready
- **Evidence:** each edit cancels and restarts the full dry run; frequent edits keep it red. (G6)
- **Breaking case:** a bot editing PR bodies → never green
- **Confidence:** proven (trace)
- **Severity hint:** minor

#### F86
- **Target:** promote's wait against publish durations
- **Claim challenged:** promotion waits for main's publish
- **Evidence:** the wait (20 min) is shorter than a build leg may take (45 min), and the message then says 'never published'. (G7, P-C)
- **Breaking case:** a 25-min publish plus an early tag → promote fails misleadingly
- **Confidence:** proven (numbers)
- **Severity hint:** minor

#### F87
- **Target:** read-back failure and re-run
- **Claim challenged:** what ships has the checked digest, or the run fails
- **Evidence:** a red read-back leaves the tag in GHCR; a re-run skips it via the guard, which doesn't know the checked digest. (P-D)
- **Breaking case:** a re-serialized copy → run 1 red, re-run green
- **Confidence:** proven (trace)
- **Severity hint:** minor

#### F88
- **Target:** which platform is checked
- **Claim challenged:** 'starts the amd64 image'
- **Evidence:** check-image runs `docker run` with no --platform: amd64 on GitHub's runners, but arm64 on this Mac (l4). (P-E, T15)
- **Breaking case:** l4 on Apple Silicon checks arm64
- **Confidence:** proven
- **Severity hint:** minor

#### F89
- **Target:** exact buildx error text
- **Claim challenged:** the classification is robust
- **Evidence:** 'absent' requires buildx's exact text; the runner's buildx isn't pinned. (P-F)
- **Breaking case:** a runner update rewords it → every publish fails (closed)
- **Confidence:** unproven
- **Would be settled by:** record `docker buildx version` and re-check the text on runner updates
- **Severity hint:** minor

#### F90
- **Target:** stderr on a successful inspect
- **Claim challenged:** a successful lookup parses
- **Evidence:** 2>&1 mixes any success-time stderr into the JSON. (P-G)
- **Breaking case:** a warning on success → jq error → a correct image fails
- **Confidence:** unproven
- **Would be settled by:** check whether inspect writes to stderr on success on the runner
- **Severity hint:** minor

#### F91
- **Target:** check-image's scope
- **Claim challenged:** the shipped backends meet the contract
- **Evidence:** only lang and version are checked; the full contract is smoke's, on a separate build. (P-H)
- **Breaking case:** a contract break that keeps lang/version → published
- **Confidence:** proven
- **Severity hint:** minor

#### F92
- **Target:** promotion across services
- **Claim challenged:** 'CI gives the same images that tag'
- **Evidence:** each matrix leg promotes alone; a missing source leaves 4 of 5 tagged and a red run. (P-I)
- **Breaking case:** one service unpublished → partial level
- **Confidence:** proven
- **Severity hint:** minor

#### F93
- **Target:** check-image when start fails
- **Claim challenged:** the check container is always cleaned up
- **Evidence:** if docker run creates but can't start the container, set -e exits before the trap is set. (P-J)
- **Breaking case:** bad entrypoint → leaked container, no logs
- **Confidence:** proven
- **Severity hint:** minor

#### F94
- **Target:** registry call timeouts
- **Claim challenged:** promote's deadline bounds the wait
- **Evidence:** imagetools calls have no timeout; a hung call runs to the job timeout. (P-K)
- **Breaking case:** a hung inspect → 30-min job timeout
- **Confidence:** proven
- **Severity hint:** minor

#### F95
- **Target:** the staging registry
- **Claim challenged:** what ships comes from a trusted staging step
- **Evidence:** registry:2 is a mutable tag; buildkit with network=host may let RUN steps reach it. (P-L)
- **Breaking case:** a compromised registry:2 reports a chosen digest
- **Confidence:** unproven
- **Would be settled by:** curl localhost:5000/v2/ from a RUN step
- **Severity hint:** minor

#### F96
- **Target:** first publish of a new package
- **Claim challenged:** an authenticated lookup of a missing package reads as absent
- **Evidence:** only the anonymous 403 was observed. (P-M)
- **Breaking case:** a sixth service's first guard exits 1
- **Confidence:** unproven
- **Would be settled by:** authenticated inspect of a missing package
- **Severity hint:** minor

#### F97
- **Target:** e09 'never cancelled'
- **Claim challenged:** no main or tag run was ever cancelled
- **Evidence:** only latest attempts are read; a cancelled first attempt that was re-run is invisible. (T8)
- **Breaking case:** cancel on main + re-run → half 1 green
- **Confidence:** proven (blind spot)
- **Severity hint:** minor

#### F98
- **Target:** e13's attribution
- **Claim challenged:** the python failure was arm64's
- **Evidence:** every multi-platform buildx log contains '[linux/arm64'; any python dry-run failure matches. (T9)
- **Breaking case:** python fails check-image for another reason → e13 passes
- **Confidence:** proven
- **Severity hint:** minor

#### F99
- **Target:** e02's scope
- **Claim challenged:** dev never runs the dry run
- **Evidence:** e02 reads ci.yml runs only; dry-run.yml runs aren't listed. (T10)
- **Breaking case:** dry-run.yml on [dev, main] → e02 green
- **Confidence:** proven
- **Severity hint:** minor

#### F100
- **Target:** 04's gaps
- **Claim challenged:** 04 catches GHCR writes, write tokens and version drift
- **Evidence:** the only-dev-to-main run isn't scanned; only $svc:$version is probed; GHCR copies go through imagetools create, which the grep doesn't target; both versions come from one expression; pick_pr may pick e12's throwaway PR. (T11)
- **Breaking case:** packages: write on only-dev-to-main.yml → 04 green
- **Confidence:** proven
- **Severity hint:** minor

#### F101
- **Target:** l2's revision case
- **Claim challenged:** l2 catches a revision mismatch read as absent
- **Evidence:** with PROMOTE_WAIT_SECONDS=0, `|| true` on the lookup still fails and the stderr still says 'revision'. (T12)
- **Breaking case:** the mutation survives l2
- **Confidence:** proven
- **Severity hint:** minor

#### F102
- **Target:** l1's matcher cases
- **Claim challenged:** only the exact answer reads as absent
- **Evidence:** `== "ERROR: "*": not found"` and a bare `403 Forbidden` match both survive l1. (T13)
- **Breaking case:** a proxy error ending ': not found' → absent, l1 green
- **Confidence:** proven
- **Severity hint:** minor

#### F103
- **Target:** observed bindings for e01, e11 and e03
- **Claim challenged:** a wrong recorded value can't pass
- **Evidence:** e01 doesn't check the PR is into main; e11 doesn't bind the run to the edited event; e03's BEFORE is hand-recorded. (T14)
- **Breaking case:** E11_RUN from a direct-into-main PR → green
- **Confidence:** proven
- **Severity hint:** minor

#### F104
- **Target:** 02's unset case
- **Claim challenged:** unset EXPECT_VERSION behaves as before
- **Evidence:** only the final PASS is asserted; an unconditional 'version  in every answer' line survives. (T16)
- **Breaking case:** the mutation → 02 green
- **Confidence:** proven
- **Severity hint:** minor

### Surfaces
- **Swept:** skipped jobs producing required-check names (none now); dry-run.yml result logic; permission inheritance (only `publish` writes; no token can post checks); ci.yml concurrency; job timeouts versus QEMU builds; promote.sh `$?`/exit-2 semantics; regex and length; no-op/immutable/create and re-read; the first-parent check; the guard on re-runs; `--revision` across platforms; check-image polling and logs; smoke.sh EXPECT_VERSION; staging registry failures (all fail closed); labels on copied indexes; `has()`; `wait_run`; 03; e08 binding; e10 steps; e09 job-level pair; l4 ordering; l3, 08 and e07. All held.
- **Unattacked:** GitHub's choice among same-name check runs on one SHA, and when a waiting job's check run is created (F80/F81 need live runs); 05 and 06 beyond a skim; dev's own protection details.

### Verdicts
Iteration 3 (final). 25 slices closed this iteration. Carried refutations still stand. Reproduction run: F97 (every earlier attempt of the re-run `main` runs: all `success`).

#### F71 — CONFIRMED major
- **Reason:** `fresh` covers only workflows and scripts, so a regression in compose or Dockerfile build inputs replays green. A gap in F59's fix.

#### F72 — CONFIRMED minor
- **Reason:** A dirty working tree, an exported `HISTORY`/`TREE`, or leaked `RUN`/`PR` can mislead the replay. That's operator misuse rather than a hidden false pass on a clean run, but it's cheap to refuse. The numeric keys are harmless (01–08 observe the newest runs by design).

#### F73 — CONFIRMED major
- **Reason:** A missing or empty log makes every negative log assertion pass. Missing evidence reads as a clean result.

#### F74 — CONFIRMED major
- **Reason:** Since the dry run moved out of ci.yml, e01 can't observe the `needs: smoke` publish gate: `publish` is skipped on PRs by its event clause anyway. The gate on `main` pushes is verified by review only.

#### F75 — CONFIRMED major
- **Reason:** e12's replay accepts any fresh dev dry run, because nothing binds the run to the switched PR.

#### F76 — CONFIRMED major
- **Reason:** e09's feature half accepts any cancelled run paired with any green run.

#### F77 — CONFIRMED minor
- **Reason:** The mechanism is real (PR runs execute the merge ref's workflows), but it needs base drift, and no recorded run is affected: `git diff bb2ec78 9f804c8` is empty.

#### F78 — CONFIRMED minor
- **Reason:** build-image.sh prints "checked" for the frontend, which is never started. The README's "each backend" is accurate, so this is a false message plus a known gap (the frontend can't start alone: nginx resolves `knock-api` at startup), not a broken criterion.

#### F79 — CONFIRMED major
- **Reason:** The script tests live only in untracked `.workflow/`, so nothing in the repo or CI guards `image-digest.sh`, `promote.sh`, `check-image.sh` or `build-image.sh`. Fixing it collides with PLAN §4 ("one smoke script … the project's only test"), which is a design decision for the user.

#### F80 — CONFIRMED minor
- **Reason:** Checks attach to the SHA, so "release-ready only from *this PR's* dry run" overclaims. The property that matters, a green dry run of this exact commit's content, does hold: main only ever receives dev, so the same SHA means the same merge content. Docs fix.

#### F81 — REFUTED
- **Reason:** It needs the owner to deliberately re-run a single job of an older run on their own repo, which is the trust root, as in F27.
- **Reopens only if:** someone other than the owner gains re-run or merge rights.

#### F82 — REFUTED
- **Reason:** Required checks are per SHA by GitHub's design. A green smoke of the same SHA is a smoke of the same content, and nothing claims the PR's own run must be the one.
- **Reopens only if:** a case is shown where the push-run smoke's content differs from what merges.

#### F83 — REFUTED
- **Reason:** An edit to a closed PR either posts a success for the same content or a failure that fails closed and is cleared by re-running the open PR's dry run.
- **Reopens only if:** it is shown letting different content merge.

#### F84 — REFUTED
- **Reason:** A fork PR at dev's exact SHA carries dev's content, and only the owner can merge it.
- **Reopens only if:** a PR with content other than dev's passes `only-dev-to-main`.

#### F85 — REFUTED
- **Reason:** Nothing here edits PRs automatically.
- **Reopens only if:** PR edits become automated.

#### F86 — REFUTED
- **Reason:** Observed publishes take about 5 min, against a 20-min wait. The README says to tag only after `main`'s run is green, and an early tag is recovered by re-running the failed promote jobs.
- **Reopens only if:** a publish leg takes more than about 15 min, or a tag pushed after a green `main` fails to promote.

#### F87 — REFUTED
- **Reason:** Every observed copy kept the staged digest. A re-serialized index would still reference the same checked platform manifests.
- **Reopens only if:** a copy is observed at a different digest.

#### F88 — CONFIRMED minor
- **Reason:** The comments say "amd64", but the check runs the host's native platform (arm64 in l4 on this Mac).

#### F89 — REFUTED
- **Reason:** Exact-text matching is F8's fix on purpose, and a reworded message fails closed and loudly.
- **Reopens only if:** a runner update rewords it.

#### F90 — REFUTED
- **Reason:** Every successful inspect in CI parsed.
- **Reopens only if:** jq fails on a successful inspect.

#### F91 — REFUTED
- **Reason:** The criterion for the shipped image is lang plus version (F2). The full contract is smoke's, run on the same sources.
- **Reopens only if:** a published image breaks the contract while smoke passed.

#### F92 — REFUTED
- **Reason:** Partial promotion followed by a re-run that converges is the accepted design (`fail-fast: false`).
- **Reopens only if:** a partial promotion can't be completed by re-running.

#### F93 — CONFIRMED minor
- **Reason:** A container that is created but fails to start leaks before the trap is set.

#### F94 — REFUTED
- **Reason:** A hung registry call is bounded by the job timeouts (F55).
- **Reopens only if:** a hang outlasts its job timeout.

#### F95 — REFUTED
- **Reason:** It falls under the deferred pinning decision, and every RUN step comes from the repo's own Dockerfiles.
- **Reopens only if:** pinning is un-deferred, or build steps not controlled by the repo appear.

#### F96 — REFUTED
- **Reason:** It fails closed and loudly, and only when a service is added, which is out of scope.
- **Reopens only if:** a new service's first publish fails at the guard.

#### F97 — CONFIRMED minor
- **Reason:** The blind spot is real (only latest attempts are read), but the history is clean: every earlier attempt of every re-run `main` run concluded `success`.

#### F98 — CONFIRMED minor
- **Reason:** e13's arm64 attribution matches any multi-platform log.

#### F99 — CONFIRMED minor
- **Reason:** e02 doesn't list dry-run.yml runs.

#### F100 — CONFIRMED minor
- **Reason:** 04's scan and probes have the listed gaps.

#### F101 — CONFIRMED minor
- **Reason:** l2's revision case survives the `|| true` mutation.

#### F102 — CONFIRMED minor
- **Reason:** l1's cases let the two matcher mutations survive.

#### F103 — CONFIRMED minor
- **Reason:** e01, e11 and e03 replays bind loosely to their recorded values.

#### F104 — CONFIRMED minor
- **Reason:** 02's unset case doesn't pin the absence of the version line.

### Carried smells
Shipping would carry N1, N3 and N5. None sits in code that a confirmed major touches: every open major is in the verification harness, not in the pipeline.

### Remediation slices
- [ ] [major] F71 — A replayed observation is stale if its commit differs from the tree under test in anything that affects a build or a run: `.github/workflows`, `scripts`, `compose.yaml`, `backends/`, `frontend/`.
- [ ] [major] F73 — A log assertion fails when the log can't be fetched or is empty, instead of passing a negative check.
- [ ] [major] F74 — The `needs: smoke` gate on a push to `main` is shown by a run, or explicitly accepted as verified by review.
- [ ] [major] F75 — e12's replay fails unless the dry-run run belongs to that PR (`pull_requests`, head SHA) and started after its `base_ref_changed` event.
- [ ] [major] F76 — e09's feature half fails unless OLD and NEW are `pull_request` runs of the same branch, NEW started after OLD, and both are fresh.
- [ ] [major] F79 — The script tests (`l1`–`l4`, `02`) are committed and run by CI, or the user records that PLAN §4's single-test rule stands.
- [ ] [minor] F72 — The replay refuses a dirty tree and an exported HISTORY/TREE/RUN/PR.
- [ ] [minor] F77 — Freshness for pull_request runs compares the merge ref's workflows.
- [ ] [minor] F78 — build-image.sh says "checked" only for images it started.
- [ ] [minor] F80 — README and PLAN say release-ready is per commit (a green dry run of this commit's content).
- [ ] [minor] F88 — check-image states, or pins, the platform it starts.
- [ ] [minor] F93 — check-image cleans up a container that failed to start.
- [ ] [minor] F97 — e09 reads every attempt of `main`/tag runs.
- [ ] [minor] F98 — e13 requires the failing step's own arm64 error.
- [ ] [minor] F99 — e02 also asserts that no dry-run.yml run exists for `dev`.
- [ ] [minor] F100 — 04 scans every workflow run of the PR's head, probes any new GHCR tag, and checks for `imagetools create` writes.
- [ ] [minor] F101 — l2 fails when a foreign revision is retried instead of failing at once.
- [ ] [minor] F102 — l1 fails both matcher mutations.
- [ ] [minor] F103 — e01, e11 and e03 replays bind to their PR, event and digests.
- [ ] [minor] F104 — 02 asserts no version line when EXPECT_VERSION is unset.

### Verdict: ESCALATED
- **Reason:**
  - **Open:** after the third adjudication, 6 confirmed majors are still open (F71, F73, F74, F75, F76, F79). Rule 4: the loop stops here instead of running a fourth pass.
  - **Where they are:** all six are in the *verification harness* (the replayed acceptance suite) or in a design decision (F79 against PLAN §4), not in the delivered pipeline. The pipeline's behaviour was verified live during this iteration: e12 BLOCKED→CLEAN, e13 red, e01/e08/e10/e11 red/blocked, X and Y published at their checked digests, the overlapping fresh pair, and e03's re-run skipping.
  - **Upstream cause:** the brief's choice to prove GitHub-hosted behaviour by *replaying recorded runs* keeps producing new integrity gaps. Each iteration closed the last set and the next teardown found new binding holes. That is a brief-level decision.
  - **Other counts:** 14 refuted this iteration, 0 INCONCLUSIVE.

### Decisions
User's decision after the escalation (2026-10-25): option 1, accept and ship.
- **F71** — waived: replay freshness ignores build inputs; a fresh ACT=1 run of the suite is the release check instead
- **F73** — waived: missing logs pass negative checks in replay; same reason, release checks are ACT=1 runs
- **F74** — waived: the `needs: smoke` gate on `main` pushes is accepted as verified by review (exercising it would mean breaking `main`)
- **F75** — waived: e12's replay binding; its ACT run (PR #21, BLOCKED→CLEAN) is the evidence
- **F76** — waived: e09's feature-half replay binding; its ACT run (40149639199 cancelled by 40149660598) is the evidence
- **F79** — waived: PLAN §4 stands (the smoke script is the project's only committed test); the script tests stay in `.workflow/acceptance`
- **Minors** F72, F77, F78, F80, F88, F93 and F97–F104 — accepted as tracked follow-ups

### Verdict: GO
- **Reason:** With F71, F73, F74, F75, F76 and F79 waived, no confirmed blocker or major is open and nothing is INCONCLUSIVE. The acceptance suite passed 24/24 against the released tree (`9f804c8`). 14 confirmed minors ship as tracked follow-ups, along with noted smells N1, N3 and N5.
