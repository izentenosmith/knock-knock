# knock-knock: the plan

> *Knock knock.* — *Who's there?* — *A Rust pod on worker-2, it took me 41 µs.*

A Kubernetes training project. A minimal React frontend knocks on one API.
Behind it sit four identical backends written in **Go, Python, Rust and
TypeScript**. The frontend never knows which one will answer; every answer is
signed, so the UI can show who picked it up, where it runs, and how long it
took.

The four apps are deliberately trivial. **What you're learning is Kubernetes
and the pipeline, not the apps.** If you find yourself polishing the Rust
code, you've drifted off the goal.

---

## 1. The app contract

Every backend is about 20 lines, listens on **port 8080**, and exposes exactly
two routes:

| Route | Purpose |
|---|---|
| `GET /api/knock` | answer the knock with a signature |
| `GET /healthz` | `200 ok` (used by probes from level 4 on) |

### The signature (`GET /api/knock`)

```json
{
  "lang": "rust",
  "version": "sha-3f9c2a1",
  "pod": "knock-rust-7f9c4d-x2k8p",
  "node": "k3d-knock-agent-1",
  "pod_started": "2026-10-08T14:02:11.123Z",
  "served": 41,
  "received_at": "2026-10-08T14:07:55.201314Z",
  "responded_at": "2026-10-08T14:07:55.201355Z",
  "took_us": 41
}
```

| Field | Source | What it teaches |
|---|---|---|
| `lang` | hard-coded | which language answered |
| `version` | `VERSION` env, set at image build from the git SHA | rolling updates (level 5) |
| `pod`, `node` | `POD_NAME`, `NODE_NAME` env via the **Downward API**; fall back to hostname / `local` outside k8s | where the answer came from |
| `pod_started` | process start time | pods are disposable |
| `served` | in-memory counter for this process | resets on restart, so state doesn't belong in pods |
| `received_at` / `responded_at` | wall clock, UTC, ISO 8601, microseconds | when |
| `took_us` | **monotonic** clock, received → just before writing the response | how long the backend itself took |

Timing rules:
- `took_us` must come from a monotonic clock (`time.Since`, `time.perf_counter_ns`,
  `Instant::now`, `process.hrtime.bigint`). Subtracting the two wall-clock
  stamps would lie whenever NTP adjusts the clock.
- The unit is **microseconds**. A trivial handler finishes in well under 1 ms,
  so milliseconds would always read `0`.
- Optional `DELAY_MS` env (default `0`): the backend sleeps that long before
  answering. It's how we make latency visible on purpose (level 9).

### The four backends

| Lang | Stack | Runtime image |
|---|---|---|
| Go | stdlib `net/http` | `scratch` |
| Python | stdlib `http.server` (`ThreadingHTTPServer`) | `python:3.13-slim` |
| Rust | `tiny_http` (the only crate) | `gcr.io/distroless/static` (musl build) |
| TypeScript | Node 24 stdlib `http`, run directly (native type stripping, no build step) | `node:24-alpine` |

