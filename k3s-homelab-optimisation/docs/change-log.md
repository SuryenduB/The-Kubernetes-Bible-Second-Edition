# K3s Homelab Change Log

Chronological audit log of platform engineering inspections, discoveries, validations, and artifact generation.

---

## 2026-10-17: Ralph Loop Iteration 1 — backup detection repair (commit 877ecc1)

- **F-08 (new):** `backup-daily-check` CronJob had failed daily since 2026-09-17: the Kuma 2.x
  push monitor's token rotated, while Secret `longhorn-backup-kuma-push` kept the stale one,
  so every push returned 404 (`/api/push/<token>` → "monitor not found") and the Job hit its
  5-minute deadline in a retry loop. Detected during Phase-1 reconciliation via
  `status.lastSuccessfulTime` vs `lastScheduleTime`.
- **Fix:** Secret re-synchronised with the live monitor token (read via Kuma's embedded
  MariaDB through exec, never printed); validated by a manual Job (`{'ok': True}`) and a
  Kuma heartbeat status=1 at 2026-10-17 00:16 UTC.
- **Extension:** `check.py` now covers both backup pipelines (Longhorn backups ≤ 26 h and
  K3s `etcd-snapshot-online-*` CRs ≤ 13 h), masks the push token in pod logs, and prints a
  precise remediation hint on 404 token desync. `ClusterRole longhorn-backup-reader`
  extended for `k3s.cattle.io/etcdsnapshotfiles`. Applied live via
  `kubernetes-manifests/monitoring/longhorn-backup-monitor.yaml` after server-side dry-run
  and `py_compile`; final manual Job logs `longhorn: OK 9.0h | etcd: OK 1.0h`, exit 0.
- **Note:** Uptime-Kuma has no notification provider configured (verified via API listing);
  detection = Kuma dashboard monitor state + Job `Failed` condition. Notification delivery is
  UNVERIFIED and recorded as such.

## 2026-10-17: Ralph Loop Iteration 2 — online backup script hardening


- **Phase-2 defect review of `k3s-etcd-safe-backup.sh`:**
  (a) `mount -t nfs -o hard` without bound would hang forever on an unreachable NAS,
  silently stopping backups from that point; (b) no mount-identity check — a stale/foreign
  filesystem at `/mnt/k3s-nas-backup` could have been used as destination; (c) failure
  causes were not distinguishable in logs; (d) `INT`/`TERM` could exit 0; (e) interrupted
  `.tmp-*` transfers were never pruned; (f) the documented `--manual-test` flag did not exist.
- **Fix (script `sha256 b87a06f4…` installed on nuc, old version backed up at
  `/root/k3s-etcd-safe-backup.sh.pre-iter2`):** `timeout`-bounded mount
  (`NAS_MOUNT_TIMEOUT_SECONDS`, default 180 s), `findmnt` mount-identity verification and
  refusal of pre-existing mounts, phase-tagged errors, single coherent trap schema always
  exiting non-zero on signals, `.tmp-*` pruning at the start of each transfer, and a real
  `--manual-test` mode (full pipeline, no publish, no prune). Between-fixture observation:
  an interim real run published `20261017-023018` (checksums verified, retention pruned the
  15th-oldest dir; NAS now at exactly 14 published dirs).
- **Fixture validation (live on nuc):**
  - A: `NAS_IP=203.0.113.1` (blackhole) + `NAS_MOUNT_TIMEOUT_SECONDS=20` → clean failure
    `[MOUNT] … timed out after 20s`, `[FATAL] exit 1`, no mount left, NAS unaffected.
  - B: foreign `tmpfs` mounted at `/mnt/k3s-nas-backup` → run refuses with `[MOUNT]`
    already mounted (source: tmpfs), exit 1, zero writes into the foreign mount, foreign
    mount left intact for the operator.
  - D: `--manual-test` → full pipeline incl. NAS checksum verification, exit 0, no publish,
    inspectable `.tmp-*` left (pruned by next real run).
- ACK/awareness: each fixture run creates one local 225 MB online snapshot as a by-product
  (snapshot deliberately happens first so local snapshots exist even during NAS outages);
  they age out with the 14-day local retention.

---


## 2026-10-17: Ralph Loop Iteration 3 — end-to-end etcd backup heartbeat

- **Gap:** the daily checker proves freshness via CR timestamps, but only proves the
  `etcd-snapshot save` side; nothing confirmed the NAS publish pipeline actually finished
  until the 04:00 UTC check.
