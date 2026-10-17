# K3s Homelab Approval-Required Change Proposals

**Document Status:** APP-01 through APP-05 APPLIED & VERIFIED 2026-10-17; APP-06 excluded (architecture change outside mission scope)  
**Operating Boundary:** Originally drafted under the **Ralph Loop Change Boundary** (no live changes). The catalog was subsequently approved and executed the same day; execution evidence is recorded in `docs/change-log.md` §7–§9.

Each proposed change includes technical rationale grounded in measured evidence, prepared assets, verification commands, and rollback procedures.

---

## 1. Approval Catalog Summary

| Item ID | Category | Change Title | Risk Level | Prepared Asset | Decision / Dependency |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **APP-01** | Backup & DR | Replace disruptive 02:00 UTC K3s shutdown cron with atomic etcd & identity backup | Low | `scripts/k3s-etcd-safe-backup.sh` | ✅ Applied & verified 2026-10-17 (change-log §7) |
| **APP-02** | DNS & HA | Scale CoreDNS to 2 replicas with host spread and PDB | Low | `kubernetes/monitoring/coredns-ha-patch.yaml` | ✅ Applied & verified 2026-10-17 — incl. failover drill (change-log §7) |
| **APP-03** | Storage | Remove default StorageClass flag from `local-path` via annotation patch | Very Low | Minimal annotation patch command | ✅ Applied & verified 2026-10-17 (change-log §7) |
| **APP-04A** | Node OS | Apply sysctl `fs.inotify.max_user_instances=8192` across active nodes | Very Low | `ansible/playbooks/node-tune.yaml` | ✅ Applied & verified 2026-10-17 (change-log §8) |
| **APP-04B** | Memory | Apply sysctl `vm.swappiness=10` across active nodes | Very Low | `ansible/playbooks/node-tune.yaml` | ✅ Applied & verified 2026-10-17 (change-log §8) |
| **APP-05** | Node Lifecycle | Structured decommission of dead node `kubernetes7` and cleanup of `kubernetes8-debian` | Medium | Staged deletion runbook | ✅ Applied & verified 2026-10-17; `server-236`/`server-252` retained (change-log §9) |
| **APP-06** | Control Plane | 3-Server Embedded etcd HA Architecture Migration | High | Architecture Proposal Runbook | ⏸ Not executed — architecture change excluded by mission scope |

---

## 2. Detailed Change Proposals

### APP-01: Replace Disruptive K3s Shutdown Cron with Online Atomic etcd Backup
- **Problem Statement:** The active root crontab on `nuc` executes `systemctl stop k3s` daily at 02:00 UTC to back up an obsolete 0-byte SQLite database (`state.db`). Embedded etcd snapshots taken locally on `nuc` are never copied off-node.
- **Proposed Action:** Install `/usr/local/bin/k3s-etcd-safe-backup.sh` and update root crontab on `nuc` to execute every 6 hours without stopping the K3s daemon.
- **Prepared Script Asset:** `scripts/k3s-etcd-safe-backup.sh`
  - Uses `k3s etcd-snapshot save` (K3s remains running).
  - Preserves server recovery assets (`/var/lib/rancher/k3s/server/token`, `tls/`, `cred/`).
  - Implements process locking via `flock /var/run/k3s-backup.lock` to prevent overlapping runs.
  - Verifies minimum 5GB free space on NAS export (`192.168.0.128:/Public/backups/k3s`).
  - Transfers files to `.tmp` staging directories on NAS before atomic rename.
  - Enforces off-node retention (14 copies).
- **Execution Command (Approval-Gated):**
  ```bash
  # 1. Copy script to nuc
  scp scripts/k3s-etcd-safe-backup.sh suryendub@192.168.0.21:/tmp/
  # 2. Install and schedule on nuc (using secure askpass/stdin)
  sudo mv /tmp/k3s-etcd-safe-backup.sh /usr/local/bin/k3s-etcd-safe-backup.sh
  sudo chmod 0750 /usr/local/bin/k3s-etcd-safe-backup.sh
  sudo crontab -l | sed 's|.*k3s-backup-to-nas.sh.*|0 */6 * * * /usr/local/bin/k3s-etcd-safe-backup.sh >> /var/log/k3s-etcd-backup.log 2>\&1|' | sudo crontab -
  ```
