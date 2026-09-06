#!/bin/bash
# ============================================================
# K3s Backup to NAS (NFS) - Triple Protection System
# Backs up SQLite datastore + config + server identity to NAS
# via NFS mount.
#
# Layout per snapshot dir on NAS:
#   k3s-state.db         - SQLite/Kine datastore (integrity-checked copy)
#   k3s-config.tar.gz    - /etc/rancher/k3s (kubeconfig, registries.yaml)
#   k3s-identity.tar.gz  - server token, node-token, tls/, cred/
#                          (WITHOUT these, a re-imaged master gets a new CA
#                          and no worker can rejoin - see Restore-K3sCluster.ps1)
#
# Source of truth: this repo (WindowsLab/k3s-backup-to-nas.sh).
# Installed at: /usr/local/bin/k3s-backup-to-nas.sh on nuc.
# Schedule: root crontab `0 2 * * *` (02:00 UTC daily).
# ============================================================
set -euo pipefail

NAS_IP="192.168.0.128"
NAS_PATH="/share/Public/backups/k3s"
MOUNT_POINT="/mnt/k3s-nas-backup"
K3S_DB="/var/lib/rancher/k3s/server/db/state.db"
SERVER_DIR="/var/lib/rancher/k3s/server"
DATE=$(date +%Y%m%d-%H%M%S)
RETENTION=10

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

cleanup() {
    # NEVER leave K3s stopped: any set -e failure between stop and the
    # explicit start must still bring the API back. `start` is idempotent.
    systemctl start k3s 2>/dev/null || true
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        umount "$MOUNT_POINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

log "Starting K3s backup to NAS..."

# Clear any stale mount left by a previous interrupted run or NAS
# event (stale handles make even `mkdir -p` fail).
umount -l "$MOUNT_POINT" 2>/dev/null || true

# Create mount point
mkdir -p "$MOUNT_POINT"

# Mount NAS via NFS
log "Mounting NAS: ${NAS_IP}:${NAS_PATH} -> ${MOUNT_POINT}"
mount -t nfs "${NAS_IP}:${NAS_PATH}" "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
    log "ERROR: Failed to mount NAS at ${MOUNT_POINT}"
    exit 1
fi

# Create backup directory on NAS
mkdir -p "${MOUNT_POINT}/${DATE}"

# Stop K3s for consistent SQLite snapshot
log "Stopping K3s for consistent snapshot..."
systemctl stop k3s
sleep 3

# Checkpoint WAL into the db BEFORE copy (never rm the -wal: that
# discards uncheckpointed transactions). K3s is stopped, so the
# checkpoint is stable.
log "Checkpointing WAL..."
sqlite3 "$K3S_DB" "PRAGMA wal_checkpoint(TRUNCATE);"

# Copy SQLite database
log "Backing up SQLite database..."
cp "$K3S_DB" "${MOUNT_POINT}/${DATE}/k3s-state.db"

# Verify backup integrity
log "Verifying backup integrity..."
INTEGRITY=$(sqlite3 "${MOUNT_POINT}/${DATE}/k3s-state.db" "PRAGMA integrity_check;" 2>&1 | head -1)
if [ "$INTEGRITY" != "ok" ]; then
    log "ERROR: Backup is corrupted: $INTEGRITY"
    rm -rf "${MOUNT_POINT}/${DATE}"
    systemctl start k3s
    exit 1
fi
log "Backup integrity: OK"

# Archive K3s config
log "Backing up K3s configuration..."
tar -czf "${MOUNT_POINT}/${DATE}/k3s-config.tar.gz" -C / etc/rancher/k3s/

# Archive server identity (token, node-token symlink, tls/, cred/).
# REQUIRED for workers to rejoin a rebuilt master transparently.
log "Backing up server identity (token/tls/cred)..."
tar -czf "${MOUNT_POINT}/${DATE}/k3s-identity.tar.gz" \
    -C / var/lib/rancher/k3s/server/token \
         var/lib/rancher/k3s/server/node-token \
         var/lib/rancher/k3s/server/tls \
         var/lib/rancher/k3s/server/cred
log "Identity archive contents:"
tar -tzf "${MOUNT_POINT}/${DATE}/k3s-identity.tar.gz" | head -8

# Restart K3s
log "Starting K3s..."
systemctl start k3s
sleep 5

# Verify K3s is healthy
if kubectl get nodes >/dev/null 2>&1; then
    log "K3s cluster healthy after backup"
else
    log "WARNING: K3s API not responding after restart"
fi

# Cleanup old backups (keep last RETENTION)
log "Cleaning up old backups (keeping last ${RETENTION})..."
cd "$MOUNT_POINT"
ls -dt */ 2>/dev/null | tail -n +$((RETENTION + 1)) | while read -r old; do
    log "Removing old backup: $old"
    rm -rf "$old"
done

# Unmount (handled by trap)
log "Backup completed successfully: ${DATE}"
log "Backup contents:"
ls -lh "${MOUNT_POINT}/${DATE}/"
