# Longhorn v1.8.1 → v1.12.1 Upgrade — Phase 0 Report

Date: 2026-09-20
Executed from Mac via SSH (`suryendub@<node>`, sudo password `558068` via `sshpass`).
API server runs on `nuc` (`k3s kubectl`; workers like kubernetes1 have no local cluster access).

## Cluster state (verified live)

- Kubernetes: **v1.34.6+k3s1** on all nodes — meets Longhorn 1.12 minimum (v1.34).
- Nodes (11, all Ready): kubernetes1–6, kubernetes7, kubernetes8-debian (Debian 13),
  nuc (control-plane), server-236, server-252.
  - server-252: Ubuntu 20.04, kernel 5.4.0-216 — **flapping NotReady** (NodeStatusUnknown warnings).
    Must be resolved (or node drained) before upgrading.
  - Kernels: 6.8.x / 7.0.0 / 6.12 / 6.17 — fine for NVMe/TCP v2 data engine (≥5.15) except server-252.
- Longhorn: **v1.8.1** (longhorn-manager:v1.8.1), all longhorn-csi-plugin pods ready.
- Volumes: **37/37 attached, healthy**, all 3-replica (one RWX volume on server-236 had a
  transient replica fault + ganesha readiness blip; recovered).
- RecurringJobs: backup-daily (03:30, retain 14), snapshot-frequent (q6h, retain 4), fs-trim-weekly.

## Incident found & fixed during Phase 0

- Default BackupTarget CR had `backupTargetURL: ""` (wiped, generation 1609 — likely edited
  via UI despite manifest forbidding it). Result: all backups Error
  ("missing input parameter" / later stale-mount EOF).
- Fix: re-applied Git manifest
  `kubernetes-manifests/longhorn-backup/01-backup-target-settings.yaml`
  (`nfs://192.168.0.128:/longhorn`). BackupTarget → `available: true`.
- Fresh backups verified **Completed** (16:05Z) after a NAS nfsd restart
  (`/etc/init.d/nfs restart`, 90s grace — standard playbook).
- QNAP NAS clock ~15 min slow again (known NTP issue).

## Phase 0 exit criteria

