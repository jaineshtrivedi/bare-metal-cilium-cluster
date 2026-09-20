#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "==> Verifying Cilium and Hubble rollouts"
kubectl_local -n kube-system rollout status ds/cilium --timeout=5m
kubectl_local -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl_local -n kube-system rollout status deployment/hubble-relay --timeout=5m

echo "==> Verifying Cilium agent health and WireGuard encryption"
kubectl_local -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl_local -n kube-system exec ds/cilium -c cilium-agent -- cilium encrypt status

echo "Cilium is healthy and encryption status is available."
