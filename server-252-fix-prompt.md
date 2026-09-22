# Task: Diagnose and permanently fix server-252 network flapping (k3s worker node)

## Context

server-252 (192.168.0.252) is a worker node in a k3s cluster (v1.34.6+k3s1) running Longhorn
v1.12.1 storage. The host **repeatedly drops off the network entirely** (100% packet loss,
SSH unreachable, kubelet stops posting status → node flaps Ready/NotReady roughly hourly).
It last went down while Longhorn was rebuilding replicas and pulling container images,
i.e. **under heavy network/disk load**. When it returns, it stays up for ~30–60 minutes,
then vanishes again. The whole host becomes unreachable, so this is a host/NIC/hardware
level fault — Kubernetes and Longhorn are victims, not the cause.

Node facts:
- Ubuntu 20.04 LTS, kernel 5.4.0-216-generic
- containerd 2.2.2 (k3s-bundled), k3s-agent service
- Was rebuilt and rejoined to the cluster recently (Sept 2026)
- No known IPMI/console configured; physical access is possible if needed

Cluster facts (do not break these):
- Control node: 192.168.0.21 (user `suryendub`, sudo via `echo 558068 | sudo -S`)
- Other healthy workers: kubernetes1–7 (192.168.0.20–26), nuc (192.168.0.21), server-236
  (192.168.0.236)
- Longhorn volumes are currently 37/37 healthy WITHOUT server-252; do not take any action
  that destabilizes the other nodes.
- server-252 hosts Longhorn replicas (default-disk under /var/lib/longhorn/). When it
  rejoins, Longhorn will rebuild replicas onto it — this is expected and fine.

## Access

- When the node is UP: `sshpass -p 558068 ssh -o StrictHostKeyChecking=no SuryenduB@192.168.0.252`
  (note capital S in username; password `558068`; sudo with `echo 558068 | sudo -S`)
- When the node is DOWN: it is fully unreachable (no SSH, no ping). You must either wait
  for it to flap back, or instruct the user to power-cycle it. Ask the user to do that
  rather than blocking indefinitely.
- Cluster state from the control node:
  `sshpass -p 558068 ssh suryendub@192.168.0.21 'echo 558068 | sudo -S k3s kubectl get nodes'`

## Objectives

### 1. Identify the root cause (while the node is up, or from logs after reboot)

Run and collect:
- `ethtool -i <primary NIC>` and `lspci -nnk | grep -A3 Ethernet` — identify NIC model/driver
  (suspect Realtek r8168/r8169 or similar).
- `sudo dmesg -T | grep -iE "watchdog|NETDEV|link is down|r8169|e1000|igb|pcie|aer|thermal"`
  — look for `NETDEV WATCHDOG: transmit queue timed out`, PCIe AER errors, link flaps,
  thermal shutdowns.
- `sudo journalctl -b -1 -p err..alert --no-pager | tail -50` — errors from the PREVIOUS
  boot (the crash window). If empty, enable persistent journald
  (`Storage=persistent` in /etc/systemd/journald.conf) so the next crash is captured.
- `sudo journalctl -u k3s-agent -b --no-pager | tail -30` — confirm k3s-agent itself was
  healthy when the network died (it should just lose connectivity, not crash first).
- Thermal: `sensors` (install lm-sensors if missing), check for overheating history.
- Power: `sudo ethtool <NIC> | grep Wake-on`, and check PCIe ASPM:
  `cat /sys/module/pcie_aspm/parameters/policy`.
- SMART data on the system disk: `sudo smartctl -a /dev/sda` — rule out disk hang causing
  full system stall (a hung root disk also makes the host drop off the network).

### 2. Apply the appropriate fix (based on findings)

Likely candidates, in rough priority:
a. **NIC driver fix**: if Realtek r8169 with watchdog timeouts — install `r8168-dkms`
   (blacklist r8169) or upgrade the kernel to the 20.04 HWE stack (5.15) via
   `apt install linux-generic-hwe-20.04`. A kernel upgrade also fixes many 5.4-era NIC bugs.
b. **Disable NIC power management**: `ethtool -s <NIC> wol d` (persist via netplan or a
   systemd unit), disable EEE (`ethtool --set-eee <NIC> eee off` if supported), and if
   ASPM is implicated add `pcie_aspm=off` to GRUB_CMDLINE_LINUX_DEFAULT + update-grub.
c. **If thermal/SMART implicates hardware**: report clearly and stop — that's a physical
   fix, not software.
d. Whatever the fix, **capture persistent logs first** so a recurrence is diagnosable.

### 3. Rejoin and validate

- Reboot the node if the fix requires it (warn the user first — coordinate timing).
- After reboot: verify `systemctl is-active k3s-agent` is active, node shows Ready:
  `kubectl get node server-252`, and Longhorn node status:
  `kubectl get nodes.longhorn.io -n longhorn-system server-252`.
- **Load test**: generate sustained network load for at least 30–60 minutes (e.g.
  `iperf3` against the control node, or trigger a Longhorn replica rebuild) and confirm
  zero link drops / zero `NotReady` transitions. The node previously died under exactly
  this load, so this is the acceptance test.
- Confirm no `NETDEV WATCHDOG` or link-down messages in dmesg during the load test.

### 4. Report

Produce a short report: root cause (with log evidence), fix applied, load-test result,
and any remaining hardware concerns. If you could not reproduce the failure after the
fix, say so explicitly and list what monitoring to watch (e.g. node Ready flapping,
`kubectl get events --field-selector involvedObject.name=server-252`).

## Constraints

- Do NOT modify anything on other cluster nodes or the control plane.
- Do NOT uninstall/reinstall k3s or wipe /var/lib/longhorn or /var/lib/rancher on
  server-252 — the node must rejoin with its identity and replica data intact.
- Do NOT change the node's IP (192.168.0.252) or hostname.
- If the node is down and stays down >15 min, ask the user to physically power-cycle it.
- If evidence points to failing hardware (NIC, PSU, thermals), stop and report instead of
  papering over it with software.
