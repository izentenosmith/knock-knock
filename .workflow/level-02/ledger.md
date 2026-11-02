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
The compose/k3d port collision (P8) is F37.

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

### Verdicts
Iteration 1. Nothing carried. 37 findings adjudicated here. One fact check (F16: `k3d cluster
create --help` gives `--wait` true with no timeout by default). No verification delegates.

#### F1 — CONFIRMED minor
- **Reason:** The deadlock is real: a required `cluster` runs the PR's smoke against the
  published pin. It needs smoke's *default* checks to change, though, and Q5 settled that
  smoke grows only through opt-in variables. No planned level changes the §1 contract.
  It's a rule nobody wrote down, not a defect on today's path.

#### F2 — CONFIRMED major
- **Reason:** The README hard-codes `sha-04f74b3` outside `k8s/`. The documented bump leaves
  it stale, so the next documented smoke command fails after the first supported bump.

#### F3 — CONFIRMED major
- **Reason:** Nothing says which of a level's two releases gets the immutable tag. The
  README's "tag main's newest merge after green" points at release 1, whose `k8s/` can't run
  that level's code. A wrong level tag is permanent.

#### F4 — CONFIRMED major
- **Reason:** ce02's "never applied" rests on the absence of output text that the product
  controls. The regex also can't match `ingress.networking.k8s.io/…`. No step conclusion is
  read.

#### F5 — CONFIRMED major
- **Reason:** ce01's "smoke never ran" rests on the absence of smoke output, which a redirect
  removes. No step conclusion is read.

#### F6 — CONFIRMED minor
- **Reason:** In observe mode the BLOCKED clause is skipped and RUN isn't bound to the
  scenario. That's the same class as level 1's F103 (minor). The user's release rule makes a
  fresh `ACT=1` run the evidence, and that run does check BLOCKED and makes the PR itself.

#### F7 — CONFIRMED major
- **Reason:** c07 accepts a green run whose `k8s/` differs from the tree's, so the CI
  criterion isn't re-proven for the released manifests. Unlike level 1's F71, the fix is
  local to c07.

#### F8 — CONFIRMED major
- **Reason:** c07 asserts neither that smoke knocked on the ingress URL nor that the cluster
  had agents. A port-forward or a one-node cluster passes.

#### F9 — CONFIRMED minor
- **Reason:** ce05's static check misses a push done with a secret. A static check can't be
  complete, but the named mutations (`secrets.`, `docker push`/`login`, a pushing action) are
  cheap to refuse.

#### F10 — CONFIRMED minor
- **Reason:** The CORS grep matches only the literal header. A moved nginx conf silently
  passes (grep exits 2), and vendored trees can false-red it. It's a scope guard for this
  level's diff, which review also covers, so minor.

#### F11 — CONFIRMED minor
- **Reason:** A partial run against a kept cluster can see objects that are no longer in
  `k8s/`. The release check (a full run) rebuilds in c01, so minor.

#### F12 — CONFIRMED minor
- **Reason:** The dump has no events, ingress/endpoints, kube-system or `--previous` logs.
  A Traefik-side failure would be hard to diagnose. Diagnostics only; nothing passes wrongly.

#### F13 — CONFIRMED minor
- **Reason:** `kubectl apply -f k8s/` reads `.yml`/`.json` too; the pin step reads `*.yaml`
  only.

#### F14 — CONFIRMED minor
- **Reason:** Text parsing gets quoted, untagged and digest images wrong. Same root as F13:
  the pin isn't read from the objects kubectl applies (see N8).

#### F15 — CONFIRMED minor
- **Reason:** Only `sha-<7>` pins can match `version`, and nothing enforces or explains that.
  A level tag as a pin fails with a misleading version message.

#### F16 — CONFIRMED minor
- **Reason:** `k3d cluster create` waits forever by default, so a stalled pull ends in a
  job-timeout cancel, and `failure()` dumps don't run.

#### F17 — REFUTED
- **Reason:** The documented path is a single `kubectl apply -f k8s/`. CI's ingress poll
  covers the window, and ce03 shows convergence. Backoff on a manual split apply is
  Kubernetes's documented behaviour, not this level's defect.
- **Reopens only if:** the documented single apply is observed not converging within the
  documented wait.

#### F18 — REFUTED
- **Reason:** The docs describe the release state. Protection is applied (with confirmation)
  before the `dev`→`main` PR, and `08` is red in the release check until it is.
- **Reopens only if:** a release is proposed while `08` is red.

#### F19 — CONFIRMED minor
- **Reason:** PLAN's 01 bullet still states level 1's required-check set as current.

#### F20 — REFUTED
- **Reason:** "Wait for main's run to be green" is the stricter reading the flow wants. A red
  `cluster` on `main` deserves a look or a re-run before tagging. A tag run's red `cluster`
  doesn't affect promotion.
- **Reopens only if:** `cluster` fails on `main` or tag runs persistently while the release is
  healthy.

#### F21 — REFUTED
- **Reason:** Level 1 used the same convention (status written in the level's PR, true at the
  tag). The status says smoke runs *through a k3d ingress*, which is true, and the Pipeline
  section says which images.
- **Reopens only if:** a release is tagged while the README describes something it doesn't do.

#### F22 — CONFIRMED minor
- **Reason:** The README's wait isn't CI's: it has no `--max-time` and no hint for a slow first
  pull. Proven as a mismatch; the impact is unproven.

#### F23 — CONFIRMED minor
- **Reason:** `sed -i ''` is BSD-only, and the README doesn't say macOS-only.

#### F24 — REFUTED
- **Reason:** How level 13 bumps the pin under PR-only protection is level 13's design
  question. Level 2 only defers to it.
- **Reopens only if:** level 13's architect review keeps a direct commit to `main`. Carry it
  there as an input.

#### F25 — REFUTED
- **Reason:** Deliberate, and it mirrors `EXPECT_VERSION` (a set-but-empty variable is a typo
  to catch, not to skip).
- **Reopens only if:** a supported environment exports it empty by default.

#### F26 — CONFIRMED minor
- **Reason:** c05, `pinned_tag` and ce04 ignore initContainers, so an unpinned sixth image
  would pass.

#### F27 — CONFIRMED minor
- **Reason:** c02 doesn't exclude a glob reading, and doesn't check that the failure names the
  stray node.

#### F28 — CONFIRMED minor
- **Reason:** The tests rely on unset `URL`/`EXPECT_*` without unsetting them. Mostly false
  reds; the RUN/PR leak is the level-1 lib's (F72, accepted).

#### F29 — CONFIRMED minor
- **Reason:** "Unchanged when unset" is compared on passing runs only.

#### F30 — CONFIRMED minor
- **Reason:** The arch check is skipped on Linux arm64 (`aarch64`). The README not being read
  is N7's accepted duplication, not a defect.

#### F31 — CONFIRMED minor
- **Reason:** ce04 misses hostPort/hostNetwork, nodeName, priorityClassName, rollout timing
  fields and initContainers.

#### F32 — CONFIRMED minor
- **Reason:** ce03 proves a restart, not that nginx failed to resolve `knock-api`.

#### F33 — CONFIRMED minor
- **Reason:** c03 accepts extra ports on `knock-api`.

#### F34 — CONFIRMED minor
- **Reason:** c04 skips an answer whose pod is unknown and whose node is missing.

