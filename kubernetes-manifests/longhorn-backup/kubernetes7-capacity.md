# Enable existing kubernetes7 storage

User-authorized on 2026-09-17 to use additional capacity for Immich recovery.
The existing Longhorn filesystem disk was Ready but scheduling-disabled.
No formatting, cleanup, reserve reduction, node restart, cordon, or drain is involved.
The reason for its historical disablement was not established; monitor free space
and rebuild activity after enabling it. This node must never be powered off or drained.

Apply the guarded, one-time patch (it intentionally fails if already enabled):

```bash
kubectl -n longhorn-system patch nodes.longhorn.io kubernetes7 --type=json \
  --patch-file=/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/kubernetes-manifests/longhorn-backup/enable-kubernetes7-disk.json
```

This operational JSON patch is not a Kubernetes resource and must not be added
to Kustomization resources. Existing disk paths, tags, and reserved capacity are preserved.
Re-disabling scheduling does not remove existing replicas; do not evict replicas
without confirmed alternate capacity and backups.

Enabling a disk exposes existing space, not new physical capacity. Three replicas
across two nodes still do not provide three-node placement. Confirm healthy
engine replicas (RW), disk free-space headroom, and distinct-node placement before
claiming node-failure resilience. Never delete all replicas to trigger a rebuild.
