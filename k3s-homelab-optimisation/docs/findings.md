# K3s Homelab Platform Findings & Remediation Register

**Audit Date:** 2026-10-17  
**Mission Status:** The cluster was audited and measured. Scripts, playbooks, manifests, and runbooks were created, and the approval-gated catalog was then executed live on 2026-10-17: **APP-01 through APP-05 are applied and runtime-verified** (see `change-log.md` §7–§9). APP-06 remains excluded by mission scope (no architecture changes). Every applied change was validated against live runtime behaviour, not just API acceptance.

---

## 1. Findings Summary Table

| ID | Area | Severity | Priority | Description | Decision | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **F-01** | Backup & DR | Critical | **P0** | Disruptive legacy backup stops K3s daily at 02:00 UTC and backs up 0-byte SQLite DB; native etcd snapshots not copied off-node | Replace with atomic `k3s etcd-snapshot save` and off-node NAS sync | **Remediated & Verified 2026-10-17** |
| **F-02** | Persistent Storage | Medium | **P2** | Dual default StorageClasses (`longhorn` and `local-path` both set to default) | Apply minimal annotation patch to set `is-default-class: "false"` on `local-path` | **Remediated & Verified 2026-10-17** |
| **F-03** | DNS & Reliability | Medium | **P2** | CoreDNS deployed with single replica (SPOF on `kubernetes6`) | Scale to 2 replicas with hostname spread and PDB via persistent manifest | **Remediated & Verified 2026-10-17** |
| **F-04** | Node OS Tuning | Low | **P3** | `fs.inotify.max_user_instances` set to default 128 on all nodes (No evidence of exhaustion) | Propose preventative tuning to 8192 via sysctl | **Remediated & Verified 2026-10-17** |
| **F-05** | Memory Hygiene | Low | **P3** | `vm.swappiness` set to 60 across nodes (0–2MB swap used; 4.5–13GB RAM free) | Propose lowering swappiness to 10 as preventative hygiene | **Remediated & Verified 2026-10-17** |
| **F-06** | Resource Management | Low | **P3** | Platform pods lack baseline CPU/memory requests | Size baseline requests and limits | Cataloged (Planning Only) |
| **F-07** | Cluster Hygiene | Medium | **P2** | 4 offline node objects registered in API (`kubernetes7`, `kubernetes8-debian`, `server-236`, `server-252`) | Differentiate temporary Hyper-V hosts from dead hardware and stale test nodes | **Remediated 2026-10-17** (`kubernetes7` + `kubernetes8-debian` decommissioned; `server-236`/`server-252` intentionally retained) |

---

## 2. Detailed Findings & Grounded Evidence

### Finding F-01: Disruptive Legacy Backup Stopping K3s Daily (P0)
- **Finding ID:** F-01
- **Area:** Backup & Disaster Recovery / Datastore
- **Current State:** `/usr/local/bin/k3s-backup-to-nas.sh` is scheduled in root crontab on `nuc` at `0 2 * * *`. It executes `systemctl stop k3s` to copy `/var/lib/rancher/k3s/server/db/state.db`.
- **Measured Live Evidence:**
  1. Crontab on `nuc`: `0 2 * * * /usr/local/bin/k3s-backup-to-nas.sh >> /var/log/k3s-backup.log 2>&1`.
  2. Inspection of `/var/lib/rancher/k3s/server/db/`: `state.db` is 0 bytes. Active datastore is embedded etcd in `/var/lib/rancher/k3s/server/db/etcd/` (591 MB).
  3. NAS check at `192.168.0.128:/share/Public/backups/k3s`: The daily backup creates directory `20261015-223825/` containing a 0-byte `k3s-state.db`, `k3s-config.tar.gz`, and `k3s-identity.tar.gz`.
  4. Native K3s embedded etcd snapshots (`k3s etcd-snapshot list`) exist locally on `nuc` in `/var/lib/rancher/k3s/server/db/snapshots/` (latest: `etcd-snapshot-nuc-1792188003`, 225 MB), but are **never copied off-node**.
