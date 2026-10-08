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

🚧 Planning. No level has been built yet. See [PLAN.md](PLAN.md).

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
