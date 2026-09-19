#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mkdir -p "$ROOT_DIR/proof"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
out="$ROOT_DIR/proof/proof-${ts}.txt"

{
  echo "# Proof capture ${ts}"
  echo
  echo "## Nodes"
  kubectl_cp1 "get nodes -o wide"
  echo
  echo "## Cilium pods"
  kubectl_cp1 "-n kube-system get pods -l k8s-app=cilium -o wide"
  echo
  echo "## Cilium status"
  kubectl_cp1 "-n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose" || true
  echo
  echo "## Demo pods"
  kubectl_cp1 "-n infra-demo get pods -o wide"
  echo
  echo "## Demo service"
  kubectl_cp1 "-n infra-demo get svc web -o wide"
  echo
  echo "## Network policies"
  kubectl_cp1 "-n infra-demo get networkpolicy -o yaml"
  echo
  echo "## Validation run"
  "$ROOT_DIR/scripts/05_validate.sh"
} | tee "$out"

echo "Proof written to $out"

