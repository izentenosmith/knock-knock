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
