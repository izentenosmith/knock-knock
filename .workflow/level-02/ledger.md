# Ledger: level-02-cluster

Append-only. Finding and smell ids are stable. Smells carried over from level 1
(`.workflow/level-01/ledger.md`) keep their ids, and new smells start at N6.

## Iteration 1

### Smells
Small diff (k8s/, one CI job, one smoke option, docs, acceptance harness): one inline pass,
pre/post suite green (`run.sh c` local tests; GitHub-side tests pending PR #33's run).
No blocking or worthwhile smell; nothing was refactored.

Carried from level 1:
- **N1** — left: condition not met (`cluster` doesn't log in to GHCR; still two logins).
- **N3** — left: condition not met (no service added, level 10 not reached). Note that
  `k8s/` is now a third place the five services are listed (one Deployment and image per
  service), which level 10's base/overlays is meant to collapse.
- **N5** — left: condition not met (`cluster` doesn't compute a version; it reads the pin).

New:
- **N6** Dispensables / Duplicate Code at `k8s/go.yaml`, `python.yaml`, `rust.yaml`,
  `ts.yaml`: four Deployments that differ only in the language. Noted: a deliberate
  decision (PLAN §4, "feel the duplication before removing it"; Kustomize is level 10, and
  the brief puts it out of scope).
  - **Promote if:** level 10, or a change has to be made in all four and one is missed.
- **N7** Dispensables / Duplicate Code: the cluster recipe (`k3d cluster create knock
  --agents 2 -p "8080:80@loadbalancer"`, `kubectl apply -f k8s/`, the Available wait plus
  ingress poll) is written in the README, in `ci.yml`'s `cluster` job, and in the
  harness's `lib-cluster.sh`. Noted: the architect kept the flags inline (Q3); the harness
  copy is the black-box restatement of the documented commands, on purpose.
  - **Promote if:** the flags change (level 3 adds a port) and one copy is left behind, or
    a fourth copy appears.
- **N8** Dispensables / Duplicate Code: "the one tag k8s/ pins" is computed three ways: by
  grep in `ci.yml`, by a parsed-YAML read in `lib-cluster.sh` (`pinned_tag`), and by grep in
  `c07`. Noted: product and tests are kept independent on purpose (a black-box test mustn't
  reuse the code it checks), and they agree on today's `k8s/`.
  - **Promote if:** they disagree on any `k8s/` (a `.yml` file, a second container, an image
    without a tag), or level 10 changes how images are set.
- **N9** Dispensables / Duplicate Code at `ci.yml`: `cluster`'s smoke-summary step is a copy
  of `smoke`'s. Noted: two identical four-line steps that change together; a composite
  action would cost more than it saves.
  - **Promote if:** a third job writes a smoke summary, or the summary format changes.
- **N10** Dispensables / Duplicate Code in the harness: "pods a Service selector matches" is
  written as jq in both `c03` and `c06`. Noted: two test-local uses with different shapes
  (any-match vs the image list).
  - **Promote if:** a third test needs it.

### Findings (unadjudicated)
Iteration 1: three read-only delegates, one per surface: product (P: k8s/, the `cluster` job,
smoke), test integrity (T: the c/ce harness), docs and back-compat (D). Sources are given as
delegate+number. No refuted findings carried (first iteration). Ranked most severe first.
F8 also covers D-swept "port collision" (P8 was folded in as F37).

#### F1
- **Target:** `cluster` as a required check, with smoke.sh shared by both jobs (P1)
- **Claim challenged:** a required `cluster` that runs published images coexists with normal work
- **Evidence:** `cluster` runs the PR's own smoke.sh against the pinned, already-published images, and images are published only after merge.
- **Breaking case:** a PR adds a contract field (or a language) to the backends and to smoke's FIELDS/LANGS → `smoke` green, `cluster` red ("answers break the contract"); the images that would turn it green can't exist until the PR merges → deadlock, broken only by an admin override or splitting the work
- **Confidence:** proven
- **Severity hint:** major

#### F2
- **Target:** the README k3d smoke command and the pin-bump procedure (D1)
- **Claim challenged:** every README command works as written after a documented bump
- **Evidence:** README hard-codes `EXPECT_VERSION=sha-04f74b3`; the bump sed rewrites `k8s/*.yaml` only, and nothing checks the README.
- **Breaking case:** the first bump PR → CI green; the README's smoke line then fails with `expected version sha-04f74b3, got sha-<new>`
- **Confidence:** proven
- **Severity hint:** major

#### F3
- **Target:** PLAN's "two releases" note against "replay a level with its tag" (D2)
- **Claim challenged:** the two-release scheme keeps levels replayable
- **Evidence:** nothing says which release gets the immutable level tag. README step 5 says to tag main's newest merge commit after its run is green, which is release 1, the code release, whose `k8s/` still pins older images.
- **Breaking case:** level 3 (CORS + Target) tagged on release 1 → `git checkout level-03… && kubectl apply -f k8s/` runs level-2 images, and the tag can't be moved
- **Confidence:** proven (the doc gap)
- **Severity hint:** major

#### F4
- **Target:** ce02 "k8s/ never applied" (T1)
- **Claim challenged:** a green ce02 proves the pins check runs before apply
- **Evidence:** only the absence of apply's verb lines is checked. A quiet apply (`>/dev/null`, `-o name`) before the check survives, and the regex misses `ingress.networking.k8s.io/…` (the digit in k8s). No step conclusions are read.
- **Breaking case:** the check step moved after a quiet apply → ce02 green
- **Confidence:** proven
- **Severity hint:** major

#### F5
- **Target:** ce01 "smoke never ran" / "bounded wait" (T2)
- **Claim challenged:** a green ce01 proves smoke didn't run against a dead cluster
- **Evidence:** this is an absence check on smoke's output, which works only because the step tees it. No step conclusion is read, and the wait's bound isn't observed.
- **Breaking case:** smoke redirected to a file (or `|| true`) → ce01 green
- **Confidence:** proven
- **Severity hint:** major

#### F6
- **Target:** ce01/ce02 "PR BLOCKED" in observe mode, and run binding (T3, T19)
- **Claim challenged:** a green ce01/ce02 means the PR was BLOCKED, and the run is the scenario's
- **Evidence:** the BLOCKED clause runs only with ACT=1. In observe mode PASS is printed without it, and nothing binds RUN to a PR into dev, an `acceptance/*` branch, or a CE-shaped head.
- **Breaking case:** `cluster` not required + `CE01_RUN=<any old red run>` → ce01 green
- **Confidence:** proven
- **Severity hint:** major

#### F7
- **Target:** c07 bound to the PR head's k8s/, not the tree's (T4)
- **Claim challenged:** c07 shows `cluster` green for the k8s/ under test
- **Evidence:** the pin comes from the newest PR head, and `fresh` compares only workflows and scripts.
- **Breaking case:** the tree's k8s/ changes after the last green PR → c07 still green on the old run
- **Confidence:** proven
- **Severity hint:** major

#### F8
- **Target:** c07 "through the ingress", "the README's flags" (T5)
- **Claim challenged:** c07 proves CI ran smoke through a 3-node k3d ingress
- **Evidence:** smoke's `knocks on <URL>` line and the node/agent count aren't asserted, and the flags appear only in stripped step scripts.
- **Breaking case:** drop `--agents 2`, or point smoke's URL at a port-forward → c07 green
- **Confidence:** proven
- **Severity hint:** major

#### F9
- **Target:** ce05 "cluster never publishes" (T6)
- **Claim challenged:** ce05 proves `cluster` can't publish
- **Evidence:** it checks only `uses`, `packages: write` and `publish.needs`; a step pushing with a PAT secret or a pushing composite action survives, and c07 checks only GITHUB_TOKEN scopes.
- **Breaking case:** a `docker login … ${{ secrets.X }} && docker push` step → ce05 and c07 green
- **Confidence:** proven
- **Severity hint:** major

#### F10
- **Target:** ce04 "no CORS" (T7)
- **Claim challenged:** ce04 proves nothing sends CORS
- **Evidence:** it greps for the literal header name. Library CORS (`cors()`, `CorsLayer`, `CORSMiddleware`) survives, a moved nginx conf makes grep exit 2 (the `&&` doesn't fire), and node_modules/target can false-red it.
- **Breaking case:** `app.use(cors())` → ce04 green
- **Confidence:** proven
- **Severity hint:** major

#### F11
- **Target:** state leakage in the shared cluster on partial runs (T8)
- **Claim challenged:** the cluster tests observe the tree's k8s/
- **Evidence:** `cluster()` reuses the cluster with `kubectl apply` (no prune), and `wait_ready` returns mid-rollout. A full `run.sh` is safe because c01 rebuilds.
- **Breaking case:** KEEP_CLUSTER=1, delete `k8s/ingress.yaml` → `run.sh c06` green
- **Confidence:** proven
- **Severity hint:** major (partial runs only)

#### F12
- **Target:** CI failure dump (P5)
- **Claim challenged:** on failure the dump shows the real cause
- **Evidence:** it covers default-namespace pods only. There are no events, ingress, svc or endpoints, nothing from kube-system (Traefik, svclb), and no `--previous` logs; the green run shows 12 "Empty reply" polls that come from Traefik.
- **Breaking case:** Traefik never ready → the dump shows five healthy pods and no cause
- **Confidence:** proven (the gap); unproven (the impact)
- **Would be settled by:** scale Traefik to 0 after create in a cluster run and read the dump
- **Severity hint:** minor

#### F13
- **Target:** CI pin step scope: `.yml`/`.json` (P2)
- **Claim challenged:** disagreeing pins fail before apply
- **Evidence:** the check reads `k8s/*.yaml` only, but `kubectl apply -f k8s/` also applies `.yml` and `.json`.
- **Breaking case:** `k8s/extra.yml` with another tag → the check passes, the bad pin is applied
- **Confidence:** proven
- **Severity hint:** minor

#### F14
- **Target:** CI pin step text parsing (P3)
- **Claim challenged:** EXPECT_VERSION is the pinned tag; disagreement messages are accurate
- **Evidence:** grep/sed rather than a YAML read: quoted images keep a trailing `"`, an untagged image yields a garbled "disagree" message, and tag@digest is misread.
- **Breaking case:** `image: "…:sha-04f74b3"` everywhere → EXPECT_VERSION `sha-04f74b3"` → smoke fails
- **Confidence:** proven
- **Severity hint:** minor

#### F15
- **Target:** a pin to a published level tag (P4)
- **Claim challenged:** any published tag works as a pin
- **Evidence:** backends report the baked `sha-<7>`; a `level-*` tag has the same digest but a different name.
- **Breaking case:** pin `:level-02-cluster` → pull OK, smoke `expected version level-02-cluster, got sha-…`; only `sha-*` pins work, and nothing enforces or explains that
- **Confidence:** proven
- **Severity hint:** minor

#### F16
- **Target:** unbounded `k3d cluster create` (P6)
- **Claim challenged:** every wait is bounded and a failure always yields the dump
- **Evidence:** create has no `--timeout`, and a job-timeout cancel skips `if: failure()`.
- **Breaking case:** a docker.io pull stalls → 15 min, then cancelled, with no diagnostics
- **Confidence:** unproven
- **Would be settled by:** a cluster run with a nonexistent `--image rancher/k3s:<tag>`
- **Severity hint:** minor

#### F17
- **Target:** startup-order convergence time (P7)
- **Claim challenged:** a frontend-first apply converges within the wait
- **Evidence:** CrashLoopBackOff doubles up to 5 min, so a manual late apply can wait minutes. In CI the curl poll protects it, and `kubectl wait` can pass during an up moment.
- **Confidence:** unproven
- **Would be settled by:** apply `frontend.yaml`, wait 3 min, apply the rest, time to the first 200
- **Severity hint:** minor

#### F18
- **Target:** `cluster` required in docs vs protection now (D3)
- **Claim challenged:** README/PLAN say `cluster` is required
- **Evidence:** protection today: dev `[smoke]`, main `[smoke, only-dev-to-main, release-ready]`. The change is a pending owner step.
- **Breaking case:** PR merges and the owner never applies it → the docs overclaim
- **Confidence:** proven (current state)
- **Severity hint:** minor

#### F19
- **Target:** PLAN 01 bullet still lists level-1 required checks (D4)
- **Claim challenged:** PLAN gives one consistent account of the required checks
- **Evidence:** the 01 bullet says `smoke` (and only-dev-to-main/release-ready on main), while the 02 note adds `cluster`.
- **Confidence:** proven
- **Severity hint:** minor

#### F20
- **Target:** release gate with `cluster` on main/tag runs (D5)
- **Claim challenged:** "wait for main's run to be green" still means "safe to tag"
- **Evidence:** publish needs only smoke, so a flaky `cluster` leaves the main run red after a successful publish, and a red `cluster` on the tag run makes a good promotion look failed.
- **Confidence:** proven (wiring)
- **Severity hint:** minor

#### F21
- **Target:** README status line (D6)
- **Claim challenged:** "Level 2 done … every PR smoke-tested through a k3d ingress"
- **Evidence:** it's written before the tag exists, and "every PR smoke-tested" suggests the PR's code runs in k3d (it runs the published pin).
- **Confidence:** proven
- **Severity hint:** minor

#### F22
- **Target:** README wait one-liner vs CI's (D7)
- **Claim challenged:** the README wait is CI's bounded wait
- **Evidence:** README drops `--max-time 5`; 120 s may not cover cold pulls on a slow link.
- **Confidence:** unproven
- **Would be settled by:** a cold-cache throttled run of the README commands
- **Severity hint:** minor

#### F23
- **Target:** README bump sed portability (D8)
- **Claim challenged:** the one-liner works for contributors
- **Evidence:** `sed -i ''` is BSD-only; GNU sed reads `''` as the script.
- **Confidence:** proven
- **Severity hint:** minor

#### F24
- **Target:** level 13's plan vs protection (D9)
- **Claim challenged:** level 13 can take over the bump
- **Evidence:** PLAN 13 commits the bump to main with `[skip ci]`, but main is PR-only with enforce_admins, and a commit on main would put dev behind main.
- **Confidence:** proven (doc contradiction; the consequence lands at level 13)
- **Severity hint:** minor

#### F25
- **Target:** smoke with an exported empty EXPECT_NODE_PREFIX (D10)
- **Claim challenged:** compose users see unchanged behaviour
- **Evidence:** `EXPECT_NODE_PREFIX=` exported → `FAIL: … set but empty` on compose (mirrors EXPECT_VERSION, deliberate).
- **Confidence:** proven
- **Severity hint:** minor

#### F26
- **Target:** c05 / pinned_tag / ce04 ignore initContainers; c05 relies on the product's image-digest.sh (T9)
- **Claim challenged:** "five images, one sha-<7> tag"
- **Breaking case:** an initContainer `busybox:latest` → c05 and ce04 green
- **Confidence:** proven
- **Severity hint:** minor

#### F27
- **Target:** c02 "literal prefix" / "names node" (T10)
- **Claim challenged:** c02 proves literal matching and that the failure names the stray node
- **Evidence:** only a regex reading is excluded, so a glob implementation passes. The literal case accepts any failure, and "names node" matches the word, not the stray value.
- **Confidence:** proven
- **Severity hint:** minor

#### F28
- **Target:** caller environment leaks into c02/c01/ce03/c07/ce0x (T11)
- **Claim challenged:** "unset" means unset; c01 smokes `$INGRESS`
- **Evidence:** no `unset` before the unset case, smoke's default URL is used, and an exported RUN/PR rebinds observations.
- **Confidence:** proven (binding); unproven (realistic false green)
- **Would be settled by:** `PR=<older green PR> ./c07-ci-cluster-job.sh`
- **Severity hint:** minor

#### F29
- **Target:** c02 "byte-for-byte when unset" covers passes only (T12)
- **Breaking case:** a reworded version-mismatch FAIL with the prefix unset → c02 green
- **Confidence:** proven
- **Severity hint:** minor

#### F30
- **Target:** c01 "README's exact commands", "arm64" (T13)
- **Evidence:** the commands are restated in lib-cluster (the README isn't read), and `uname -m` is `aarch64` on Linux arm64, so the arch check is skipped there.
- **Confidence:** proven
- **Severity hint:** minor

#### F31
- **Target:** ce04 misses other later-level fields (T14)
- **Evidence:** nodeName, priorityClassName, hostPort/hostNetwork/externalIPs, minReadySeconds/progressDeadlineSeconds, DELAY_MS via args, secretKeyRef, and initContainers.
- **Breaking case:** `hostPort: 8081` → ce04 green
- **Confidence:** proven
- **Severity hint:** minor

#### F32
- **Target:** ce03 doesn't prove *why* the frontend restarted (T15)
- **Evidence:** it checks only `restartCount >= 1`; there's no `host not found in upstream` in the logs.
- **Confidence:** proven
- **Severity hint:** minor

#### F33
- **Target:** c03 tolerates extra Service ports (T16)
- **Breaking case:** add port 9090 → c03 green
- **Confidence:** proven
- **Severity hint:** minor

#### F34
- **Target:** c04 skips answers with an unknown pod and no node (T17)
- **Evidence:** `null != null` is false, so the answer isn't flagged (smoke's contract check would catch the missing field).
- **Confidence:** proven
- **Severity hint:** minor

#### F35
- **Target:** harness hygiene (T18)
- **Evidence:**
  - Without `nc` the port guard reads "free".
  - `k3d cluster create` switches the user's kubeconfig context.
  - A create that fails late leaves an unowned cluster.
  - An ACT failure after `gh pr create` leaves the PR and branch open, and the next ACT run's `gh pr create` fails.
- **Confidence:** unproven
- **Would be settled by:** `nc` hidden from PATH + 127.0.0.1:8080 held, then c01
- **Severity hint:** minor

#### F36
- **Target:** ce01/ce02 observe-mode run binding (T19, the run-selection half of F6)
- **Evidence:** only `fresh` and the output are checked; no event, base, or head shape.
- **Confidence:** proven
- **Severity hint:** minor

#### F37
- **Target:** compose and k3d both on :8080 (P8)
- **Evidence:** both bind 8080; whichever starts second fails, and smoke tests whatever owns the port (the README documents "compose down first").
- **Confidence:** unproven
- **Would be settled by:** `docker compose up -d`, then the README's `k3d cluster create`
- **Severity hint:** minor

### Surfaces
- **Swept (P):**
  - the k3d download and sha256 (matches the release digest);
  - pinned images exist, public, multi-arch (anonymous pull in CI);
  - the Service/label/Deployment-name contract;
  - smoke's `EXPECT_NODE_PREFIX` (literal `startswith`, bash 3.2);
  - script injection and permissions (no `${{ }}` in the new `run:` blocks, read-only token);
  - the Ingress without an ingressClassName (Traefik admits it);
  - four languages through the ClusterIP (now probabilistic, about 4e-5 to miss one in 40);
  - disagreeing `.yaml` pins fail before apply.
  All held.
- **Swept (D):**
  - the check name `cluster` is reported on every required event (PRs, pushes, tags);
  - `publish` independent of `cluster`;
  - concurrency groups;
  - no open PR stranded by the rollout;
  - the k3d pin and the pin facts (`04f74b3` = main, same app code as level 1);
  - the nginx/frontend contract;
  - the POD_NAME/NODE_NAME reasoning;
  - the README k3d commands on macOS zsh;
  - PLAN §1/§2/§3/§4 and README Requirements;
  - the compose quickstart and the smoke job unchanged.
  All held.
- **Swept (T):**
  - harness ownership (never deletes a cluster it didn't create; worktrees refuse each other's);
  - `fail` inside `$(…)` and `&&`-lists under `set -e`;
  - c03 selector/owner logic;
  - c04 spec check;
  - c06 Ingress checks;
  - c07 permissions parse and tally regex;
  - 08 strings;
  - the run.sh glob and order;
  - the fake_api node cycle;
  - ce05's existing checks.
  Held apart from the findings above.
- **Unattacked:**
  - whether `kubectl wait --all`'s timeout is per resource (only matters for F16);
  - GHCR visibility via the API (the token lacks read:packages; the anonymous CI pull is the evidence);
  - ce03 false reds from backoff;
  - level-1 lib.sh internals beyond what level 2 calls.
