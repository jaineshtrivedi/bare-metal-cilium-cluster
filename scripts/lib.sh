#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$ROOT_DIR/inventory.env}"

if [[ ! -f "$INVENTORY" ]]; then
  echo "Missing inventory: $INVENTORY"
  echo "Copy inventory.sample.env to inventory.env and set host IPs first."
  exit 1
fi

# shellcheck source=/dev/null
source "$INVENTORY"

CP1="${CP_NODES[0]}"
ALL_NODES=("${CP_NODES[@]}" "${WORKER_NODES[@]}")

ssh_node() {
  local node="$1"
  shift
  ssh ${SSH_OPTS:-} "${SSH_USER}@${node}" "$@"
}

scp_to_node() {
  local src="$1"
  local node="$2"
  local dst="$3"
  scp ${SSH_OPTS:-} "$src" "${SSH_USER}@${node}:$dst"
}

kubectl_cp1() {
  ssh_node "$CP1" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl $*"
}

run_on_all_nodes() {
  local cmd="$1"
  for node in "${ALL_NODES[@]}"; do
    echo "==> ${node}"
    ssh_node "$node" "$cmd"
  done
}

node_interface_for() {
  local node="$1"
  if [[ "${NODE_INTERFACE}" != "auto" ]]; then
    printf "%s" "$NODE_INTERFACE"
  else
    ssh_node "$node" "ip route show default | awk '{print \$5; exit}'"
  fi
}