- **Severity:** Critical
- **Priority:** P0
- **Prepared Remediation:** Prepared replacement script `scripts/k3s-etcd-safe-backup.sh` that uses `k3s etcd-snapshot save`, never stops K3s, archives server-token and TLS recovery assets, checks destination free space, uses atomic file transfers, and enforces retention.
- **Runtime State:** **Remediated & Verified 2026-10-17.** Hardened script installed on `nuc` (`/usr/local/bin/k3s-etcd-safe-backup.sh`, sha256 `20a74f2e…`); root crontab now runs it every 6 h (`0 */6 * * *`); legacy disruptive line removed (no more K3s stops). Verified: manual + real cron runs produced 225 MB snapshots with matching sha256 on the NAS; K3s `ActiveEnterTimestamp` unchanged throughout. Legacy script/crontab retained for rollback.

---

### Finding F-02: Dual Default StorageClasses (P2)
- **Finding ID:** F-02
- **Area:** Persistent Storage
- **Current State:** Both `local-path` and `longhorn` have annotation `storageclass.kubernetes.io/is-default-class: "true"`.
- **Measured Live Evidence:**
  1. `kubectl get sc` confirms both classes marked default.
  2. Total PVCs: 40 bound to `longhorn`, 5 bound to `nfs-nas`, 7 static PVCs with omitted `storageClassName` bound to NFS PVs.
  3. `local-path` has 0 active PVCs.
  4. All 6 active Longhorn nodes (`kubernetes1`–`kubernetes6`) are Ready and Schedulable, with 524 GB total available storage.
- **Severity:** Medium
- **Priority:** P2 (Downgraded from P1; existing PVCs are bound and unaffected).
- **Prepared Remediation:** Patch `local-path` annotation to `is-default-class: "false"`. Confirm that changing the default affects only future unqualified dynamic PVCs and will not mutate existing PVCs. A minimal annotation patch is preferred over manifest re-creation due to immutable StorageClass parameters.
- **Runtime State:** **Remediated & Verified 2026-10-17.** Applied via the owning addon file `/var/lib/rancher/k3s/server/manifests/local-storage.yaml` (a bare `kubectl patch` would have been reverted by the K3s addon controller). `local-path` default annotation is now `"false"`; `longhorn` is the sole default. All 45 existing PVCs remain `Bound`; `local-path-provisioner` unaffected. Original file backed up in `/root/k3s-manifests-backup-20261017/`.

---

### Finding F-03: CoreDNS Single Replica SPOF (P2)
- **Finding ID:** F-03
- **Area:** Cluster DNS / High Availability
- **Current State:** CoreDNS deployment runs with `spec.replicas: 1` on `kubernetes6`.
- **Measured Live Evidence:**
  1. `kubectl -n kube-system get deployment coredns` shows `1/1` replicas.
  2. In-cluster CoreDNS resolution (`validate-dns.sh`) currently functions with 4ms average latency.
  3. CoreDNS is managed by K3s Addon controller from `/var/lib/rancher/k3s/server/manifests/coredns.yaml`.
  4. The packaged manifest specifies resources (`requests: cpu: 100m, memory: 70Mi`) and `topologySpreadConstraints` across `kubernetes.io/hostname` with `maxSkew: 1`.
  5. 6 active worker nodes + 1 control plane node are available, ensuring 2 replicas can easily schedule on separate physical hosts.
- **Severity:** Medium
- **Priority:** P2 (Downgraded from P1; service is currently operational).
- **Prepared Remediation:** Manifest `kubernetes/monitoring/coredns-ha-patch.yaml` scales replicas to 2 and adds a `PodDisruptionBudget` (`minAvailable: 1`). Note: To guarantee persistence across K3s restarts, the patch must be reflected in `/var/lib/rancher/k3s/server/manifests/`.
- **Runtime State:** **Remediated & Verified 2026-10-17.** Applied via the owning addon file `/var/lib/rancher/k3s/server/manifests/coredns.yaml`: `replicas: 2`, PDB `coredns-pdb` (`minAvailable: 1`, allowed disruptions 1), hard host spread (`DoNotSchedule`; an interim soft-spread rollout co-located both replicas on `kubernetes3`, corrected under the hard constraint). Two Ready replicas on distinct nodes (`kubernetes3` + `kubernetes6` after the failover drill); `validate-dns.sh` passed; a deliberate replica deletion recovered in <5 s with DNS continuity. Original file backed up in `/root/k3s-manifests-backup-20261017/`.

---

