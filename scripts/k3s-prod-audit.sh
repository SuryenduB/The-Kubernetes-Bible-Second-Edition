#!/bin/bash
# k3s-prod-audit.sh - Node-level audit script
set -e
TS=$(date +%s)
HN=$(hostname)
OD="/tmp/audit-$HN-$TS"
mkdir -p "$OD"

echo ">>> Audit started on $HN at $TS"

# 1. System
uname -a > "$OD/system.txt"
free -h >> "$OD/system.txt"
uptime >> "$OD/system.txt"

# 2. K3s
if command -v k3s &> /dev/null; then
    k3s --version > "$OD/k3s_version.txt"
fi
systemctl status k3s* --no-pager > "$OD/k3s_service.txt" 2>&1 || true

# 3. Certs
if [ -d /var/lib/rancher/k3s/server/tls ]; then
    find /var/lib/rancher/k3s/server/tls -name "*.crt" -exec sh -c 'echo "--- $1 ---" && openssl x509 -enddate -noout -in "$1"' -- {} \; > "$OD/certs.txt"
fi

# 4. Disk
df -h > "$OD/disk.txt"
mount | grep longhorn > "$OD/longhorn.txt" || true

# 5. Net
ip addr > "$OD/net.txt"

# 6. Reg
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    sed 's/password: .*/password: [REDACTED]/' /etc/rancher/k3s/registries.yaml > "$OD/reg.txt"
fi

# 7. Log
journalctl -u k3s* -n 50 --no-pager > "$OD/k3s.log" 2>&1 || true

# Package
BP="/tmp/k3s-prod-audit-$HN.tar.gz"
tar -czf "$BP" -C /tmp "audit-$HN-$TS"
chmod 644 "$BP"
rm -rf "$OD"

echo ">>> Audit complete: $BP"
