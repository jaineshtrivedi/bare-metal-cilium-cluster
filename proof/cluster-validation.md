# Cluster Validation Evidence

Captured on 2026-09-20 after deployment and final policy validation.

## Nodes

Command:

```bash
kubectl get nodes -o wide
```

Result:

```text
NAME      STATUS   ROLES           VERSION   INTERNAL-IP
cp1       Ready    control-plane   v1.35.4   65.109.78.121
cp2       Ready    control-plane   v1.35.4   65.109.49.142
cp3       Ready    control-plane   v1.35.4   65.108.7.94
worker1   Ready    <none>          v1.35.4   65.108.65.56
worker2   Ready    <none>          v1.35.4   65.109.28.75
```

All five nodes are ready, with three control-plane nodes and two workers.

## Cilium

Commands:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium encrypt status
```

Observed results:

```text
Cilium agents:          5/5 Running
Cilium:                 Ok 1.19.3
Kubernetes:             Ok 1.35.4
KubeProxyReplacement:   True
Hubble:                 Ok
Cluster health:         5/5 reachable
Encryption:             Wireguard
WireGuard peers:        4 per node
```

## Workload Distribution

```bash
kubectl -n infra-demo get pods -l app=web -o wide
```

Result after the recovery test:

```text
web-85987675cd-664rj   1/1   Running   10.233.67.209   worker1
web-85987675cd-g8xhd   1/1   Running   10.233.67.192   worker1
web-85987675cd-tr4rt   1/1   Running   10.233.68.212   worker2
```

Application replicas run across both workers.

## External Access

The Service is a NodePort on TCP `30080`. The validation script successfully fetched the application through every node address:

```text
65.109.78.121:30080 OK
65.109.49.142:30080 OK
65.108.7.94:30080 OK
65.108.65.56:30080 OK
65.109.28.75:30080 OK
```

## Policy Enforcement

Policies applied:

```text
NetworkPolicy/default-deny-ingress
NetworkPolicy/allow-web-from-approved-clients
CiliumNetworkPolicy/allow-external-web
```

Final validation result:

```text
Allowed client reached the web Service.
Blocked client denied as expected.
External NodePort traffic remained reachable.
Validation complete.
```