- **Implementation:** new Kuma push monitor `etcd-nas-backup` (id 26, push type, interval
  21600 s) created via the socket API (`conditions: []` pattern, same as uptime-kuma-sync);
  its token delivered to nuc as `/root/.kuma-etcd-push-token` (chmod 600, never printed);
  `k3s-etcd-safe-backup.sh` now pushes a completion heartbeat at the very end of a
  successful publish (script `sha256 2d9993ce…`; push resolves the uptime-kuma ClusterIP
  via `k3s kubectl` with a cached file fallback, and a push failure can never fail the
  backup itself).
- **Live validation:** manual end-to-end run published `20261017-024141` (225 MB snapshot +
  archives, checksums verified, retention pruned the oldest dir) and pushed the heartbeat —
  Kuma heartbeat id 202382: `status=1, msg='etcd NAS backup published 20261017-024141
  (225MB)'`, exit 0.
- **Recovery note (in docs/backup-restore-runbook.md):** if the Kuma data store is rebuilt,
  the monitor and its token must be re-provisioned (same procedure as the Longhorn monitor);
  the monitoring script simply skips pushing when the token file is absent.
## 2026-10-17: Ralph Loop Mission Execution

### 1. Repository & Secret Protection Hardening
- **Action:** Audited existing Git tracking and credentials against homelab safety rules.
- **Change:** Updated root `.gitignore` and created `k3s-homelab-optimisation/.gitignore` to strictly exclude raw command outputs, `.key`, `.pem`, tokens, kubeconfigs, and raw secret YAMLs.
- **Validation:** `git status` confirmed zero un-sanitized or sensitive files staged.

### 2. Cluster & Node Discovery (Step 1 of Ralph Loop)
- **Action:** Executed read-only discovery across the cluster and physical hardware.
- **Discovered Facts:**
  - 7 active Ubuntu nodes: 1 Server (`nuc` at `192.168.0.21`) and 6 Agents (`kubernetes1` to `kubernetes6`).
  - Active Datastore: Single-voter embedded etcd (`nuc-1e55bd21`).
  - Running Versions: K3s `v1.34.6+k3s1`, containerd `2.2.2-bd1.34`, Ubuntu `24.04.2 LTS`.
  - Discovered 4 legacy/offline node objects: `server-236`, `server-252`, `kubernetes8-debian`, `kubernetes7`.
- **Artifacts:**
  - `k3s-homelab-optimisation/reports/cluster-state-*.txt`
  - `k3s-homelab-optimisation/reports/node-state-*.txt`

### 3. Verification of Datastore & Backup Finding (P0)
- **Action:** Inspected `/var/lib/rancher/k3s/server/db/` and root crontab on `nuc`.
- **Finding (F-01):** Discovered that `/usr/local/bin/k3s-backup-to-nas.sh` stops K3s daily at 02:00 UTC to back up an obsolete 0-byte SQLite database (`state.db`), while active etcd is online and functional.
- **Remediation Prepared:** Authored `scripts/verify-etcd-snapshot.sh` and Ansible task `ansible/roles/k3s_server/tasks/main.yaml` for online atomic snapshots.

### 4. Cluster Network, DNS, and Storage Conformance Validation
- **Action:** Ran automated non-destructive test scripts in dynamic isolated namespaces.
- **Results:**
  - `scripts/validate-dns.sh`: CoreDNS resolved internal service discovery (4ms) and public records. Identified single-replica SPOF.
  - `scripts/validate-network.sh`: Pod-to-pod cross-node ICMP passed with 0% loss, 0.59ms latency, and 1400-byte MTU without fragmentation.
  - Storage: 38 Longhorn volumes verified healthy and attached. Dual default StorageClasses identified (`local-path` and `longhorn`).

### 5. Automation & Manifest Engineering
- **Action:** Created structured Ansible playbooks, roles, inventories, and Kubernetes manifests:
  - `ansible/ansible.cfg`, `ansible/inventory.example.yaml`, `ansible/group_vars/all.yaml`
  - `ansible/roles/{common,k3s_server,k3s_agent}`
  - `ansible/playbooks/{audit.yaml,node-tune.yaml,etcd-snapshot.yaml}`
  - `kubernetes/storage/default-storageclass-fix.yaml`
  - `kubernetes/monitoring/coredns-ha-patch.yaml`
  - `kubernetes/policies/pod-security-standards-audit.yaml`
  - `kubernetes/tests/smoke-test-workload.yaml`
- **Validation:** Executed server-side dry run via `kubectl apply --dry-run=server`; all manifests passed validation against the live apiserver.

