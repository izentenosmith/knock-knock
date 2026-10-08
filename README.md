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

✅ **Level 0 done:** the four backends, the React UI and Docker Compose.
Levels 1 and up are still to come. See [PLAN.md](PLAN.md).

## Quickstart

```bash
docker compose up --build
```

Open [localhost:8080](http://localhost:8080), then knock: on Compose the
answers rotate go → python → rust → ts, perfectly. In another terminal:

```bash
scripts/smoke.sh
```

It fires 40 knocks (`scripts/smoke.sh 100` for more), checks the contract and
prints the tally. Needs `curl` and `jq`.

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

## Requirements

Docker, [k3d](https://k3d.io), `kubectl`. Go, Python, Rust and Node are only
needed to run a backend outside a container.

## License

[MIT](LICENSE)
