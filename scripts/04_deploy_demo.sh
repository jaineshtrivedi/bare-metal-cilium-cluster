#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "==> Deploying demo app and network policies"
sed "s/__NODE_PORT__/${NODE_PORT}/g" \
  "$ROOT_DIR/manifests/demo/app.yaml" | kubectl_local apply -f -
sed "s#__POD_CIDR__#${POD_CIDR}#g" \
  "$ROOT_DIR/manifests/demo/network-policies.yaml" | kubectl_local apply -f -
kubectl_local -n infra-demo rollout status deployment/web --timeout=3m

echo "Demo deployed."