### Finding F-04: Reclassification of Sysctl Inotify Limits (P3)
- **Finding ID:** F-04
- **Area:** Linux Kernel Parameter Tuning
- **Current State:** `fs.inotify.max_user_instances` is set to the default value of 128 on all 7 nodes.
- **Measured Live Evidence:**
  1. All 7 active nodes (`nuc`, `kubernetes1`–`kubernetes6`) show `fs.inotify.max_user_instances = 128`.
  2. `fs.inotify.max_user_watches` ranges from 60,586 to 123,358 across nodes.
  3. Inotify file descriptor inspection shows current usage is well below limits across all nodes.
  4. Journalctl query across `kernel`, `containerd`, and `k3s` services over the past 7 days returned **0 inotify or ENOSPC errors**.
  5. There is **no evidence of inotify exhaustion**.
- **Severity:** Low
- **Priority:** **P3 (Downgraded from P1).** This is a preventative hygiene recommendation, not an active defect.
- **Prepared Remediation:** Prepared Ansible role `common` to tune `fs.inotify.max_user_instances=8192` as a preventative safeguard for Longhorn CSI and container monitoring.
- **Runtime State:** **Applied & Verified 2026-10-17.** Written to `/etc/sysctl.d/99-k3s-inotify.conf` on all 7 active nodes (`nuc`, `kubernetes1`–`kubernetes6`) via direct per-node SSH and applied with `sysctl --system`; live value is now `8192` on every node (`fs.inotify.max_user_watches` untouched). Rollback: remove the file and run `sysctl --system` per node.

---

### Finding F-05: Reclassification of Sysctl Swappiness (P3)
- **Finding ID:** F-05
- **Area:** Linux Memory Management
- **Current State:** `vm.swappiness` is set to default 60 on all nodes.
- **Measured Live Evidence:**
  1. `swapon --show` and `free -m` confirm swap usage is negligible:
     - `nuc`: 0B used (4GB swap file, 5.4GB available RAM).
     - `kubernetes1`: 2MB used (11.2GB available RAM).
     - `kubernetes2`: 1.3MB used (13.0GB available RAM).
     - `kubernetes3`: 1.5MB used (12.3GB available RAM).
     - `kubernetes4`: Swap completely disabled (0 swap, 5.3GB available RAM).
     - `kubernetes5`: 0B used (4.5GB available RAM).
     - `kubernetes6`: 0B used (12.3GB available RAM).
  2. There is **zero memory pressure or swap thrashing** in the cluster.
  3. K3s natively tolerates swap enabled without issues.
- **Severity:** Low
- **Priority:** **P3 (Independent change record).** Tuning swappiness to 10 is low-risk hygiene.
- **Prepared Remediation:** Prepared sysctl tuning via Ansible playbook `node-tune.yaml`.
- **Runtime State:** **Applied & Verified 2026-10-17.** Written to `/etc/sysctl.d/99-k3s-swappiness.conf` on all 7 active nodes and applied with `sysctl --system`; live value is now `10` on every node (swap remains enabled where present). Rollback: remove the file and run `sysctl --system` per node.

---

### Finding F-07: Stale Offline Node Assessment (P2)
- **Finding ID:** F-07
- **Area:** Cluster Hygiene & Lifecycle Management
- **Current State (after remediation):** 2 node objects remain registered in `NotReady` condition (`server-236`, `server-252` — intentionally retained). `kubernetes7` and `kubernetes8-debian` were fully decommissioned on 2026-10-17.
- **Measured Live Evidence (original assessment):**
  1. **`server-236`:** Roles `control-plane,etcd,master`. Offline since 2026-10-04. Hyper-V guest on HP-1 (.103). Hosts private registry (`192.168.0.236:5000`). Marked `neverCordon` in `homelab-nodes.json`. Expected to return when HP-1 is powered on. Already removed from active etcd voter list (`EtcdIsVoter: False`). **Excluded — retained.**
  2. **`server-252`:** Roles `control-plane,etcd,master`. Offline since 2026-09-25. Hyper-V guest on DELL-1. Marked `neverCordon`. Expected to return. Removed from etcd voting list (`EtcdIsVoter: False`). **Excluded — retained.**
  3. **`kubernetes8-debian`:** Roles `<none>`. Cordoned, offline since 2026-10-15. Had 7 assigned pods (DaemonSets) and **16 stopped Longhorn replicas**. Cleaned up with the Longhorn prerequisite first, so no storage objects were orphaned.
  4. **`kubernetes7`:** Roles `worker`. Not cordoned, offline since 2026-10-06. Suffered unrecoverable hardware failure (broken power switch; marked `neverPowerOff` in `homelab-nodes.json`). Had grown to 68 stuck pods by execution time (41 at audit; incl. 39 Tailscale proxy pods and a stale CoreDNS replica) and 3 stale VolumeAttachments for already-deleted PVs. **Decommissioned.**
