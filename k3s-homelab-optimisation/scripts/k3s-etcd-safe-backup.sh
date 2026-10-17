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
#    Local pruning only touches `etcd-snapshot-*` files (pre-join snapshots kept)
#    because the prune pattern does not match `pre-join-*` names.
# 7. Redaction & Safety: Never logs tokens, keys, or passwords. Failure phases are
#    tagged ([PRECOND]/[SNAPSHOT]/[STAGING]/[MOUNT]/[TRANSFER]/[RETENTION])
#    so partial failures are distinguishable in the log.
# 8. Strict Error Handling: Exits non-zero on failure; traps and cleans up mounts.
#    Intuitive INT/TERM handling: an interrupted run exits 143, never 0.
# 9. Cron-Safe: Sets an explicit PATH (cron's default PATH does not include
#    /usr/local/bin, where the k3s binary lives).
# 10. Bounded NAS Mount: `mount -t nfs -o hard` alone would RETRY FOREVER when
#    the NAS is unreachable (a silent, permanent backup outage). The mount call
#    is wrapped in `timeout` and fails cleanly. After mounting, the source
#    identity is verified with findmnt, so a stale or foreign filesystem left
#    mounted at ${MOUNT_POINT} can never receive backups or eat the root disk.
# 11. Manual Test Mode: --manual-test performs the complete pipeline but stops
#    before publishing (no rename into the date directory) and does not prune.
#
# ENV OVERRIDES (for testing only; cron uses the defaults):
#   NAS_IP, NAS_MOUNT_TIMEOUT_SECONDS
#
# ROLLBACK PROCEDURE (to restore previous legacy cron if required):
#   sudo crontab -e
#   Replace the k3s-etcd-safe-backup.sh entry with:
#   0 2 * * * /usr/local/bin/k3s-backup-to-nas.sh >> /var/log/k3s-backup.log 2>&1
#
# MANUAL TEST PROCEDURE:
#   sudo /usr/local/bin/k3s-etcd-safe-backup.sh --manual-test   (no publish)
#   NAS_IP=203.0.113.1 /usr/local/bin/k3s-etcd-safe-backup.sh    (fail-fast test)
# ==============================================================================
set -euo pipefail

# Cron environment is minimal; ensure the k3s binary and system tools resolve.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Configuration Defaults (NAS_IP/NAS_MOUNT_TIMEOUT_SECONDS may be overridden via env)
LOCK_FILE="/var/run/k3s-backup.lock"
NAS_IP="${NAS_IP:-192.168.0.128}"
NAS_PATH="/share/Public/backups/k3s"
MOUNT_POINT="/mnt/k3s-nas-backup"
NAS_MOUNT_TIMEOUT_SECONDS="${NAS_MOUNT_TIMEOUT_SECONDS:-180}"
LOCAL_SNAP_DIR="/var/lib/rancher/k3s/server/db/snapshots"
SERVER_DIR="/var/lib/rancher/k3s/server"
CONFIG_DIR="/etc/rancher/k3s"
RETENTION_COUNT=14
MIN_FREE_SPACE_KB=5242880 # 5 GB in KB
MANUAL_TEST=0
DATE=$(date +%Y%m%d-%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

phase() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $*" >&2
}

# 1. Prevent Overlapping Runs
mkdir -p "$(dirname "${LOCK_FILE}")" 2>/dev/null || true
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
    phase "PRECOND" "Another backup run is currently in progress. Exiting."
    exit 1
fi

# Single coherent exit/signal handling: interrupt & termination always exit
# non-zero (130/143) so a killed run can never report success.
cleanup() {
    local rc=$1
    if [ -n "${MOUNTED_BY_US:-}" ] && mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        umount "${MOUNT_POINT}" 2>/dev/null || umount -l "${MOUNT_POINT}" 2>/dev/null || true
    fi
    if [ -n "${TMP_STAGE:-}" ]; then
        rm -rf "${TMP_STAGE}" 2>/dev/null || true
    fi
    if [ -d "${MOUNT_POINT}" ] && [ -z "${MOUNT_EXISTED_BEFORE:-}" ]; then
        rmdir "${MOUNT_POINT}" 2>/dev/null || true
    fi
    if [ "${rc}" -ne 0 ]; then
        phase "FATAL" "Backup run completed with FAILURE (exit code ${rc})."
    fi
    exit ${rc}
}
trap 'cleanup $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log "=== Starting Non-Disruptive K3s etcd & Identity Backup ==="

# 2. Verify Root / K3s Preconditions
if [ "$(id -u)" -ne 0 ]; then
    phase "PRECOND" "This backup script must be executed as root."
    exit 1
fi

if ! command -v k3s >/dev/null 2>&1; then
    phase "PRECOND" "k3s binary not found in PATH."
    exit 1
fi

