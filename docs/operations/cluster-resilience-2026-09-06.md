# Cluster resilience status — 2026-09-06

## Completed in this incident

- Recovered the NFS provisioner by recreating its stale NFS mount.
- Recovered the IIQ SQL database and validated it with `DBCC CHECKDB`.
- Added explicit Uptime Kuma ingress access to protected application namespaces.
- Corrected Homepage's allowed-host configuration for Kubernetes service DNS.
- Created a pre-repair Longhorn snapshot for the IIQ MSSQL volume.

## Remaining physical recovery

`kubernetes8-debian` is unreachable and has not reported kubelet status. The
LinguaCafe MariaDB volume is faulted/detached and its only surviving replica is
on that node. No Longhorn backup exists for that volume. Do not delete the PVC,
replica, or volume: recovery requires bringing `kubernetes8-debian` back or
restoring a database/Longhorn backup supplied by the operator.

## Control-plane high availability

The cluster currently has one K3s server: `nuc` (192.168.0.21). The other
nodes are agents. Surviving loss of NUC requires host-level K3s conversion or
reinstallation of at least two additional servers using the same server token,
with embedded-etcd quorum. Kubernetes manifests alone cannot provide API-server
HA when the only server is powered off.

After adding servers, validate quorum and then add topology spread constraints
and disruption budgets to every user-facing Deployment. Keep Longhorn replicas
on independent, reachable nodes and require a successful backup before marking
stateful workloads resilient.
