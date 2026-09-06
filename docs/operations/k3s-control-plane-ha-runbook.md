# K3s Control-Plane HA Runbook

## Current limitation

As of 2026-09-06, `nuc` (`192.168.0.21`) is the only K3s server. The other
machines are agents. If NUC is powered off, the Kubernetes API endpoint at
`192.168.0.21:6443` is unavailable; Kubernetes manifests cannot change that.

This runbook is intentionally separate from application manifests because the
repair requires host-level K3s installation and access to the server token.

## Target topology

Use three K3s servers with embedded etcd, for example:

```text
nuc           192.168.0.21  server + embedded etcd
kubernetes1   192.168.0.19  server + embedded etcd
kubernetes2   192.168.0.20  server + embedded etcd
```

Keep an odd number of servers. Three servers tolerate one server failure; five
servers tolerate two. Do not run an even-numbered control plane merely to use
more machines.

## Preconditions

Before changing a host:

1. Confirm all three machines have stable addresses and synchronized clocks.
2. Back up K3s datastore state and validate that the backup can be read.
3. Record the installed K3s version on NUC and use the same version on new servers.
4. Confirm TCP 6443, 2379, and 2380 are allowed between server nodes.
5. Confirm the server token is available on NUC or in the protected backup; never
   commit it to Git or paste it into logs.
6. Confirm Longhorn has healthy replicas before taking a node out of service.

## Migration outline

On the first additional server, install K3s with the existing server URL and
token, using the existing cluster's version and the desired fixed API address:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://192.168.0.21:6443 \
  K3S_TOKEN='<read from protected secret storage>' \
  INSTALL_K3S_VERSION='<match nuc>' \
  sh -s - server
```

Repeat on the second additional server. Verify the etcd member list and
`kubectl get nodes` from NUC before proceeding. Then configure clients and
Uptime Kuma to use a stable load-balanced API endpoint or a DNS name backed by
the three server addresses. Do not point clients at a single server IP as the
long-term endpoint.

After each host joins, validate:

```bash
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
kubectl -n kube-system get pods -o wide
kubectl -n longhorn-system get nodes.longhorn.io
```

Only after the new servers are healthy should NUC be rebooted as a controlled
failure test. During the test, verify the API endpoint, Longhorn attachment,
Uptime Kuma, and each application monitor. Restore NUC and confirm etcd returns
to a healthy three-member quorum.

## Not performed from the current session

This migration was not executed because the available kubeconfig provides
Kubernetes API access but no host SSH/console access to install K3s or retrieve
the protected server token. Attempting to change this through Kubernetes
resources alone would not create a second control plane and could leave the
cluster unrecoverable.
