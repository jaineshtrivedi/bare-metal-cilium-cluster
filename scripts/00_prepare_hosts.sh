#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

for node in "${ALL_NODES[@]}"; do
  echo "==> Preparing ${node}"
  ssh_node "$node" "KUBERNETES_MINOR='${KUBERNETES_MINOR}' bash -s" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg containerd jq socat conntrack ipset ethtool

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/ /
EOF

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
  ufw allow 22/tcp
  ufw allow 6443/tcp
  ufw allow 2379:2380/tcp
  ufw allow 10250/tcp
  ufw allow 10257/tcp
  ufw allow 10259/tcp
  ufw allow 8472/udp
  ufw allow 4240/tcp
fi
REMOTE
done

echo "All nodes prepared."