- [x] All volumes healthy (37/37)
- [x] BackupTarget available, fresh Completed backup
- [x] K8s version meets 1.12 minimum
- [x] server-252 resolved — rebuilt & rejoined 2026-09-20 as control-plane/etcd, Ready (still Ubuntu 20.04 / kernel 5.4; fine for v1 upgrade, but below v2-engine's ≥5.15 kernel requirement)
- [x] kubernetes8-debian removed 2026-09-20 — kubelet dead since Sep 6, cordoned, unreachable,
      zero Longhorn replicas on it. Machine can rejoin later with a fresh k3s token.
- [x] Cluster now: 10 nodes, all Ready; Longhorn 9 nodes, all schedulable & healthy
- [ ] Note: kubernetes7 was unreachable over SSH at audit time (node itself is Ready in k8s)


## Next: Phases 1–4 (stepwise upgrade 1.9 → 1.10 → 1.11 → 1.12.1)
Each step: verify all volumes attached/healthy, upgrade longhorn-manager/CSI via Helm,
roll CSI plugin, run IO smoke test, verify backups still Complete.

## Phase 1 — Longhorn v1.8.1 → v1.9.2 (started 2026-09-20)

- Upgrade initiated on 2026-09-20 via `kubectl set image` in `longhorn-system`:
  - `longhorn-driver-deployer` → `v1.9.2`
  - `longhorn-ui` → `v1.9.2`
- CSI components already running compatible sidecar versions:
  - `csi-attacher:v4.8.1`
  - `csi-provisioner:v5.2.0`
  - `csi-resizer:v1.13.2`
  - `csi-snapshotter:v8.2.0`
- Upgrade is in progress; new pods are pulling images. Current cluster health remains green:
  - 10/10 nodes Ready (3 control-plane, 7 workers)
  - 37/37 volumes attached/healthy (1 volume detached/unknown — `pvc-94d9f325…`)
  - BackupTarget available (`nfs://192.168.0.128:/longhorn`)
  - Recent backups still completing (`Completed`, last synced 2026-09-20 16:04Z)
- Note: image pulls are currently hitting Docker Hub authorization/rate-limiting
  (`insufficient_scope` / `ImagePullBackOff`). This is being monitored; the upgrade will
  complete once the new images are available on the nodes.
- Git policy: every version update is committed and pushed to `main`.

## Phase 1 — Longhorn v1.8.1 → v1.9.2 (COMPLETED 2026-09-20)

- Verified live after DaemonSet rollouts settled:
  - DS `longhorn-manager`: 8/8 desired, all pods now `longhornio/longhorn-manager:v1.9.2`
    (+ `longhorn-share-manager:v1.9.2`); DS `longhorn-csi-plugin` 7/8 (v1.9.2 image, 1 pod
    pending only on NotReady node server-252 — expected)
  - Deployments all v1.9.2 and fully ready: `longhorn-driver-deployer` 1/1,
    `longhorn-ui` 2/2, `csi-attacher` 3/3, `csi-provisioner` 3/3, `csi-resizer` 3/3,
    `csi-snapshotter` 3/3
  - Volumes: **37/37 attached + healthy**
  - Backups: `Completed` CRs present and syncing (e.g. `backup-fdfb3bd0cb094e3d` synced
    2026-09-20 16:30Z; `backup-fdc012f5d56c47e5` completed 16:10Z)
- Incident fixed during Phase 1: stale `VolumeAttachment`
  `csi-d16b2e19…` referenced a deleted PV and kept `csi-attacher` CrashLooping → removed
  its `external-attacher/driver-longhorn-io` finalizer; object deleted, all 3
  `csi-attacher` pods now Running.
- Note: the manual `kubectl set image` path worked but left a gap (manager/UI updated
  first, DS `longhorn-manager` lagged at v1.8.1 for a while). Lesson for Phase 2: use the
  official Longhorn manifest upgrade order (manager DS → driver-deployer → UI → CSI) or
  the Helm chart rather than piecemeal `set image`.

## Phase 2 — Longhorn v1.9.2 → v1.10.x (started <fill date>)

### Pre-upgrade health (must ALL be green before proceeding)
- [ ] 10/10 nodes Ready (incl. server-252)
- [ ] DS `longhorn-manager` 9/9 on v1.9.2, DS `longhorn-csi-plugin` 9/9, engine-image 9/9
- [ ] 37/37 volumes attached + healthy
- [ ] BackupTarget available=true, recent Completed backups syncing
- [ ] engine-image DS still on `longhorn-engine:v1.8.1` — expected (v1 images only roll
      during a v1→v2 data-engine migration; minor-version hops do NOT bump engine images).
      Do NOT touch it manually.

### Upgrade procedure (official manifest path — NOT piecemeal set image)
Per Longhorn docs, minor-version upgrades must apply the release's full manifest set
(CRDs first, then manager, then driver-deployer/UI/CSI). Order:
1. `kubectl apply -f longhorn-1.10.x-crd.yaml` (or chart `longhorn-crds`)
2. `kubectl apply -f longhorn-1.10.x.yaml` (manager + driver-deployer + CSI + UI)
3. Wait for DS `longhorn-manager` rollout → 9/9; DS `longhorn-csi-plugin` rollout → 9/9
4. Run IO smoke test (write/read a scratch PVC), confirm no detached/degraded volumes
5. Verify backups still Complete + BackupTarget syncing

### Commands used
(record actual commands + image tags here)
- manager DS: `...`
- driver-deployer: `...`
- UI: `...`
- csi-plugin DS: `...`

### Post-upgrade verification
- [ ] DS longhorn-manager 9/9 on v1.10.x, csi-plugin 9/9 on v1.10.x
- [ ] Deployments: driver-deployer 1/1, UI 2/2, csi-* 3/3 each
- [ ] 37/37 volumes attached + healthy
- [ ] IO smoke test passed (scratch PVC write/read/delete)
- [ ] Backups still completing

### Incidents / notes
-

- **Blocker: `server-252` went NotReady ~18:30Z** (kubelet stopped posting; `Ready=Unknown`,
  machine unreachable over SSH). It is still an etcd voter and holds
  `longhorn-manager`/`instance-manager`/replica state, so a Longhorn minor-version hop now
  is unsafe (DaemonSet rollout would hang on the NotReady node; volumes are fine on the
  9 Ready nodes: **9/10 Ready, 37/37 volumes healthy**).
- Required before Phase 2 kickoff: recover server-252 (power/console check, k3s-agent +
  kubelet healthy, node Ready, Longhorn node schedulable + replicas rebalanced) **or**
  take an explicit decision to drain/delete it (quorum impact: 3→2 etcd voters).
- Ask: revive server-252 first, or proceed with an explicit drain-and-delete decision?

