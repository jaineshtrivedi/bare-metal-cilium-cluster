#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "==> Cluster nodes"
kubectl_local get nodes -o wide

echo "==> Cilium status"
kubectl_local -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose

echo "==> Pods spread across nodes"
kubectl_local -n infra-demo get pods -o wide

echo "==> NodePort service"
kubectl_local -n infra-demo get svc web -o wide

echo "==> External reachability through every node on port ${NODE_PORT}"
for node in "${ALL_NODES[@]}"; do
  echo "Checking http://${node}:${NODE_PORT}"
  curl -fsS --max-time 10 "http://${node}:${NODE_PORT}" >/dev/null
done

echo "==> Network policy: allowed client should reach web"
kubectl_local -n infra-demo delete pod allowed-client --ignore-not-found
kubectl_local -n infra-demo run allowed-client --image=curlimages/curl:8.10.1 --restart=Never --labels=role=allowed --command -- sleep 3600
kubectl_local -n infra-demo wait pod/allowed-client --for=condition=Ready --timeout=90s
kubectl_local -n infra-demo exec allowed-client -- curl -fsS --max-time 5 http://web

echo "==> Network policy: blocked client should time out"
kubectl_local -n infra-demo delete pod blocked-client --ignore-not-found
kubectl_local -n infra-demo run blocked-client --image=curlimages/curl:8.10.1 --restart=Never --labels=role=blocked --command -- sleep 3600
kubectl_local -n infra-demo wait pod/blocked-client --for=condition=Ready --timeout=90s
for attempt in {1..15}; do
  if ! kubectl_local -n infra-demo exec blocked-client -- curl -fsS --max-time 2 http://web >/dev/null 2>&1; then
    echo "Blocked client denied as expected."
    break
  fi
  if [[ "$attempt" -eq 15 ]]; then
    echo "Blocked client unexpectedly reached the service after policy convergence."
    exit 1
  fi
  sleep 2
done

echo "Validation complete."
