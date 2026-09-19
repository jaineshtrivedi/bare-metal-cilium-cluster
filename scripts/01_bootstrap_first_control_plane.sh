#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mkdir -p "$ROOT_DIR/state"
IFACE="$(node_interface_for "$CP1")"

echo "==> Bootstrapping first control-plane node ${CP1} using VIP ${CONTROL_PLANE_VIP} on ${IFACE}"
ssh_node "$CP1" "CONTROL_PLANE_VIP='${CONTROL_PLANE_VIP}' IFACE='${IFACE}' POD_CIDR='${POD_CIDR}' SERVICE_CIDR='${SERVICE_CIDR}' CLUSTER_DNS_DOMAIN='${CLUSTER_DNS_DOMAIN}' KUBE_VIP_VERSION='${KUBE_VIP_VERSION}' bash -s" <<'REMOTE'
set -euo pipefail

mkdir -p /etc/kubernetes/manifests
ctr image pull "ghcr.io/kube-vip/kube-vip:${KUBE_VIP_VERSION}"
ctr run --rm --net-host "ghcr.io/kube-vip/kube-vip:${KUBE_VIP_VERSION}" vip /kube-vip manifest pod \
  --interface "${IFACE}" \
  --address "${CONTROL_PLANE_VIP}" \
  --controlplane \
  --arp \
  --leaderElection >/etc/kubernetes/manifests/kube-vip.yaml

cat >/root/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: stable
controlPlaneEndpoint: "${CONTROL_PLANE_VIP}:6443"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
  dnsDomain: "${CLUSTER_DNS_DOMAIN}"
apiServer:
  certSANs:
    - "${CONTROL_PLANE_VIP}"
EOF

kubeadm init --config /root/kubeadm-config.yaml --upload-certs --skip-phases=addon/kube-proxy

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chmod 0600 /root/.kube/config
REMOTE

scp ${SSH_OPTS:-} "${SSH_USER}@${CP1}:/etc/kubernetes/admin.conf" "$ROOT_DIR/state/admin.conf"
sed -i.bak "s#server: https://.*:6443#server: https://${CONTROL_PLANE_VIP}:6443#" "$ROOT_DIR/state/admin.conf"
rm -f "$ROOT_DIR/state/admin.conf.bak"

ssh_node "$CP1" "kubeadm token create --print-join-command" >"$ROOT_DIR/state/join-worker.sh"
ssh_node "$CP1" "kubeadm init phase upload-certs --upload-certs | tail -n 1" >"$ROOT_DIR/state/certificate-key"
chmod 0600 "$ROOT_DIR/state/"*

echo "First control-plane node is initialized."
echo "Join material written under state/."
