# Operations Runbook

Set the local kubeconfig before Kubernetes operations:

```bash
export KUBECONFIG="$PWD/state/admin.conf"
```

## Reconcile Managed State

```bash
make cluster
```

Limit a diagnostic rerun when appropriate:

```bash
./scripts/02_deploy_cluster.sh --limit worker2
```

## Recover CNI After an Interrupted Bootstrap

If kubeadm completed but the run stopped before the network-plugin play, all nodes report `NetworkPluginNotReady`. On a rerun, Kubespray may wait for those nodes before reaching Cilium. Install only the network role, then resume normally:

```bash
make recover-cni
make cluster
```

This recovery is idempotent and does not reset kubeadm or etcd.

If a Cilium `mount-cgroup` or `install-cni-binaries` init container reports permission denied under `/opt/cni/bin`, regenerate inventory before recovery. The inventory sets Kubespray's required `kube_owner: root`, and the tagged recovery corrects ownership on every node.

## Add a Worker

Add its stable address to `WORKER_NODES`, regenerate inventory, and run Kubespray's scaling playbook:

```bash
make inventory
cd state/kubespray
../venv/bin/ansible-playbook \
  -i ../inventory/inventory.ini \
  scale.yml --become --limit <new-worker-name>
```

Allow all required inter-node ports for the new address before scaling.

## Remove a Node

Drain workloads and run the removal playbook before deleting the address from inventory:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
cd state/kubespray
../venv/bin/ansible-playbook \
  -i ../inventory/inventory.ini \
  remove-node.yml --become \
  --extra-vars "node=<node>" \
  --extra-vars reset_nodes=true
```

Node removal is destructive. Confirm the exact node and etcd quorum first.

## Upgrade Kubernetes

Change `KUBERNETES_VERSION` to a release supported by the pinned Kubespray version, then:

```bash
make inventory
make upgrade
make validate
```

Upgrade one Kubernetes minor release at a time and review Kubespray release notes before changing its pinned version.

## Test Worker Failure

For planned maintenance:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl get pods -A -o wide
kubectl uncordon <node>
```

For an unplanned test, power off one worker. The node should become `NotReady`, and Deployment replicas should be recreated on healthy capacity.

## Test Control-Plane Failure

Stop kubelet on one control-plane host or power it off. The remaining two etcd members retain quorum, and node-local API proxies continue using healthy API servers.

If the failed host is the endpoint in `state/admin.conf`, edit the kubeconfig and replace its `server` address with another healthy control-plane address:

```bash
$EDITOR state/admin.conf
kubectl get nodes
```

Restore the preferred endpoint after recovery.

## Verify Cluster and Cilium

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl -n kube-system get ds cilium
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium encrypt status
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list
```

Test every external path:

```bash
source inventory.env
for ip in "${CP_NODES[@]}" "${WORKER_NODES[@]}"; do
  curl --fail --max-time 10 "http://${ip}:${NODE_PORT}"
done
```

Observe policy flows with Hubble:

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80
hubble observe --server localhost:4245 --namespace infra-demo
```

## Reset the Cluster

`make reset` runs Kubespray's destructive reset playbook on every inventoried host. Use it only when intentionally dismantling the cluster.
