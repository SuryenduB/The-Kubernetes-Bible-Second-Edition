#!/usr/bin/env bash
# verify-etcd-snapshot.sh: Inspect and verify K3s embedded etcd snapshots.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"

CONTROL_PLANE_IP="192.168.0.21"
SSH_USER="suryendub"

echo "=== K3s Embedded etcd Snapshot Verification ==="
echo "Target Control Plane Node: ${CONTROL_PLANE_IP} (${SSH_USER})"

# Fetch sudo password securely in-memory from SecretStore
SUDO_PASS=$(pwsh -NoProfile -Command 'Get-Secret -Name "k3s-homelab-sudo" -AsPlainText' 2>/dev/null || echo "")

REMOTE_CHECK=$(cat <<'EOF'
echo "--- K3S ETCD-SNAPSHOT LIST ---"
k3s etcd-snapshot list 2>/dev/null || echo "k3s etcd-snapshot command failed or not a server"

echo "--- LOCAL SNAPSHOT DIRECTORY ---"
SNAPSHOT_DIR="/var/lib/rancher/k3s/server/db/snapshots"
if [ -d "${SNAPSHOT_DIR}" ]; then
  ls -lh "${SNAPSHOT_DIR}"
  LATEST_SNAP=$(ls -t "${SNAPSHOT_DIR}" | head -n 1)
  if [ -n "${LATEST_SNAP}" ]; then
    echo "Latest snapshot: ${LATEST_SNAP}"
    SNAP_SIZE=$(stat -c%s "${SNAPSHOT_DIR}/${LATEST_SNAP}")
    echo "Size in bytes: ${SNAP_SIZE}"
    if [ "${SNAP_SIZE}" -gt 10000000 ]; then
      echo "Status: Snapshot size check PASSED (>10MB)"
    else
      echo "Status: WARNING - Snapshot size seems suspiciously small (<10MB)"
    fi
  fi
else
  echo "Snapshot directory does not exist: ${SNAPSHOT_DIR}"
fi

echo "--- ETCD DATA DIRECTORY ---"
ls -ld /var/lib/rancher/k3s/server/db/etcd 2>/dev/null || true
du -sh /var/lib/rancher/k3s/server/db/etcd 2>/dev/null || true
EOF
)

if [ -n "${SUDO_PASS}" ]; then
  printf "%s\n%s\n" "${SUDO_PASS}" "${REMOTE_CHECK}" | \
    ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${CONTROL_PLANE_IP}" \
      "sudo -S -p '' bash -s 2>/dev/null" | "${REDACT}"
else
  ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${CONTROL_PLANE_IP}" \
    "bash -c '${REMOTE_CHECK}'" | "${REDACT}"
fi


echo "=== Verification complete ==="
