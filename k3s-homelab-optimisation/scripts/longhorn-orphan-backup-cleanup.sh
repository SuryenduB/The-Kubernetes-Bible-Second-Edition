#!/usr/bin/env bash
# ==============================================================================
# longhorn-orphan-backup-cleanup.sh: prune backups of deleted Longhorn volumes
#
# WHY THIS EXISTS
#   Deleting a PVC does not cascade to its Longhorn backups. On 2026-11-22 the
#   homelab had 430 backups for 40 volumes that no longer existed (0 PVCs, 0
#   VolumeSnapshots): 5.62 GiB on the NAS. `backup-daily` retains only 14, but
#   retention never applies once the volume is gone.
#
# SAFETY INVARIANTS (all must hold before a backup is a candidate)
#   1. The volume is NOT a current Longhorn Volume.
#   2. No PVC in any namespace references the volume (`spec.volumeName`).
#   3. No VolumeSnapshot/VolumeSnapshotContent mentions the volume anywhere.
#   4. The volume is NOT in the optional keep list
#      (/etc/longhorn-orphan-backup-cleanup/keep-volumes.txt, one name per line).
#   5. The backup is older than LONGHORN_ORPHAN_BACKUP_MIN_AGE_DAYS (default 30).
#   6. The candidate set is regenerated immediately before deletion, and each
#      object's existence is re-checked one at a time.
#
# Deletion is IRREVERSIBLE: Longhorn removes the backup from the backupstore.
# The age floor and keep list are the recovery window. Run --help first.
#
# USAGE
#   sudo ./longhorn-orphan-backup-cleanup.sh              # dry run (default)
#   sudo ./longhorn-orphan-backup-cleanup.sh --apply      # perform deletions
#   LONGHORN_ORPHAN_BACKUP_MIN_AGE_DAYS=90 sudo ... --apply
#
# SCHEDULE (nuc, weekly, after the 18:00 backup slot)
#   0 3 * * 0 /usr/local/bin/longhorn-orphan-backup-cleanup.sh --apply \
#     >> /var/log/longhorn-orphan-backup-cleanup.log 2>&1
# ==============================================================================
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LOCK_FILE="/var/run/longhorn-orphan-backup-cleanup.lock"
NAMESPACE="longhorn-system"
KEEP_FILE="${LONGHORN_ORPHAN_BACKUP_KEEP_FILE:-/etc/longhorn-orphan-backup-cleanup/keep-volumes.txt}"
MIN_AGE_DAYS="${LONGHORN_ORPHAN_BACKUP_MIN_AGE_DAYS:-30}"
APPLY=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] $*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    "") ;;
    --apply) APPLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (supported: --apply, --help)" ;;
esac

[ "$(id -u)" -eq 0 ] || die "Run as root (kubectl needs cluster admin)."
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH."
command -v python3 >/dev/null 2>&1 || die "python3 not found in PATH."

mkdir -p "$(dirname "${LOCK_FILE}")" 2>/dev/null || true
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
    die "Another orphan-backup cleanup is already running."
fi

CANDIDATES=$(mktemp)
FRESH=$(mktemp)
trap 'rm -f "${CANDIDATES}" "${FRESH}"' EXIT