Every Dockerfile runs as non-root. The ones with something to build (Go, Rust,
the frontend) are multi-stage; Python and TypeScript have nothing to build and are
a single stage. The four backends take `VERSION` as a build arg (the frontend
doesn't report one). Image sizes span from about 8 MB to about 240 MB, and that gap is
part of the lesson.

### The frontend

A minimal **React** app (Vite, plain JSX, plain CSS, no UI library, a single
`App.jsx`). It's built to static files and served by `nginx`, which also
proxies `/api/` to the hostname `knock-api:8080`. The browser only ever talks
to its own origin, so there's no CORS.

UI:
- **Knock** sends one request. **Fire N** sends N, with a **sequential / parallel** toggle.
- **Tiles:** one per answer, coloured and labelled by language (Go 🐹 cyan,
  Python 🐍 yellow, Rust 🦀 orange, TS 🟦 blue). Hover shows the full
  signature.
- **Timing per tile:**
  - `took`: server time (`took_us`)
  - `rtt`: client round trip, measured with `performance.now()`
  - `network ≈ rtt − took`: everything that isn't the backend (proxy, kube-proxy, ingress, the network)
- **Tally:** answers per language and per pod. This is where a distribution you
  didn't expect becomes visible.
- **Target** (from level 3): the URL to knock on. The default `/api` goes
  through the L7 path; you can point it at the L4 Service port to compare.

---

## 2. Repo layout

```
knock-knock/
├── backends/
│   ├── go/          main.go, go.mod, Dockerfile
│   ├── python/      main.py, Dockerfile
│   ├── rust/        src/main.rs, Cargo.toml, Cargo.lock, Dockerfile
│   └── ts/          server.ts, package.json, Dockerfile
├── frontend/        Vite + React, nginx.conf, Dockerfile
├── compose.yaml     level 0 local run
├── scripts/
│   ├── smoke.sh         fire N knocks, assert all 4 langs answered + contract fields present
│   ├── build-image.sh   build one image once, check it, copy the same digest to GHCR (CI)
│   ├── check-image.sh   start one backend image, check its lang and version (CI)
│   ├── image-digest.sh  digest of an image tag, or nothing if the registry says it's missing (CI)
│   └── promote.sh       give a published image its level tag, same digest (CI)
├── k8s/             plain YAML from level 2; kustomize base/overlays from level 10
├── .github/workflows/
├── PLAN.md
├── README.md
├── LICENSE
└── .gitignore
```

---

## 3. Levels

Each level is **one concept**, finished with an annotated git tag. Tags are
zero-padded so they sort, and they are **immutable**: if a level turns out to
be wrong, fix it in a later commit instead of moving the tag. To replay a
level: `git checkout level-05-rolling-update`.

Every level is written up in the same four parts:
1. **Goal:** the one concept.
2. **Do:** the steps.
3. **See:** what the UI must show to prove it worked.
4. **Break it:** one exercise that breaks the thing on purpose and explains the result.

| Tag | Concept | What you see in the UI |
|---|---|---|
| `level-00-app` | The four backends + React UI + `compose.yaml` | tiles in four colours, perfect rotation |
| `level-01-pipeline` | GitHub Actions: build, smoke test, push to GHCR | (nothing new; images now live in a registry) |
| `level-02-cluster` | k3d cluster, Deployments, one Service across four Deployments, Ingress | the same UI, now running in Kubernetes |
| `level-03-load-balancing` | L4 Service vs L7 ingress, connection reuse | sequential knocks on L4 stick to one pod |
| `level-04-probes` | readiness / liveness | an unhealthy backend drops out of the tally |
| `level-05-rolling-update` | rolling update, `maxSurge` / `maxUnavailable` | `version` changes partway through a burst |
| `level-06-scaling` | replicas as weights, HPA (metrics-server ships with k3d) | the distribution shifts |
| `level-07-resources` | requests / limits, OOMKilled | `served` resets to 0, the pod restarts |
| `level-08-nodes` | multi-node, topology spread, `kubectl drain` | `node` changes |
| `level-09-config` | ConfigMap → `DELAY_MS` per language | `took` rises for one language; `network` doesn't |
| `level-10-kustomize` | replace 4× duplicated YAML with base + overlays | (nothing new; less YAML) |
| `level-11-canary` | Gateway API weighted routing | exactly ~10% of answers from the canary |
| `level-12-network-policy` | NetworkPolicy | one language can't be reached |
| `level-13-gitops` | Argo CD pulls from the repo; CI bumps the image tag | push to `main` → new `version` in the UI, no `kubectl` |

### Level notes

**00 — app.** All four backends plus the React UI, run with
`docker compose up --build`. The four backend services share the network alias
`knock-api`. Docker DNS returns all four IPs, and nginx round-robins across the
addresses a hostname resolves to, so compose shows **perfect rotation**. Write
that down: it's the baseline that Kubernetes will *not* reproduce at level 3.
The rotation is perfect only with `worker_processes 1`: each nginx worker keeps
its own round-robin counter, and with the default `auto` (one worker per CPU)
the first knocks all land on the same backend.

**01 — pipeline.** GitHub Actions, four workflows. `publish.yml` only ever
runs when another workflow calls it, and only `ci.yml`'s call (after a green
smoke test) can push.
- `ci.yml` runs on pushes to `dev` and `main`, on `level-*` tags, and on PRs into
  `dev` and `main`. Its `smoke` job runs the quickstart:
  `docker compose up --build --wait`, then `scripts/smoke.sh` with
  `EXPECT_VERSION=sha-<7>` (on PRs, `<7>` comes from GitHub's test merge commit).
  On `main` and `level-*` tags, its `publish` job calls `publish.yml` for real.
- `dry-run.yml` runs only on PRs into `main` (also when a PR's base is changed to
  `main`): it calls `publish.yml` without pushing, and `release-ready` is green
  only if that dry run passed. No other run ever produces a `release-ready`
  check, so nothing else can stand in for it.
- `publish.yml` (reusable) builds the five images as a matrix
  (`scripts/build-image.sh`): each image is built once, for `linux/amd64` and
  `linux/arm64` (QEMU), into a registry on the runner; each backend's amd64
  image is started from there and checked (`scripts/check-image.sh`); then, on
  `main`, that exact image is copied to
  `ghcr.io/izentenosmith/knock-knock-<svc>:sha-<7>` (same digest). `VERSION` =
  `sha-<7>`. Each backend is checked before *it* is pushed; the images are
  pushed independently, so a failed one leaves the others published, and a
  re-run finishes the rest. Only the `publish` job's token can write packages.
- `only-dev-to-main.yml` runs only on PRs into `main` (also when a PR's base is
  changed to `main`) and fails unless the head is this repo's `dev`.
- Tags are **immutable** in the registry too. A `sha-<7>` that already exists is
  never rebuilt (re-running a run is safe); one built from another commit stops
  the run. A `level-*` tag doesn't build at all: `scripts/promote.sh` retags the
  `sha-<7>` that `main` published (waiting for it if `main` is still
  publishing), so both names share one digest. A level tag on anything but one
  of `main`'s own merge commits, or not named `level-NN-<slug>`, fails before any
  image changes. A tag run uses the tagged commit's workflows, so this holds for
  commits released with this pipeline.
- `dev` and `main` are protected: PRs only, with `smoke` required (and
  `only-dev-to-main` and `release-ready` on `main`; level 2 adds `cluster` to
  both). A ruleset stops `level-*`
  tags from being moved or deleted. Merge `dev` into `main` with a merge commit,
  so `main` always contains `dev`. Pushes to `main` and tags never cancel each
  other: each commit gets its own concurrency group.

The smoke test is the project's only test, and it grows with each level.

**02 — cluster.** `k3d cluster create knock --agents 2 -p "8080:80@loadbalancer"`
(k3d ships Traefik as the ingress, plus servicelb and metrics-server, so we use
what's built in). The port mapping puts the ingress on `localhost:8080`, compose's
address, so the smoke test's default `URL` is unchanged; stop compose first.
Then `kubectl apply -f k8s/` (plain YAML, the default namespace).
- Four Deployments (`knock-go`, `knock-python`, `knock-rust`, `knock-ts`, one
  replica each) carry a shared label `pool: knock`, and **one** Service
  `knock-api` selects that label. The frontend gets its own Deployment and
  Service, and the Ingress routes `/` to it. The frontend's nginx still proxies
  to `knock-api:8080`, now the Service.
- `POD_NAME` / `NODE_NAME` come from the Downward API. A knock can prove only
  `node`: a pod's hostname is its name, so `pod` reads the same with or without
  `POD_NAME`. The smoke test's opt-in `EXPECT_NODE_PREFIX=k3d-knock-` fails on any
  answer whose `node` doesn't start with it (`local` means `NODE_NAME` isn't
  wired, or the knock landed on compose).
- **The manifests pin images that are already published.** All five reference one
  `sha-<7>` that `main` published (no `latest`), the same string the backends
  report as `version`. A commit can't pin its own `sha-<7>` (it's published only
  after the merge), so until level 13 the pin moves by hand, in a PR into `dev`. A
  level that changes app code therefore ships in two releases: the code, then the
  pin bump to the code release's `sha-<7>`. The level tag goes on the second, so
  `git checkout level-NN-…` plus `kubectl apply -f k8s/` runs that level's code.