### 6. Runbook & Documentation Suite Generation
- **Action:** Authored the complete operational documentation suite:
  - `docs/current-state.md`
  - `docs/architecture.md` (with Mermaid diagrams)
  - `docs/findings.md` (prioritised P0–P3 register)
  - `docs/optimisation-plan.md` (phased implementation plan)
  - `docs/risk-register.md` (comprehensive risk analysis)
  - `docs/backup-restore-runbook.md` (etcd & Longhorn disaster recovery)
  - `docs/upgrade-runbook.md` (controlled zero-downtime upgrades)
  - `docs/node-maintenance-runbook.md` (cordon/drain/storage safety)
  - `docs/validation-report.md` (test evidence and measurements)
  - `docs/approval-required.md` (gated change catalog)
  - `docs/change-log.md` (audit trail)

### 7. Approval-Gated Execution — APP-01, APP-02, APP-03 (2026-10-17 01:03–01:25 CEST)

All three changes were applied through the **owning K3s addon manifest files** on `nuc`
(`/var/lib/rancher/k3s/server/manifests/`) rather than bare `kubectl` patches, so they persist
across K3s restarts; the K3s addon watcher applied each within ~20 s. Pre-change backups of every
file were stored in `/root/k3s-manifests-backup-20261017/`, and workstation copies in
`reports/ralph-20261017/`.

- **APP-01 (F-01) — Online etcd backup + off-node NAS copy: APPLIED.**
  - Hardened `k3s-etcd-safe-backup.sh` (adds cron-safe `PATH`, sha256 + `tar -tzf` verification of the off-node copy, preserves `pre-join-*` snapshots) installed to `/usr/local/bin/` (`sha256 20a74f2e…`).
  - Root crontab legacy line (`0 2 * * *`, stops K3s) replaced with `0 */6 * * *` running the new script; K3s is never stopped. Backup of original crontab: `/root/crontab-before-app01-20261017.bak`.
  - Evidence: manual run + a real cron end-to-end run produced three 225 MB snapshots (NAS dirs `20261017-011245`, `20261017-011401`, `20261017-011601`); NAS/local sha256 match verified externally; `ActiveEnterTimestamp` of the k3s unit unchanged (`Fri 2026-10-16 16:32:27 CEST`). Legacy script retained for rollback.
  - Note: the previous audit session had already swapped the crontab line at 01:03 using the pre-hardening script; this execution superseded that script version and performed the full validation.
- **APP-02 (F-03) — CoreDNS HA: APPLIED + FAILOVER TESTED.**
  - Addon file edited: `replicas: 2`, `PodDisruptionBudget coredns-pdb` (`minAvailable: 1`), hard host spread (`whenUnsatisfiable: DoNotSchedule`). Live after ~20 s.
  - Observation: an interim soft-spread (`ScheduleAnyway`) rollout co-located both replicas on `kubernetes3`; the hard constraint corrected placement to `kubernetes2` + `kubernetes6` (the RS hash returned to the original `67f677679b` template).
  - Evidence: two Ready replicas on distinct nodes; `allowed disruptions: 1`; `validate-dns.sh` passed (internal `kubernetes.default` → `10.43.0.1`, external `google.com`, 5 queries in 0.04 s); failover drill (deleted one replica) — deployment stayed Ready=2 with zero endpoints gap observed and DNS answered post-recovery.
- **APP-03 (F-02) — Single default StorageClass: APPLIED.**
  - `local-storage.yaml` edited: `storageclass.kubernetes.io/is-default-class: "false"` on `local-path`; live after ~20 s.
  - Evidence: `longhorn` is now the sole default; all 45 PVCs remain `Bound` (40 longhorn / 5 nfs-nas / 7 static); `local-path-provisioner` unaffected.

### 8. Approval-Gated Execution — APP-04 (Node sysctl hygiene; F-04/F-05)

- Applied `fs.inotify.max_user_instances = 8192` and `vm.swappiness = 10` on all 7 active nodes (`nuc` `192.168.0.21` + `kubernetes1`–`kubernetes6` `192.168.0.19/20/22/23/24/25`) via direct per-node SSH with before/after capture.
- Persisted as `/etc/sysctl.d/99-k3s-inotify.conf` and `/etc/sysctl.d/99-k3s-swappiness.conf`; applied with `sysctl --system`.
- Evidence: `fs.inotify.max_user_instances` 128 → 8192 and `vm.swappiness` 60 → 10 on every node (`fs.inotify.max_user_watches` unchanged); all nodes remained `Ready`.
- Rollback: delete the two files and run `sysctl --system` per node (values revert to kernel/Ubuntu defaults).

### 9. Approval-Gated Execution — APP-05 (Stale node decommission; F-07)

