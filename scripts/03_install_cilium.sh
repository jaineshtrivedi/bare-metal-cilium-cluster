#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

IFACE="$(node_interface_for "$CP1")"

echo "==> Installing Cilium ${CILIUM_VERSION}"
ssh_node "$CP1" "CONTROL_PLANE_VIP='${CONTROL_PLANE_VIP}' CILIUM_VERSION='${CILIUM_VERSION}' bash -s" <<'REMOTE'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add cilium https://helm.cilium.io/ >/dev/null
helm repo update >/dev/null
helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${CONTROL_PLANE_VIP}" \
  --set k8sServicePort=6443 \
  --set operator.replicas=2 \
  --set ipam.mode=kubernetes \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --wait
REMOTE

sed \
  -e "s/__LB_POOL_START__/${LB_POOL_START}/g" \
  -e "s/__LB_POOL_STOP__/${LB_POOL_STOP}/g" \
  "$ROOT_DIR/manifests/cilium/lb-pool.yaml" | ssh_node "$CP1" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -"

sed \
  -e "s/__NODE_INTERFACE__/${IFACE}/g" \
  "$ROOT_DIR/manifests/cilium/l2-announcement-policy.yaml" | ssh_node "$CP1" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -"

kubectl_cp1 "-n kube-system rollout status ds/cilium --timeout=5m"
kubectl_cp1 "-n kube-system rollout status deployment/cilium-operator --timeout=5m"
kubectl_cp1 "-n kube-system rollout status deployment/hubble-relay --timeout=5m"

echo "Cilium installed and bare-metal LoadBalancer IPAM configured."