case "${1:-}" in
    ""|"--manual-test") : ;;
    *)  phase "PRECOND" "Unknown argument: $1 (supported: --manual-test)"; exit 1 ;;
esac
if [ "${1:-}" = "--manual-test" ]; then
    MANUAL_TEST=1
    log "Manual test mode: complete pipeline, no publish, no pruning."
fi

# 3. Verify Server-Token & Identity Files Exist
if [ ! -f "${SERVER_DIR}/token" ]; then
    phase "PRECOND" "Critical recovery file missing: ${SERVER_DIR}/token"
    exit 1
fi

TOKEN_SIZE=$(stat -c%s "${SERVER_DIR}/token" 2>/dev/null || echo 0)
if [ "${TOKEN_SIZE}" -lt 10 ]; then
    phase "PRECOND" "Server token exists but size is suspiciously small (${TOKEN_SIZE} bytes)."
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
    phase "SNAPSHOT" "Failed to locate generated snapshot file matching ${SNAPSHOT_NAME} in ${LOCAL_SNAP_DIR}."
    exit 1
fi

SNAP_SIZE=$(stat -c%s "${SNAP_FILE}")
if [ "${SNAP_SIZE}" -lt 10485760 ]; then # 10 MB
    phase "SNAPSHOT" "Snapshot file ${SNAP_FILE} is suspiciously small (${SNAP_SIZE} bytes). Integrity check failed."
    exit 1
fi
log "Snapshot generated successfully: $(basename "${SNAP_FILE}") (${SNAP_SIZE} bytes)."

# 5. Create Local Staging Archives for Configuration & Identity
TMP_STAGE=$(mktemp -d /tmp/k3s-backup-stage.XXXXXX)
chmod 0700 "${TMP_STAGE}"

log "Archiving K3s cluster configuration..."
tar -czf "${TMP_STAGE}/k3s-config.tar.gz" -C / etc/rancher/k3s/

log "Archiving server identity (token, tls certificates, and credentials)..."
tar -czf "${TMP_STAGE}/k3s-identity.tar.gz" \
    -C / var/lib/rancher/k3s/server/token \
         var/lib/rancher/k3s/server/node-token \
         var/lib/rancher/k3s/server/tls \
         var/lib/rancher/k3s/server/cred

# 6. Mount NAS Destination via NFS (bounded; identity-verified)
MOUNT_EXISTED_BEFORE=""
if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    MOUNT_EXISTED_BEFORE=1
    EXISTING_SRC=$(findmnt -n -o SOURCE "${MOUNT_POINT}" 2>/dev/null || echo "unknown")
    phase "MOUNT" "${MOUNT_POINT} is already mounted (source: ${EXISTING_SRC}). Refusing to use or unmount a foreign/stale mount."
    phase "MOUNT" "If this is a stale ${NAS_IP}:${NAS_PATH} mount, umount ${MOUNT_POINT} and re-run."
    exit 1
fi

mkdir -p "${MOUNT_POINT}"
log "Mounting remote backup target ${NAS_IP}:${NAS_PATH} (bounded by ${NAS_MOUNT_TIMEOUT_SECONDS}s timeout) ..."
if ! timeout "${NAS_MOUNT_TIMEOUT_SECONDS}" mount -t nfs -o rw,sync,hard "${NAS_IP}:${NAS_PATH}" "${MOUNT_POINT}"; then
    phase "MOUNT" "NFS mount of ${NAS_IP}:${NAS_PATH} failed or timed out after ${NAS_MOUNT_TIMEOUT_SECONDS}s. Aborting (e.g. NAS unreachable)."
    exit 1
fi

EXPECTED_NFS_SRC="${NAS_IP}:${NAS_PATH}"
ACTUAL_NFS_SRC=$(findmnt -n -o SOURCE "${MOUNT_POINT}" 2>/dev/null || echo "unknown")
if [ "${ACTUAL_NFS_SRC}" != "${EXPECTED_NFS_SRC}" ]; then
    phase "MOUNT" "Mount identity mismatch: expected '${EXPECTED_NFS_SRC}', got '${ACTUAL_NFS_SRC}'. Backups must never land on an unexpected filesystem."
    exit 1
fi
MOUNTED_BY_US=1
log "Mount verified: ${ACTUAL_NFS_SRC} at ${MOUNT_POINT}."

# 7. Check Destination Free Space
AVAILABLE_KB=$(df -P "${MOUNT_POINT}" | tail -1 | awk '{print $4}')
if [ "${AVAILABLE_KB}" -lt "${MIN_FREE_SPACE_KB}" ]; then
    phase "MOUNT" "Insufficient free space on NAS destination. Available: ${AVAILABLE_KB} KB, Required: ${MIN_FREE_SPACE_KB} KB."
    exit 1
fi
log "Destination free space check passed: $((AVAILABLE_KB / 1024)) MB available."