- **`kubernetes7` (dead hardware, broken power switch) — fully decommissioned.** 68 stuck pods (incl. 39 Tailscale proxy pods and a stale CoreDNS replica) force-deleted with `--force --grace-period=0`; 3 stale VolumeAttachments (stuck `deleting` since 2026-09-22 on a dead `external-attacher/driver-longhorn-io` finalizer; their PVs were already deleted) finalizer-cleared and removed; Longhorn node object removed; Kubernetes node object removed. A second pod purge removed 3 DaemonSet pods that were recreated before the node object went away.
- **`kubernetes8-debian` (stale test node) — fully decommissioned.** Pre-flight redundancy sweep: each of the 16 stopped Longhorn replicas belonged to a volume that already held **3 running replicas on active nodes** (zero-impact deletion). 16 replica CRs deleted → 7 stuck pods force-deleted → Kubernetes node object removed → Longhorn node object cleaned (direct deletion is refused by Longhorn v1.12 while the node is down; after `allowScheduling: false` it was auto-removed within 10 s — Longhorn only forgets a down, unschedulable, empty node once its Kubernetes object is gone).
- **`server-236` / `server-252` intentionally untouched** (Hyper-V guests expected to return; `server-236` hosts the private registry).
- Evidence (post-change): K8s nodes = 7 `Ready` (`nuc` + `kubernetes1`–`kubernetes6`) + the 2 retained `NotReady`; Longhorn nodes = `kubernetes1`–`kubernetes6` + the 2 retained; Longhorn volumes 39/40 healthy (the 1 detached/unknown volume pre-dates this change); 0 pods / 0 replicas / 0 VolumeAttachments remaining for the decommissioned nodes; DNS smoke query resolved. Pre-change object snapshots saved in `reports/ralph-20261017/app05-before/`.
- Rollback: none intended (decommissioning dead nodes). If `kubernetes8-debian` is ever powered on again, its K3s agent will re-register and Longhorn will re-create its node entry on demand.
- Note: workstation shell-history hygiene spot check found no `sshpass`/`password=`-style commands in `~/.zsh_history` (counts only; contents not read).

### 10. T-06 — languard CrashLoopBackOff repair (2026-10-17 ~02:45–03:05 CEST)

- **Symptom:** Deployment `languard` (monitoring) `1/3` `CrashLoopBackOff`, 223 container restarts over ~9 h. Backend looping `Waiting for another LanGuard container to finish startup migrations...`; scheduler crashing `django.db.utils.OperationalError: no such table: core_schedulerruntimestate`.
- **Root cause (verified in-image, read-only exec):** `/entrypoint.sh` in `ghcr.io/hillaliy/languard-backend:latest` guards migrations with a `mkdir`-based lock on `/data/.startup-lock` and only removes it via an EXIT/INT/TERM trap. A container killed after the lock is created but before the trap (OOM/eviction/grace expiry → SIGKILL) leaves the empty lock dir on the PVC; every later backend then waits forever because `mkdir` never succeeds. The scheduler container's k8s `command:` overrides the image ENTRYPOINT, so it never runs migrations and crashed on missing tables — migrations had never run past `core.0050`.
- **Fix (manifest `kubernetes-manifests/monitoring/languard.yaml`):**
  - New `initContainer db-init` (same backend image): clears any `/data/.startup-lock` at pod start (safe because `strategy: Recreate` guarantees no concurrent holder, and the scheduler never holds the lock) and runs `manage.py migrate --fake-initial` up front.
  - `terminationGracePeriodSeconds: 60` so the entrypoint trap has a fair chance to clean up before SIGKILL.
  - First apply failed on a real settings gap: Django `validate_production_settings` requires `ALLOWED_HOSTS` — init env now mirrors the full backend env.
- **Evidence (live):** db-init log shows `Removing stale /data/.startup-lock...` + `Applying core.0051_devicerelatedlink... OK` and `core.0052_schedulerruntimestate... OK`; pod `languard-6fbbf9bbb6-l4c64` 3/3 ready with 0 restarts and >90 s stable; scheduler started with its normal banner; `/data/.startup-lock` absent after backend's own lock cycle; from the Mac: `http://192.168.0.22:8000/api/v1/health/` → `200 {"status":"ok"}` (with `Host: languard.tail35421d.ts.net`), `:8080` → `200`. Note: rollout re-scheduled the pod kubernetes6 → kubernetes3 (hostNetwork ports 8000/8080 now bound on kubernetes3).
- **Rollback:** `git revert` the manifest and `kubectl rollout undo deploy/languard -n monitoring` (pre-fix live spec snapshotted to scratch `languard/deploy-pre-fix.yaml`).
- **Residuals:** upstream image fixes (staleness-tolerant lock, scheduler-side migration wait) belong to `ghcr.io/hillaliy/languard-backend` — recorded in `docs/approval-required.md` (upstream report/out-of-image change). Initialization race converges crash-free because init containers precede all main containers.

