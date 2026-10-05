#!/bin/sh
# k7-watchdog.sh - health-triggered reboot watchdog for kubernetes7.
#
# Runs hourly from systemd timer. Reboots ONLY when the K3s runtime is actually
# sick (k3s-agent down or containerd unresponsive) on two consecutive runs,
# and at most once per 6 hours (cooldown file). A healthy node is never
# rebooted. SMART pending-sector growth is logged for early disk-failure
# warning but never triggers a reboot by itself.
#
# State: /var/lib/k7-watchdog/ | Log: /var/log/k7-watchdog.log

STATE_DIR=/var/lib/k7-watchdog
LOG=/var/log/k7-watchdog.log
FAIL_FILE="$STATE_DIR/consec_failures"
LAST_REBOOT_FILE="$STATE_DIR/last_reboot_epoch"
SMART_FILE="$STATE_DIR/smart_pending"
COOLDOWN_SEC=21600
CRICTL="crictl -r unix:///run/k3s/containerd/containerd.sock"

mkdir -p "$STATE_DIR"
log() { echo "$(date -Is) $1" >>"$LOG"; }

failures=0

# 1. k3s-agent must be active.
if ! systemctl is-active --quiet k3s-agent; then
    log "FAIL: k3s-agent not active"
    failures=$((failures + 1))
fi

# 2. containerd must answer (this is what wedged on 2026-10-04: sandbox
#    reservations leaked, new pods stuck ContainerCreating, exec EOF).
if ! $CRICTL ps >/dev/null 2>&1; then
    log "FAIL: containerd unresponsive"
    failures=$((failures + 1))
fi

# 3. SMART watch (informational only): log pending-sector growth.
if command -v smartctl >/dev/null 2>&1; then
    pending=$(smartctl -A /dev/sda 2>/dev/null | awk '/Current_Pending_Sector/{print $10}')
    if [ -n "$pending" ]; then
        if [ -f "$SMART_FILE" ]; then
            prev=$(cat "$SMART_FILE")
            if [ "$pending" -gt "$prev" ]; then
                log "WARN: SMART Current_Pending_Sector grew ${prev} -> ${pending} (/dev/sda degrading)"
            fi
        fi
        echo "$pending" >"$SMART_FILE"
    fi
fi

if [ "$failures" -eq 0 ]; then
    echo 0 >"$FAIL_FILE"
    exit 0
fi

consec=0
[ -f "$FAIL_FILE" ] && consec=$(cat "$FAIL_FILE")
consec=$((consec + 1))
echo "$consec" >"$FAIL_FILE"
log "FAIL: ${failures} check(s) failed, ${consec} consecutive failing run(s)"

if [ "$consec" -lt 2 ]; then
    log "INFO: waiting for one more consecutive failure before rebooting"
    exit 0
fi

now=$(date +%s)
last=0
[ -f "$LAST_REBOOT_FILE" ] && last=$(cat "$LAST_REBOOT_FILE")
if [ $((now - last)) -lt $COOLDOWN_SEC ]; then
    log "INFO: cooldown active, skipping reboot"
    exit 0
fi

log "ACTION: rebooting (runtime sick twice in a row, cooldown expired)"
echo "$now" >"$LAST_REBOOT_FILE"
echo 0 >"$FAIL_FILE"
/sbin/reboot