# 8. Atomic Off-Node Copy via Staging Directory
TMP_TARGET_DIR="${MOUNT_POINT}/.tmp-${DATE}"
TARGET_DIR="${MOUNT_POINT}/${DATE}"
# flock guarantees this run is alone; any .tmp-* still present is litter from an
# interrupted previous run and is safe to remove before publishing.
rm -rf "${MOUNT_POINT}"/.tmp-* 2>/dev/null || true
mkdir -p "${TMP_TARGET_DIR}"

log "Transferring snapshot and identity archives to temporary target on NAS..."
cp "${SNAP_FILE}" "${TMP_TARGET_DIR}/$(basename "${SNAP_FILE}")"
cp "${TMP_STAGE}/k3s-config.tar.gz" "${TMP_TARGET_DIR}/k3s-config.tar.gz"
cp "${TMP_STAGE}/k3s-identity.tar.gz" "${TMP_TARGET_DIR}/k3s-identity.tar.gz"

# 9. Verify the off-node copy BEFORE it is promoted to a backup directory
log "Verifying off-node copy integrity (sha256 + archive listing)..."
SRC_HASH=$(sha256sum "${SNAP_FILE}" | awk '{print $1}')
DST_HASH=$(sha256sum "${TMP_TARGET_DIR}/$(basename "${SNAP_FILE}")" | awk '{print $1}')
if [ "${SRC_HASH}" != "${DST_HASH}" ]; then
    phase "TRANSFER" "Snapshot checksum mismatch during NAS transfer. Aborting. src=${SRC_HASH} dst=${DST_HASH}"
    rm -rf "${TMP_TARGET_DIR}"
    exit 1
fi
log "Snapshot checksum verified: ${SRC_HASH}"

for archive in k3s-config.tar.gz k3s-identity.tar.gz; do
    if ! tar -tzf "${TMP_TARGET_DIR}/${archive}" >/dev/null 2>&1; then
        phase "VERIFY" "Archive ${archive} failed integrity listing on NAS. Aborting."
        rm -rf "${TMP_TARGET_DIR}"
        exit 1
    fi
done
log "Config and identity archives verified (tar -tzf)."

# Kuma heartbeat configuration (see runbook: backup-restore-runbook.md)
KUMA_TOKEN_FILE="/root/.kuma-etcd-push-token"
KUMA_HOST_CACHE="/root/.kuma-etcd-push-host-cache"

# 12. Push completion heartbeat to Uptime-Kuma (best-effort; never fails the backup).
# The push monitor "etcd-nas-backup" proves the FULL pipeline (snapshot + NAS publish
# + verification + retention) end to end. If pushes at the 6-hourly cadence stop,
# the monitor goes DOWN in Uptime-Kuma (dashboard-visible).
kuma_push() {
    local host
    host=$(k3s kubectl get svc -n monitoring uptime-kuma -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if ! [[ "${host:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Fall back to the cluster IP cached at the last successful push.
        host=$(tail -n 1 "${KUMA_HOST_CACHE}" 2>/dev/null || echo "")
    fi
    if ! [[ "${host:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log "Skipping Uptime-Kuma heartbeat: uptime-kuma service IP not resolvable."
        return 0
    fi
    local token
    if [ -s "${KUMA_TOKEN_FILE}" ]; then
        token=$(tr -d '\r\n' < "${KUMA_TOKEN_FILE}")
    else
        log "Skipping Uptime-Kuma heartbeat: token file absent (${KUMA_TOKEN_FILE})."
        return 0
    fi
    local out
    if out=$(curl -fsS --max-time 20 \
        "http://${host}/api/push/${token}?status=up&msg=etcd%20NAS%20backup%20published%20${DATE}%20(${PUBLISHED_MB}MB)" 2>&1); then
        log "Uptime-Kuma heartbeat pushed for backup ${DATE}."
        echo "${host}" > "${KUMA_HOST_CACHE}"
    else
        phase "HEARTBEAT" "Uptime-Kuma push failed (backup itself is intact): ${out}"
    fi
}

if [ "${MANUAL_TEST}" -eq 1 ]; then
    log "Manual test mode: pipeline verified up to publication point. NOT publishing ${TARGET_DIR}."
    log "Manual test mode: leaving ${TMP_TARGET_DIR} for inspection; it will be pruned at next real run."
    log "=== K3s Online etcd & Identity Backup MANUAL TEST OK ==="
    exit 0
fi

# Atomic rename from temporary target to final backup directory
mv "${TMP_TARGET_DIR}" "${TARGET_DIR}"
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

# 12. Completion heartbeat (best-effort; a monitoring failure must never fail the backup).
PUBLISHED_MB=$(du -sm "${TARGET_DIR}" 2>/dev/null | awk '{print $1}')
kuma_push

log "=== K3s Online etcd & Identity Backup Completed Successfully ==="
