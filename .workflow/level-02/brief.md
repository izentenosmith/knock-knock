# Build Plan: level-02-cluster — the same UI, now in Kubernetes

**Category:** enhancement
**Summary:** Plain YAML under `k8s/` deploys the published GHCR images to a k3d cluster: four
backend Deployments behind **one** Service `knock-api` (selected by the shared label
`pool: knock`), a frontend Deployment and Service, and a Traefik Ingress for `/`. The same
`scripts/smoke.sh` passes through the ingress on the laptop and in a new required CI job
`cluster`.

**Why now** (use this to break ties between criteria): every later level (3 L4 vs L7,
4 probes, 5 rolling update, 6 scaling, 8 drain, 9 config, 10 Kustomize, 13 Argo CD) needs a
cluster built from plain YAML that runs the published, immutable images. Level 2 is the
first consumer of level 1's GHCR images. When criteria conflict, **"what you apply is what
runs"** wins: the manifests in `k8s/` are the artifact under test, they only ever reference
images that are already published, and the smoke test stays strict (no retries) so later
levels can see dropped requests.

**Current behavior:**
- The app runs only on Docker Compose (`compose.yaml`): the four backends share the network
  alias `knock-api`, and nginx in the frontend (`worker_processes 1`) round-robins across the
  addresses that name resolves to, **once, at startup**. The frontend listens on 8080 and is
  published on `localhost:8080`.
- All four backends already read `POD_NAME` and `NODE_NAME` from the environment, falling
  back to the hostname and `local`. They listen on 8080 and run as non-root. No app code
  change is needed for this level.
- `scripts/smoke.sh [N]` (default 40, `URL=` default `http://localhost:8080/api/knock`,
  optional `EXPECT_VERSION=`) fails unless all four languages answered and every answer
  carries the nine contract fields with a valid `took_us`; it never retries a knock.
- `ci.yml` has `smoke` (compose, amd64) and `publish` (`needs: smoke`, `main` and
  `level-*` tags only). `dry-run.yml` provides `release-ready`; `only-dev-to-main.yml`
  provides `only-dev-to-main`. Protection: `smoke` required on `dev`; `smoke`,
  `only-dev-to-main`, `release-ready` on `main`. `level-*` tags are immutable (ruleset).
- GHCR holds `ghcr.io/izentenosmith/knock-knock-<svc>:sha-04f74b3` (the newest `main`
  publish) for `go`, `python`, `rust`, `ts`, `frontend`: public, multi-arch
  (`linux/amd64` + `linux/arm64`). The backends in it answer `version: sha-04f74b3`. App
  code is identical to `level-01-pipeline` (`52dd932`).
- There is no `k8s/` directory, no k3d anywhere, and k3d isn't installed on the Mac.
- Level 1's design record lives in `.workflow/level-01/`; the acceptance suite in
  `.workflow/acceptance/` (runner glob `[0-9el][0-9]*-*.sh`).

**Desired behavior:**

*Cluster (documented in the README, identical in CI):*
- `k3d cluster create knock --agents 2 -p "8080:80@loadbalancer"`: one server, two agents,
  k3d's built-in Traefik, servicelb and metrics-server, the ingress on `localhost:8080`.
- `kubectl apply -f k8s/` (flat directory, default namespace) creates everything.
- Readiness is waited for **outside** the smoke test: every Deployment `Available`
  (bounded), then a bounded poll until `GET /api/knock` through the ingress answers 200, then
  the strict smoke test.
- Compose and the cluster both use host port 8080; the README says to stop compose first.