- **Validation:**
  ```bash
  sudo /usr/local/bin/k3s-etcd-safe-backup.sh
  ./scripts/verify-etcd-snapshot.sh
  ```
- **Rollback:**
  ```bash
  sudo crontab -l | sed 's|.*k3s-etcd-safe-backup.sh.*|0 2 * * * /usr/local/bin/k3s-backup-to-nas.sh >> /var/log/k3s-backup.log 2>\&1|' | sudo crontab -
  ```

**Status (2026-10-17): ✅ Applied & verified.** Hardened script (sha256 `20a74f2e…`) installed on `nuc`; cron `0 */6 * * *`; manual + real cron runs produced 225 MB snapshots with matching NAS sha256; K3s was never stopped. Original crontab backed up on `nuc` (`/root/crontab-before-app01-20261017.bak`). See change-log §7.

---

### APP-02: Deploy CoreDNS High-Availability Patch & PDB
- **Problem Statement:** CoreDNS runs with a single replica on `kubernetes6`. If `kubernetes6` reboots, DNS resolution fails cluster-wide.
- **Proposed Action:** Apply `kubernetes/monitoring/coredns-ha-patch.yaml` to scale replicas to 2, enforce hostname topology spread, and attach a `PodDisruptionBudget` (`minAvailable: 1`).
- **Persistence Mandate:** Because CoreDNS is an Addon managed from `/var/lib/rancher/k3s/server/manifests/coredns.yaml`, the change must also be mirrored into the server manifests directory on `nuc` to persist across K3s restarts.
- **Execution Command (Approval-Gated):**
  ```bash
  kubectl apply -f kubernetes/monitoring/coredns-ha-patch.yaml
  ```
- **Validation:**
  ```bash
  kubectl -n kube-system get deployment coredns
  kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
  ./scripts/validate-dns.sh
  ```
- **Rollback:**
  ```bash
  kubectl -n kube-system scale deployment coredns --replicas=1
  kubectl -n kube-system delete pdb coredns-pdb
  ```

**Status (2026-10-17): ✅ Applied & verified.** Applied via the addon file `/var/lib/rancher/k3s/server/manifests/coredns.yaml` (replicas 2 + `coredns-pdb` + hard host spread `DoNotSchedule`) so it survives K3s restarts; replicas live on distinct nodes; `validate-dns.sh` passed; a failover drill kept DNS serving. See change-log §7.

---

### APP-03: Remove Default StorageClass Flag from `local-path`
- **Problem Statement:** Both `local-path` and `longhorn` have `storageclass.kubernetes.io/is-default-class: "true"`, causing ambiguous volume binding for unqualified dynamic volume claims.
- **Proposed Action:** Execute a minimal annotation patch to set `is-default-class: "false"` on `local-path`. This does not mutate existing PVCs (all 40 production PVCs remain bound to `longhorn`).
- **Execution Command (Approval-Gated):**
  ```bash
  kubectl patch storageclass local-path -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
  ```
- **Validation:**
  ```bash
  kubectl get storageclass
  ```
- **Rollback:**
  ```bash
  kubectl patch storageclass local-path -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
  ```

**Status (2026-10-17): ✅ Applied & verified.** Applied via the addon file `/var/lib/rancher/k3s/server/manifests/local-storage.yaml`; `longhorn` is now the sole default; all 45 PVCs stayed `Bound`. See change-log §7.

---

### APP-04A: Preventative Sysctl Tuning — `fs.inotify.max_user_instances` (P3)
- **Problem Statement:** Current setting is 128 across all nodes. While 0 inotify errors have occurred, increasing this value prevents future exhaustion under container runtime scale.
- **Proposed Action:** Deploy `/etc/sysctl.d/99-k3s-inotify.conf` containing `fs.inotify.max_user_instances = 8192` across the 7 active nodes.
- **Execution Command (Approval-Gated):**
  ```bash
  # Via Ansible playbook:
  ansible-playbook -i inventory/nodes.yaml ansible/playbooks/node-tune.yaml --tags inotify
  ```
- **Rollback:** Remove `/etc/sysctl.d/99-k3s-inotify.conf` and run `sudo sysctl --system`.

