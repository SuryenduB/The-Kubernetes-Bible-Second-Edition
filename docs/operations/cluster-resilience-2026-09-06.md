# Cluster resilience status — 2026-09-06

## Completed in this incident

- Recovered the NFS provisioner by recreating its stale NFS mount.
- Recovered the IIQ SQL database and validated it with `DBCC CHECKDB`.
- Added explicit Uptime Kuma ingress access to protected application namespaces.
- Corrected Homepage's allowed-host configuration for Kubernetes service DNS.
- Created a pre-repair Longhorn snapshot for the IIQ MSSQL volume.
- Rebuilt LinguaCafe MariaDB after the operator approved data loss; the new
  volume is healthy with three running replicas on `kubernetes1`, `kubernetes6`,
  and `kubernetes7`.
- Created and verified Longhorn backup `backup-8143af524ac74592` for the rebuilt
  MariaDB volume on QNAP.
- Spread LinguaCafe web replicas across nodes and added a disruption budget.
- Removed a stale Longhorn manager endpoint from the unreachable node and
  restarted QNAP NFS after backup clients reported I/O errors.

## Root cause of the LinguaCafe outage

The Longhorn StorageClass requested three replicas, but the old MariaDB volume
had only one actual replica. That replica lived on `kubernetes8-debian`, which
stopped reporting kubelet status. The volume therefore became faulted and had
no surviving data path. The old volume also had no Longhorn backup, so it could
not be restored independently of the failed node.

The replacement volume was not considered repaired until both conditions were
true: Longhorn reported `healthy`, and three replica CRs were `running` on
reachable nodes. The replacement was then backed up to QNAP and its backup was
verified at 100%.

`kubernetes8-debian` remains unreachable and should not be used for new
stateful replicas until it is physically recovered and its Longhorn node health
passes preflight checks.

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
