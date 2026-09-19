#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "==> Cluster nodes"
kubectl_cp1 "get nodes -o wide"

echo "==> Cilium status"
kubectl_cp1 "-n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose" || true

echo "==> Pods spread across nodes"
kubectl_cp1 "-n infra-demo get pods -o wide"

echo "==> Service external address"
kubectl_cp1 "-n infra-demo get svc web -o wide"
LB_IP="$(kubectl_cp1 "-n infra-demo get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" | tr -d "'")"
if [[ -z "$LB_IP" ]]; then
  echo "LoadBalancer IP is not assigned yet."
  exit 1
fi

echo "==> External reachability from ${CP1}: http://${LB_IP}"
ssh_node "$CP1" "curl -fsS --max-time 5 http://${LB_IP}"

echo "==> Network policy: allowed client should reach web"
kubectl_cp1 "-n infra-demo run allowed-client --image=curlimages/curl:8.10.1 --restart=Never --labels=role=allowed --command -- sleep 3600" || true
kubectl_cp1 "-n infra-demo wait pod/allowed-client --for=condition=Ready --timeout=90s"
kubectl_cp1 "-n infra-demo exec allowed-client -- curl -fsS --max-time 5 http://web"

echo "==> Network policy: blocked client should time out"
kubectl_cp1 "-n infra-demo run blocked-client --image=curlimages/curl:8.10.1 --restart=Never --labels=role=blocked --command -- sleep 3600" || true
kubectl_cp1 "-n infra-demo wait pod/blocked-client --for=condition=Ready --timeout=90s"
if kubectl_cp1 "-n infra-demo exec blocked-client -- curl -fsS --max-time 5 http://web"; then
  echo "Blocked client unexpectedly reached the service."
  exit 1
else
  echo "Blocked client denied as expected."
fi

echo "Validation complete."