**Status (2026-10-17): ✅ Applied & verified.** Applied to all 7 active nodes via direct per-node SSH; `/etc/sysctl.d/99-k3s-inotify.conf` persisted and live value `8192` on every node. See change-log §8.

---

### APP-04B: Preventative Sysctl Tuning — `vm.swappiness` (P3)
- **Problem Statement:** Desktop default swappiness (60) is present across nodes, though actual swap usage is negligible (0–2MB) and available RAM is high (4.5–13GB).
- **Proposed Action:** Deploy `/etc/sysctl.d/99-k3s-swappiness.conf` containing `vm.swappiness = 10` across nodes with active swap.
- **Execution Command (Approval-Gated):**
  ```bash
  # Via Ansible playbook:
  ansible-playbook -i inventory/nodes.yaml ansible/playbooks/node-tune.yaml --tags swappiness
  ```
- **Rollback:** Remove `/etc/sysctl.d/99-k3s-swappiness.conf` and run `sudo sysctl --system`.

**Status (2026-10-17): ✅ Applied & verified.** Applied to all 7 active nodes via direct per-node SSH; `/etc/sysctl.d/99-k3s-swappiness.conf` persisted and live value `10` on every node. See change-log §8.

---

### APP-05: Corrected Stale Offline Node Management
- **Problem Statement:** 4 offline nodes appear in `kubectl get nodes`. They represent very different failure domains and cannot be treated with a single blanket deletion command.

#### Node-by-Node Plan & Technical Rationale:

1. **`server-236` — EXCLUDE FROM DELETION:**
   - **Role:** `control-plane,etcd,master`
   - **Reason:** It is a Hyper-V guest on host HP-1 (.103) hosting the cluster's insecure private registry (`192.168.0.236:5000`). It is offline because HP-1 is powered off. Marked `neverCordon` in `homelab-nodes.json`. It is an intended cluster node expected to return when HP-1 is powered on. etcd voter status is already disabled (`EtcdIsVoter: False`).
   - **Action:** Retain node object in Kubernetes metadata.

2. **`server-252` — EXCLUDE FROM DELETION:**
   - **Role:** `control-plane,etcd,master`
   - **Reason:** Hyper-V guest on DELL-1. Marked `neverCordon`. Expected to return. Removed from etcd voting (`EtcdIsVoter: False`).
   - **Action:** Retain node object in Kubernetes metadata.

3. **`kubernetes8-debian` — PREREQUISITE LONGHORN CLEANUP REQUIRED:**
   - **Role:** `<none>` (Test worker node, offline since 2026-10-15).
   - **Blocker:** Has **16 stopped Longhorn replicas** registered on it. Deleting the Kubernetes node object first will orphan Longhorn replica metadata and trigger storage reconciliation alerts.
   - **Staged Action:**
     1. Evict and delete the 16 stopped replicas in Longhorn via Longhorn UI or CRD.
     2. Delete Longhorn node object: `kubectl -n longhorn-system delete nodes.longhorn.io kubernetes8-debian`.
     3. Only then delete Kubernetes node: `kubectl delete node kubernetes8-debian`.

4. **`kubernetes7` — DECOMMISSIONING & TERMINATING POD PURGE:**
   - **Role:** `worker`
   - **Reason:** Physical hardware failure (broken power switch, unrecoverable; marked `neverPowerOff` in `homelab-nodes.json`).
   - **Current State:** 41 pods stuck in `Terminating` state (including 39 Tailscale proxy pods) and 3 stale VolumeAttachments for deleted PVs.
   - **Staged Action:**
     1. Force delete terminating pods: `kubectl delete pod <pod> -n <ns> --force --grace-period=0`.
     2. Delete stale VolumeAttachments: `kubectl delete volumeattachment csi-1a3b0d... csi-b96efc... csi-c38df8...`.
     3. Delete Longhorn node: `kubectl -n longhorn-system delete nodes.longhorn.io kubernetes7`.
     4. Delete Kubernetes node object: `kubectl delete node kubernetes7`.

