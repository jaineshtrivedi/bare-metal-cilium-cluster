# Bare-Metal Kubernetes Cluster with Cilium

This repository deploys a reproducible five-node Kubernetes cluster on Ubuntu 24.04 hosts reachable only through their routed public addresses. Kubespray manages the host and Kubernetes lifecycle; Cilium provides networking, policy enforcement, Hubble observability, kube-proxy replacement, and WireGuard encryption.

## Architecture

- Three control-plane nodes run stacked etcd and tolerate one control-plane failure.
- Two worker nodes provide application capacity.
- Kubespray `v2.31.0` provides idempotent host preparation, containerd, Kubernetes `1.35.4`, certificates, joins, upgrades, and node lifecycle.
- Kubespray runs a local nginx API proxy on each node, so kubelets and cluster components retain access when one API server fails.
- Cilium replaces kube-proxy and encrypts inter-node pod traffic with kernel WireGuard.
- The demo is exposed on TCP `30080` on every node through a Cilium-managed `NodePort` Service.

External request path:

```text
Internet client -> any healthy node public IP:30080
                -> Cilium eBPF service load balancing
                -> ready web pod on either worker
```

## Prerequisites

- Five clean Ubuntu 24.04 hosts with unique public addresses.
- Root SSH access, or an SSH user with passwordless sudo, and Python 3 on every host.
- Internet access from the workstation and nodes.
- Workstation tools: `bash`, `git`, `make`, Python 3.11 or newer (or `uv`), `ssh`, `curl`, and `kubectl`.
- An unlocked SSH key in `ssh-agent` when the key is passphrase-protected.
- Inter-node firewall access for the ports listed below.

Unlock a protected key once per shell session:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/jainesht
```

## Configure

```bash
cp inventory.sample.env inventory.env
$EDITOR inventory.env
```

Set the three control-plane and two worker public addresses. The local `inventory.env` is ignored by Git.

For the current five hosts:

```bash
CP_NODES=("65.109.78.121" "65.109.49.142" "65.108.7.94")
WORKER_NODES=("65.108.65.56" "65.109.28.75")
NODE_PORT="30080"
```

## Required Network Access

Allow these paths before deployment. Restrict cluster-management ports to the five node addresses and the administrator address rather than opening them globally.

| Protocol/port | Source | Destination | Purpose |
|---|---|---|---|
| TCP 22 | administrator | all nodes | SSH and Ansible |
| TCP 6443 | nodes and administrator | control planes | Kubernetes API |
| TCP 2379-2380 | control planes | control planes | etcd client and peer traffic |
| TCP 10250 | nodes and administrator | all nodes | kubelet API |
| UDP 8472 | all nodes | all nodes | Cilium VXLAN |
| UDP 51871 | all nodes | all nodes | Cilium WireGuard |
| TCP 4240 | all nodes | all nodes | Cilium health |
| TCP 30080 | external clients | all nodes | demo application |

If no host or provider firewall is enabled, deployment can proceed, but management ports will be reachable from the Internet. That is acceptable only for a short-lived isolated environment and should be corrected before treating the cluster as production infrastructure.

## Deploy

Run each stage independently:

```bash
make setup
make inventory
make preflight
make cluster
make cilium
make demo
make validate
make proof
```

Or run the complete deployment:

```bash
make deploy
make proof
```

The stages are:

1. `setup` clones the pinned Kubespray release and creates an isolated Python environment.
2. `inventory` generates Kubespray inventory and cluster variables from `inventory.env`.
3. `preflight` verifies SSH, Python, and privilege escalation on all five hosts without installing Kubernetes.
4. `cluster` runs Kubespray's idempotent `cluster.yml` playbook.
5. `cilium` verifies Cilium, Hubble, and WireGuard status.
6. `demo` applies the sample application and network policies.
7. `validate` checks node health, Cilium, all five public NodePort paths, and allowed/denied policy paths.
8. `proof` writes timestamped evidence under `proof/`.

Kubespray exports the administrator kubeconfig to `state/admin.conf`:

```bash
export KUBECONFIG="$PWD/state/admin.conf"
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n infra-demo get pods,svc -o wide
curl http://65.109.78.121:30080
```

## Idempotency and Recovery

Correct a transient SSH, package, or registry failure and rerun:

```bash
make cluster
```

Kubespray converges managed state instead of replaying one-shot bootstrap commands. To narrow a diagnostic retry:

```bash
./scripts/02_deploy_cluster.sh --limit cp2
```

Operational procedures for scaling, upgrades, failure tests, and diagnostics are in [docs/operations.md](docs/operations.md).

## Demo Policies

The `infra-demo` namespace contains a three-replica nginx Deployment and a fixed `NodePort` Service. Its policies are:

- `default-deny-ingress` denies ingress by default.
- `allow-web-from-approved-clients` allows labeled in-cluster clients on TCP/80.
- The same allow policy permits traffic originating outside the Pod CIDR, keeping the public NodePort reachable while unlabeled in-cluster clients remain denied.

## Assumptions and Limits

- Node public addresses are stable for the lifetime of the cluster.
- Pod and Service CIDRs do not overlap any routed network used by the nodes.
- Cilium VXLAN and WireGuard traffic can pass between all five hosts.
- The administrative kubeconfig points at the first control-plane address. If that host fails, change its `server` field to another healthy control-plane address.
- NodePort provides multiple externally reachable node addresses, not one floating public VIP. Health-aware DNS or a dedicated external load balancer would provide a single production endpoint.
- The demo is stateless; no persistent storage provider is installed.
