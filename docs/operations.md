# Operations Runbook

## Add a Worker Node

1. Add the new host IP to `WORKER_NODES` in `inventory.env`.
2. Prepare the host:

```bash
make prepare
```

3. Generate a fresh worker join command on the first control-plane node:

```bash
ssh root@<cp1> 'kubeadm token create --print-join-command'
```

4. Run the join command on the new node.
5. Verify:

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

## Add a Control-Plane Node

1. Prepare the host with `make prepare`.
2. Upload certificates and capture the certificate key:

```bash
ssh root@<cp1> 'kubeadm init phase upload-certs --upload-certs'
```

3. Generate a fresh join command:

```bash
ssh root@<cp1> 'kubeadm token create --print-join-command'
```

4. Run the join command with:

```bash
--control-plane --certificate-key <certificate-key>
```

5. Verify etcd and API health:

```bash
kubectl get nodes
kubectl -n kube-system get pods -l component=etcd -o wide
```

## Simulate a Worker Failure

To simulate planned maintenance:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl get pods -A -o wide | grep <node>
kubectl uncordon <node>
```

Expected result: Deployment-managed pods move to other schedulable nodes. DaemonSet pods such as Cilium remain on the drained node.

To simulate an unplanned failure, power off a worker host. Expected result: the node becomes `NotReady`, existing pods on that node eventually become unavailable, and replacement Deployment pods are created on healthy nodes.

## Simulate a Control-Plane Failure

Power off the current kube-vip leader or stop kubelet on it:

```bash
systemctl stop kubelet
```

Expected result:

- the API VIP moves to another control-plane node
- `kubectl` through the VIP continues working after failover
- etcd remains healthy as long as two of three control-plane nodes are up

Recover by starting kubelet again:

```bash
systemctl start kubelet
```

## Verify Cluster and Cilium Health

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl -n kube-system get ds cilium
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bpf lb list
```

## Verify Load and Scheduling

Apply the simple load generator:

```bash
kubectl apply -f manifests/ops/load-generator.yaml
kubectl top nodes
kubectl top pods -n infra-demo
```

If metrics are unavailable, install metrics-server or use host-level tools such as `top`, `htop`, `sar`, and containerd metrics.

## Debug Networking Issues

Start with the service and endpoints:

```bash
kubectl -n infra-demo get svc,endpoints,endpointslice -o wide
kubectl -n infra-demo describe svc web
```

Check Cilium status and endpoint identity:

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium endpoint list
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium policy get
```

Observe flows with Hubble:

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80
hubble observe --server localhost:4245 --namespace infra-demo
```

Check L2 advertisement:

```bash
kubectl get ciliuml2announcementpolicy
kubectl get ciliumloadbalancerippool
arp -an | grep <load-balancer-ip>
```

Packet-level checks on the announcing node:

```bash
tcpdump -ni <interface> host <load-balancer-ip> or arp
```

