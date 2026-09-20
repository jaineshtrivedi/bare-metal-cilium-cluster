# Operations Evidence

Captured on 2026-09-20 against the deployed five-node cluster.

## Load Exercise

The repository load generator was applied and reached the web Service repeatedly:

```bash
kubectl apply -f manifests/ops/load-generator.yaml
kubectl -n infra-demo wait pod/load-generator --for=condition=Ready --timeout=90s
```

Observed state:

```text
NAME             READY   STATUS    NODE
load-generator   1/1     Running   worker2
```

Cilium remained healthy during the exercise, and its service table contained both exposure paths:

```text
0.0.0.0:30080/TCP    NodePort
10.233.30.8:80/TCP   ClusterIP
```

The temporary generator was removed after the test.

## Worker Failure and Recovery

`worker1` was drained to simulate planned failure or maintenance:

```bash
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data --timeout=5m
```

Observed behavior:

```text
node/worker1 cordoned
pod/web-7964fbdc48-8jt92 evicted
node/worker1 drained
worker1   Ready,SchedulingDisabled
```

The evicted replica was recreated on `worker2`, giving three available replicas there while `worker1` was unschedulable. During the drain, HTTP checks against TCP `30080` succeeded through all five node addresses.

Recovery:

```bash
kubectl uncordon worker1
kubectl rollout restart deployment/web -n infra-demo
kubectl rollout status deployment/web -n infra-demo --timeout=3m
```

Observed result:

```text
node/worker1 uncordoned
worker1   Ready
deployment "web" successfully rolled out
```

The final rollout placed replicas on both `worker1` and `worker2`. A full validation after recovery passed external connectivity and both policy paths.

## Networking Diagnostics

Service backend discovery:

```bash
kubectl -n infra-demo get endpointslice \
  -l kubernetes.io/service-name=web -o wide
```

Observed endpoints:

```text
10.233.67.192,10.233.67.209,10.233.68.212
```

Cilium endpoint identities were ready for allowed, blocked, load, and web pods. Useful diagnostic commands demonstrated during validation were:

```bash
kubectl -n infra-demo get ciliumendpoint
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list
```

## Adding a Node

No sixth host was available, so node addition was demonstrated as the reproducible Kubespray procedure rather than changing the five-node topology.

1. Add the new stable address to `WORKER_NODES` in `inventory.env`.
2. Regenerate inventory:

```bash
make inventory
```

3. Verify SSH and privilege escalation:

```bash
make preflight
```

4. Run the Kubespray scaling playbook for only the new inventory host:

```bash
cd state/kubespray
../venv/bin/ansible-playbook \
  -i ../inventory/inventory.ini \
  scale.yml --become --limit worker3
```

5. Verify the node and Cilium agent:

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

Kubespray handles host preparation, containerd, kubelet registration, and Cilium deployment idempotently.
