# Bare-Metal Kubernetes Cluster with Cilium

This repository builds a five-node Kubernetes cluster on Ubuntu 24.04 bare-metal hosts using kubeadm and Cilium. It is designed for an interview assignment: the setup is reproducible, avoids managed Kubernetes and cloud load balancers, and includes validation/proof commands.

## Architecture

- 5 hosts on one L2 network.
- 3 control-plane nodes for API and etcd quorum.
- 2 worker nodes for application capacity.
- kube-vip provides a highly available Kubernetes API virtual IP.
- Cilium is the CNI, runs kube-proxy replacement, enforces NetworkPolicy, and advertises Service `LoadBalancer` IPs on the LAN through L2 announcements.
- Demo app is exposed with a Kubernetes `LoadBalancer` Service backed by Cilium LB IPAM, not a cloud load balancer.

Traffic flow for the demo app:

1. A client connects to the assigned `LoadBalancer` IP from the LAN.
2. Cilium elects a node to answer ARP for that IP.
3. The elected node receives the packet and Cilium service load balancing forwards it to a ready backend pod.
4. Cilium forwards the request to a ready backend pod on any node.

## Prerequisites

- Root SSH access to all five Ubuntu 24.04 hosts.
- The five hosts are on the same L2 network.
- One unused IP for the control-plane VIP.
- A small unused IP range for Service `LoadBalancer` addresses.
- Internet access from the nodes to fetch Ubuntu packages and container images.
- From your workstation: `bash`, `ssh`, `scp`, and `make`.

## Quick Start

Copy and edit the inventory:

```bash
cp inventory.sample.env inventory.env
$EDITOR inventory.env
```

Then run the build:

```bash
make prepare
make init
make join
make cilium
make demo
make validate
make proof
```

The scripts write temporary cluster join material and the kubeconfig to `state/`. Command evidence is written under `proof/`.

## Step-by-Step Details

### 1. Prepare Hosts

```bash
make prepare
```

This runs on every host:

- disables swap
- loads required kernel modules
- enables bridge netfilter and IPv4 forwarding
- installs containerd
- configures containerd with systemd cgroups
- installs kubeadm, kubelet, and kubectl from the configured Kubernetes minor train

### 2. Initialize the First Control Plane

```bash
make init
```

This creates the kube-vip static pod manifest, runs `kubeadm init`, skips kube-proxy, and stores:

- `state/admin.conf`
- `state/join-worker.sh`
- `state/certificate-key`

### 3. Join the Remaining Nodes

```bash
make join
```

This joins the remaining two control-plane nodes with the uploaded cert key, then joins the two worker nodes.

### 4. Install Cilium

```bash
make cilium
```

Cilium is installed with Helm using:

- kube-proxy replacement
- Kubernetes IPAM
- Hubble relay and UI
- L2 announcements
- Cilium LoadBalancer IPAM

The LoadBalancer pool and L2 policy are applied from `manifests/cilium/`.

### 5. Deploy Demo App and Policies

```bash
make demo
```

This deploys:

- namespace `infra-demo`
- 3-replica nginx Deployment
- `LoadBalancer` Service labeled for Cilium L2 exposure
- two NetworkPolicies:
  - `default-deny-ingress`
  - `allow-web-from-approved-clients`

### 6. Validate

```bash
make validate
```

Validation checks:

- all nodes are `Ready`
- Cilium daemonset and operator are healthy
- app pods are scheduled across nodes
- app Service has an external IP
- the app is reachable through the external IP
- an allowed client pod can reach the app
- a blocked client pod cannot reach the app

### 7. Capture Proof

```bash
make proof
```

This writes a timestamped text file under `proof/` containing node status, Cilium status, demo app status, service details, policies, and the validation output.

## Common Commands

Use the kubeconfig produced by the bootstrap:

```bash
export KUBECONFIG="$PWD/state/admin.conf"
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n infra-demo get svc web -o wide
```

Run Cilium connectivity tests after the cluster is stable:

```bash
cilium connectivity test
```

If the Cilium CLI is not installed locally, inspect from a Cilium pod:

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list
```

## Assumptions

- Nodes share a flat L2 network, so ARP/NDP-based VIP and Service announcement are appropriate.
- The selected control-plane VIP and LoadBalancer pool are outside DHCP allocation and not used elsewhere.
- Node disks and hardware are already provisioned by the interview environment.
- No external persistent storage class is configured because the demo app is stateless.

## Repository Layout

```text
.
├── DESIGN.md
├── README.md
├── docs/
│   ├── operations.md
│   └── proof-template.md
├── inventory.sample.env
├── manifests/
│   ├── cilium/
│   ├── demo/
│   └── ops/
└── scripts/
```