#### Execution Result (2026-10-17)
✅ **Applied & verified.** `kubernetes7`: 68 stuck pods force-deleted, 3 stale VolumeAttachments finalizer-cleared, Longhorn + Kubernetes node objects removed. `kubernetes8-debian`: 16 stopped replicas verified redundant (3 running replicas elsewhere per affected volume) before deletion, then pods purged and both node objects removed (the Longhorn node required `allowScheduling: false` first — v1.12 only forgets a down/unschedulable/empty node once its Kubernetes object is gone; it was then auto-removed within 10 s). `server-236`/`server-252` untouched. Post-checks: 7 Ready nodes, 39/40 Longhorn volumes healthy, 0 leftover pods/replicas/VolumeAttachments. See change-log §9.

---

## 3. New Approval-Required Items (from session, 2026-10-17)

### APP-06: Upstream languard fix — staleness-tolerant migration lock (P3)
- **Context:** This session mitigated the languard outage (F-08 / change-log §10) **inside the cluster manifests** with an initContainer that clears a stale `/data/.startup-lock` and pre-runs migrations. The underlying defect is in `ghcr.io/hillaliy/languard-backend:latest` `/entrypoint.sh` (mkdir-based lock, removed only via trap; no staleness handling) and in the shipped k8s guidance (scheduler container bypassing ENTRYPOINT via k8s `command`, relying on crash-retry to wait for migrations).
- **Why not done now:** Fixing it means changing image content (fork/patch image and pin a digest, or upstream PR) — outside the authorized change scope (no image swaps/pinning in this mission).
- **Staged Action (owner decision needed):**
  1. Report the entrypoint lock issue upstream (hillaliy/LanGuard) attaching the empty-folder scenario; propose `mkdir`+`flock`/pidfile with staleness check or lock-dir mtime/TTL.
  2. If upstream is unresponsive, pin a forked image digest with the fixed entrypoint and remove the initContainer accordingly.
- **Approval gate:** image fork/digest pin + any upstream report publishing cluster details (scrub first).

### APP-07: Languard node pin decision (P3)
- **Context:** languard runs `hostNetwork` (ports 8000/8080 bound on its node). Since this session's rollout it binds on **kubernetes3** (was kubernetes6). The only placement constraint is "not kubernetes4". Any future workload claiming 8000/8080 on kubernetes3 will make languard unschedulable there; scheduling is otherwise node-agnostic.
- **Staged Action:** owner decides whether to pin languard to a fixed worker (nodeSelector) or reserve ports 8000/8080 catalog-wide; if pinned, update ALLOWED_HOSTS (`192.168.0.25` currently hardcodes the *old* node IP — after this rollout the live node IP is `192.168.0.22`).
- **Approval gate:** deliberate workload placement change (placement decisions are owner-controlled in this homelab).

### APP-08: Uptime-Kuma notification channels — alert delivery (P2)
- **Context (discovered 2026-10-17 ~03:50):** T-09 added host-level node-down detection (7 SSH port monitors); Kuma's `notification` table contains **0 channels**, so ALL monitoring (incl. new backup freshness / robustness beats) is dashboard-only. Nothing pages when a node drops, a backup beat goes down, or a monitor fails.
- **Staged Action (owner decision needed):** create notification channel(s) in the Kuma UI (endpoint/API-key owned by user), wire to the node-*, longhorn-backup-daily, etcd-nas-backup, and build health monitors; set `default notification` for new monitors if desired. Cron-managed monitors are unaffected — channels attach to existing monitors.
- **Approval gate:** requires owner-issued credentials for any external pager (NTFY/Telegram/Discord/email target) — out of agent scope.

### APP-09: openlingo image availability (P3 — app owner build action)
- **Context (observed 2026-10-17 ~04:00 CEST):** `openlingo` (openlingo ns) has been `ImagePullBackOff` for ~9 h pulling `192.168.0.236:5000/openlingo:v10-dynamic-models`; the private registry is reachable and healthy (Kuma `registry-docker-tcp` monitor up), so the tag is simply not built/pushed yet. Kuma monitor `openlingo` correctly reports DOWN — detection works.
- **Staged Action:** build & push the tag (per shipped flow `k3s-build` to the private registry or equivalent), then the deployment self-recovers on the next pull.
- **Approval gate:** user-owned build/change of their dev application — deliberately out of this reliability mission's scope.
