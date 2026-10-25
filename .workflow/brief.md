# Build Plan: level-01-pipeline — CI and publishing to GHCR

**Category:** enhancement
**Summary:** Every PR and push to `dev`/`main` builds the five images and gates them on
the smoke test. Merging to `main` publishes multi-arch, immutable `sha-<7>` images to
public GHCR packages, and a `level-*` tag promotes those exact digests. `dev` and
`main` are protected as in `nights-watch`.

**Why now** (use this to break ties between criteria): level 2 (k3d on an arm64 Mac)
needs native arm64 images it can pull **without credentials**, and every later level
(5 rolling update by `version`, 13 Argo CD) relies on `push → gated build → immutable
tag in a registry`. A publish that can ship an untested image, or a tag that can change
what it points at, undermines everything after it. When criteria conflict, gating and
immutability win over speed.

**Current behavior:**
- No `.github/` directory. Nothing runs on push. The images exist only on the
  developer's Mac, built by `docker compose up --build`.
- `scripts/smoke.sh [N]` (with `URL=` to override the target) fires N knocks. It fails
  unless all four `lang` values answered and every answer has the nine contract fields
  with `took_us` a non-negative integer, then prints the tally. It never checks
  `version`.
- `compose.yaml` passes `VERSION` (default `dev`) as a build arg to the four backends.
  The compose project already names the images `knock-knock-<svc>` for `go`, `python`,
  `rust`, `ts` and `frontend`.
- The repo is public. `main` and `dev` are unprotected. Any merge method is allowed.
  There are no rulesets. The default `GITHUB_TOKEN` is **read-only**. Work has been
  fast-forwarded to `main` locally and pushed.
- PLAN §3's level 01 note says CI "builds the five images (matrix)". That wording is
  superseded by this plan, see the docs criterion.

**Desired behavior:**

*CI (`ci.yml`):*
- **Triggers:** `push` to `dev` and `main`, `push` of `level-*` tags, and
  `pull_request` into `dev` and `main`. No other events, and never
  `pull_request_target`.
- **Concurrency:** one group per ref. On refs other than `main` and tags, a newer run
  cancels the one in progress. On `main` and on tags, runs are never cancelled.
- **Job `smoke`:**
  - Sets `VERSION=sha-<7>`: the first 7 characters of the commit SHA under test, fixed
    length, never `git`'s variable `--short`.
  - Runs `docker compose up --build --wait -d` (amd64, the runner's native
    architecture), then the smoke test with `EXPECT_VERSION` set to that same value.
  - Writes the tally to the job summary.
  - On failure, dumps `docker compose logs`.
- **Job `only-dev-to-main`:** runs only on PRs into `main`. Fails unless the head
  branch is `dev`. The branch name reaches the shell only through `env`.
- **Job `publish`:** calls `publish.yml` after `smoke` succeeds, and only in three
  cases:
  - a push to `main`, as a real publish;
  - a push of a `level-*` tag, as a promotion;
  - a PR into `main`, as a dry run.
- **Permissions:** `contents: read` at the top level. Only the `publish` call gets
  `packages: write`.

*Publish (`publish.yml`, reusable, `on: workflow_call`):*
- **Inputs:** the version string (`sha-<7>`), whether to push, and (on tag runs) the
  level tag to promote.
- **Build and push modes:** a matrix over the five services with `fail-fast: false`.
  For each service it builds `linux/amd64` + `linux/arm64` via QEMU/buildx, from the
  service's own build context, with build arg `VERSION=<version>`.
  - Each image gets OCI labels `org.opencontainers.image.source` (repo URL),
    `.revision` (full SHA) and `.version` (`<version>`).
  - Provenance and SBOM attestations are off, so each manifest list holds exactly two
    platforms.
  - **Dry run** (PR into `main`): full multi-arch build, no registry login, no push.
  - **Real publish** (push to `main`): log in to GHCR with `GITHUB_TOKEN`. If
    `ghcr.io/izentenosmith/knock-knock-<svc>:<version>` already exists, skip the build
    and push and say so in the summary. Otherwise build and push that tag.
