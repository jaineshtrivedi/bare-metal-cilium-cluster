#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "==> Deploying demo app and network policies"
ssh_node "$CP1" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -" <"$ROOT_DIR/manifests/demo/app.yaml"
ssh_node "$CP1" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -" <"$ROOT_DIR/manifests/demo/network-policies.yaml"
kubectl_cp1 "-n infra-demo rollout status deployment/web --timeout=3m"

echo "Demo deployed."

