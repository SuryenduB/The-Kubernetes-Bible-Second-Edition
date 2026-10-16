#!/usr/bin/env bash
# ==============================================================================
# k3s-etcd-safe-backup.sh: Non-Disruptive Online etcd & Identity Backup to NAS
#
# DESIGN & SAFETY PRINCIPLES:
# 1. Non-Disruptive: Uses native `k3s etcd-snapshot save`. K3s is NEVER stopped.
# 2. Server-Token Preservation: Backs up /var/lib/rancher/k3s/server/token, tls,
#    and creds required for worker reconnection upon control-plane rebuild.
# 3. Overlap Prevention: Uses flock file locking on /var/run/k3s-backup.lock.
# 4. Atomic Off-Node Copy: Writes to temporary files on NAS before renaming, then
#    verifies the copy with sha256sum (snapshot) and tar -tzf (archives) BEFORE
#    the atomic rename. A corrupt/mismatched copy never lands as a backup.
# 5. Free Space Verification: Checks for at least 5GB free space on NAS destination.
# 6. Retention Enforcement: Retains only the last N (default: 14) remote backups.
#    Local pruning only touches `etcd-snapshot-*` files (pre-join snapshots kept).
# 7. Redaction & Safety: Never logs tokens, keys, or passwords.
# 8. Strict Error Handling: Exits non-zero on failure; traps and cleans up mounts.
# 9. Cron-Safe: Sets an explicit PATH (cron's default PATH does not include
#    /usr/local/bin, where the k3s binary lives).
#
# ROLLBACK PROCEDURE (to restore previous legacy cron if required):
#   sudo crontab -e
#   Replace the k3s-etcd-safe-backup.sh entry with:
#   0 2 * * * /usr/local/bin/k3s-backup-to-nas.sh >> /var/log/k3s-backup.log 2>&1
#
# MANUAL TEST PROCEDURE:
#   sudo /usr/local/bin/k3s-etcd-safe-backup.sh --manual-test
# ==============================================================================
set -euo pipefail

