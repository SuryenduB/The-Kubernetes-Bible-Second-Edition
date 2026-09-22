# Longhorn Backup Configuration

Automated snapshot + NFS backup for all Longhorn volumes (40 volumes, ~222 GiB logical as of 2026-09-17).
Mechanism: RecurringJobs in the `default` group auto-schedule to any volume with no
explicit recurring job - existing and future. No per-PVC wiring.

## Contents
| File | What it does |
|---|---|
| `01-backup-target-settings.yaml` | `BackupTarget` CR `default` (v1.8+ replaced the legacy `backup-target` Setting) pointing at `nfs://192.168.0.128:/backups/longhorn`, poll interval 5m, plus `allow-recurring-job-while-volume-detached: true` |
| `02-recurring-jobs.yaml` | `snapshot-frequent` (6h, retain 4) + `backup-daily` (03:30 UTC, retain 14, concurrency 1), both in `default` group |
| `03-filesystem-trim-optional.yaml` | Optional weekly `filesystem-trim` for churny DB volumes - opt-in via volume label `recurring-job-group.longhorn.io/fs-trim=enabled` |
| `04-node-failure-resilience.yaml` | Strict replica anti-affinity, node-down pod deletion, best-effort auto-balance |
| `05-storage-reserve.yaml` | Per-disk reserve 20% (existing disks keep their baked-in absolute values; applies to newly added disks) |
| `06-storageclass-r1.yaml` | `longhorn-r1` single-replica StorageClass for lightweight, rebuildable data |
| `07-nfs40-premount.yaml` | Self-healing DaemonSet that keeps a healthy **NFSv4.0 pre-mount** of the backupstore inside every longhorn-manager / instance-manager / engine namespace (the very old QNAP does not support NFSv4.1 and Longhorn hardcodes `nfsvers=4.1`) - see `NFS41-INCIDENT-REPORT.md` |

All manifests validated against the live cluster's admission webhook (Longhorn v1.8.1,
apiVersion `longhorn.io/v1beta2`, RecurringJob `spec.name` required).

## Prerequisites (hard gate before applying `01-`)
1. QNAP NFS export `/backups/longhorn` created with:
   - Access limited to node IPs (192.168.0.21, .19, .20, .22-.26)
   - Squash set to **No squash** (`no_root_squash`) - Longhorn writes backups as root
2. Root write test from a worker node:
   ```sh
   # on any worker, as root:
   mount -t nfs 192.168.0.128:/backups/longhorn /mnt && touch /mnt/root-write-test && ls -la /mnt/root-write-test && rm /mnt/root-write-test && umount /mnt
   ```
3. Control-plane backup at 02:00 measured < 90 min (else move backup-daily later)

## Apply
```sh
kubectl apply -k kubernetes-manifests/longhorn-backup
```

## First run
Trigger `backup-daily` manually once (Longhorn UI -> Recurring Job -> Run Now, or
`kubectl -n longhorn-system create job` is NOT applicable - use UI/Volume attach),
then measure duration and confirm backups appear:
```sh
kubectl -n longhorn-system get backups.longhorn.io -o wide
kubectl -n longhorn-system get settings.longhorn.io backup-target -o jsonpath='{.value}'
```

## Restore drill
Restore `monitoring/beszel-hub-data` (1Gi, small + low-risk) into a scratch namespace
via Longhorn UI: Backup -> Restore PVC, then verify data mounts.

## Operational notes
- **The very old QNAP does not support NFSv4.1** (4.1 mounts establish but reads die
  with EIO; no firmware/repair/config path exists) and Longhorn hardcodes
  `nfsvers=4.1`, so backups only work through the NFSv4.0 pre-mount kept alive by the
  `nfs40-premount` DaemonSet (`07-`). Full root cause, verification, and the live-state
  audit are in `NFS41-INCIDENT-REPORT.md`. There is **no NAS-side fix** - the
  DaemonSet *is* the permanent solution; the only true cure is replacing the NAS.
- **Never edit `backup-target` via the Longhorn UI** - this repo is the source of truth.
  Changing the target later *orphans* all previously taken backups (by design).
- Backups are **crash-consistent**, not app-quiesced. DB transaction logs inside the
  volumes (MSSQL/MySQL/LDAP WAL) make restores recoverable.
- Snapshot chains (retain 4 x 6h — reduced from 12 on 2026-09-17 when disks hit ~80%) live on **worker NVMe**, not the NAS. Check disk
  headroom after Day 3, especially k1/k5/k6. Use `03-filesystem-trim` for reclamation.
- `linguacafe/linguacafe-mariadb-pvc` was found **detached + faulted** during Phase 0
  recon with zero backups - repair or rebuild this volume before relying on backups.