- **Severity:** Medium
- **Priority:** P2
- **Prepared Remediation:** Multi-step approval catalog separating node preservation from decommissioning.
- **Runtime State:** **Remediated & Verified 2026-10-17.** Executed per the staged plan:
  - `kubernetes7`: 68 stuck pods force-deleted; 3 stale VolumeAttachments (stuck in `deleting` since 2026-09-22 on a dead `external-attacher/driver-longhorn-io` finalizer, with PVs already deleted) finalizer-cleared and removed; Longhorn node object removed; Kubernetes node object removed.
  - `kubernetes8-debian`: all 16 stopped replicas verified redundant first (every affected volume already held **3 running replicas on active nodes**), then deleted; pods purged; Kubernetes node object removed; Longhorn node object cleaned (direct deletion is refused while a node is down — after `allowScheduling: false`, Longhorn v1.12 auto-removed the object within 10 s once its Kubernetes object was gone).
  - Post-checks: 7 Ready nodes (`nuc` + `kubernetes1`–`kubernetes6`); Longhorn nodes = `kubernetes1`–`kubernetes6` + retained `server-236`/`server-252`; 39/40 Longhorn volumes healthy (the 1 detached/unknown volume pre-dates this change); 0 pods / 0 replicas / 0 stale VolumeAttachments left on the decommissioned nodes; DNS smoke query resolved.

---

### Finding F-08: languard migration-lock deadlock after killed container (P2 — discovered live, 2026-10-17)
- **Finding ID:** F-08 (new during session; not part of the original audit set)
- **Area:** Workload Reliability / Shared-PVC Startup Coordination
- **Observed Live State:** `languard` (monitoring) stuck `CrashLoopBackOff` — 223 restarts, ~9 h. Backend forever printed `Waiting for another LanGuard container to finish startup migrations...`; scheduler crashed with `no such table: core_schedulerruntimestate`.
- **Root Cause (verified by exec into image, read-only):** `/entrypoint.sh` (`ghcr.io/hillaliy/languard-backend:latest`) creates `/data/.startup-lock` with plain `mkdir` and relies solely on an EXIT/INT/TERM trap to remove it. A container killed between `mkdir` and the trap (OOM, eviction, kubelet restart, container restart at grace expiry) leaves an empty lock dir on the PVC that makes `mkdir` fail forever — a permanently poisoned lock with no staleness handling. Secondary defect: the k8s scheduler container's `command:` overrides the image ENTRYPOINT, so it bypasses the entrypoint entirely and hit the missing migrations.
- **Mitigation Applied:** `kubernetes-manifests/monitoring/languard.yaml` — `initContainer db-init` clears any stale lock at pod start (provably safe under `strategy: Recreate`: no concurrent holder can exist) and runs migrations up front, removing the scheduler startup race; `terminationGracePeriodSeconds: 60`. See change-log §10.
- **Residual Limitations:**
  1. The image's entrypoint lock protocol remains stale-lock-prone upstream (`ghcr.io/hillaliy/languard-backend`) — any languard container crash mid-migration will be self-healing only thanks to the initContainer, not the image. Fix belongs upstream.
  2. Backend + scheduler share the SQLite file over the same PVC from two containers in one pod; SQLite across concurrent writers remains a structural risk (upstream design; not changed in this session).
  3. Languard uses `hostNetwork` (fixed ports 8000/8080), so its node placement is load-bearing: after this rollout it binds on **kubernetes3** (port conflict would prevent start). No dedicated node pin exists beyond "not kubernetes4".
- **Runtime State:** **Mitigated & verified live 2026-10-17** — evidence in change-log §10 and task file T-06.