- Because `cluster` runs each PR's smoke test against the *pinned* images, smoke's
  default checks (no variables set) must keep passing against them. A check that
  only newer images can pass is opt-in (a variable, like `EXPECT_NODE_PREFIX`),
  and `cluster` sets it only once the pin has moved. Otherwise the required check
  would wait for images that can't be published until the PR merges.
- There are no probes until level 4, so a pod counts as ready as soon as it
  starts. Waiting belongs to the environment, never to the smoke test: every
  Deployment `Available`, then the ingress answering a knock, then the strict
  smoke test. If the frontend starts before the Service exists, nginx can't
  resolve `knock-api` and exits; it restarts until the Service is there. That can
  take minutes: the restarts back off (up to 5 min), and CoreDNS caches the "no
  such host" answer for 30 s. A single `kubectl apply -f k8s/` creates the
  Service before nginx starts, so the normal path never sees it.
- CI gains the job `cluster`, beside `smoke` and required on `dev` and `main`
  like it. It installs a pinned k3d, creates the cluster with the same command,
  applies `k8s/` as committed (it never builds), waits, and runs the same smoke
  test through the ingress with `EXPECT_VERSION` = the pin and
  `EXPECT_NODE_PREFIX=k3d-knock-`. Pins that disagree fail before anything is
  applied. On failure it dumps the pods, their descriptions and logs. `publish`
  still needs only `smoke`: `cluster` tests the already-published pin, not the
  image about to be pushed.

