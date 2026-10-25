# knock-knock

> *Knock knock.* — *Who's there?* — *A Rust pod on worker-2, it took me 41 µs.*

A hands-on Kubernetes and CI/CD training project.

A minimal React frontend knocks on a single API. Behind it, four identical
backends answer: **Go**, **Python**, **Rust** and **TypeScript**. The
frontend never knows who will pick up. Every answer is signed with the
language, pod, node, version, and how long the backend took, so the UI shows
how your traffic is actually being distributed.

The apps are trivial on purpose. You learn Kubernetes and the pipeline by
watching them behave.

## Status

✅ **Level 1 done:** every PR is built and smoke-tested by GitHub Actions, and
each release to `main` publishes multi-arch images to GHCR. Level 0 (the four
backends, the React UI and Docker Compose) is underneath. Levels 2 and up are
still to come. See [PLAN.md](PLAN.md).

## Quickstart

```bash
docker compose up --build
```

Open [localhost:8080](http://localhost:8080), then knock: on Compose the
answers rotate through all four languages in a fixed order (whatever order
Docker's DNS listed them in when nginx started), perfectly. In another terminal:

```bash
scripts/smoke.sh
```

It fires 40 knocks (`scripts/smoke.sh 100` for more), checks the contract and
prints the tally. Needs `curl` and `jq`. `URL=…` knocks somewhere else, and
`EXPECT_VERSION=…` also requires that `version` in every answer. CI builds with
`VERSION=sha-<7>` and checks it; locally the images say `dev` unless built
with a version:

```bash
VERSION=sha-3f9c2a1 docker compose up --build --wait -d
```

```bash
EXPECT_VERSION=sha-3f9c2a1 scripts/smoke.sh
```

Same app, very different images (arm64, `docker images`):

| Image | Runtime base | Disk | Compressed |
|---|---|---|---|
| rust | `distroless/static` | 7.8 MB | 1.3 MB |
| go | `scratch` | 9.3 MB | 2.8 MB |
| frontend | `nginx:alpine` | 93 MB | 26 MB |
| python | `python:3.13-slim` | 202 MB | 43 MB |
| ts | `node:24-alpine` | 237 MB | 62 MB |

## How it works

```
browser ──▶ frontend (React + nginx) ──▶ /api/knock ──▶ knock-api ──┬──▶ go
                                                                     ├──▶ python
                                                                     ├──▶ rust
                                                                     └──▶ ts
```

Every backend returns the same signature:

```json
{ "lang": "rust", "version": "sha-3f9c2a1", "pod": "knock-rust-7f9c4d-x2k8p",
  "node": "k3d-knock-agent-1", "served": 41, "took_us": 41, "...": "..." }
```

The full contract is in [PLAN.md § 1](PLAN.md#1-the-app-contract).

## Levels

Each level teaches one concept and ends with a git tag you can check out and
replay.

| Tag | Concept |
|---|---|
| `level-00-app` | the four backends + React UI on Docker Compose |
| `level-01-pipeline` | GitHub Actions: build, smoke test, push to GHCR |
| `level-02-cluster` | k3d, Deployments, one Service over four Deployments, Ingress |
| `level-03-load-balancing` | L4 vs L7, connection reuse |
| `level-04-probes` | readiness / liveness |
| `level-05-rolling-update` | rolling updates |
| `level-06-scaling` | replicas as weights, HPA |
| `level-07-resources` | requests / limits, OOMKilled |
| `level-08-nodes` | multi-node, topology spread, drain |
| `level-09-config` | ConfigMaps, injected latency |
| `level-10-kustomize` | base + overlays |
| `level-11-canary` | Gateway API weighted routing |
| `level-12-network-policy` | NetworkPolicy |
| `level-13-gitops` | Argo CD, push-to-deploy |

```bash
git checkout level-03-load-balancing
```

## Pipeline

```
feature ──PR──▶ dev ──PR (merge commit)──▶ main ──▶ ghcr.io/…:sha-<7> ──tag──▶ :level-NN-…
          smoke        smoke, release-ready (dry run),  publish                  promote
                       only-dev-to-main
```

1. Work on a branch and open a PR into `dev`. CI runs the smoke test.
2. Open a PR from `dev` into `main`. A dry run (`dry-run.yml`) builds all five
   images for both platforms and starts and checks each backend, but pushes
   nothing. `release-ready` (required) is green only if this PR's own dry run
   passed; nothing else can produce that check. Merge it with a **merge commit**.
3. CI on `main` publishes `ghcr.io/izentenosmith/knock-knock-<svc>:sha-<7>` for
   all five images, for `linux/amd64` and `linux/arm64`. Each image is built
   once into a registry on the runner; each backend is started from there and
   checked for its `version`, and only then is that exact image (same digest)
   copied to GHCR.
4. The packages come out **public**: published by this public repo's workflow,
   they take the repo's visibility, so anyone (and k3d) can pull without logging
   in. If one ever shows up private, switch it once on GitHub: the package →
   *Package settings* → *Change visibility* → **Public**.
5. Tag `main`'s merge commit, by name, not whatever you have checked out, and
   push only that tag. Level tags can never be moved or deleted, so wait for
   step 3's run to be green first, and check the commit:

   ```bash
   git fetch origin && git log -1 --oneline origin/main
   ```

   ```bash
   git tag -a level-NN-<slug> origin/main -m "…" && git push origin level-NN-<slug>
   ```

   CI gives the same images that tag (same digest, no rebuild). If `main` is
   still publishing that commit, the promotion waits for it. A tag on anything
   but one of `main`'s own merge commits, or that doesn't look like
   `level-NN-<slug>`, fails without touching any image. (A tag run uses the
   workflows of the tagged commit, so these checks hold for commits released
   with this pipeline; always tag `origin/main`'s newest merge commit.)

The pipeline never overwrites a published tag: re-running a run skips what is
already published, and promotion refuses to move a level tag. (Anyone with
write access to the packages could still change them by hand on GitHub.)

Any published backend runs on its own:

```bash
docker run --rm -p 8081:8080 ghcr.io/izentenosmith/knock-knock-rust:level-01-pipeline
```

```bash
curl localhost:8081/api/knock
```

## Requirements

Docker, `curl` and `jq` (level 0 and 1); [k3d](https://k3d.io) and `kubectl`
from level 2. Go, Python, Rust and Node are only needed to run a backend outside
a container.

## License

[MIT](LICENSE)