### 11. T-07 — Longhorn volume robustness counts in backup checker (2026-10-17 ~03:05–03:15 CEST)

- `kubernetes-manifests/monitoring/longhorn-backup-monitor.yaml`: ClusterRole `longhorn-backup-reader` now grants `get`/`list` on `volumes.longhorn.io`; `check.py` gained section 3 — every `volumes.longhorn.io` CR is classified by `status.robustness`/`status.state`: `degraded`/`faulted` (and `unknown` on a non-detached volume) → beat goes down; `unknown` on a detached volume is held distinct and does NOT alert (the intentionally detached iiq volume).
- Validation: `py_compile` OK; live manual Job `manual-check-t07` (from the real CronJob, real RBAC/Secret): `longhorn-vol: OK 40 volumes (unknown-detached=1 expected)` plus both freshness checks OK, push `{'ok': True}`; job deleted after. Degraded branch not exercised against prod data (no synthetic volume degradation) — documented in task table.
- Rollback: `git revert` the file + `kubectl apply` (RBAC/configmap only).
- Negative path (altered state) is code-validated only; the stateful classification logic is a straight count — no thresholds to fuzz.

### 12. T-08 — metrics-server HA via k3s addon file (2026-10-17 ~03:15–03:35 CEST)

- **Source of truth:** `/var/lib/rancher/k3s/server/manifests/metrics-server/metrics-server-deployment.yaml` on `nuc` (k3s-reconciled Addon). Backup: `/root/metrics-server-deployment.pre-ha-20261017` (sha df341b81…). New sha `e7527d16…`.
- **Change (mirrors upstream v0.8.1 `high-availability-1.21+.yaml`, archived in `reports/ralph-20261017/app08-metrics-ha/`):** `replicas: 2`; hard podAntiAffinity (`k8s-app=metrics-server`, `kubernetes.io/hostname`); appended PodDisruptionBudget `metrics-server` `minAvailable: 1`. Kept k3s's tuned values (mirror image, cipher list, 70Mi request, existing tolerations, `maxUnavailable: 1`).
- **Evidence:** rollout success; pods Ready on kubernetes2 + kubernetes6 (distinct nodes); PDB `currentHealthy: 2, disruptionsAllowed: 1`; APIService `v1beta1.metrics.k8s.io` "all checks passed"; `kubectl top nodes` sane. Bounded drill: deleted one pod — `kubectl top node` kept working via the surviving replica; replacement scheduled on kubernetes3; rollout OK.
- **Rollback:** reinstall `/root/metrics-server-deployment.pre-ha-20261017` over the addon file via `remote-admin.sh` (watcher restores single-replica state within ~20 s; PDB doc would remain unless removed — remove with `kubectl delete pdb metrics-server -n kube-system`).
- **Residual:** upstream recommends `--enable-aggregator-routing=true` on kube-apiserver to truly load-balance both instances; that is an API-server CLI flag on `nuc` — forbidden (server-node change). Requests are still spread at the Service level.

### 13. T-09 — node-down detection via existing Kuma sync (2026-10-17 ~03:35–03:50 CEST)

- `kubernetes-manifests/monitoring/uptime-kuma-monitors.yaml`: seven `node-<name>-ssh` TCP/22 monitors for the **active** nodes (nuc `192.168.0.21`, kubernetes1–6 `.19/.20/.22/.23/.24/.25`), interval 60 s, maxretries 3 — a node reads DOWN when SSH stops answering ~3 min. server-236/252 deliberately not listed (retained NotReady nodes would sit permanently red; `.236` liveness is already covered by the existing `registry-docker-tcp` monitor).
- Sync applied via a manual run of the existing `uptime-kuma-sync` CronJob: `created=7 updated=0 unchanged=25` — no pre-existing monitors touched (the previous session's additive-only constraint held).
- **Evidence:** Uptime-Kuma `heartbeat` table (read-only exec into the running pod's embedded MariaDB): all seven monitors have status=1 rows at 01:06:46–01:07:48 UTC with pings 0–2 ms.
- **Residual / approval:** Kuma's `notification` table has **0 channels** — this detection surfaces on the dashboard and through any future channel, but nothing pages anyone today. Wiring paging/notification targets needs owner-owned credentials/decisions → `docs/approval-required.md` APP-08.
- **Rollback:** delete the seven blocks from `monitors.yaml` and drop the monitors in the Kuma UI (sync is additive-only).
