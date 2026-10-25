#!/usr/bin/env bash
# Deletes the k3d cluster the level-02 tests created, and nothing else. run.sh calls it last
# (KEEP_CLUSTER=1 keeps the cluster up for a look).
. "$(dirname "$0")/lib.sh"
. "$HERE/lib-cluster.sh"

if owned; then k3d cluster delete "$CLUSTER" >/dev/null 2>&1 && echo "deleted the test cluster $CLUSTER"; fi
rm -f "$OWNED" "$KUBECFG"
