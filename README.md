# Bare-Metal Kubernetes Cluster with Cilium

This repository deploys a reproducible five-node Kubernetes cluster on Ubuntu 24.04 bare-metal hosts. Kubespray manages the host and Kubernetes lifecycle; Cilium provides networking, policy enforcement, observability, kube-proxy replacement, and LAN-facing `LoadBalancer` Services.

## Architecture

- Three control-plane nodes run a stacked etcd cluster and tolerate one control-plane failure.
- Two worker nodes provide application capacity.
- Kubespray `v2.31.0` supplies idempotent Ansible roles for host preparation, containerd, Kubernetes `1.35.4`, certificates, joins, upgrades, and node lifecycle.
- kube-vip advertises one highly available Kubernetes API virtual IP with ARP.
- Cilium replaces kube-proxy, supplies Kubernetes IPAM, enforces policies, and runs Hubble.
- Cilium LoadBalancer IPAM allocates LAN addresses; L2 announcements advertise selected Services without a cloud load balancer.

External request path:

```text
LAN client -> Service LoadBalancer IP -> elected Cilium announcer
           -> Cilium eBPF service load balancing -> ready pod on any node
```

## Prerequisites

- Five clean Ubuntu 24.04 hosts on the same L2 network.
- Root SSH access, or an SSH user with passwordless sudo, and Python 3 on every host.
- One unused LAN address for the Kubernetes API VIP.
- An unused LAN range for Service `LoadBalancer` addresses.
- Internet access from the workstation and nodes.
- Workstation tools: `bash`, `git`, `make`, Python 3.11 or newer (or `uv`), `ssh`, `curl`, and `kubectl`.

## Configure

```bash
cp inventory.sample.env inventory.env
$EDITOR inventory.env
```

Set the five node addresses, API VIP, LAN interface, and LoadBalancer range. The interface used by kube-vip must exist on every control-plane node. Keep all selected VIPs outside DHCP allocation.

## Deploy

Run each stage independently for clearer failure recovery:

```bash
make setup
make inventory
make cluster
make cilium
make demo
make validate
make proof
```

Or run the complete deployment:

```bash
make deploy
```

The stages are:

1. `setup` clones the pinned Kubespray release into ignored local state and creates its Python virtual environment.
2. `inventory` generates Kubespray inventory and cluster variables from `inventory.env`.
3. `cluster` runs Kubespray's `cluster.yml`, including host preparation, containerd, kube-vip, Kubernetes, Cilium, and Hubble.
4. `cilium` applies the environment-specific LoadBalancer address pool and L2 announcement policy.
5. `demo` applies the sample application and two network policies.
6. `validate` checks node/Cilium health, external reachability, and allowed/denied policy paths.
7. `proof` captures timestamped evidence under `proof/`.

Kubespray exports the admin kubeconfig to `state/admin.conf`:

```bash
export KUBECONFIG="$PWD/state/admin.conf"
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n infra-demo get svc web -o wide
```

## Idempotency and Recovery

If a run stops because of a transient package, registry, or SSH failure, correct the cause and rerun:

```bash
make cluster
```

Kubespray converges managed state instead of replaying hand-written bootstrap mutations. Use Ansible options when narrowing a retry:

```bash
./scripts/02_deploy_cluster.sh --limit cp2
```

Regenerate inventory after changing node membership or cluster variables:

```bash
make inventory
make cluster
```

Operational procedures for scaling, upgrades, failure tests, and diagnostics are in [docs/operations.md](docs/operations.md).

## Demo and Policies

The `infra-demo` namespace contains a three-replica nginx Deployment and a Cilium-backed `LoadBalancer` Service. Its policies are:

- `default-deny-ingress`: denies ingress to every pod in the namespace.
- `allow-web-from-approved-clients`: allows pods labeled `role=allowed` to reach TCP/80 on the web pods.

The validation script recreates one allowed client and one blocked client on every run. It requires the allowed request to succeed and the blocked request to fail.

## Assumptions

- Nodes and clients share the relevant L2 network, making ARP-based API and Service advertisement appropriate.
- The same LAN interface name is available on all control-plane nodes. Cilium can use a separate interface regular expression.
- Pod and Service CIDRs do not overlap the LAN, VPN, or other routed networks.
- Host disks and firmware are already provisioned.
- The demo is stateless; no persistent storage provider is installed.

## Repository Layout

```text
.
├── DESIGN.md
├── Makefile
├── docs/
│   ├── operations.md
│   └── proof-template.md
├── inventory.sample.env
├── manifests/
│   ├── cilium/
│   ├── demo/
│   └── ops/
└── scripts/
    ├── 00_setup_kubespray.sh
    ├── 01_generate_inventory.sh
    ├── 02_deploy_cluster.sh
    ├── 03_configure_cilium.sh
    ├── 04_deploy_demo.sh
    ├── 05_validate.sh
    └── 06_capture_proof.sh
```
