# Design Note

## Goal and Cluster Shape

The system is a production-minded Kubernetes cluster across five dedicated Ubuntu 24.04 hosts. Three hosts run both the control plane and stacked etcd, preserving quorum through one control-plane failure. Two workers provide application capacity and allow scheduling and node-loss behavior to be demonstrated independently.

## Lifecycle Tooling

Kubespray is the cluster lifecycle layer. It uses established, idempotent Ansible roles around kubeadm to prepare hosts, configure containerd and kernel settings, initialize Kubernetes, join nodes, install the CNI, renew certificates, scale membership, and perform ordered upgrades.

This is safer than maintaining those operations as independent shell mutations. A failed run can be corrected and converged again, desired state lives in a structured inventory, and routine operations use upstream playbooks. Kubespray is pinned to `v2.31.0`, while Kubernetes is pinned to `1.35.4`; version changes are deliberate repository edits rather than implicit downloads.

The tradeoff is additional dependency weight and abstraction. Troubleshooting requires familiarity with Ansible and Kubespray roles, and the deployment inherits Kubespray's supported version matrix. Pinning the release and keeping environment-specific configuration small makes that dependency explicit and reviewable.

## Highly Available API

Kubespray deploys kube-vip as a static pod on each control-plane node. The instances use leader election and ARP to advertise one API VIP. If the leader fails, another control-plane node takes over the address. Kubespray configures the API endpoint and certificate SAN consistently, avoiding a manually timed bootstrap sequence.

```text
operator/kubelet -> CONTROL_PLANE_VIP:6443 -> active kube-vip node -> kube-apiserver
```

## Networking

Cilium is the primary CNI and replaces kube-proxy. Service translation therefore happens in Cilium eBPF rather than kube-proxy's iptables or IPVS rules. Kubernetes IPAM allocates node PodCIDRs, and Hubble supplies flow visibility.

Kubespray installs and owns the Cilium Helm release. This repository adds only the site-specific resources that Kubespray cannot infer:

- `CiliumLoadBalancerIPPool` defines unused LAN addresses.
- `CiliumL2AnnouncementPolicy` advertises selected Service addresses.
- Services opt in through the label `expose: l2`.

```text
client -> LAN LoadBalancer IP -> elected Cilium announcer
       -> Cilium service load balancer -> ready backend pod
```

The demo Service uses `externalTrafficPolicy: Cluster`, allowing the announcing node to choose a ready backend on any node. This avoids coupling L2 leader election to local pod placement.

## Policy Model

The demo namespace includes a default-deny ingress policy and a narrow allow policy for clients carrying `role=allowed` to contact web pods on TCP/80. Validation creates both allowed and blocked clients and treats unexpected access or denial as a failed run.

## Operations and Failure Behavior

Node additions are inventory changes followed by Kubespray's `scale.yml`; node removals use `remove-node.yml` and explicit confirmation. Cluster upgrades use `upgrade-cluster.yml`, which handles control-plane and worker ordering. Re-running `cluster.yml` detects and corrects managed drift.

On worker failure, Kubernetes marks the node unavailable and Deployment replicas are rescheduled onto healthy capacity. One failed control-plane node leaves etcd with quorum. kube-vip moves the API address after control-plane leader failure, while Cilium re-elects an announcer when the node holding a Service address disappears.

## Limitations

- L2 announcements require clients and nodes to share a broadcast domain. Routed environments should use Cilium BGP Control Plane instead.
- The two-worker layout has limited spare capacity; disruption budgets and resource requests must be sized with one-node loss in mind.
- Kubespray state is configuration, not a replacement for etcd and application-data backups.
- No persistent storage, ingress controller, external DNS, identity provider, or secrets manager is included.
- A single interface name is assumed for kube-vip. Heterogeneous hosts need host-specific inventory variables.
- The admin kubeconfig and generated Kubespray inventory are sensitive local state and remain ignored by Git.