- **Promotion mode** (push of a `level-*` tag): no build. For each service:
  - If `<version>` is missing from GHCR, fail with a message saying the commit was
    never published from `main`.
  - If the level tag already exists at the same digest as `<version>`, it's a no-op.
  - If the level tag exists at a different digest, fail.
  - Otherwise create the level tag from the `<version>` manifest (`imagetools create`),
    so its digest is identical.
- **Summary:** publish writes each service's tag, digest and action (pushed / skipped /
  promoted / no-op) to the job summary.

*Repository settings (applied once, by `gh api`, **only after explicit user
confirmation**):*
- `dev` and `main` get classic branch protection, copied from `nights-watch`:
  - PR required, with 0 approvals;
  - `enforce_admins: true`;
  - no force pushes, no deletions;
  - `strict: false` (branches needn't be up to date);
  - required checks: `smoke` on `dev`; `smoke` and `only-dev-to-main` on `main`.
- A tag ruleset on `refs/tags/level-*`: creation allowed; updating and deleting
  blocked; no bypass actors.
- Merge commits stay enabled. The convention, written in the README, is that PRs from
  `dev` into `main` use **merge commits** so `main` always contains `dev`. Feature PRs
  into `dev` can use squash or merge.

*Registry:*
- The five packages are public and linked to the repo. Pulling them needs no login.
- The first publish may create them as private. If so, switching them to public is a
  one-time manual step on GitHub's website, done by the user and documented in the
  README.

*Docs:*
- PLAN §3's level 01 note describes the pipeline as built:
  - CI is one compose job; the matrix lives in publish;
  - publish is a reusable workflow gated on `smoke`;
  - tags are immutable, and a level tag promotes;
  - dry-run publish on PRs into `main`;
  - branch protection.
- README status says level 1 is done, and documents the release flow:
  1. feature → PR into `dev`;
  2. `dev` → PR into `main`, merge commit;
  3. CI publishes `sha-<7>`;
  4. switch the packages to public if needed (once);
  5. tag `level-NN-…` on `main`'s merge commit.
- The README also documents `EXPECT_VERSION`.

**Key interfaces (test seams):**
- **Smoke test.** `scripts/smoke.sh [N]`, with `URL=` and optional `EXPECT_VERSION=`.
  It's the policy test and runs identically on a laptop, in CI and against k3d later.
  - Unset `EXPECT_VERSION` means behaviour is byte-for-byte as today.
  - Set, it means every answer's `version` must equal it, otherwise
    `FAIL: … version …` and exit code ≠ 0.
- **Workflow file names.** `ci.yml` and `publish.yml` (names fixed by PLAN).
  `publish.yml` is invoked only via `workflow_call`, never by a trigger of its own.
- **Check-name contract.** Job names `smoke` and `only-dev-to-main` are referenced by
  branch protection. Renaming either one blocks PRs, so treat them as a public API.
- **Image contract.**
  - Name and tags: `ghcr.io/izentenosmith/knock-knock-<svc>` for
    `<svc>` ∈ {`go`, `python`, `rust`, `ts`, `frontend`}, with tags `sha-<7>` and
    `level-NN-<slug>`. No `latest`, no other floating tag.
  - Content: a manifest list of exactly `linux/amd64` + `linux/arm64`. The three OCI
    labels as above.
  - Behaviour: the backends answer `version: sha-<7>`.
- **Observable surfaces for verification:**
  - `gh run list` / `gh run view` (status, jobs, summary);
  - `docker buildx imagetools inspect` (platforms, digests, labels);
  - an anonymous `docker pull` after `docker logout ghcr.io`;
  - `gh api` for branch protection, rulesets and repo merge settings.
- **Static check.** `actionlint` must pass on both workflow files before any push.

**Acceptance criteria** (ordered — first is the tracer-bullet candidate, each one a
single red→green slice; "verifiable at" names the earliest point it can be observed):

- [x] **Tracer bullet.** A PR into `dev` triggers `ci.yml`, and job `smoke` goes green.
      It builds all five images through compose, brings them up healthy and passes the
      smoke test with 4 languages, and the tally appears in the job summary.
      *Verifiable at: the first PR into `dev`.*
- [x] **`EXPECT_VERSION`.** With `EXPECT_VERSION=sha-abc1234`, the smoke script passes
      against images built with `VERSION=sha-abc1234` and fails, naming `version`,
      against images built with the default `dev`. Unset, it behaves exactly as today.
      *Verifiable at: a laptop, no GitHub needed.*
- [x] **CI proves the version plumbing.** In CI, `smoke` builds with
      `VERSION=sha-<first 7 of the commit under test>` and passes with
      `EXPECT_VERSION` set to the same value. *Verifiable at: the first PR into `dev`.*
- [x] **Dry run on PRs into `main`.** A PR from `dev` into `main` runs `smoke`,
      `only-dev-to-main` and a dry-run `publish`. All five services build for both
      platforms, with no login and no push. GHCR is unchanged afterwards.
      *Verifiable at: the first `dev`→`main` PR.*
- [x] **Real publish.** After a PR from `dev` into `main` is merged with a merge
      commit, the push to `main` publishes `ghcr.io/izentenosmith/knock-knock-<svc>:sha-<7>`
      for all five services. `<7>` comes from the merge commit's SHA. Each image is a
      manifest list of exactly `linux/amd64` and `linux/arm64`, carrying the `source`,
      `revision` and `version` labels. *Verifiable at: the first merge to `main`.*
- [x] **Anonymous pull.** After `docker logout ghcr.io`, pulling the `sha-<7>` rust
      image succeeds. A container started from it answers `/api/knock` with
      `"version":"sha-<7>"`, and `lang` matches the image. This also holds for the
      native arm64 variant on the Mac. *Verifiable at: after the first publish, once
      the packages are public.*
- [x] **Promotion.** Pushing the annotated tag `level-01-pipeline` on `main`'s merge
      commit runs CI on the tag. `publish` creates the `level-01-pipeline` tag for all
      five services, with **no build step** executing, and each level tag's digest is
      identical to that service's `sha-<7>` digest. *Verifiable at: the level tag push,
      after user confirmation.*
- [x] **Branch protection.** With the settings applied, `gh api` shows protection on
      `dev` and `main` matching the `nights-watch` shape, with the required checks
      named as above. A direct `git push` to `dev` or `main` is rejected.
      *Verifiable at: after settings are applied, with user confirmation.*
- [x] **Docs.** PLAN §3's level 01 note and the README release flow describe the
      pipeline as built (see Desired behavior → Docs), including the one-time step to
      make the packages public.

*Edge cases:*
- [x] **A failing smoke test blocks publishing.** When `smoke` fails on a push to
      `main`, the `publish` job doesn't run, nothing reaches GHCR, and the failed job's
      log includes `docker compose logs` output.
- [x] **Feature branches never publish.** A PR into `dev` or a push to `dev` never
      runs `publish` in any mode, and has no `packages: write` permission anywhere in
      the run.
- [x] **Re-runs are safe.** Re-running a successful `main` run skips every service
      ("`sha-<7>` already exists") and pushes nothing. Each `sha-<7>` digest is
      unchanged before and after.
- [x] **A partial failure converges.** If one service's publish fails, the other four
      still finish (`fail-fast: false`). Re-running the failed jobs publishes only the
      missing service, and the four already published are skipped by the guard.
- [x] **A level tag on an unpublished commit fails.** Pushing a `level-*` tag on a
      commit whose `sha-<7>` doesn't exist in GHCR fails `publish` with a message
      saying the commit was never published from `main`. No level tag is created for
      any service.
- [x] **A conflicting level tag fails.** If a service's level tag already exists at a
      different digest from `sha-<7>`, promotion of that service fails. A level tag
      already at the same digest is a no-op, and the run is green.
- [x] **The tag ruleset holds.** With the ruleset applied, deleting
      `level-01-pipeline` on the remote, or force-pushing it to another commit, is
      rejected. Creating a new `level-*` tag is allowed.
- [x] **Only `dev` may merge into `main`.** A PR into `main` from any branch other than
      `dev` fails `only-dev-to-main`, and the error names the rule. A branch name
      containing shell metacharacters doesn't execute (input goes through `env`).
- [x] **Concurrency never cuts off a publish.** Two quick pushes to a feature PR
      cancel the older run. Two quick pushes to `main` (or a tag) both run to
      completion; neither is cancelled.
- [x] **A private package shows up before level 2.** If a package is still private
      after the first publish, the anonymous-pull criterion fails visibly (an
      authentication error). It's never reported as passing.

**Test seams & prior art:**
- **Smoke script.** The only existing test, and the black-box harness for the app
  contract. Extend it in its own style: `set -euo pipefail`, compatible with bash 3.2
  (macOS `/bin/bash`), a `fail()` helper that prints `FAIL: …` to stderr, `jq -s` over
  a temp file of answers, env overrides like `URL`.
  - Its existing negative checks (a backend stopped means a failing knock; a bad
    `took_us` from a fake server means a contract failure) are the pattern for the
    `EXPECT_VERSION` red test. Serve a canned answer with a different `version`, or
    build with the default `VERSION=dev`.
- **Workflow prior art.** `izentenosmith/nights-watch` `.github/workflows/ci.yml`:
  - the trigger block `pull_request`/`push` on `[dev, main]`;
  - `only-dev-to-main` with `if: github.event_name == 'pull_request' &&
    github.base_ref == 'main'`, and the head ref passed through `env` with the comment
    explaining why. Mirror this verbatim.
  - Actions pinned to major versions.
- **Protection prior art.** `gh api repos/izentenosmith/nights-watch/branches/{dev,main}/protection`
  is the reference shape to reproduce. The knock-knock checks `smoke` and
  `only-dev-to-main` replace its `unit`.
- **Verification of workflows.** There's no local runner: `actionlint` is the
  pre-push gate. Behavioural criteria are observed on real runs with `gh run view`
  and with `docker buildx imagetools inspect` against GHCR.
  - For the destructive edge cases (unpublished-commit tag, conflicting tag, ruleset
    rejection), prefer a throwaway tag name that **does not** match `level-*`
    wherever the behaviour allows it, so no public package or protected tag gets
    polluted. Where only a real `level-*` name exercises the path (the ruleset
    itself), confirm with the user first.
- **Image inspection.** Level 0 already established the per-image runtime checks
  (`/api/knock` fields, `version`, non-root user via `docker image inspect`). Reuse them
  against the pulled GHCR images.

**Deferred by design** (constraints, not work — carried from architect-deep-dive):
- **Build cache.** GHA cache, one scope per service when it comes. Deferred behind the
  cache flags on the build step; images, tags and the guard are unaffected. Forced by
  publish runs over ~10 min or CI over ~5 min, sustained. No criterion may assume or
  require a cache.
- **arm64 smoke test in CI.** Deferred behind the CI job's `runs-on`; the smoke script
  is architecture-agnostic. Forced by an arm64-only bug reaching the Mac. In CI, arm64
  is only *built* (dry run and publish).
- **Full-SHA action pinning and Dependabot.** Deferred behind the `uses:` lines;
  major-version tags for now. Forced by `sha_pinning_required` being enabled, or an
  incident with an action.
- **Signing, provenance, SBOM.** Deferred behind the build-step flags; attestations
  stay off for now. Forced by a supply-chain level, or Argo CD verifying images.
- **Manual republish (`workflow_dispatch`).** Deferred behind `publish.yml`'s trigger
  list, which today is `workflow_call` only. Forced by the first time a re-publish is
  needed.

**Out of scope:**
- Any app code change in the backends or frontend. The `/api/knock` contract,
  `compose.yaml` and the local quickstart stay as they are. The smoke script's only
  change is the optional `EXPECT_VERSION`.
- k3d, Kubernetes manifests, the CI k3d job (level 2), CORS and the `Target` field
  (level 3), `DELAY_MS` (level 9), Argo CD and tag bumps (level 13).
- Floating tags (`latest`, `main`, `dev`). Publishing from `dev` or from feature
  branches. Publishing from PR runs.
- A matrix in CI (CI stays one compose job).
- Pull secrets or PATs anywhere.
- Changing `nights-watch`.
- Automating the switch to public (not possible for personal-account packages).

**Acceptance tests** (stage 3 — tdd is done when these pass):
- **Command:** `.workflow/acceptance/run.sh` (all), or `.workflow/acceptance/run.sh <pattern>`
  (e.g. `02`, `e0`).
- **Modes:**
  - Tests marked **ACTS** push throwaway branches, tags or PRs, or re-run workflows on
    the public repo. They only act with `ACT=1`, which must be confirmed with the user
    first. Without it, they observe a given `RUN=<id>` or stay red with
    "not observed yet".
  - Only `02` runs fully locally. The others observe GitHub and GHCR, and turn green
    only once the pipeline has actually run there.
- **Red reasons at creation (2026-10-24):** `02` fails on behaviour (`EXPECT_VERSION`
  is ignored). The rest fail because nothing exists yet: no `ci.yml`, no PR, no
  published image, no tag, no protection, no ruleset.
- [x] Tracer bullet: a PR into `dev` runs `smoke` green → `01-pr-into-dev-runs-smoke.sh`
      (the tally-in-job-summary part isn't checked: no public API exposes job summaries;
      check it in the UI).
- [x] `EXPECT_VERSION` → `02-smoke-expect-version.sh` (local, fake API fixture at the
      boundary).
- [x] CI proves the version plumbing → `03-ci-proves-version.sh`
- [x] Dry run on PRs into `main` → `04-dry-run-publish-on-pr-into-main.sh`
- [x] Real publish → `05-merge-to-main-publishes.sh`
- [x] Anonymous pull → `06-anonymous-pull.sh` (anonymous through an empty
      `DOCKER_CONFIG`, so it never logs the user out).
- [x] Promotion → `07-level-tag-promotes.sh` ("no build step" is observed as identical
      digests).
- [x] Branch protection → `08-branch-protection.sh` (through the API; a real direct-push
      attempt would land a commit on `dev` if protection were missing).
- Not acceptance-testable: **Docs** (PLAN and README describe the pipeline as built).
  It's prose, not behaviour; checked in refactor-review and devils-advocate.
- [x] Edge case: a failing smoke test blocks publishing →
      `e01-failed-smoke-blocks-publish.sh` (ACTS: a throwaway broken PR into `dev`).
      This covers the compose-logs dump and "nothing published after a red smoke". The
      `needs: smoke` gate on a real `main` push can't be exercised without breaking
      `dev`; tdd covers that half.
- [x] Edge case: feature branches never publish → `e02-feature-branches-never-publish.sh`
      (reads each job's `GITHUB_TOKEN Permissions` log section).
- [x] Edge case: re-runs are safe → `e03-rerun-is-a-no-op.sh` (ACTS: re-runs `main`'s CI).
- Not acceptance-testable (implemented, not exercised): **a partial failure converges.** It needs one service's
  publish to fail on a real runner (fault injection on GitHub). Covered by tdd at the
  publish matrix (`fail-fast: false`) and the per-service guard, which `e03` also
  exercises.
- [x] Edge case: a level tag on an unpublished commit fails →
      `e05-level-tag-on-unpublished-commit-fails.sh` (ACTS: uses
      `level-99-acceptance-unpublished`). **Must run before the tag ruleset is applied**;
      it refuses to act once a ruleset exists.
- [x] Edge case: a conflicting level tag fails → `e06-level-tag-same-digest-is-a-no-op.sh`
      covers the same-digest no-op half (ACTS: re-runs the level tag's CI). The
      different-digest failure half needs a forged tag in a public package and a PAT
      with `packages: write`, which Q7 forbids; tdd covers it at the promotion step.
- [x] Edge case: the tag ruleset holds → `e07-level-tags-are-immutable.sh` (through the
      API; deleting a real level tag to test it is what the ruleset forbids).
- [x] Edge case: only `dev` may merge into `main` → `e08-only-dev-into-main.sh` (ACTS:
      branch `acceptance/x-$(id)`; `uid=` in the log would mean it was executed).
- [x] Edge case: concurrency never cuts off a publish →
      `e09-concurrency-never-cuts-a-publish.sh`. The `main`/tag half always observes the
      full history; the feature half ACTS with two quick pushes.
- Edge case: a private package shows up before level 2 → covered by
  `06-anonymous-pull.sh`. A private package fails it with an authentication error,
  which is the visible failure this criterion asks for; there's no separate test.

## Revisions
- 2026-10-24 — stage 3: acceptance tests written under `.workflow/acceptance/`
  (16 tests, all red; 2 criteria not acceptance-testable, 1 folded into `06`). Mapping
  recorded above. `02` uses `fixtures/fake_api.py` as a fake for the compose stack at
  the smoke test's boundary.
- 2026-10-24 — stage 4 (feedback edge): the feature branch is `feat/pipeline`, not
  `level-01-pipeline`. A branch with the same name as the level tag makes
  `git checkout level-01-pipeline` ambiguous (the README's replay instruction) and makes
  `--branch level-01-pipeline` filters match both the PR runs and the tag run.
- 2026-10-24 — stage 4 (feedback edge): AT-01 read compose's progress output in one
  format (`Image knock-knock-<svc> Built`, single spaces), but the runner's compose
  prints ` <svc>  Built` and `Container knock-knock-<svc>-1  Healthy`. The criterion is
  unchanged ("all five built and healthy"); the test now accepts either build-line form
  and any run of whitespace, and requires a `Healthy` line for every service.
- 2026-10-24 — stage 4 (feedback edge): e01's setup never broke anything. The line it
  appended, `this is not python`, is valid Python (an identity comparison) and sits
  after `serve_forever()`, so the backend stayed healthy and CI rightly passed (run
  40103734116, PR #2). The setup now raises at import
  (`raise RuntimeError("broken on purpose …")` as the first line), so the container
  dies, `compose up --wait` fails, and the traceback lands in `docker compose logs`.
  The criterion and the assertions are unchanged.
- 2026-10-24 — stage 4 (feedback edge): AT-04 required every job under `publish` to
  succeed, but on a dry run the promotion job is skipped by design (it only runs on
  `level-*` tags). The criterion is unchanged: "all five services build for both
  platforms". The test now requires no publish job to fail and a green build for each
  of the five services; skipped jobs are allowed.
- 2026-10-24 — stage 4 (feedback edge): the packages came out **public** on the first
  publish (AT-06 passed anonymously right after run 40108140731). Published by the
  public repo's workflow and linked by the `source` label, they took the repo's
  visibility. The "one-time manual switch to public" is therefore a fallback, not a
  step. The README release flow says so; AT-06 and the private-package criterion are
  unchanged.
- 2026-10-24 — stage 4 done: all 16 acceptance tests green (`.workflow/acceptance/run.sh`,
  replaying ACT runs from `observed.env`). Releases: PR #1 → `dev`, #6 → `main`
  (`c063e45`, first publish), #7 → `dev`, #8 → `main` (`52dd932`), tag
  `level-01-pipeline` on `52dd932` (run 40110298668: promotion on attempt 1, no-op re-run on attempt 2).
  Not exercised on GitHub: a partial publish failure converging, and promotion failing
  on a level tag at a different digest (implemented in `publish.yml`, see the not
  acceptance-testable notes). Found while building: GitHub's default `run` shell has no
  `pipefail` (fixed with `defaults.run.shell: bash`); a missing GHCR package answers
  403, not "not found" (the lookup treats both as absent).
- 2026-10-24 — loop iteration 2 (remediation slices from `.workflow/ledger.md`): the
  pipeline changed shape and the suite changes with it.
  - Shape: `only-dev-to-main` is now its own workflow (`only-dev-to-main.yml`, PRs into
    `main` only, including base edits). The dry run is the `dry-run` job, with the
    required `release-ready` after it; the real publish is the `publish` job. `main`
    requires `smoke`, `only-dev-to-main` and `release-ready`.
  - New local tests against a real registry (`registry:2` on localhost):
    - `l1` image-digest classification and `--revision` (F8, F25);
    - `l2` promotion decision (F1, F4, F24, F29);
    - `l3` check-image (F2).
  - New ACTS tests:
    - `e10`: a contract failure inside smoke.sh turns `smoke` red (F22);
    - `e11`: switching a PR's base to `main` blocks it (F10).
  - `e01` now targets `main` from a throwaway branch: a red smoke skips the dry run,
    `release-ready` is red, and the PR is blocked (F5, F17).
  - Assertions read a job's *output* (`job_output`, which drops the step script and env
    that GitHub echoes into each step's log header), never the echoed script (F14–F16).
  - `04`:
    - reads the version the dry run used from its own output, and proves absence
      through `image-digest.sh` (F18, F39);
    - requires buildx platform lines and a check-image line per backend (F19);
    - requires that no job in the run holds `packages: write` (F23).
  - `07` checks the remote tag is annotated and on `main`, and that promote ran while
    build was skipped (F40).
  - `08` expects `release-ready` on `main`.
  - `e06` compares against the source digests (immutable) instead of a snapshot taken
    just before (F14).
  - `e08` uses a payload that prints `beef` to stderr if executed (F20).
  - `e09`'s `main` half requires two overlapping `main` runs, both green (F21).
  - The lib skips `acceptance/*` PRs and picks runs by head branch (F41).
  - Not acceptance-testable:
    - F9: a fork's `dev` needs a second account's fork. Covered by the head-repo
      comparison, with `04`/`e08`/`e11` proving the rule still passes `dev` and rejects
      the rest.
    - F26: credentials not persisted; checkout config, visible in the workflow.
    - F32: job summaries have no public API; check in the UI.
- 2026-10-25 — loop iteration 3 (remediation slices F42–F70):
  - **Design change (F42).** The dry run and `release-ready` move out of `ci.yml` into
    `dry-run.yml`, triggered only by PRs into `main` (opened, synchronize, reopened,
    edited). Push runs never produce a `release-ready` check, so the required check can
    only come from the PR's own dry run.
    - A red smoke no longer skips the dry run. The dry run pushes nothing, and the
      required `smoke` check still blocks the merge.
    - e01 now asserts: red smoke, nothing published, PR BLOCKED.
    - New ACTS test `e13`: a breakage only the arm64 dry run sees (smoke green) turns
      `release-ready` red (F5).
    - New ACTS test `e12`: a PR from `dev` switched to `main` is BLOCKED until its own
      dry run passes (F42).
  - **"What ships is what was checked" (F43).** Publish builds both platforms once into a
    registry on the runner, starts the amd64 image from there, then copies that exact
    index to GHCR (same digest).
  - **Freshness (F59).** Every test that observes a GitHub run fails "stale observation"
    unless that run's commit has the same `.github/workflows` and `scripts` as the tree
    under test (`TREE`, default `HEAD`). The exception is 07, e05 and e06: they observe
    the `level-01-pipeline` release, which ran the workflows at `52dd932`, and they say
    so in their output. A new level tag is permanent, so the current promote code is
    covered by `l2` until the next level's tag, whose run is the first on GitHub.
- 2026-10-25 — stage 4, iteration 3 (feedback edge): with build-once publishing (F43),
  every build, the dry run included, pushes to the runner's own staging registry
  (`localhost:5000`). AT-04's "no push" means nothing pushed to GHCR: the test now matches
  `pushing manifest for ghcr.io` and a GHCR login, not any push.
- 2026-10-25 — after the loop (the user accepted escalation option 1): replayed
  observations (`observed.env`) are a convenience, not release evidence. **The release
  check for a level is a fresh `ACT=1` run of the ACTS tests plus the full suite against
  the released tree.** The script tests stay in `.workflow/acceptance` (PLAN §4 unchanged).

