#!/usr/bin/env bash
# sweep.sh - one uniform disk measurement of every K3s homelab node.
#
# Why this exists: per-node totals are only comparable when every node is
# measured with the same command, from the same namespace, at the same moment.
# This runs the measurement inside the node-disk-cleanup DaemonSet pods, which
# are already privileged + hostPID, so it needs no SSH and reaches nodes whose
# SSH is unreachable from the Mac (server-236, server-252).
#
# Both the Kubernetes node name and the hostname are printed: they differ for
# server-236 ("install-Virtual-Machine") and server-252 ("k3s-master"), and
# confusing those is a known source of misattributed measurements.
#
# Rows are rounded to whole MiB and the TOTAL is the sum of the printed rows,
# so the table's arithmetic can be checked by eye.
#
# Usage (from the repo root):
#   k3s-storage-cleanup/scripts/sweep.sh
#   k3s-storage-cleanup/scripts/sweep.sh > before.txt
#
# Env: NS (default monitoring), SELECTOR (default app=node-disk-cleanup),
#      CONTAINER (default cleanup-loop).
set -uo pipefail

NS="${NS:-monitoring}"
SELECTOR="${SELECTOR:-app=node-disk-cleanup}"
CONTAINER="${CONTAINER:-cleanup-loop}"

command -v kubectl >/dev/null 2>&1 || { echo "sweep: kubectl not found" >&2; exit 1; }

pods="$(kubectl -n "$NS" get pods -l "$SELECTOR" \
          -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{"\n"}{end}' 2>/dev/null)"
if [ -z "${pods// /}" ]; then
  cat >&2 <<'EOF'
sweep: no measurement pods found.
The measurement runs inside a privileged hostPID pod (nsenter -t 1), so it
needs the cleanup DaemonSet. Restore it first:

  kubectl apply -f kubernetes-manifests/monitoring/node-disk-cleanup.yaml

Then re-run. To measure a single node by hand instead:
  printf 'df -P -k / | tail -1\n' | k3s-homelab-optimisation/scripts/remote-admin.sh suryendub@<ip>
EOF
  exit 1
fi

raw="$(mktemp)"
trap 'rm -f "$raw"' EXIT

while read -r pod node; do
  [ -n "${pod:-}" ] || continue
  out="$(kubectl -n "$NS" exec -i "$pod" -c "$CONTAINER" -- \
           nsenter -t 1 -m -u -i -n -p -- sh -s "$node" 2>/dev/null <<'REMOTE'
node="${1:-unknown}"
h=$(hostname)
set -- $(df -P -k / | tail -1)
total=${2:-0}; used=${3:-0}; pct=${5:-?}
imgs=$(crictl images -q 2>/dev/null | wc -l)
snap=$(du -sk /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs 2>/dev/null | cut -f1)
cont=$(du -sk /var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content 2>/dev/null | cut -f1)
lh=$(du -sk /var/lib/longhorn 2>/dev/null | cut -f1)
dock=$(du -sk /var/lib/docker 2>/dev/null | cut -f1)
jcap=$(grep -rhsE '^[[:space:]]*SystemMaxUse' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null | tail -1 | cut -d= -f2)
jrnl=$(journalctl --disk-usage 2>/dev/null | sed -E 's/.*take up //; s/ in the file system.*//')
echo "$node|$h|$used|$total|$pct|${imgs:-0}|$(( ${snap:-0} + ${cont:-0} ))|${lh:-0}|${dock:-0}|${jcap:-none}|${jrnl:-?}"
REMOTE
)"
  if [ -z "$out" ]; then
    echo "sweep: pod $pod ($node) unreadable, node skipped" >&2
    continue
  fi
  echo "$out" >> "$raw"
done <<< "$pods"

if [ ! -s "$raw" ]; then
  echo "sweep: every node failed; nothing measured" >&2
  exit 1
fi

sort -t'|' -k1,1 "$raw" | awk -F'|' '
BEGIN {
  printf "%-22s %-24s %9s %10s %4s %5s %14s %12s %11s %6s %9s\n",
         "NODE", "HOSTNAME", "USED_MIB", "TOTAL_MIB", "%", "IMGS", "CONTAINERD_MIB", "LONGHORN_MIB", "DOCKER_MIB", "JCAP", "JOURNAL"
  rule()
}
function rule() {
  printf "%-22s %-24s %9s %10s %4s %5s %14s %12s %11s %6s %9s\n",
         "----------------------", "------------------------", "---------", "----------", "----", "-----", "--------------", "------------", "-----------", "------", "---------"
}
{
  u = int($3 / 1024 + 0.5); t = int($4 / 1024 + 0.5)
  c = int($7 / 1024 + 0.5); l = int($8 / 1024 + 0.5); d = int($9 / 1024 + 0.5)
  printf "%-22s %-24s %9d %10d %4s %5d %14d %12d %11d %6s %9s\n",
         $1, $2, u, t, $5, $6, c, l, d, $10, $11
  su += u; st += t; sc += c; sl += l; sd += d; si += $6; n++
}
END {
  rule()
  printf "%-22s %-24s %9d %10d %4s %5d %14d %12d %11d %6s %9s\n",
         "TOTAL (" n " nodes)", "MiB", su, st, "", si, sc, sl, sd, "", ""
  printf "%-22s %-24s %9.1f %10.1f %4s %5s %14.1f %12.1f %11.1f %6s %9s\n",
         "", "GiB", su / 1024, st / 1024, "", "", sc / 1024, sl / 1024, sd / 1024, "", ""
}'
