#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "==> Deploying demo app and network policies"
kubectl_local apply -f "$ROOT_DIR/manifests/demo/app.yaml"
kubectl_local apply -f "$ROOT_DIR/manifests/demo/network-policies.yaml"
kubectl_local -n infra-demo rollout status deployment/web --timeout=3m

echo "Demo deployed."
