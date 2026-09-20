#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

KUBESPRAY_DIR="$ROOT_DIR/state/kubespray"
KUBESPRAY_INVENTORY="$ROOT_DIR/state/inventory"

if [[ ! -d "$KUBESPRAY_DIR/inventory/sample" ]]; then
  echo "Kubespray is not initialized. Run make setup first."
  exit 1
fi

if [[ "${#CP_NODES[@]}" -ne 3 || "${#WORKER_NODES[@]}" -lt 2 ]]; then
  echo "Expected exactly 3 control-plane nodes and at least 2 workers."
  exit 1
fi

rm -rf "$KUBESPRAY_INVENTORY"
cp -R "$KUBESPRAY_DIR/inventory/sample" "$KUBESPRAY_INVENTORY"

cat >"$KUBESPRAY_INVENTORY/inventory.ini" <<EOF
[kube_control_plane]
EOF

for index in "${!CP_NODES[@]}"; do
  number=$((index + 1))
  address="${CP_NODES[$index]}"
  printf 'cp%s ansible_host=%s ip=%s access_ip=%s etcd_member_name=etcd%s\n' \
    "$number" "$address" "$address" "$address" "$number" \
    >>"$KUBESPRAY_INVENTORY/inventory.ini"
done

cat >>"$KUBESPRAY_INVENTORY/inventory.ini" <<EOF

[etcd:children]
kube_control_plane

[kube_node]
EOF

for index in "${!WORKER_NODES[@]}"; do
  number=$((index + 1))
  address="${WORKER_NODES[$index]}"
  printf 'worker%s ansible_host=%s ip=%s access_ip=%s\n' \
    "$number" "$address" "$address" "$address" \
    >>"$KUBESPRAY_INVENTORY/inventory.ini"
done

cat >>"$KUBESPRAY_INVENTORY/inventory.ini" <<EOF

[k8s_cluster:children]
kube_control_plane
kube_node

[all:vars]
ansible_user=${SSH_USER}
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='${ANSIBLE_SSH_COMMON_ARGS}'
EOF

if [[ -n "${SSH_PRIVATE_KEY_FILE:-}" ]]; then
  printf 'ansible_ssh_private_key_file=%s\n' "$SSH_PRIVATE_KEY_FILE" \
    >>"$KUBESPRAY_INVENTORY/inventory.ini"
fi

cat >"$KUBESPRAY_INVENTORY/group_vars/k8s_cluster/zz-cluster.yml" <<EOF
---
kube_version: "${KUBERNETES_VERSION}"
kube_network_plugin: cilium
kube_proxy_remove: true
kube_proxy_mode: ipvs
kube_pods_subnet: "${POD_CIDR}"
kube_service_addresses: "${SERVICE_CIDR}"
cluster_name: "${CLUSTER_NAME}"
dns_domain: "${CLUSTER_DNS_DOMAIN}"
kube_override_hostname: "{{ inventory_hostname }}"
container_manager: containerd
kubeconfig_localhost: true
kubeconfig_localhost_ansible_host: true
kubectl_localhost: true
loadbalancer_apiserver_localhost: true
loadbalancer_apiserver_type: nginx
EOF

cat >"$KUBESPRAY_INVENTORY/group_vars/k8s_cluster/zz-cilium.yml" <<'EOF'
---
cilium_kube_proxy_replacement: true
cilium_ipam_mode: kubernetes
cilium_l2announcements: false
cilium_encryption_enabled: true
cilium_encryption_type: wireguard
cilium_enable_hubble: true
cilium_enable_hubble_ui: true
cilium_hubble_install: true
cilium_hubble_tls_generate: true
EOF

echo "Generated Kubespray inventory at state/inventory."
"$ROOT_DIR/state/venv/bin/ansible-inventory" \
  -i "$KUBESPRAY_INVENTORY/inventory.ini" --graph
