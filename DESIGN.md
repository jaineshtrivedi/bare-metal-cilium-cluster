# Design Note

## Goal and Constraints

The cluster spans five Ubuntu 24.04 hosts that are accessible through routed public `/32` addresses. There is no provider-managed private network, shared broadcast domain, floating address, or cloud load balancer available. The design therefore avoids features that require Layer-2 adjacency and uses only capabilities deployable through root SSH.

Three hosts run the control plane and stacked etcd, preserving quorum through one control-plane failure. Two workers provide application capacity and demonstrate scheduling and node-loss behavior.

## Lifecycle Tooling

Kubespray is the lifecycle layer. Its idempotent Ansible roles prepare hosts, configure containerd, initialize Kubernetes, join nodes, install Cilium, renew certificates, scale membership, and perform ordered upgrades. Kubespray is pinned to `v2.31.0`, and Kubernetes is pinned to `1.35.4`, making version changes deliberate and reviewable.

## API Availability

Without a portable floating address, the design uses Kubespray's local nginx API proxy. Every worker talks to a local proxy that balances across the three API servers, so one failed control plane does not disconnect kubelets or Cilium agents. Control-plane components use their local API endpoint.

The exported administrator kubeconfig targets the first control-plane public address. This is operationally simple but not a floating administrative endpoint. During failure, an administrator can change the kubeconfig server to either remaining control-plane address.

## Networking and Encryption

Cilium is the primary CNI and replaces kube-proxy. Pod networking uses VXLAN, which works across routed node addresses without underlay route changes. Cilium's kernel WireGuard mode encrypts inter-node pod traffic before it crosses the public network. Hubble supplies flow visibility.

Control-plane, etcd, and kubelet connections are already authenticated and encrypted by Kubernetes TLS. Host or provider firewalls should restrict those ports to the five node addresses and administrator addresses.

## External Exposure

The application is exposed through a fixed NodePort, TCP `30080`, available on every healthy node address:

```text
client -> node public IP:30080 -> Cilium eBPF service load balancer -> ready pod
```

`externalTrafficPolicy: Cluster` allows any node to forward to a ready pod on either worker. This offers several usable external endpoints without a cloud load balancer. It does not provide one automatically failing-over IP; clients can use another node address after failure, or DNS can publish several A records.

## Network Policy

The namespace starts with default-deny ingress. A Kubernetes NetworkPolicy allows labeled in-cluster clients to reach web pods on TCP/80. A separate CiliumNetworkPolicy allows the `world` identity so public NodePort traffic remains usable without admitting unlabeled cluster pods. The validation uses both an allowed and blocked pod.

## Operations and Failure Behavior

Inventory changes plus Kubespray's `scale.yml` add nodes. `remove-node.yml` removes them, and `upgrade-cluster.yml` performs ordered upgrades. Re-running `cluster.yml` reconciles managed drift.

After a worker failure, Deployment replicas are recreated where capacity permits. After one control-plane failure, etcd retains quorum and node-local API proxies remove the failed backend. NodePort remains available through the other node addresses.

## Tradeoffs and Limitations

- Public-address clustering increases firewall importance and consumes public network bandwidth.
- WireGuard protects pod traffic but does not hide node addresses or replace firewall policy.
- The administrator kubeconfig has no automatic endpoint failover.
- NodePort is less convenient than a single load-balancer address and exposes a high port.
- Two workers provide limited spare capacity during failure.
- No persistent storage, ingress controller, external DNS, identity provider, or secrets manager is included.
- Kubespray state is configuration, not a substitute for etcd and application-data backups.
