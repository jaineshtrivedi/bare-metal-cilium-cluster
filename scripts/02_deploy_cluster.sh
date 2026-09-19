#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

KUBESPRAY_DIR="$ROOT_DIR/state/kubespray"
KUBESPRAY_INVENTORY="$ROOT_DIR/state/inventory"
ANSIBLE_PLAYBOOK="$ROOT_DIR/state/venv/bin/ansible-playbook"

if [[ ! -x "$ANSIBLE_PLAYBOOK" || ! -f "$KUBESPRAY_INVENTORY/inventory.ini" ]]; then
  echo "Kubespray environment or inventory is missing. Run make setup inventory first."
  exit 1
fi

(
  cd "$KUBESPRAY_DIR"
  "$ANSIBLE_PLAYBOOK" \
    -i "$KUBESPRAY_INVENTORY/inventory.ini" \
    cluster.yml \
    --become "$@"
)

generated_config="$KUBESPRAY_INVENTORY/artifacts/admin.conf"
if [[ ! -f "$generated_config" ]]; then
  echo "Kubespray completed but did not export $generated_config."
  exit 1
fi

install -m 0600 "$generated_config" "$ROOT_DIR/state/admin.conf"
echo "Cluster converged successfully. Kubeconfig: state/admin.conf"
