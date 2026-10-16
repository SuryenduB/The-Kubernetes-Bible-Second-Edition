#!/usr/bin/env bash
# ==============================================================================
# remote-admin.sh: Run a bash script as root on an allowlisted homelab node.
#
# USAGE:
#   scripts/remote-admin.sh suryendub@192.168.0.21 < script.sh
#   scripts/remote-admin.sh suryendub@192.168.0.21 script.sh
#
# SECURITY CONTRACT:
#   - The sudo password is fetched in-memory from the PowerShell SecretStore
#     (vault LocalStore, secret "k3s-homelab-sudo"). It is piped to the remote
#     `sudo -S` over stdin and NEVER appears in argv, SSH command strings,
#     files, or logs.
#   - SSH host-key verification stays at the user's default (enabled).
#   - Output passes through redact-output.sh before being returned.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"

TARGET="${1:?usage: remote-admin.sh <user@host> [script-file]}"

# Allowlist: only the seven active homelab management addresses.
case "${TARGET}" in
  suryendub@192.168.0.19|\
  suryendub@192.168.0.20|\
  suryendub@192.168.0.21|\
  suryendub@192.168.0.22|\
  suryendub@192.168.0.23|\
  suryendub@192.168.0.24|\
  suryendub@192.168.0.25)
    ;;
  *)
    echo "[remote-admin] ERROR: target ${TARGET} is not an allowlisted homelab node." >&2
    exit 2
    ;;
esac

if [ -n "${2:-}" ]; then
  if [ ! -f "${2}" ]; then
    echo "[remote-admin] ERROR: script file not found: ${2}" >&2
    exit 2
  fi
  REMOTE_SCRIPT="$(cat "${2}")"
else
  REMOTE_SCRIPT="$(cat)"
fi

if [ -z "${REMOTE_SCRIPT}" ]; then
  echo "[remote-admin] ERROR: empty remote script." >&2
  exit 2
fi

SUDO_PASS="$(pwsh -NoProfile -Command 'Get-Secret -Name "k3s-homelab-sudo" -AsPlainText' 2>/dev/null || true)"
if [ -z "${SUDO_PASS}" ]; then
  echo "[remote-admin] ERROR: could not fetch sudo secret from SecretStore. Aborting." >&2
  exit 2
fi
# Never leak the secret on abnormal exit.
trap 'unset SUDO_PASS 2>/dev/null || true' EXIT INT TERM

printf '%s\n%s\n' "${SUDO_PASS}" "${REMOTE_SCRIPT}" | \
  ssh -o BatchMode=yes -o ConnectTimeout=8 "${TARGET}" "sudo -S -p '' bash -s" 2>&1 | "${REDACT}"
