#!/usr/bin/env bash
# collect-node-state.sh: Collect detailed Linux and K3s node diagnostics from all nodes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"
OUT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"

NODES=(
  "nuc:192.168.0.21:suryendub"
  "kubernetes1:192.168.0.19:suryendub"
  "kubernetes2:192.168.0.20:suryendub"
  "kubernetes3:192.168.0.22:suryendub"
  "kubernetes4:192.168.0.23:suryendub"
  "kubernetes5:192.168.0.24:suryendub"
  "kubernetes6:192.168.0.25:suryendub"
)

# Fetch sudo password securely in-memory from PowerShell SecretStore
SUDO_PASS=$(pwsh -NoProfile -Command 'Get-Secret -Name "k3s-homelab-sudo" -AsPlainText' 2>/dev/null || echo "")

for entry in "${NODES[@]}"; do
  IFS=":" read -r name ip user <<< "${entry}"
  report_file="${OUT_DIR}/node-state-${name}-${TIMESTAMP}.txt"
  echo ">>> Collecting node diagnostics for ${name} (${ip}) ..."
  echo "=== Node Diagnostic Report: ${name} (${ip}) at $(date) ===" | tee "${report_file}"

  # Test connectivity
  if ! ssh -o BatchMode=yes -o ConnectTimeout=3 "${user}@${ip}" "true" 2>/dev/null; then
    echo "[-] Cannot reach ${name} (${ip}) via SSH. Skipping." | tee -a "${report_file}"
    continue
  fi

  remote_script=$(cat <<'EOF'
echo "--- HOSTNAMECTL ---"
hostnamectl || true
echo "--- UNAME ---"
uname -a || true
echo "--- OS RELEASE ---"
cat /etc/os-release || true
echo "--- VIRTUALIZATION ---"
systemd-detect-virt || true
echo "--- CPU INFO ---"
lscpu | grep -E "Model name|CPU\(s\):|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\):|CPU max MHz|CPU min MHz" || true
echo "--- MEMORY & SWAP ---"
free -h || true
swapon --show || true
echo "--- BLOCK DEVICES ---"
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,ROTA || true
echo "--- FILESYSTEM USAGE ---"
df -hT || true
echo "--- INODE USAGE ---"
df -i || true
echo "--- NETWORK INTERFACES ---"
ip -brief address || true
echo "--- IP ROUTES ---"
ip route || true
echo "--- TIMEDATECTL ---"
timedatectl || true
echo "--- SYSCTL VALUES ---"
sysctl vm.swappiness fs.inotify.max_user_instances fs.inotify.max_user_watches net.ipv4.ip_forward || true
echo "--- FAILED SYSTEMD SERVICES ---"
systemctl --failed --no-pager || true
echo "--- K3S SERVICE STATUS ---"
systemctl status k3s --no-pager || true
systemctl status k3s-agent --no-pager || true
EOF
)

  echo -e "\n=== Standard System Discovery ===" >> "${report_file}"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "${user}@${ip}" "${remote_script}" 2>&1 | "${REDACT}" >> "${report_file}"

  if [ -n "${SUDO_PASS}" ]; then
    echo -e "\n=== Privileged K3s Discovery ===" >> "${report_file}"
    remote_sudo_script=$(cat <<'EOF'
echo "--- K3S CONFIGS ---"
if [ -f /etc/rancher/k3s/config.yaml ]; then
  echo "/etc/rancher/k3s/config.yaml:"
  cat /etc/rancher/k3s/config.yaml
fi
if [ -d /etc/rancher/k3s/config.yaml.d ]; then
  echo "/etc/rancher/k3s/config.yaml.d/ contents:"
  ls -la /etc/rancher/k3s/config.yaml.d/
  cat /etc/rancher/k3s/config.yaml.d/*.yaml 2>/dev/null || true
fi
if [ -f /etc/rancher/k3s/registries.yaml ]; then
  echo "/etc/rancher/k3s/registries.yaml:"
  cat /etc/rancher/k3s/registries.yaml
fi
if [ -f /etc/systemd/system/k3s.service ]; then
  echo "/etc/systemd/system/k3s.service:"
  cat /etc/systemd/system/k3s.service
fi
if [ -f /etc/systemd/system/k3s-agent.service ]; then
  echo "/etc/systemd/system/k3s-agent.service:"
  cat /etc/systemd/system/k3s-agent.service
fi
if [ -d /var/lib/rancher/k3s/server/manifests ]; then
  echo "/var/lib/rancher/k3s/server/manifests/ files:"
  ls -la /var/lib/rancher/k3s/server/manifests/
fi
if command -v k3s >/dev/null 2>&1; then
  echo "--- ETCD SNAPSHOTS (if server) ---"
  k3s etcd-snapshot list 2>/dev/null || true
fi
echo "--- RECENT K3S JOURNAL ERRORS ---"
journalctl -u k3s -u k3s-agent --priority=err --since "24 hours ago" --no-pager | tail -n 30 || true
EOF
    printf "%s\n%s\n" "${SUDO_PASS}" "${remote_sudo_script}" | ssh -o BatchMode=yes -o ConnectTimeout=5 "${user}@${ip}" "sudo -S -p '' bash -s 2>/dev/null" 2>&1 | "${REDACT}" >> "${report_file}"
  fi


  echo "Finished ${name}. Report saved to ${report_file}"
done

echo "=== All node diagnostics collected successfully ==="