# Build the eligibility table. One uniform snapshot of cluster state.
collect_candidates() {
    python3 - "${MIN_AGE_DAYS}" "${KEEP_FILE}" > "$1" <<'PYCODE'
import datetime, json, os, subprocess, sys

min_age_days = int(sys.argv[1])
keep_file = sys.argv[2]

def get(*args, optional=False):
    result = subprocess.run(["kubectl", *args, "-o", "json"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        if optional:
            return {"items": []}
        sys.stderr.write(result.stderr)
        sys.exit(1)
    return json.loads(result.stdout)

longhorn_volumes = {
    item["metadata"]["name"]
    for item in get("get", "volumes.longhorn.io", "-n", "longhorn-system")["items"]
}
pvc_volumes = {
    item.get("spec", {}).get("volumeName")
    for item in get("get", "pvc", "-A")["items"]
    if item.get("spec", {}).get("volumeName")
}
snapshot_blob = json.dumps(
    get("get", "volumesnapshots", "-A", optional=True)
) + json.dumps(
    get("get", "volumesnapshotcontents", optional=True)
)
keep_volumes = set()
if os.path.isfile(keep_file):
    with open(keep_file, encoding="utf-8") as handle:
        keep_volumes = {
            line.strip() for line in handle
            if line.strip() and not line.lstrip().startswith("#")
        }

backups = get("get", "backups.longhorn.io", "-n", "longhorn-system")["items"]
now = datetime.datetime.now(datetime.timezone.utc)
eligible = []
for backup in backups:
    metadata = backup.get("metadata", {})
    status = backup.get("status", {})
    volume = status.get("volumeName") or metadata.get("labels", {}).get("backup-volume")
    name = metadata.get("name", "")

    # Guard 1: volume must be gone from Longhorn.
    if volume in longhorn_volumes:
        continue
    # Guard 2: no surviving PVC may reference it.
    if volume in pvc_volumes:
        continue
    # Guard 3: no VolumeSnapshot may mention it.
    if volume and volume in snapshot_blob:
        continue
    # Guard 4: owner keep list.
    if volume in keep_volumes:
        continue
    # Guard 5: recovery window.
    created = metadata.get("creationTimestamp", "")
    try:
        age_days = (now - datetime.datetime.fromisoformat(
            created.replace("Z", "+00:00"))).days
    except (ValueError, AttributeError):
        continue
    if age_days < min_age_days:
        continue

    size_bytes = 0
    try:
        size_bytes = int(status.get("size", 0) or 0)
    except (TypeError, ValueError):
        pass
    eligible.append((name, volume or "unknown", age_days, size_bytes))

for name, volume, age_days, size_bytes in sorted(eligible, key=lambda row: row[0]):
    print(f"{name}\t{volume}\t{age_days}\t{size_bytes}")
PYCODE
}

collect_candidates "${CANDIDATES}"
candidate_count=$(wc -l < "${CANDIDATES}" | tr -d ' ')
total_bytes=$(awk -F'\t' '{s+=$4} END {print s+0}' "${CANDIDATES}")

log "Eligibility: min age ${MIN_AGE_DAYS}d; keep file ${KEEP_FILE} ($([ -f "${KEEP_FILE}" ] && echo present || echo absent))."
log "Candidates: ${candidate_count} backup(s), $(awk -F'\t' '{s+=$4} END {printf "%.2f", s/1024/1024/1024}' "${CANDIDATES}") GiB (backup CR sizes, NOT filesystem bytes)."

if [ "${candidate_count}" -eq 0 ]; then
    log "Nothing to do."
    exit 0
fi

printf '%-26s %-42s %6s %10s\n' "BACKUP" "VOLUME" "AGE_D" "MiB"
while IFS=$'\t' read -r name volume age size; do
    printf '%-26s %-42s %6s %10.1f\n' \
        "${name}" "${volume}" "${age}" "$(awk -v b="${size}" 'BEGIN {print b/1024/1024}')"
done < "${CANDIDATES}"

if [ "${APPLY}" -eq 0 ]; then
    log "DRY RUN - no changes made. Re-run with --apply to delete."
    exit 0
fi

# Revalidate the whole set immediately before the first deletion.
collect_candidates "${FRESH}"
deleted=0
deleted_bytes=0
declare -A affected_volumes

while IFS=$'\t' read -r name volume age size; do
    # The object must still exist and still be in the fresh candidate set.
    if ! grep -qF "${name}	" "${FRESH}"; then
        log "SKIP ${name}: no longer eligible."
        continue
    fi
    if ! kubectl -n "${NAMESPACE}" get "backups.longhorn.io" "${name}" >/dev/null 2>&1; then
        log "SKIP ${name}: already gone."
        continue
    fi
    if kubectl -n "${NAMESPACE}" delete "backups.longhorn.io" "${name}" \
        --wait=true --timeout=120s >/dev/null 2>&1; then
        deleted=$((deleted + 1))
        deleted_bytes=$((deleted_bytes + size))
        affected_volumes["${volume}"]=1
        log "DELETED ${name} (${volume}, ${age}d)."
    else
        log "FAILED ${name}; continuing with the rest."
    fi
done < "${CANDIDATES}"

# Remove BackupVolume CRs only for volumes with no remaining backups.
backupvolumes_removed=0
for volume in "${!affected_volumes[@]}"; do
    remaining=$(kubectl -n "${NAMESPACE}" get backups.longhorn.io \
        -l "backup-volume=${volume}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [ "${remaining}" -ne 0 ] && continue
    kubectl -n "${NAMESPACE}" get backupvolumes.longhorn.io -o name 2>/dev/null \
        | grep -F "backupvolumes.longhorn.io/${volume}" | while read -r object; do
            if kubectl -n "${NAMESPACE}" delete "${object}" \
                --wait=true --timeout=120s >/dev/null 2>&1; then
                log "DELETED ${object} (no backups remain)."
            fi
        done
    backupvolumes_removed=$((backupvolumes_removed + 1))
done

log "Done: ${deleted}/${candidate_count} backup(s) deleted, $(printf '%.2f' "$(awk -v b="${deleted_bytes}" 'BEGIN {print b/1024/1024/1024}')") GiB of backup CR size, ${backupvolumes_removed} volume record(s) reconciled."
[ "${deleted}" -eq "${candidate_count}" ] || die "Some deletions failed or lost eligibility; investigate."