#### F35 — CONFIRMED minor
- **Reason:** `! nc -z …` reads "free" when `nc` is missing. The rest (the kubeconfig context,
  an ACT PR left open on failure) matches the documented commands and level 1's accepted
  harness shape.

#### F36 — REFUTED
- **Reason:** A duplicate of F6's run-binding half, adjudicated there.
- **Reopens only if:** never on its own; through F6.

#### F37 — REFUTED
- **Reason:** The README says to stop compose first. The second start fails loudly with a bind
  error, and with the README's `EXPECT_NODE_PREFIX` a smoke that lands on compose fails
  (`node` is `local`).
- **Reopens only if:** a collision passes smoke with the prefix set.

**Smells cross-check.**
- N8 (the pin computed three ways) is the root of F13/F14. The fix reads the pin from the
  objects kubectl would apply, which retires the CI's text parsing rather than patching it.
- N7 (the recipe in three places) is where F2/F22 drift lives. The fixes keep the copies
  identical; they don't merge them.

### Remediation slices
- [ ] [major] F2 — The README's k3d smoke command passes for whatever pin `k8s/` holds: no
      `sha-<7>` appears in the README outside an example, and the bump changes only `k8s/`.
- [ ] [major] F3 — PLAN's level 02 note and README step 5 say which release a level is tagged
      on when it changes app code: the pin-bump release, whose `k8s/` pins the code release's
      `sha-<7>`.