# Cron environment is minimal; ensure the k3s binary and system tools resolve.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Configuration Defaults
LOCK_FILE="/var/run/k3s-backup.lock"
NAS_IP="192.168.0.128"
NAS_PATH="/share/Public/backups/k3s"
MOUNT_POINT="/mnt/k3s-nas-backup"
LOCAL_SNAP_DIR="/var/lib/rancher/k3s/server/db/snapshots"
SERVER_DIR="/var/lib/rancher/k3s/server"
CONFIG_DIR="/etc/rancher/k3s"
RETENTION_COUNT=14
MIN_FREE_SPACE_KB=5242880 # 5 GB in KB
DATE=$(date +%Y%m%d-%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# 1. Prevent Overlapping Runs
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
    log_error "Another backup run is currently in progress. Exiting."
    exit 1
fi

cleanup() {
    local exit_code=$?
    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        umount "${MOUNT_POINT}" 2>/dev/null || umount -l "${MOUNT_POINT}" 2>/dev/null || true
    fi
    if [ -d "${MOUNT_POINT}" ]; then
        rmdir "${MOUNT_POINT}" 2>/dev/null || true
    fi
    if [ ${exit_code} -ne 0 ]; then
        log_error "Backup run completed with FAILURE (exit code ${exit_code})."
    fi
    exit ${exit_code}
}
trap cleanup EXIT INT TERM

log "=== Starting Non-Disruptive K3s etcd & Identity Backup ==="

# 2. Verify Root / K3s Preconditions
if [ "$(id -u)" -ne 0 ]; then
    log_error "This backup script must be executed as root."
    exit 1
fi

if ! command -v k3s >/dev/null 2>&1; then
    log_error "k3s binary not found in PATH."
    exit 1
fi

# 3. Verify Server-Token & Identity Files Exist
if [ ! -f "${SERVER_DIR}/token" ]; then
    log_error "Critical recovery file missing: ${SERVER_DIR}/token"
    exit 1
fi

TOKEN_SIZE=$(stat -c%s "${SERVER_DIR}/token" 2>/dev/null || echo 0)
if [ "${TOKEN_SIZE}" -lt 10 ]; then
    log_error "Server token exists but size is suspiciously small (${TOKEN_SIZE} bytes)."
    exit 1
fi
log "Verified server-token presence (${TOKEN_SIZE} bytes) for cluster recovery."

# 4. Trigger Online Embedded etcd Snapshot (Zero Downtime)
SNAPSHOT_NAME="etcd-snapshot-online-${DATE}"
log "Triggering online etcd snapshot: ${SNAPSHOT_NAME} (K3s remains active) ..."
k3s etcd-snapshot save --name "${SNAPSHOT_NAME}"

# Locate generated snapshot file
SNAP_FILE=$(find "${LOCAL_SNAP_DIR}" -name "*${SNAPSHOT_NAME}*" -type f | head -n 1)
if [ -z "${SNAP_FILE}" ] || [ ! -f "${SNAP_FILE}" ]; then
    log_error "Failed to locate generated snapshot file matching ${SNAPSHOT_NAME} in ${LOCAL_SNAP_DIR}."
    exit 1
fi

SNAP_SIZE=$(stat -c%s "${SNAP_FILE}")
if [ "${SNAP_SIZE}" -lt 10485760 ]; then # 10 MB
    log_error "Snapshot file ${SNAP_FILE} is suspiciously small (${SNAP_SIZE} bytes). Integrity check failed."
    exit 1
fi
log "Snapshot generated successfully: $(basename "${SNAP_FILE}") (${SNAP_SIZE} bytes)."

# 5. Create Local Staging Archives for Configuration & Identity
TMP_STAGE=$(mktemp -d /tmp/k3s-backup-stage.XXXXXX)
chmod 0700 "${TMP_STAGE}"
stage_cleanup() {
    rm -rf "${TMP_STAGE}"
}
trap 'stage_cleanup; cleanup' EXIT INT TERM

log "Archiving K3s cluster configuration..."
tar -czf "${TMP_STAGE}/k3s-config.tar.gz" -C / etc/rancher/k3s/

log "Archiving server identity (token, tls certificates, and credentials)..."
tar -czf "${TMP_STAGE}/k3s-identity.tar.gz" \
    -C / var/lib/rancher/k3s/server/token \
         var/lib/rancher/k3s/server/node-token \
         var/lib/rancher/k3s/server/tls \
         var/lib/rancher/k3s/server/cred

# 6. Mount NAS Destination via NFS
mkdir -p "${MOUNT_POINT}"
log "Mounting remote backup target ${NAS_IP}:${NAS_PATH} ..."
mount -t nfs -o rw,sync,hard,intr "${NAS_IP}:${NAS_PATH}" "${MOUNT_POINT}"

if ! mountpoint -q "${MOUNT_POINT}"; then
    log_error "Failed to mount NFS export ${NAS_IP}:${NAS_PATH} at ${MOUNT_POINT}."
    exit 1
fi

# 7. Check Destination Free Space
AVAILABLE_KB=$(df -P "${MOUNT_POINT}" | tail -1 | awk '{print $4}')
if [ "${AVAILABLE_KB}" -lt "${MIN_FREE_SPACE_KB}" ]; then
    log_error "Insufficient free space on NAS destination. Available: ${AVAILABLE_KB} KB, Required: ${MIN_FREE_SPACE_KB} KB."
    exit 1
fi
log "Destination free space check passed: $((AVAILABLE_KB / 1024)) MB available."

# 8. Atomic Off-Node Copy via Staging Directory
TARGET_DIR="${MOUNT_POINT}/${DATE}"
TEMP_TARGET_DIR="${MOUNT_POINT}/.tmp-${DATE}"
rm -rf "${TEMP_TARGET_DIR}"
mkdir -p "${TEMP_TARGET_DIR}"

log "Transferring snapshot and identity archives to temporary target on NAS..."
cp "${SNAP_FILE}" "${TEMP_TARGET_DIR}/$(basename "${SNAP_FILE}")"
cp "${TMP_STAGE}/k3s-config.tar.gz" "${TEMP_TARGET_DIR}/k3s-config.tar.gz"
cp "${TMP_STAGE}/k3s-identity.tar.gz" "${TEMP_TARGET_DIR}/k3s-identity.tar.gz"

# 9. Verify the off-node copy BEFORE it is promoted to a backup directory
log "Verifying off-node copy integrity (sha256 + archive listing)..."
SRC_HASH=$(sha256sum "${SNAP_FILE}" | awk '{print $1}')
DST_HASH=$(sha256sum "${TEMP_TARGET_DIR}/$(basename "${SNAP_FILE}")" | awk '{print $1}')
if [ "${SRC_HASH}" != "${DST_HASH}" ]; then
    log_error "Snapshot checksum mismatch during NAS transfer. Aborting. src=${SRC_HASH} dst=${DST_HASH}"
    rm -rf "${TEMP_TARGET_DIR}"
    exit 1
fi
log "Snapshot checksum verified: ${SRC_HASH}"

for archive in k3s-config.tar.gz k3s-identity.tar.gz; do
    if ! tar -tzf "${TEMP_TARGET_DIR}/${archive}" >/dev/null 2>&1; then
        log_error "Archive ${archive} failed integrity listing on NAS. Aborting."
        rm -rf "${TEMP_TARGET_DIR}"
        exit 1
    fi
done
log "Config and identity archives verified (tar -tzf)."

# Atomic rename from temporary target to final backup directory
mv "${TEMP_TARGET_DIR}" "${TARGET_DIR}"
log "Atomic transfer complete: ${TARGET_DIR}"

# 10. Enforce Off-Node Retention
log "Enforcing retention policy (keeping last ${RETENTION_COUNT} backups)..."
cd "${MOUNT_POINT}"
# Exclude hidden directories and temporary markers
ls -dt 20* 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)) | while read -r old_dir; do
    if [ -d "${old_dir}" ]; then
        log "Pruning expired backup: ${old_dir}"
        rm -rf "${old_dir}"
    fi
done

# 11. Local Snapshot Retention (keep last 14 days of scheduled snapshots locally;
#     pre-join snapshots are deliberately NOT pruned - they document the etcd migration).
log "Pruning local scheduled snapshots older than 14 days in ${LOCAL_SNAP_DIR}..."
find "${LOCAL_SNAP_DIR}" -name "etcd-snapshot-*" -type f -mtime +14 -delete || true

log "=== K3s Online etcd & Identity Backup Completed Successfully ==="