*Manifests (`k8s/`, plain YAML, no Kustomize):*
- Four backend Deployments, `knock-go`, `knock-python`, `knock-rust`, `knock-ts`, one
  replica each. Their pods carry the shared label `pool: knock` (plus a per-Deployment label
  for the Deployment's own selector). Each container exposes 8080 and gets
  `POD_NAME` ← `metadata.name` and `NODE_NAME` ← `spec.nodeName` through the Downward API.
- **One** Service `knock-api` (ClusterIP, port 8080 → 8080) selecting only `pool: knock`.
  No per-language Service exists.
- A frontend Deployment (one replica) and a ClusterIP Service for it on 8080. Its nginx is
  unchanged and keeps proxying `/api/` to `knock-api:8080`, which is now the Service.
- One Ingress routing path `/` (prefix) to the frontend Service, served by k3d's Traefik.
- **Image pin:** all five `image:` fields are `ghcr.io/izentenosmith/knock-knock-<svc>:sha-04f74b3`
  (one tag for all five, already published, equal to the `version` the backends report). No
  `latest`, no other floating tag, no `imagePullSecrets`.
- **Bump (until level 13):** a normal PR into `dev` that changes the five `image:` lines to
  a newer published `sha-<7>`. The README gives the one-line command. A level that changes
  app code ships in two releases (code first, then the pin bump); level 2 changes none.

*Smoke test:*
- New optional `EXPECT_NODE_PREFIX=…`: when set, every answer's `node` must start with it,
  otherwise `FAIL: …` naming `node` and exit ≠ 0. Set but empty is a failure, like
  `EXPECT_VERSION`. Unset means behaviour and output are byte-for-byte as today. CI and the
  README use `EXPECT_NODE_PREFIX=k3d-knock-`.
- No retries are added. A failed knock still fails the run.

*CI (`ci.yml`, new job `cluster`):*
- Runs on the same events as `smoke`, in parallel with it, with `contents: read` only.
- Installs a **pinned** k3d release (`v5.9.0`) from its GitHub release, never a script from
  a moving branch; creates the cluster with the README's exact flags; applies `k8s/`; waits
  as above; runs `scripts/smoke.sh` with `EXPECT_NODE_PREFIX=k3d-knock-` and
  `EXPECT_VERSION` = the single tag the manifests pin.
- The pinned tag is read from `k8s/`. If the five images don't share exactly one tag, the job
  fails before applying, saying the pins disagree.
- Writes the smoke output to the job summary (as `smoke` does). On failure, dumps
  `kubectl get pods -o wide`, `kubectl describe pods` and the containers' logs.
- `publish` keeps `needs: smoke` only and doesn't wait for `cluster`.

*Repository settings (applied once, by `gh api`, **only after explicit user
confirmation**, and only after `cluster` has run green on `dev`):*
- `cluster` joins the required checks: `dev` = `smoke`, `cluster`; `main` = `smoke`,
  `cluster`, `only-dev-to-main`, `release-ready`. Nothing else in the protection changes.

*Docs:*
- PLAN §3's level 02 note describes the cluster as built: the create command with its port
  mapping, the pin and how it's bumped, the `cluster` job and its required status, waiting
  outside smoke, `EXPECT_NODE_PREFIX`, and why `pod` can't prove the Downward API through a
  knock (a pod's hostname is its name). PLAN §2's `scripts/smoke.sh` line stays accurate.
- README: status says level 2 is done; a k3d quickstart (install, create, apply, wait,
  smoke, delete), the "compose down first" note, `EXPECT_NODE_PREFIX`, the pin-bump command,
  and `cluster` in the pipeline's required checks.

**Key interfaces (test seams):**
- **The documented commands.** `k3d cluster create knock --agents 2 -p "8080:80@loadbalancer"`,
  `kubectl apply -f k8s/`, the wait, and `scripts/smoke.sh`. This is the outermost seam, the
  one a learner uses and CI repeats.
- **The ingress URL.** `http://localhost:8080/` (the UI) and `/api/knock` (the contract
  through Traefik → frontend nginx → `knock-api` → a backend pod).
- **Smoke test.** `scripts/smoke.sh [N]` with `URL=`, `EXPECT_VERSION=` and the new
  `EXPECT_NODE_PREFIX=`. It's the policy test for compose, k3d-in-CI and the laptop alike.
- **Manifest contract (names later levels and nginx depend on; treat them as public API):**
  - Service `knock-api`, port 8080, selector exactly `pool: knock`.
  - Backend Deployments `knock-<lang>`, so pod names read `knock-rust-…` as in PLAN §1.
  - Every backend pod labelled `pool: knock`; the frontend pod not.
  - The env names `POD_NAME`/`NODE_NAME` with their `fieldRef`s.
  - Image refs `ghcr.io/izentenosmith/knock-knock-<svc>:sha-<7>`, one tag across all five.
- **Cluster objects** for verification through `kubectl`: Deployments, pods (`-o wide`
  for nodes), the `knock-api` EndpointSlices (which pods back the one Service), nodes
  (`kubernetes.io/arch`).
- **Check-name contract.** The job name `cluster` is referenced by branch protection.
  Renaming it blocks PRs; treat it as public API, like `smoke`.
- **Observable surfaces on GitHub:** `gh run view` (jobs, logs), `gh pr view` (merge state),
  `gh api …/protection`.
- **Static check.** `actionlint` must pass on `ci.yml` before any push.

**Acceptance criteria** (ordered — first is the tracer-bullet candidate, each one a single
red→green slice; "verifiable at" names the earliest point it can be observed):

- [ ] **Tracer bullet: same UI, now in Kubernetes.** From scratch on the Mac, the README's
      exact commands (create, apply, wait) give a cluster whose ingress at
      `localhost:8080` serves the UI, and `scripts/smoke.sh` with
      `EXPECT_VERSION=sha-04f74b3` and `EXPECT_NODE_PREFIX=k3d-knock-` passes with all four
      languages. The nodes are `arm64` and the images were pulled anonymously.
      *Verifiable at: the laptop, with k3d installed.*
- [ ] **`EXPECT_NODE_PREFIX`.** Set to `k3d-knock-`, smoke passes when every `node` starts
      with it and fails, naming `node`, when any answer says `local` (or another prefix).
      Set but empty fails. Unset, the output is byte-for-byte as before.
      *Verifiable at: the laptop, no cluster (fake API).*
- [ ] **One Service over four Deployments.** In the running cluster, `knock-api` is the only
      Service in front of the backends, it selects exactly `pool: knock`, and its endpoints
      are four ready pods: one each from `knock-go`, `knock-python`, `knock-rust` and
      `knock-ts`. The frontend pod isn't among them.
      *Verifiable at: the laptop cluster.*
- [ ] **Downward API.** Every backend container's `POD_NAME` comes from `metadata.name` and
      `NODE_NAME` from `spec.nodeName` (pod spec). Each answer's `node` names the node that
      pod is scheduled on, and its `pod` names that pod. *Verifiable at: the laptop cluster.*
- [ ] **Immutable pin.** All five `image:` refs in `k8s/` are
      `ghcr.io/izentenosmith/knock-knock-<svc>:<one sha-<7> tag>`, that tag exists on GHCR for
      every service, and the running backends report it as `version`.
      *Verifiable at: the laptop (registry) and the cluster.*
- [ ] **Ingress routes `/` to the frontend.** `GET /` through the ingress returns the
      frontend's HTML, and `/api/knock` reaches a backend only through the frontend's nginx
      (the Ingress has no rule pointing at `knock-api`). *Verifiable at: the laptop cluster.*
- [ ] **CI `cluster` job.** A PR into `dev` runs `cluster`, which creates k3d (pinned
      `v5.9.0`, the README's flags), applies `k8s/`, and passes smoke through the ingress with
      `EXPECT_VERSION` = the pinned tag and `EXPECT_NODE_PREFIX=k3d-knock-`. It holds only
      `contents: read`. *Verifiable at: the first PR into `dev`.*
- [ ] **Required on `dev` and `main`.** With the settings applied, `gh api` shows `cluster`
      among the required checks of both branches, with every other protection field as
      before. *Verifiable at: after settings are applied, with user confirmation.*
- [ ] **Docs.** PLAN §3's level 02 note and the README describe the cluster as built (see
      Desired behavior → Docs).

*Edge cases:*
- [ ] **An unpublished pin fails CI loudly.** A PR whose `k8s/` pins a `sha-<7>` that GHCR
      doesn't have turns `cluster` red within its bounded wait, the log shows the
      `ImagePullBackOff`/`ErrImagePull` pod dump, smoke never runs, and the PR is blocked.
      *Verifiable at: a throwaway PR (ACTS), once `cluster` is required.*
- [ ] **Disagreeing pins fail before applying.** If the five images in `k8s/` don't share
      exactly one tag, `cluster` fails before `kubectl apply`, saying the pins disagree.
      *Verifiable at: a throwaway PR (ACTS).*
- [ ] **Startup order converges.** If the frontend starts before the `knock-api` Service
      exists (nginx can't resolve it and exits), applying the rest of `k8s/` converges: the
      frontend restarts and smoke passes without anyone deleting a pod.
      *Verifiable at: the laptop cluster.*
- [ ] **Nothing from later levels.** No object in `k8s/` has probes, resources,
      `replicas` other than 1, topology spread or affinity, a ConfigMap or `DELAY_MS`, a
      LoadBalancer or NodePort Service, or a kustomization; no backend sets CORS.
      *Verifiable at: the laptop, statically.*
- [ ] **The cluster job never publishes.** `cluster` has no `packages: write`, and
      `publish` still needs only `smoke`. *Verifiable at: the first PR into `dev` (job
      permissions log) and in the workflow.*
- [ ] **Level 1 still holds.** The full level 1 acceptance suite passes against the level 2
      tree in the release check (fresh `ACT=1` run). *Verifiable at: the release check.*

**Test seams & prior art:**
- **Smoke script.** Extend it in its own style: `set -euo pipefail`, bash 3.2 compatible
  (macOS `/bin/bash`), the `fail()` helper printing `FAIL: …`, `jq -s` over the answers
  file, opt-in env checks after the language check. `EXPECT_VERSION`'s block (set-but-empty
  check, a single comparison, one extra summary line only when set) is the exact pattern
  for `EXPECT_NODE_PREFIX`.
- **Fake API at the boundary.** `.workflow/acceptance/fixtures/fake_api.py` and
  `02-smoke-expect-version.sh` already prove smoke's opt-in checks without a stack (canned
  answers, pass / fail-naming-field / unset-unchanged). Mirror them for the node prefix.
- **CI prior art.** `ci.yml`'s `smoke` job: `persist-credentials: false`, `shell: bash`
  default (pipefail), `smoke.sh 2>&1 | tee smoke.txt`, summary on `always()`, logs dump on
  `failure()`, `timeout-minutes`. Mirror its shape; actions stay pinned to major versions.
- **GitHub observation.** The level 1 harness (`lib.sh`: run picking by head branch,
  `job_output`, freshness against the tree, `ACT=1` gating, throwaway `acceptance/*`
  branches; `08-branch-protection.sh` for protection; `e01` for a throwaway red PR into a
  protected branch). Level 2 tests take the prefixes `c` (criteria) and `ce` (edge cases);
  the runner's glob widens to include `c`.
- **Local cluster tests** own the cluster: they run the README's exact commands, **refuse**
  to start if a k3d cluster named `knock` exists or port 8080 is taken, and delete only a
  cluster they created.
- **Image checks.** `scripts/image-digest.sh` answers whether a tag exists on GHCR; reuse it
  for the pin check.

**Deferred by design** (constraints, not work — carried from architect-deep-dive):
- **Automated pin bump.** Deferred behind the five `image:` lines; hand-edited PRs until
  then. Forced by level 13 (Argo CD, `kustomize edit set image`). No criterion may assume a
  bot or workflow edits `k8s/`.
- **In-cluster testing of the PR's own images.** Deferred behind the `cluster` job's steps
  (it applies `k8s/` as committed). Forced when probes or rolling updates (level 4 or 5) make
  the PR's own image matter in the cluster.
- **k3s/Traefik versions beyond the k3d pin.** Deferred behind k3d's default k3s image.
  Forced by a k3s default that breaks CI or diverges between the laptop and CI.
- **`cluster` required on `main` only.** Deferred behind the protection settings. Forced by
  an observed flake rate that blocks work.
- **A longer readiness poll** (N consecutive 200s). Deferred behind the CI wait step.
  Forced by an observed warm-up 502 in CI.
- Carried from level 1: build cache, an arm64 smoke in CI, full-SHA action pinning,
  signing/provenance/SBOM, manual republish.

**Out of scope:**
- Any app code change: backends, frontend, nginx config, `compose.yaml`.
- L4/LoadBalancer port, the `Target` field, CORS (3). Probes (4). Rolling-update tuning (5).
  Replicas as weights, HPA (6). Requests/limits (7). Topology spread, affinity, drain (8).
  ConfigMaps, `DELAY_MS` (9). Kustomize (10). Gateway API (11). NetworkPolicy (12). Argo CD
  and automated bumps (13).
- A namespace other than `default`; a k3d config file; Helm.
- Retries, waits or warm-up logic inside `scripts/smoke.sh`.
- Running the PR's own images in the CI cluster; building images in `cluster`.
- Changing level 1's workflows' behaviour (`publish`, `dry-run`, `only-dev-to-main`), other
  than adding the `cluster` job beside `smoke` in `ci.yml`.
- Committing the script tests or adding a second committed test (PLAN §4 stands).

**Acceptance tests** (stage 3 — tdd is done when these pass):
- **Command:** `.workflow/acceptance/run.sh c` (level 2 only), `.workflow/acceptance/run.sh`
  (every level: the release check). Single tests: `run.sh c03`, `run.sh ce0`.
- **Modes:**
  - **Local cluster** (`c01`, `c03`, `c04`, `c06`, `ce03`): one k3d cluster `knock`, created
    by the README's exact commands and shared by these tests. The tests refuse to start if
    a `knock` cluster exists that the harness didn't create, or if `:8080` is taken. `run.sh`
    deletes the harness's cluster at the end (`KEEP_CLUSTER=1` keeps it). Helpers in
    `lib-cluster.sh`; `c01` always rebuilds from scratch.
  - **Static / local** (`c02`, `c05`, `ce04`, `ce05`): no cluster. `c05` asks GHCR.
  - **GitHub** (`c07`, `08`, `ce01`, `ce02`): observe GitHub. **ACTS** `ce01`/`ce02` push
    throwaway `acceptance/*` PRs into `dev` only with `ACT=1` (ask first); otherwise they
    observe `RUN=<id>` or stay red with "not observed yet".
- **Red reasons at creation (2026-10-25):**
  - `c02` fails on behaviour: smoke ignores `EXPECT_NODE_PREFIX`.
  - `ce05` fails on behaviour: `ci.yml` has no `cluster` job.
  - `08` fails on behaviour: `dev` requires only `smoke`.
  - `c07` fails because the newest PR into `dev` has no `k8s/`.
  - The rest fail because there are no manifests in `k8s/` (`ce01`/`ce02`: not observed yet).
  - Level 1's 24 tests stay green.
- [ ] Tracer bullet: same UI, now in Kubernetes → `c01-same-ui-in-kubernetes.sh`
- [ ] `EXPECT_NODE_PREFIX` → `c02-smoke-expect-node-prefix.sh`. "Unset unchanged" is checked
      as byte-identical output to `level-01-pipeline`'s smoke.sh against the same fake.
- [ ] One Service over four Deployments → `c03-one-service-four-deployments.sh`
- [ ] Downward API → `c04-downward-api.sh`
- [ ] Immutable pin → `c05-immutable-pin.sh`. The "running backends report it" half is
      `c01`'s `EXPECT_VERSION=<pin>`.
- [ ] Ingress routes `/` to the frontend → `c06-ingress-routes-to-frontend.sh`
- [ ] CI `cluster` job → `c07-ci-cluster-job.sh`
- [ ] Required on `dev` and `main` → `08-branch-protection.sh`, level 1's protection test with
      its required-check sets updated (see Revisions).
- Not acceptance-testable: **Docs**. It's prose, not behaviour; checked in refactor-review
  and devils-advocate.
- [ ] Edge case: an unpublished pin fails CI loudly → `ce01-unpublished-pin-fails.sh` (ACTS)
- [ ] Edge case: disagreeing pins fail before applying → `ce02-disagreeing-pins-fail.sh` (ACTS)
- [ ] Edge case: startup order converges → `ce03-startup-order-converges.sh`
- [ ] Edge case: nothing from later levels → `ce04-nothing-from-later-levels.sh`
- [ ] Edge case: the cluster job never publishes → `ce05-cluster-never-publishes.sh` (static:
      `publish.needs`, no `packages: write`). The runtime token half is `c07`'s.
- Edge case: level 1 still holds → no test of its own. It's the whole suite (`run.sh` with
  no pattern), run fresh with `ACT=1` at the release check.