- [ ] [major] F4 — ce02 fails unless the `cluster` job's apply step (and every step after the
      pin check) concluded `skipped` (read through the job's step conclusions), and the
      pin-check step concluded `failure`.
- [ ] [major] F5 — ce01 fails unless the `cluster` job's smoke step concluded `skipped` and
      the wait step concluded `failure`.
- [ ] [major] F7 — c07 fails ("stale observation") unless the observed PR head's `k8s/` is
      identical to the tree's `k8s/`.
- [ ] [major] F8 — c07 fails unless the `cluster` output shows smoke knocked on
      `http://localhost:8080/api/knock` and the cluster had both agents
      (`k3d-knock-agent-0`, `k3d-knock-agent-1`).
- [ ] [minor] F1 — PLAN's level 02 note states the rule: smoke's default (unset-variable)
      checks must pass against the pinned images, so any check that only new images can
      satisfy is opt-in until the pin moves.
- [ ] [minor] F6 — In observe mode, ce01/ce02 fail unless RUN is a `pull_request` run into
      `dev` from their own `acceptance/*` branch.
- [ ] [minor] F9 — ce05 fails if the `cluster` job references any secret, logs in to a
      registry, or pushes an image.
- [ ] [minor] F10 — ce04 fails if the nginx config it checks is missing, and catches CORS
      wired through a library (case-insensitive `cors` in backend sources, excluding vendored
      trees).
- [ ] [minor] F11 — A reused harness cluster holds exactly `k8s/`'s objects (pruned), and
      the wait covers finished rollouts.
- [ ] [minor] F12 — On failure, the `cluster` job's dump also shows events, the
      Ingress/Services/EndpointSlices, kube-system pods and previous container logs.
- [ ] [minor] F13 — The pin check reads every object `kubectl apply -f k8s/` would apply,
      `.yml`/`.json` included.
- [ ] [minor] F14 — The pin check reads image references from the parsed objects, so quoting,
      missing tags and digests are handled. An image without a tag fails, saying so.
- [ ] [minor] F15 — A pin that isn't a `sha-<7>` tag fails the `cluster` job before applying,
      saying pins must be `sha-<7>`.
- [ ] [minor] F16 — Cluster creation in CI is bounded, and a stalled create fails the job
      (so the failure dump runs) instead of being cancelled.
- [ ] [minor] F19 — PLAN's 01 bullet doesn't contradict the 02 note on required checks.
- [ ] [minor] F22 — The README's wait is CI's wait (the same flags), with a note on what to
      do if a first, slow pull times out.
- [ ] [minor] F23 — The README's pin-bump command works with both BSD and GNU tools.
- [ ] [minor] F26 — c05, `pinned_tag` and ce04 include initContainers.
- [ ] [minor] F27 — c02 fails a glob-reading implementation (`EXPECT_NODE_PREFIX='k3d-*'`
      against `k3d-other-agent-0`), and requires the failure to name the stray node value.
- [ ] [minor] F28 — c01, c02 and ce03 unset `URL`, `EXPECT_VERSION` and `EXPECT_NODE_PREFIX`
      where they mean them unset, and c01/ce03 pass `URL` explicitly.
- [ ] [minor] F29 — c02 also compares failure output (a version mismatch, a missing language)
      with the base smoke when the prefix is unset.
- [ ] [minor] F30 — c01's arch check runs on `aarch64` hosts too.
- [ ] [minor] F31 — ce04 also refuses hostPort/hostNetwork, nodeName, priorityClassName,
      minReadySeconds/progressDeadlineSeconds and initContainers' forbidden fields.
- [ ] [minor] F32 — ce03 requires the frontend's previous log to show nginx failing to
      resolve `knock-api`.
- [ ] [minor] F33 — c03 requires `knock-api` to have exactly one port, 8080→8080.
- [ ] [minor] F34 — c04 flags any answer whose pod isn't a known backend pod or whose node is
      missing.
- [ ] [minor] F35 — The harness fails if `nc` is missing, instead of reading the port as free.

### Verdict: NO-GO
- **Reason:** 6 confirmed majors are open (F2, F3, F4, F5, F7, F8), plus 23 confirmed minors.
  8 refuted, 0 INCONCLUSIVE. Iteration 1 of at most 3. Carried smells: N1, N3, N5, N6–N10.

## Iteration 2

### Closed slices
- [x] F2 — verified by review: the README's k3d smoke command no longer names a pin
      (`grep sha-04f74b3 README.md` finds nothing); the bump changes only `k8s/`
- [x] F3 — verified by review: PLAN 02 note and README step 5 tag a code-changing level on
      its pin-bump release
- [x] F7 — verified by c07-ci-cluster-job.sh (fails "stale observation" when the PR head's
      `k8s/` differs from the tree's)
- [x] F8 — verified by c07-ci-cluster-job.sh (requires three `Creating node` lines and
      `knocks on http://localhost:8080/api/knock`)
- [x] F1 — verified by review: PLAN 02 note states the default-checks rule
- [x] F9 — verified by ce05-cluster-never-publishes.sh (mutation: a `docker push` step turns it red)
- [x] F10 — verified by ce04-nothing-from-later-levels.sh (nginx.conf required; `cors` in sources)
- [x] F11 — verified by the reuse path in lib-cluster.sh (`apply --prune --all`, rollout status)
      under c03/c06 partial runs
- [x] F12 — verified by review of the `cluster` failure step; exercised by ce01 at the ACT run
- [x] F13 — verified by review: the pin check reads `kubectl apply --dry-run=client -f k8s/`
- [x] F14 — verified locally: the CI pin script against the k3d cluster yields
      `sha-04f74b3`, no bad images
- [x] F15 — verified by review: a non-`sha-<7>` pin fails the pin check
- [x] F16 — verified by review: `Create the cluster` has `timeout-minutes: 5`
- [x] F19 — verified by review: PLAN 01 bullet names `cluster`
- [x] F22 — verified by review: the README wait has CI's flags and a re-run note
- [x] F23 — verified locally: the `perl` bump rewrites all five pins on macOS
- [x] F26 — verified by c05-immutable-pin.sh and ce04 (init containers read, and refused)
- [x] F27 — verified by c02-smoke-expect-node-prefix.sh (mutations: glob matching and a vague
      message both turn it red)
- [x] F28 — verified by c01/c02/ce03 (explicit `URL`; `unset` in c02)
- [x] F29 — verified by c02-smoke-expect-node-prefix.sh (failure output compared)
- [x] F30 — verified by c01-same-ui-in-kubernetes.sh (`arm64|aarch64`)
- [x] F31 — verified by ce04-nothing-from-later-levels.sh
- [x] F32 — verified by ce03-startup-order-converges.sh (nginx's `host not found in upstream`)
- [x] F33 — verified by c03-one-service-four-deployments.sh
- [x] F34 — verified by c04-downward-api.sh
- [x] F35 — verified by lib-cluster.sh (`command -v nc` before the port check)
- Implemented, not yet observed: F4, F5, F6 (ce01/ce02 step conclusions and run binding).
  Their red/green needs the throwaway PRs, i.e. an `ACT=1` run (owner's confirmation).
- c07 re-observed on the remediated tree: PR #33, run 40207453154, PASS (the k8s/ binding,
  three nodes, the ingress URL).

### Smells
- **N1, N3, N5** — left: condition not met.
- **N6** — left: condition not met (the four Deployments are unchanged).
- **N7** — left: the README and CI copies of the wait are identical again (F22). No fourth
  copy.
- **N8** — retired as a CI concern: CI now reads the pin from kubectl's parsed objects, not
  text. Tests still compute it independently on purpose (`pinned_tag`, c07's grep).
- **N9, N10** — left: condition not met.
- No new smells. Small remediation diff, inline pass.

### Findings (unadjudicated)
Iteration 2: three read-only delegates over the remediation diff `1b87eaa..HEAD`: docs/flow (D),
CI/product (P), harness (T). The refuted F17, F18, F20, F21, F24, F25, F36, F37 weren't
re-reported. Findings are condensed from the delegates' reports; ids are new.

#### F38
- **Target:** nginx resolve-once after a Service is recreated (D1; observed live in this
  iteration)
- **Claim challenged:** the docs cover how the frontend behaves when `knock-api` changes
- **Evidence:** nginx resolves `knock-api` once. A recreated Service gets a new ClusterIP, and
  a running frontend keeps proxying to the dead one. With no probes the pod never restarts.
  Seen live: a frontend with 0 restarts, `/api/knock` timing out, and the Service healthy.
  Undocumented.
- **Breaking case:** `kubectl delete -f k8s/knock-api.yaml && kubectl apply -f k8s/` → every
  knock fails until `kubectl rollout restart deployment/frontend`
- **Confidence:** proven
- **Severity hint:** major

#### F39
- **Target:** the `cluster` gate when smoke fails (T2)
- **Claim challenged:** `cluster` is green only if smoke through the ingress passes
- **Evidence:** no test turns `cluster` red through a smoke failure. c07 sees green, ce01/ce02
  need smoke *skipped*, and ce05 is a static push scan. `|| true`, `continue-on-error` or a
  shell without pipefail on the smoke step would all survive. (`smoke` has e10 for this risk.)
- **Confidence:** proven
- **Severity hint:** major

#### F40
- **Target:** harness safety: the kubeconfig context against the owned container (T1)
- **Claim challenged:** the harness only ever touches the cluster it created
- **Evidence:** `owned()` checks the Docker container, while `kc` uses the `k3d-knock` context
  from the user's kubeconfig, and nothing binds the two. `apply --prune --all` and ce03's
  `delete -f k8s/` go through that context.
- **Breaking case:** two Docker runtimes, each with a `knock` cluster, and a kubeconfig
  pointing at the other one → prune and delete act on a cluster the harness didn't create
- **Confidence:** unproven
- **Would be settled by:** two Docker contexts with crossed kubeconfigs, then c03
- **Severity hint:** major

#### F41
- **Target:** the CI pin check's claims (P1)
- **Claim challenged:** the pins are "one sha-<7> tag that main published"
- **Evidence:** only the tag's shape is checked. The repository isn't checked (any registry
  and name pass), and publication only surfaces later as ImagePullBackOff. The comment and the
  error text claim more than that.
- **Confidence:** proven
- **Severity hint:** major

#### F42
- **Target:** the failure dump on a stalled create (P2)
- **Evidence:** the dump is kubectl-only. A create killed by the step timeout likely leaves no
  kubeconfig, so the dump exits at its first line with no docker or k3d state.
- **Confidence:** unproven
- **Would be settled by:** a stalled create (an unreachable `--image`) and reading the dump
- **Severity hint:** major

#### F43
- **Target:** the dump's namespace scope (P3)
- **Evidence:** only `get pods` is all-namespaces. Events, describe and logs are default-only,
  so no Traefik, svclb or CoreDNS logs or events.
- **Confidence:** proven
- **Severity hint:** minor

#### F44
- **Target:** the job timeout against the sum of the step bounds (P4)
- **Evidence:** the bounded steps reach about 14 min, plus unbounded downloads, against a
  15-min job timeout. A job timeout is a cancel, so there's no dump.
- **Confidence:** proven (arithmetic)
- **Severity hint:** minor

#### F45
- **Target:** the jq image filter (P5)
- **Evidence:** `..|objects|select(has("image"))` matches image volumes (objects) and any map
  with an `image` key (labels, data), which gives false reds or misses the volume's reference.
- **Confidence:** proven by reading (not in k8s/ today)
- **Severity hint:** minor

#### F46
- **Target:** empty or missing images in the pin check (P6)
- **Evidence:** `image: ""` yields a misleading "not \nsha-…" message, no images gives an empty
  "disagree", and a container without `image` passes the check and fails later at apply.
- **Confidence:** proven / unproven (the missing-key case)
- **Severity hint:** minor

#### F47
- **Target:** a green pin check is silent (P7)
- **Evidence:** the step prints nothing on success, so a run can't show which images it read.
- **Confidence:** proven
- **Severity hint:** minor

#### F48
- **Target:** the pin step is skipped when create fails (P8)
- **Evidence:** the check needs the API server. A create flake reports the pin step as
  skipped, not failure.
- **Confidence:** proven
- **Severity hint:** minor

#### F49
- **Target:** the release-2 contents (D2, D5)
- **Evidence:** "release 2 = a PR that moves the pin" doesn't say release 2 must hold only the
  pin bump plus the `k8s/`/CI changes that need the new images. Anything else merged into
  `dev` meanwhile ships with release 2 but isn't what `k8s/` runs. Changes that need the new
  images block release 1 if put there.
- **Confidence:** proven
- **Severity hint:** minor

#### F50
- **Target:** the level tag's images against the cluster's (D3)
- **Evidence:** promote retags release 2's `sha-<M2>`, while `k8s/` at the tag runs
  `sha-<M1>`: same code, different `version`. Undocumented.
- **Confidence:** proven
- **Severity hint:** minor

#### F51
- **Target:** the PLAN example for opt-in checks (D4)
- **Evidence:** `EXPECT_NODE_PREFIX` is given as "a check only newer images can pass", but
  level 1's images already pass it, and `cluster` sets it now.
- **Confidence:** proven
- **Severity hint:** minor

#### F52
- **Target:** the PLAN CoreDNS "30 s" claim (D6)
- **Evidence:** `cache 30` is a cap. The kubernetes plugin's denial TTL is likely 5 s, so the
  number is unverified.
- **Confidence:** unproven
- **Would be settled by:** the coredns ConfigMap and `dig` on the SOA TTL with the Service absent
- **Severity hint:** minor

#### F53
- **Target:** the PLAN claim "the normal path never sees it" (D7)
- **Evidence:** `frontend.yaml` applies before `knock-api.yaml`, so it's a race won by pod
  start time. "Never" overclaims.
- **Confidence:** unproven
- **Severity hint:** minor

#### F54
- **Target:** the perl bump with an unset or malformed NEW (D8)
- **Evidence:** writes `knock-knock-go:` or a non-sha tag silently. CI catches it at PR time;
  locally it fails as InvalidImageName.
- **Confidence:** proven
- **Severity hint:** minor

#### F55
- **Target:** third-party images in k8s/ (D9)
- **Evidence:** the pin check fails on any non-knock image (for example a level 12 client pod).
  Undocumented.
- **Confidence:** proven
- **Severity hint:** minor

#### F56
- **Target:** PLAN describes the old pin check and dump (D10)
- **Confidence:** proven
- **Severity hint:** minor

#### F57
- **Target:** "a level that changes app code" (D11)
- **Evidence:** the trigger is anything baked into an image: backends, frontend incl.
  nginx.conf, the Dockerfiles.
- **Confidence:** proven
- **Severity hint:** minor

#### F58
- **Target:** README Requirements don't list perl (D12)
- **Confidence:** proven
- **Severity hint:** minor

#### F59
- **Target:** ce05 scan bypasses (T3)
- **Evidence:**
  - `secrets['X']` and `toJSON(secrets)`;
  - `docker  login` or `docker --config d login`;
  - `docker image push`;
  - `crane`/`skopeo`/`oras`/`podman`;
  - `--output type=registry`;
  - `push: true` on another action.
- **Confidence:** proven
- **Severity hint:** major

#### F60
- **Target:** c07 node and port checks are presence-only (T4)
- **Breaking case:** `--agents 3`, `--servers 3`, or `-p 8080:80@server:0` → c07 green
- **Confidence:** proven
- **Severity hint:** minor

#### F61
- **Target:** c07 binds to the head's k8s/, while the run used the merge ref (T5)
- **Breaking case:** `dev` changed a `k8s/` file the PR didn't touch → c07 still green
- **Confidence:** proven
- **Severity hint:** minor

#### F62
- **Target:** ce03's failure trap ignores KEEP_CLUSTER (T6)
- **Confidence:** proven
- **Severity hint:** minor

#### F63
- **Target:** the ce04 CORS grep scope (T7)
- **Evidence:** `|| true` swallows grep exit 2 (a missing `backends/`), and the scope leaves
  out the frontend Dockerfile, other nginx confs and `k8s/`. The pattern is substring-only,
  and vendored dirs can give false reds.
- **Confidence:** proven
- **Severity hint:** minor

#### F64
- **Target:** ce04 ignores ConfigMap/Secret/projected volumes (T8)
- **Confidence:** proven
- **Severity hint:** minor

#### F65
- **Target:** wait_ready's `for d in $(kc get …)` (T9)
- **Evidence:** a failing `kc get` gives zero iterations, and only the ingress probe gates.
- **Confidence:** proven (path)
- **Severity hint:** minor

#### F66
- **Target:** ce01/ce02 binding and step-read robustness (T10)
- **Evidence:** a gh error exits without a `FAIL:` line, `grep -qx ""` matches an empty
  `heads`, and BLOCKED is read once after 5 s (UNKNOWN possible) and isn't attributed to
  `cluster`.
- **Confidence:** proven
- **Severity hint:** minor

#### F67
- **Target:** c01's arch check uses the shell's arch, not Docker's (T11)
- **Confidence:** proven
- **Severity hint:** minor

#### F68
- **Target:** ce03's transient read; working tree vs committed `k8s/` (T12)
- **Confidence:** proven
- **Severity hint:** minor

#### F69
- **Target:** ce04 truthiness: `[]` or `0` give false reds (T13)
- **Confidence:** proven
- **Severity hint:** minor

#### F70
- **Target:** the stalled-create comment against the job-level dump (P2/P4 interplay, folded
  into F42/F44)
- **Evidence:** a duplicate entry kept so ids stay contiguous.
- **Confidence:** proven
- **Severity hint:** minor

### Surfaces
- **Swept (P):** step names match exactly; pipefail failure in the image capture; List vs
  single output; the dry-run is read-only; empty k8s/ fails before apply; the regex and sed
  on port/digest/uppercase; the `GITHUB_ENV` write; the dump can't fail the job; `.json`,
  `.yml` and flow-style files are read like the apply reads them. All held.
- **Swept (D):** the README smoke command and wait; the perl quoting (zsh/bash,
  macOS/Linux); release 2's `sha-<7>` is published; the promote first-parent check; level 2
  needs one release; no stale `*.yaml`-only claim; the PLAN 01 bullet; backoff and nginx
  exit. All held.
- **Swept (T):** c02's rotation arithmetic and mutations; `x=$(cmd) && fail` under `set -e`;
  the ce03 trap preserving status; the UID check; the DNS sleep; ce01's cancel-vs-failure
  steps; ce02 mutations; pipeline failure propagation; c03 ports; c04 nulls; run.sh globs;
  `.cluster-owned` gitignored and per worktree; `--prune --all` inside an owned cluster. All
  held.
- **Unattacked:** whether a step `timeout-minutes` concludes `failure` or `cancelled`;
  `events --sort-by` with null timestamps; 08 and c06 (outside the diff); k3d log format
  without a TTY (seen in CI: it matches); bash 3.2 for the new code.

### Verdicts
Iteration 2. Closed this iteration: 26 slices (F1–F3, F7–F35 except F4–F6, which are
implemented and wait for the ACT run). Carrying 8 refuted. 33 new findings adjudicated here
on the delegates' evidence; no verification delegates.

#### F38 — CONFIRMED minor
- **Reason:** It's real and was observed live, but not on the documented path: nothing in
  level 2 recreates the Service under a running frontend. It's the resolve-once lesson in
  Kubernetes form, and it belongs in the docs.

#### F39 — CONFIRMED major
- **Reason:** The core gate (red smoke ⇒ red `cluster`) has no test, while `smoke` has e10
  for the same risk. A `|| true` would ship unnoticed.

#### F40 — CONFIRMED major
- **Reason:** The code path is proven: `kc` isn't bound to the owned container. The scenario
  is rare, but it would breach the harness's one safety rule with destructive commands, and
  the fix (a private kubeconfig from k3d) is cheap.

#### F41 — CONFIRMED minor
- **Reason:** The repository isn't checked, and the text overclaims "published". Publication
  is deliberately left to the pull (ce01's path), so the fix is a repository check plus
  honest wording.

#### F42 — CONFIRMED minor
- **Reason:** The dump has no docker/k3d state for create-time failures (proven gap). Whether
  the kubeconfig is absent is unproven, but the docker/k3d state is what such a failure needs
  either way.

#### F43 — CONFIRMED minor
- **Reason:** Events, describe and logs are default-namespace only.

#### F44 — CONFIRMED minor
- **Reason:** The step bounds can sum to more than the job timeout, and a cancel skips the
  dump.

#### F45 — CONFIRMED minor
- **Reason:** The filter isn't container-precise. Not reachable with today's `k8s/`, but
  cheap.

#### F46 — CONFIRMED minor
- **Reason:** Empty or missing images give misleading messages.

#### F47 — CONFIRMED minor
- **Reason:** A silent pass leaves no evidence of what was read.

#### F48 — REFUTED
- **Reason:** A create failure is reported by its own step. ce02 on a flake goes falsely red,
  never falsely green.
- **Reopens only if:** a create flake is shown making a pin test pass.

#### F49 — CONFIRMED minor
- **Reason:** What release 2 must contain is unstated.

#### F50 — CONFIRMED minor
- **Reason:** It's undocumented that the level tag's image reports a different `version` from
  the replayed cluster.

#### F51 — CONFIRMED minor
- **Reason:** The example is wrong for level 2 itself.

#### F52 — CONFIRMED minor
- **Reason:** An unverified specific number. The fix is to state the mechanism without it.

#### F53 — CONFIRMED minor
- **Reason:** "Never" overclaims a race. Wording.

#### F54 — REFUTED
- **Reason:** CI's pin check rejects both at PR time with a clear message, and a local apply
  fails loudly.
- **Reopens only if:** a malformed bump passes `cluster`.

#### F55 — REFUTED
- **Reason:** `k8s/` holds only the five images by design (ce04/c05). Admitting another image
  is a future level's design decision (12).
- **Reopens only if:** level 12's design adds a non-knock image to `k8s/`.

#### F56 — CONFIRMED minor
- **Reason:** PLAN's description of the pin check and the dump is stale.

#### F57 — CONFIRMED minor
- **Reason:** "App code" under-describes what's baked into images.

#### F58 — CONFIRMED minor
- **Reason:** perl is now a documented requirement.

#### F59 — CONFIRMED minor
- **Reason:** The scan has named bypasses. It's a static scan, inherently incomplete. Widening
  it to forbid any `secrets`, `login` or `push` mention in `cluster` closes these cheaply, and
  F39's test covers the gate itself.

#### F60 — CONFIRMED minor
- **Reason:** Presence isn't equality. Exact node lines and the loadbalancer port-mapping line
  are cheap.

#### F61 — CONFIRMED minor
- **Reason:** The merge ref can differ from the head. Binding to the images the run itself
  printed (F47) closes the pin half. Other `k8s/` fields remain a residual, noted.

#### F62 — CONFIRMED minor
- **Reason:** The trap contradicts the KEEP_CLUSTER promise.

#### F63 — CONFIRMED minor
- **Reason:** A missing `backends/` passes vacuously, and the scope is narrow.

#### F64 — CONFIRMED minor
- **Reason:** Config volumes aren't checked.

#### F65 — CONFIRMED minor
- **Reason:** An empty list skips the rollout wait silently.

#### F66 — CONFIRMED minor
- **Reason:** An empty `heads` matches. BLOCKED is read once.

#### F67 — CONFIRMED minor
- **Reason:** Rosetta or a remote engine skips the arch check.

#### F68 — REFUTED
- **Reason:** A dirty `k8s/` is operator misuse, the same class as level 1's F72 (accepted).
  The release check runs on a clean tree, and the transient read only gives false reds.
- **Reopens only if:** a release check is run on a dirty tree.

#### F69 — CONFIRMED minor
- **Reason:** Empty arrays or zeros would false-red ce04.

#### F70 — REFUTED
- **Reason:** A duplicate of F42/F44.
- **Reopens only if:** never on its own.

### Remediation slices
- [ ] [major] F39 — A new ACTS test (ce06): a throwaway PR into `dev` whose `k8s/` breaks the
      Downward API for one backend (NODE_NAME a literal `local`) turns `cluster` red: the
      smoke step concludes `failure`, its output has `FAIL: … node … local`, and the PR is
      BLOCKED. `smoke` stays green. ce05 also refuses `continue-on-error` and `|| true` in
      `cluster`, and a non-bash shell.
- [ ] [major] F40 — Every harness kubectl call uses a kubeconfig written by
      `k3d kubeconfig get knock` for the owned cluster, never the user's kubeconfig.
- [ ] [minor] F41 — The pin check fails unless every image is
      `ghcr.io/izentenosmith/knock-knock-<name>:<tag>`, and its text no longer claims to
      verify publication.
- [ ] [minor] F42 — On failure, the dump also shows `docker ps -a` and `k3d node list`.
- [ ] [minor] F43 — On failure, events, describe and logs cover kube-system too (Traefik).
- [ ] [minor] F44 — The job timeout exceeds the sum of its bounded steps plus the downloads,
      and the downloads are bounded.
- [ ] [minor] F45 — The pin check reads container images only (`containers`,
      `initContainers`, `ephemeralContainers`).
- [ ] [minor] F46 — An empty or missing image fails the pin check with a message saying so.
- [ ] [minor] F47 — A passing pin check prints the images it read.
- [ ] [minor] F61 — c07 requires the images the run printed to equal the tree's images.
- [ ] [minor] F38 — PLAN's level 02 note says a recreated `knock-api` leaves a running
      frontend on the old address until it restarts (`kubectl rollout restart
      deployment/frontend`).
- [ ] [minor] F49 — README/PLAN say release 2 holds only the pin bump plus the `k8s/`/CI
      changes that need the new images, with nothing else merged into `dev` in between.
- [ ] [minor] F50 — README/PLAN say the level tag's images report release 2's `sha-<7>` while
      the replayed cluster reports release 1's.
- [ ] [minor] F51 — PLAN's opt-in example is accurate for level 2.
- [ ] [minor] F52 — PLAN states the DNS-caching mechanism without an unverified number.
- [ ] [minor] F53 — PLAN says the single apply wins the race in practice, not "never".
- [ ] [minor] F56 — PLAN describes the pin check and the dump as built.
- [ ] [minor] F57 — The two-release trigger is "anything baked into an image".
- [ ] [minor] F58 — README Requirements list perl.
- [ ] [minor] F59 — ce05 fails if `cluster` mentions `secrets`, `login` or `push` at all.
- [ ] [minor] F60 — c07 requires exactly the three expected `Creating node` lines and k3d's
      "portmapping '8080:80' targets the loadbalancer" line.
- [ ] [minor] F62 — ce03's failure trap keeps the cluster when KEEP_CLUSTER is set (and says
      it's broken).
- [ ] [minor] F63 — ce04's CORS check fails if a scanned directory is missing, and scans
      `backends/`, `frontend/` and `k8s/` (excluding vendored and build directories).
- [ ] [minor] F64 — ce04 refuses ConfigMap, Secret and projected volumes.
- [ ] [minor] F65 — wait_ready fails if it finds no Deployments.
- [ ] [minor] F66 — ce01/ce02 fail with a `FAIL:` line on empty bindings, and poll the merge
      state until it's known.
- [ ] [minor] F67 — c01's arch check uses Docker's architecture.
- [ ] [minor] F69 — ce04's checks treat empty arrays and zeros as absent.

### Verdict: NO-GO
- **Reason:**
  - Open: 2 confirmed majors (F39, F40) and 26 new confirmed minors. F4–F6 are implemented
    but unobserved (the ACT run). 7 refuted this iteration, 0 INCONCLUSIVE.
  - Iteration 2 of at most 3. Progress is monotonic: 26 slices closed.
  - Carried smells: N1, N3, N5, N6, N7, N9, N10.

## Iteration 3

### Closed slices
- [x] F39 — verified statically by ce05-cluster-never-publishes.sh (mutations: `|| true` on the
      cluster smoke step, `continue-on-error`, `shell: sh` all turn it red). The runtime half,
      ce06-red-smoke-fails-cluster.sh, waits for the ACT run.
- [x] F40 — verified by lib-cluster.sh: `kc` uses only `.cluster-kubeconfig` from
      `k3d kubeconfig get knock`, and `owned()` requires it. The full local suite ran through it.
- [x] F41 — verified by review of the pin check (repository regex, wording)
- [x] F42 — verified by review: the dump runs `docker ps -a` and `k3d node list` first
- [x] F43 — verified by review: all-namespaces events, describe, ingress/svc/endpointslices,
      Traefik's log
- [x] F44 — verified by review: job 25 min against about 14 min of bounded steps; k3d download
      `--max-time 120`
- [x] F45 — verified locally: the container-only filter on the k3d cluster prints the five images
- [x] F46 — verified by review: explicit errors for no containers and an empty image
- [x] F47 — verified locally: the `k8s/ runs:` output (bash 3.2 and 5)
- [x] F61 — verified by c07-ci-cluster-job.sh (compares the printed images with the tree's), on
      the next run
- [x] F38, F49, F50, F51, F52, F53, F56, F57, F58 — verified by review of PLAN.md and README.md
- [x] F59 — verified by ce05 (mutation: `secrets['GHCR_PAT']` turns it red)
- [x] F60 — verified by c07 (exact node lines plus the loadbalancer port mapping), on the next run
- [x] F62 — verified by review of ce03's trap
- [x] F63, F64, F69 — verified by ce04 (rewritten: `present`, volumes, scanned directories must exist)
- [x] F65 — verified by lib-cluster.sh `wait_ready` (fails on no or unlistable Deployments)
- [x] F66 — verified by `bind_run`/`merge_state` in lib-cluster.sh, used by ce01/ce02/ce06
- [x] F67 — verified by c01 (Docker's architecture), green locally
- [x] F60, F61 — re-observed: c07 PASS on PR #33's run 40209005241 (exact nodes, loadbalancer
      mapping, printed images equal to the tree's)

### Smells
- **N1, N3, N5, N6, N7, N9, N10** — left: condition not met. N8 stays retired.
- No new smells. ce01/ce02/ce06 now share `bind_run`/`merge_state` (lib-cluster.sh) instead of
  three copies.

### Findings (unadjudicated)
Iteration 3 (final): three read-only delegates: the last round's CI/docs diff (C), its harness
diff (H), and an end-to-end read against the done criteria (E). Findings are condensed; ids
are new. Plus one found while verifying (F96).

#### F71
- **Target:** CI pin check, a trailing image-less container (C1)
- **Evidence:** `$(…)` strips trailing newlines, so an empty image last in the stream escapes
  `grep -qx ''`. "No containers" is misreported when the only image is empty.
- **Confidence:** proven
- **Severity hint:** minor

#### F72
- **Target:** `has("containers")` matches non-pod objects (C2)
- **Evidence:** a ConfigMap, CRD schema or CR with a `containers` key gives a jq type error or
  a false "no image". Not reachable today.
- **Confidence:** proven (jq)
- **Severity hint:** minor

#### F73
- **Target:** the pin check doesn't count or name the five images (C3, E5)
- **Evidence:** a misspelled or duplicated knock-knock name passes until the pull fails. The
  comment and PLAN overstate "the five".
- **Confidence:** proven
- **Severity hint:** minor

#### F74
- **Target:** PLAN's dump wording against the dump's real scope (C4)
- **Evidence:** pod logs come from default only, plus Traefik's; there are no logs from the
  helm-install job, CoreDNS or svclb.
- **Confidence:** proven
- **Severity hint:** minor

#### F75
- **Target:** README and PLAN disagree on release-2 contents (C5)
- **Evidence:** README's "holds only the PR … plus …" with "CI changes" contradicts PLAN's "only
  … `cluster` changes, nothing else merged in between". A build-affecting CI change in
  release 2 would break "same code".
- **Confidence:** proven
- **Severity hint:** minor

#### F76
- **Target:** unbounded kubectl apply/dry-run against a hung API server (C6)
- **Evidence:** a job-timeout cancel skips the dump.
- **Confidence:** unproven
- **Severity hint:** minor

#### F77
- **Target:** README "each tile now names a real pod and node" (E1, E7)
- **Evidence:** App.jsx shows `pod` on the tile and `node` only in the hover tooltip (PLAN §1:
  "Hover shows the full signature"); the tally has no node view. Level 2 changes no app code.
- **Confidence:** proven
- **Severity hint:** major

#### F78
- **Target:** the required `cluster` check never loads the UI (E2)
- **Evidence:** CI requests only `/api/knock`. An Ingress `/` → `knock-api` would pass `cluster`
  while `/` has no UI. c01/c06 catch it locally at the release check.
- **Confidence:** proven
- **Severity hint:** major

#### F79
- **Target:** a wrong POD_NAME fieldRef is invisible to CI (E3)
- **Evidence:** smoke checks only `node`; c04 checks the spec locally.
- **Confidence:** proven
- **Severity hint:** minor

#### F80
- **Target:** nginx.conf's rotation comments and README's silence on random order in k3d (E4)
- **Confidence:** proven
- **Severity hint:** minor

#### F81
- **Target:** learners' k3d/kubectl versions are unpinned (E6)
- **Confidence:** unproven
- **Severity hint:** minor

#### F82
- **Target:** the README tagline "worker-2" (E7)
- **Confidence:** proven
- **Severity hint:** minor

#### F83
- **Target:** `cluster` not yet required in live protection (E8, F18's territory)
- **Confidence:** proven (current state)
- **Severity hint:** minor

#### F84
- **Target:** ci.yml doesn't re-run on `edited` (a base change) (E9, pre-existing)
- **Confidence:** unproven
- **Severity hint:** minor

#### F85
- **Target:** ce05's static ban misses `set +e`, `set +o pipefail`, `if`/`!`/`& wait`; two of
  its patterns can't hide a failure under `-e` (H1)
- **Confidence:** proven
- **Severity hint:** major

#### F86
- **Target:** the ownership record when the private kubeconfig is missing or empty (H2)
- **Evidence:** OWNED is written before KUBECFG. An empty KUBECFG or a round-2 cluster makes
  `owned()` false; cluster-down skips the delete but removes OWNED, so the cluster is
  orphaned and refused forever.
- **Confidence:** proven (control flow)
- **Severity hint:** minor

#### F87
- **Target:** ce03's KEEP_CLUSTER warning is invisible through run.sh (H3)
- **Confidence:** proven
- **Severity hint:** minor

#### F88
- **Target:** merge_state may stop on a transient DRAFT/UNSTABLE right after `gh pr ready` (H4)
- **Confidence:** unproven
- **Would be settled by:** the ACT=1 runs of ce01/ce02/ce06, logging the states read
- **Severity hint:** minor

#### F89
- **Target:** ce05 lets `vars.*` credentials and `imagetools create` through (H5)
- **Confidence:** proven
- **Severity hint:** minor

#### F90
- **Target:** ACT cleanup leaks the throwaway PR if `wait_run` fails (H6; ce01/ce02/ce06)
- **Confidence:** proven
- **Severity hint:** minor

#### F91
- **Target:** `.cluster-kubeconfig` is mode 0644 (it holds a client key; gitignored) (H7)
- **Confidence:** proven
- **Severity hint:** minor

#### F92
- **Target:** ce04 `present` counts `""`; misses revisionHistoryLimit, paused,
  imagePullSecrets, hostPID/IPC, ephemeralContainers (H8)
- **Confidence:** proven
- **Severity hint:** minor

#### F93
- **Target:** c01's arch check is skipped silently if `docker info` fails or reads another
  context (H9)
- **Confidence:** proven / unproven
- **Severity hint:** minor

#### F94
- **Target:** ce05's substring ban could false-red a future diagnostic (`kubectl get secrets`) (H10)
- **Confidence:** proven (hypothetical edit)
- **Severity hint:** minor

#### F95
- **Target:** duplicate of F73 (E5)
- **Severity hint:** minor

#### F96
- **Target:** c07 permissions parse could SIGPIPE (found by Tyr while re-observing)
- **Evidence:** `awk … {exit}` at the end of `job_log | … | sed | awk` lets sed die with
  SIGPIPE. Under pipefail the assignment exits 141 with no FAIL line. Seen once, after which
  c07 passed on reruns.
- **Confidence:** proven
- **Severity hint:** minor

### Surfaces
- **Swept (C):** the jq filter over a List; `grep -qx ''` mid-stream; the indented echo under
  bash 3.2 and 5; error order under pipefail; the dump can't fail or flood; the 25-min budget
  against the summed bounds; PLAN's level-1-images and Service-recreate claims; the README perl
  and Requirements. All held.
- **Swept (E):** names, ports and env across k8s/, nginx, backends and Dockerfiles; the pin is
  main's published head; the two-release rule against promote.sh and publish.yml; level-1
  workflows untouched; no scope creep; arm64; the version check. All held.
- **Swept (H):** the ce04 `$?` idiom; bind_run's empty-read guard; c07's node grep and awk
  extraction against real log formatting; ce06's breakage (`local` fallback → the prefix FAIL;
  Wait unaffected; `smoke` untouched); `kc` ignores KUBECONFIG; wait_ready; ce05's shell and
  continue-on-error checks; merge_state under errexit. All held.
- **Unattacked:** the ACT-mode tests can't run until `dev` has `k8s/` (true since iteration
  1, not new); live k3d/GitHub timing; file modes on disk.

### Verdicts
Iteration 3 (final). Closed this iteration: 26 slices (F39–F69 confirmed set, F60/F61
re-observed). Carried refutations stand: F17, F18, F20, F21, F24, F25, F36, F37, F48, F54, F55,
F68, F70. 26 new findings adjudicated here on the delegates' evidence. One re-run made: c07
against run 40209005241 (5/5 green after F96's fix).

#### F71 — CONFIRMED minor
- **Reason:** A trailing image-less container escapes the explicit check (it still fails later,
  at apply or the wait).

#### F72 — REFUTED
- **Reason:** `k8s/` may hold only Deployments, Services and an Ingress (ce04), so no other
  object reaches the filter.
- **Reopens only if:** a level admits other kinds into `k8s/` (that level must revisit the
  filter).

#### F73 — CONFIRMED minor
- **Reason:** The comment and PLAN claim "the five"; the step checks the repository family
  only. c05 enforces the exact five locally at the release check.

#### F74 — CONFIRMED minor
- **Reason:** PLAN's wording overstates the log scope.

#### F75 — CONFIRMED minor
- **Reason:** README and PLAN disagree on release 2's contents.

#### F76 — REFUTED
- **Reason:** The bounded steps cover the realistic failures, and a hung API server is
  unproven.
- **Reopens only if:** a `cluster` run is cancelled at the job timeout without a dump.

#### F77 — CONFIRMED minor
- **Reason:** README overclaims: the tile shows `pod`, `node` is on hover. Every
  signature field is visible in the UI, which is "the same UI" by design (no app change at
  level 2), so "shows pod and node names" holds through the hover. The README sentence is
  wrong. Whether tiles should show `node` is a product question for the user, not a defect
  here.

#### F78 — CONFIRMED minor
- **Reason:** The brief's CI criterion is "smoke through the ingress", which holds. The UI half
  of done-criterion 1 is proven by c01/c06 in the release check, the level's evidence. A UI
  probe in `cluster` would be defense in depth: a tracked follow-up, not a gap in the release
  evidence.

#### F79 — CONFIRMED minor
- **Reason:** Same shape as F78. c04 proves the spec at the release check, and CI doesn't.

#### F80 — CONFIRMED minor
- **Reason:** README doesn't say k3d's order is random. (The nginx.conf comments are app code,
  out of scope; level 3 is the lesson.)

#### F81 — REFUTED
- **Reason:** Deferred by design (k3s/Traefik versions beyond the k3d pin).
- **Reopens only if:** a learner's k3d/kubectl diverges from CI in an observed failure.

#### F82 — REFUTED
- **Reason:** Level-0 flavour text, not a level-2 claim.
- **Reopens only if:** the tagline is presented as an instruction.

#### F83 — REFUTED
- **Reason:** F18 stands, and no release has been proposed while 08 is red.
- **Reopens only if:** a release is proposed while `08` is red.

#### F84 — REFUTED
- **Reason:** Pre-existing in level 1, and checks attach to the SHA (level 1's F82 refuted the
  same mechanism).
- **Reopens only if:** a case is shown where a re-targeted PR's checks don't match the merged
  content.

#### F85 — CONFIRMED minor
- **Reason:** The static scan is inherently incomplete. The claim it backs ("a red smoke fails
  `cluster`") is proven at runtime by ce06 in the ACT=1 release check, which runs the actual
  workflow and would catch `set +o pipefail`. Hardening the scan is a tracked follow-up.

#### F86 — CONFIRMED minor
- **Reason:** It can orphan a harness cluster. It fails closed: refused, never deleted.

#### F87 — CONFIRMED minor
- **Reason:** run.sh drops the warning.

#### F88 — INCONCLUSIVE
- **Settled by:** the ACT=1 runs of ce01/ce02/ce06 at the release check (the user's
  confirmation is needed); they read the merge state live
- **Pass:** 1

#### F89 — CONFIRMED minor
- **Reason:** Same class as F85, and ce06 covers the runtime claim.

#### F90 — CONFIRMED minor
- **Reason:** The same shape level 1 accepted (e01 and others).

#### F91 — CONFIRMED minor
- **Reason:** The file holds a local test cluster's admin key with world-readable permissions.

#### F92 — CONFIRMED minor
- **Reason:** `""` is inconsistent with the rule, and some fields aren't covered.

#### F93 — CONFIRMED minor
- **Reason:** The check is skipped silently on a `docker info` failure.

#### F94 — REFUTED
- **Reason:** It's hypothetical, and a false red is loud; narrow the ban when a real diagnostic
  needs it.
- **Reopens only if:** a needed diagnostic is blocked.

#### F95 — REFUTED
- **Reason:** A duplicate of F73.

#### F96 — CONFIRMED minor
- **Reason:** The flake was real (exit 141) but only ever false red. Fixed while verifying:
  both awk filters now read to the end. c07 went 5/5.

### Remediation slices
- [ ] [minor] F71 — The pin check's empty-image test also catches a trailing image-less container.
- [ ] [minor] F73 — The pin-check comment and PLAN say what the step checks (the knock-knock
      repository family, one sha tag). c05 checks the exact five.
- [ ] [minor] F74 — PLAN describes the dump's log scope exactly.
- [ ] [minor] F75 — README step 5 matches PLAN on release 2's contents.
- [ ] [minor] F77 — README says tiles name the pod, and hovering a tile shows its node (with
      the rest of the signature).
- [ ] [minor] F78 — `cluster` also fetches `/` through the ingress and requires the frontend's
      page.
- [ ] [minor] F79 — CI fails when an answer's `pod` isn't a `knock-<lang>-` pod name.
- [ ] [minor] F80 — README's k3d section says the order is random now (level 3 explains why).
- [ ] [minor] F85 — ce05 also refuses `set +e`/`set +o`, `if`/`!` around smoke, and
      backgrounding in the smoke step.
- [ ] [minor] F86 — The harness writes KUBECFG before OWNED, and cluster-down keeps OWNED when
      it can't delete.
- [ ] [minor] F87 — run.sh shows a test's warnings after its FAIL line.
- [ ] [minor] F89 — ce05 also refuses `vars.` and `imagetools`.
- [ ] [minor] F90 — The ACT tests close their throwaway PR on any failure after creating it.
- [ ] [minor] F91 — The private kubeconfig is written mode 0600.
- [ ] [minor] F92 — ce04's `present` treats `""` as absent, and refuses revisionHistoryLimit,
      paused, imagePullSecrets, hostPID/hostIPC, ephemeralContainers.
- [ ] [minor] F93 — c01 fails if Docker's architecture can't be read.
- [x] F96 — fixed during verification (awk reads to the end); c07 5/5 green.

### Verdict: ESCALATED
- **Reason:**
  - **Defects:** none open above minor. 0 confirmed blockers or majors; 16 confirmed minors
    (F71, F73–F75, F77–F80, F85–F87, F89–F93), F96 fixed. 11 refuted this iteration.
  - **What stops a GO:** iteration 3 is the cap, and two things are open that only the user
    can unblock.
    - **F88 is INCONCLUSIVE.** It settles only in an ACT=1 run.
    - **Some acceptance tests aren't green yet:** `08` (protection), and ce01/ce02/ce06
      (ACTS; they branch from `dev`, which doesn't have `k8s/` until PR #33 merges).
  - **Upstream cause:** none. The loop converged on the design. Every major after iteration 1
    was in the verification harness or the docs, and none in the manifests.
  - **The user's options:**
    1. Merge PR #33 into `dev`, apply protection, then run the release check with ACT=1. If
       it's green: GO with the 16 minors as tracked follow-ups (or fix some first).
    2. Fix some or all of the minors before merging. That's a fourth pass outside this
       loop's cap, at the user's call.
    3. Hold.

### Release check (pre-main), 2026-10-25
Tree `a099b64` (= `dev` @ `de73a5c`'s content), `ACT=1 .workflow/acceptance/run.sh`, 17:36–18:06 -03:
36/41 green.
- **Level 2, all green, live:**
  - ce01 (run 40233332085, PR #40), ce02 (run 40233596884, PR #41) and ce06 (run 40233771616,
    PR #42): each red for its own reason and BLOCKED. Throwaway PRs closed, branches deleted.
  - c01–c07, ce03–ce05 and 08 (with `cluster` now required) also green.
- **F88 settled:** `merge_state` read BLOCKED in all three ACT runs. REFUTED by that observation
  (reopens only if an ACT run reads a transient state).
- **Level 1:** 01, 02, 03, 06, 07, e01, e02, e06, e07, e08, e10–e13 and l1–l4 green.
- **Not green, and why:**
  - **04, 05, e03:** stale observation. They observe `main`'s and the `dev`→`main` runs, which
    still ran level 1's workflows. They need the level 2 release to `main`, then a re-run.
  - **e05:** history-only by design. It refuses to act once the tag ruleset exists. Replay mode
    (observed.env, `HISTORY=1`) passes, as at the level 1 release.
  - **e09:**
    - The feature half re-ran live with `ACT=1` and passed (run 40233988723 cancelled by
      40234013819; PR #43 closed).
    - No `main` or tag run has ever been cancelled.
    - The overlapping-`main`-pair half can't be fresh until two `main` commits carry level 2's
      workflows. It was replayed from level 1's pair (`HISTORY=1`). Justification:
      `ci.yml`'s concurrency block is unchanged since `04f74b3`.

### Release check (released tree), 2026-10-29
- **The release.**
  - #44 (this ledger's pre-main entry) → `dev` (`dedf4ec`). Then release PR #45 `dev` → `main`
    with all four required checks green: smoke, cluster, only-dev-to-main, release-ready (dry
    run 40909016027).
  - Merged as `ef37ffe` (merge commit, parents `04f74b3` and `dedf4ec`).
  - `main`'s run 40910931310 is green: smoke, cluster, and `sha-ef37ffe` published for all five.
  - The released tree equals the tested tree (`git diff HEAD origin/main` is empty).
- **Re-proven fresh after the merge:**
  - 04 (against #45);
  - 05 and 03 (`main`'s run);
  - 06 (anonymous pull of `sha-ef37ffe`);
  - e03 (`ACT=1`: re-ran 40910931310, all five skipped, digests unchanged).
- **Full suite against `ef37ffe`'s tree (replay of the live runs):** 40/41 green.
  - The level 1 ACTS tests e01, e08 and e10–e13 replay the live `ACT=1` runs of 2026-10-25,
    which ran the same workflows and scripts (now in `observed.env`).
  - The level 2 tests are all green, and the local cluster tests were rebuilt from scratch.
- **e09 is the exception, by design.**
  - Its feature half is fresh (40233988723 cancelled by 40234013819).
  - No `main` or tag run has ever been cancelled.
  - The overlapping-`main`-pair half needs two `main` commits on level 2's workflows, and only
    one exists. It's replayed from level 1's pair; the concurrency block is unchanged since
    `04f74b3`.
  - It becomes fresh with the next release to `main`.
- **Found while running it (level 1 harness, minor):**
  - l1–l3 seed from local `knock-knock-<svc>:latest` images, but `compose.yaml` has no `name:`,
    so compose names images after the checkout directory. In a worktree
    (`level-02-cluster-setup-1d316a-<svc>`) they fail unless the images already exist.
  - Passed with `COMPOSE_PROJECT_NAME=knock-knock docker compose build` first.
  - The follow-up is a level 1 harness fix: the l-tests build with
    `-p knock-knock` / `COMPOSE_PROJECT_NAME`.
- **Tag:** `level-02-cluster` on `ef37ffe` is ready (it's one of `main`'s first-parent merge
  commits and its run is green). It waits for the owner's confirmation.

### Level tag, 2026-10-30
- The owner confirmed. Annotated `level-02-cluster` pushed on `ef37ffe` (origin/main's head, a
  first-parent merge commit).
- Tag run 41062584922 is green: smoke, cluster, and five `publish / promote` jobs. `publish /
  build` was skipped, so nothing was rebuilt.
- 07 (`LEVEL_TAG=level-02-cluster`) passes. Every service's `:level-02-cluster` digest equals
  its `:sha-ef37ffe` digest:
  go `5faa385d…`, python `57ad6068…`, rust `cfb307aa…`, ts `b94ca87b…`, frontend `4086a171…`.
  These are the digests e03 recorded before its re-run.
- Minor (harness): 07's pass line still says "level-01 release" whatever `LEVEL_TAG` is.
