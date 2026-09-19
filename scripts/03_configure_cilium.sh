#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

IFACE_PATTERN="${CILIUM_L2_INTERFACE_PATTERN:-${NODE_INTERFACE}}"

echo "==> Applying the Cilium LoadBalancer IP pool and L2 announcement policy"
sed \
  -e "s/__LB_POOL_START__/${LB_POOL_START}/g" \
  -e "s/__LB_POOL_STOP__/${LB_POOL_STOP}/g" \
  "$ROOT_DIR/manifests/cilium/lb-pool.yaml" | kubectl_local apply -f -

sed \
  -e "s/__NODE_INTERFACE__/${IFACE_PATTERN}/g" \
  "$ROOT_DIR/manifests/cilium/l2-announcement-policy.yaml" | kubectl_local apply -f -

kubectl_local -n kube-system rollout status ds/cilium --timeout=5m
kubectl_local -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl_local -n kube-system rollout status deployment/hubble-relay --timeout=5m

echo "Cilium LoadBalancer IPAM and L2 announcements are configured."