## Revisions
- 2026-10-25 — stage 3: acceptance tests written (12 new, all red for the reasons above).
  - **Smoke's summary line.** With `EXPECT_NODE_PREFIX` set, smoke prints
    `node prefix <prefix> in every answer`, mirroring `version <v> in every answer`. The
    prefix is compared literally (not a regex, not a substring).
  - **`08-branch-protection.sh` changed.** Its required-check sets now include `cluster`
    (`dev`: `cluster smoke`; `main`: `cluster only-dev-to-main release-ready smoke`). Level 2
    supersedes level 1's sets, so the single protection test asserts the current shape; every
    other protection field it checks is unchanged.
  - **Fixture.** `fixtures/fake_api.py` takes an optional third argument, the node names to
    cycle (default `local`, as before).
  - **Runner.** `run.sh`'s glob gains `c*`/`ce*`, and it calls `cluster-down.sh` last.
  - **`ce02` setup.** Moves only the go pin to `level-01-pipeline`, a published tag, so the run
    fails on the disagreement, not on a pull.
- 2026-10-25 — stage 4 (feedback edge): `c02` compared smoke's output against
  `level-01-pipeline`'s smoke.sh. That version predates level 1's iteration-2 fix, which
  added the `version … in every answer` line, so "as before" would have meant a smoke older
  than the one level 2 changes. "As before" is the smoke at level 2's base, `04f74b3` (the
  newest level-1 release). The criterion is unchanged; the test's baseline is corrected.
