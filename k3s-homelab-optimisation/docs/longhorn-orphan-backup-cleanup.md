# Longhorn orphan-backup cleanup

**Status:** implemented and scheduled on `nuc` 2026-11-22 (APP-10).

## Problem

Deleting a PVC does not cascade to its Longhorn backups. On 2026-11-22 the
cluster held **430 backups for 40 volumes that no longer existed** — 0 surviving
PVCs, 0 VolumeSnapshots — consuming **5.62 GiB** on the NAS backupstore
(`192.168.0.128:/longhorn`). The `backup-daily` recurring job retains only 14
backups, but retention cannot act once the volume object is gone.

## Implementation

- Script: `scripts/longhorn-orphan-backup-cleanup.sh` (installed on `nuc` at
  `/usr/local/bin/longhorn-orphan-backup-cleanup.sh`, mode 0750).
- Schedule: weekly, `0 3 * * 0`, after the 18:00 etcd backup slot:
  `... --apply >> /var/log/longhorn-orphan-backup-cleanup.log 2>&1`.
- Default mode is **dry run**; `--apply` is required to delete anything.

## Eligibility (all must hold)

1. Not a current `volumes.longhorn.io` object.
2. No PVC in any namespace has it as `spec.volumeName`.
3. No VolumeSnapshot or VolumeSnapshotContent mentions it.
4. Not listed in `/etc/longhorn-orphan-backup-cleanup/keep-volumes.txt`.
5. Backup older than `LONGHORN_ORPHAN_BACKUP_MIN_AGE_DAYS` (default 30).
6. Revalidated by regenerating the candidate set immediately before deletion,
   then re-checking each object one at a time.

Only Backup CRs are deleted one at a time with `--wait=true --timeout=120s`;
the corresponding BackupVolume CR is removed once no backups remain. Longhorn
then removes the backupstore files. Deletion is **irreversible** — the 30-day
floor and keep list are the recovery window.

## Verification (2026-11-22)

- Before: 721 Backup CRs / 64 BackupVolume CRs / 10,803,512 KiB backupstore.
- After: 291 Backup CRs / 24 BackupVolume CRs / 4,909,528 KiB backupstore.
- 430 deleted, 0 orphan-volume backups remaining, 0 failures.
- Cluster stayed healthy: 10/10 nodes Ready, pod phases unchanged.
- Installed script dry-run after cleanup: 0 candidates, exit 0.

## Operations

```bash
# Review what would be deleted (safe, no changes)
sudo /usr/local/bin/longhorn-orphan-backup-cleanup.sh

# Protect an archived volume from future pruning
echo 'pvc-xxxxxxxx-....' | sudo tee -a /etc/longhorn-orphan-backup-cleanup/keep-volumes.txt

# Wider recovery window for one run
LONGHORN_ORPHAN_BACKUP_MIN_AGE_DAYS=90 sudo /usr/local/bin/longhorn-orphan-backup-cleanup.sh --apply
```

## Rollback

Disable the cron entry (`sudo crontab -e` and remove the
`longhorn-orphan-backup-cleanup.sh` line). Deleted backups cannot be restored
from this host; recover from the NAS backupstore only if Longhorn has not yet
garbage-collected the blocks.
