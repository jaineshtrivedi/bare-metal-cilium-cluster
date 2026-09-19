#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

JOIN_WORKER="$(cat "$ROOT_DIR/state/join-worker.sh")"
CERT_KEY="$(cat "$ROOT_DIR/state/certificate-key")"

for node in "${CP_NODES[@]:1}"; do
  IFACE="$(node_interface_for "$node")"
  echo "==> Joining control-plane node ${node}"
  ssh_node "$node" "CONTROL_PLANE_VIP='${CONTROL_PLANE_VIP}' IFACE='${IFACE}' KUBE_VIP_VERSION='${KUBE_VIP_VERSION}' JOIN_WORKER='${JOIN_WORKER}' CERT_KEY='${CERT_KEY}' bash -s" <<'REMOTE'
set -euo pipefail
mkdir -p /etc/kubernetes/manifests
ctr image pull "ghcr.io/kube-vip/kube-vip:${KUBE_VIP_VERSION}"
ctr run --rm --net-host "ghcr.io/kube-vip/kube-vip:${KUBE_VIP_VERSION}" vip /kube-vip manifest pod \
  --interface "${IFACE}" \
  --address "${CONTROL_PLANE_VIP}" \
  --controlplane \
  --arp \
  --leaderElection >/etc/kubernetes/manifests/kube-vip.yaml
${JOIN_WORKER} --control-plane --certificate-key "${CERT_KEY}"
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chmod 0600 /root/.kube/config
REMOTE
done

for node in "${WORKER_NODES[@]}"; do
  echo "==> Joining worker node ${node}"
  ssh_node "$node" "${JOIN_WORKER}"
done

echo "All remaining nodes joined."

