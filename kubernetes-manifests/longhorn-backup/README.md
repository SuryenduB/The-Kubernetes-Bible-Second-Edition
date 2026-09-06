# Longhorn Backup Configuration

Automated snapshot + NFS backup for all Longhorn volumes (13 volumes, ~74 GiB logical).
Mechanism: RecurringJobs in the `default` group auto-schedule to any volume with no
explicit recurring job - existing and future. No per-PVC wiring.

## Contents
| File | What it does |
|---|---|
| `01-backup-target-settings.yaml` | `BackupTarget` CR `default` (v1.8+ replaced the legacy `backup-target` Setting) pointing at `nfs://192.168.0.128:/backups/longhorn`, poll interval 5m, plus `allow-recurring-job-while-volume-detached: true` |
| `02-recurring-jobs.yaml` | `snapshot-frequent` (6h, retain 12) + `backup-daily` (03:30 UTC, retain 14, concurrency 1), both in `default` group |
| `03-filesystem-trim-optional.yaml` | Optional weekly `filesystem-trim` for churny DB volumes - opt-in via volume label `recurring-job-group.longhorn.io/fs-trim=enabled` |

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
- **Never edit `backup-target` via the Longhorn UI** - this repo is the source of truth.
  Changing the target later *orphans* all previously taken backups (by design).
- Backups are **crash-consistent**, not app-quiesced. DB transaction logs inside the
  volumes (MSSQL/MySQL/LDAP WAL) make restores recoverable.
- Snapshot chains (retain 12 x 6h) live on **worker NVMe**, not the NAS. Check disk
  headroom after Day 3, especially k1/k5/k6. Use `03-filesystem-trim` for reclamation.
- `linguacafe/linguacafe-mariadb-pvc` was found **detached + faulted** during Phase 0
  recon with zero backups - repair or rebuild this volume before relying on backups.