**03 — load balancing.** This is the core lesson.
- A Service is **L4**: kube-proxy balances *connections*, not requests, and in
  iptables mode it picks pods at random, not in round robin.
- Expose `knock-api` as a LoadBalancer Service on its own port (the `Target`
  field in the UI, plus `Access-Control-Allow-Origin: *` on the backends,
  added only now).
- Sequential knocks reuse one keep-alive connection and stick to one pod.
  Parallel knocks open up to 6 connections (the browser's HTTP/1.1 limit per
  host) and spread at random.
- The `/api` path through ingress / nginx is **L7**: each request is balanced
  on its own. Explain why the two paths behave differently.
- Bonus: `kubectl port-forward svc/knock-api` always hits a single pod. Find out why.

**04 – 12.** One concept each, as listed in the table.

**13 — gitops.** Argo CD in the cluster watches `k8s/overlays/local`. On
`main`, `publish.yml` runs `kustomize edit set image` and commits the bump with
`[skip ci]` so it doesn't trigger itself. The pipeline is now complete:
`git push` → build → registry → manifest bump → Argo CD sync → new `version`
tiles.

---

## 4. Decisions

| Decision | Choice | Why |
|---|---|---|
| Frontend | React (Vite), static, served by nginx | minimal; nginx gives us same-origin `/api` |
| Local cluster | k3d | light, multi-node with one flag, ships ingress + LB + metrics-server |
| Registry | GHCR | free, same place as the repo, `GITHUB_TOKEN` auth |
| CI/CD | GitHub Actions + Argo CD (pull-based) | a local cluster can't be reached from CI, so CD has to pull |
| Manifests | plain YAML → Kustomize (level 10) | feel the duplication before removing it; skip Helm |
| Levels | annotated, immutable git tags | replayable checkpoints |
| Tests | one smoke script, run against compose, k3d-in-CI and your laptop | testing the apps isn't the goal; the contract is |

## 5. Out of scope (until level 13 feels easy)

Service mesh, Prometheus / Grafana, a cloud cluster (AKS is the natural next
step), TLS, auth, databases, Helm.