- 2026-10-25 — loop iteration 1 → 2 (remediation slices from `.workflow/level-02/ledger.md`):
  - **CI shape (F4/F5/F13–F16).** `cluster` creates the cluster first, bounded at 5 min with
    a step timeout so a stall still fails and dumps. Then it reads the pin from
    `kubectl apply --dry-run=client -f k8s/` (every file kubectl reads, parsed, init
    containers included). Untagged or digest images fail, as do disagreeing pins and a
    non-`sha-<7>` pin, all before the apply step.
  - **Step names are part of the check-name contract.** `Create the cluster`,
    `Read the one tag k8s/ pins`, `Apply k8s/`, `Wait for the ingress` and
    `Smoke test through the ingress` are read by ce01/ce02 through the job's step
    conclusions. Renaming one turns those tests red.
  - **Failure dump (F12).** Adds every namespace's pods, the Ingress/Services/EndpointSlices,
    events and previous container logs.
  - **Docs (F1–F3, F19, F22, F23).**
    - The README's smoke command no longer names a pin, the wait matches CI's, and the bump
      uses `perl`.
    - A level that changes app code is tagged on its pin-bump release.
    - Smoke's default checks must keep passing against the pinned images (new checks are
      opt-in until the pin moves).
  - **Harness.**
    - c07 requires the observed PR head's `k8s/` to equal the tree's, k3d's three
      `Creating node` lines and smoke's `knocks on http://localhost:8080/api/knock`.
    - ce01/ce02 read step conclusions and bind RUN to their own branch's PR into `dev`.
    - ce05 refuses secrets and pushes in `cluster`.
    - ce04 covers more later-level fields and library CORS.
    - c02 adds glob/value/failure-output cases.
    - c03 requires exactly one port.
    - c04 flags unknown pods.
    - ce03 checks nginx's own error and ignores terminating pods.
    - The cluster reuse path prunes and waits for rollouts.
    - The harness requires `nc`.
