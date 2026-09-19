# Proof Template

Use this file as the short evidence section in the final submission. Paste command output or attach screenshots for each item.

## Cluster Nodes

Command:

```bash
kubectl get nodes -o wide
```

Expected: five nodes are `Ready`; three have the control-plane role.

## Cilium Health

Command:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --verbose
```

Expected: one Cilium agent per node, Cilium operator ready, no fatal status errors.

## Pods Running Across Nodes

Command:

```bash
kubectl -n infra-demo get pods -o wide
```

Expected: `web` replicas are running and spread across multiple nodes.

## App Reachable Externally

Command:

```bash
kubectl -n infra-demo get svc web -o wide
curl -v http://<external-ip>
```

Expected: Service has an external IP from the configured pool and returns the nginx page.

## Network Policies Enforced

Command:

```bash
kubectl -n infra-demo exec allowed-client -- curl -fsS --max-time 5 http://web
kubectl -n infra-demo exec blocked-client -- curl -fsS --max-time 5 http://web
```

Expected: allowed client succeeds; blocked client times out or fails.

## Failure Handling

Worker drain command:

```bash
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data
kubectl -n infra-demo get pods -o wide
kubectl uncordon <worker>
```

Expected: Deployment pods reschedule to healthy nodes and recover.

