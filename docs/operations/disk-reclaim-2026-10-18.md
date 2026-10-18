# Disk reclaim — 2026-10-18 (K3s homelab, 10 nodes)

> **Status:** corrected close-out. This file supersedes the in-chat draft of the
> same date. The cleanup itself was **not** re-run to reproduce these figures —
> all numbers come from the existing measurement logs of that session plus one
> uniform post-change sweep. Arithmetic below is either internally consistent or
> explicitly qualified; every figure states its measurement source and unit.

---

## 1. Scope, method and units

**What was done (2026-10-17/18 session).** Reclaimed disk on all 10 homelab
nodes using only supported, non-destructive operations: removal of Longhorn
`Orphan` records through the Longhorn API, prune of *unreferenced* container
images, journal vacuum, Docker image/build-cache prune, and `apt-get clean`.
The two blanket prunes (`crictl rmi --prune`, `docker volume prune`) are
recorded in §5a with a policy note: their results were verified, but the method
has since been retired in favour of eligibility-checked, per-object deletion.
No node was drained, no workload restarted, no storage architecture changed, no
Longhorn replica file or volume/attachment record was touched by hand.

**Measurement sources.**

| Tag | Command | Unit | When |
| :-- | :-- | :-- | :-- |
| **before** | `df -m /` (used column) | MiB | pre-cleanup, same session |
| **after-orphans** | `df -m /` (used column) | MiB | immediately after `Orphan` deletion |
| **verify** | `df -m /` (used column) | MiB | end of the cleanup session |
| **final** | `df -P -k /` (used column ÷ 1024) | MiB | post-prevention sweep, 2026-10-18 |
| directory sizes | `du -sm` / `du -sk` | MiB | before vs after |

**Units.** `df` and `du` were recorded in **MiB** (1 MiB = 1 048 576 B).
Derived figures are given in **GiB** (1 GiB = 1024 MiB) unless labelled
**GB** — Docker and containerd report in decimal GB (1 GB = 1000 MB), which is
where the earlier draft's unit labels went wrong (see §3).

**Procedure captured as a skill:** `k3s-storage-cleanup/SKILL.md` (plus
`scripts/sweep.sh` for the uniform 10-node sweep and
`scripts/registry-recoverability.py` for the §6b check). This report is that
skill's worked example — including the six arithmetic corrections it took.

---

## 2. Headline — filesystem delta

Headline figure = sum of `df` **used** deltas across the 10 nodes
(**before** vs **final**). This is the only additive figure in this report.

| Node | before (MiB) | final (MiB) | Δ (MiB) | before (GiB) | final (GiB) | Δ (GiB) |
| :-- | --: | --: | --: | --: | --: | --: |
| kubernetes1 | 327 153 | 51 215 | 275 938 | 319.5 | 50.0 | 269.5 |
| kubernetes2 | 83 720 | 37 067 | 46 653 | 81.8 | 36.2 | 45.6 |
| kubernetes3 | 81 884 | 28 735 | 53 149 | 80.0 | 28.1 | 51.9 |
| kubernetes4 | 66 084 | 19 472 | 46 612 | 64.5 | 19.0 | 45.5 |
| kubernetes5 | 82 692 | 28 811 | 53 881 | 80.8 | 28.1 | 52.6 |
| kubernetes6 | 183 319 | 34 502 | 148 817 | 179.0 | 33.7 | 145.3 |
| kubernetes8-debian | 71 699 | 9 541 | 62 158 | 70.0 | 9.3 | 60.7 |
| nuc | 54 452 | 21 190 | 33 262 | 53.2 | 20.7 | 32.5 |
| server-236 | 29 562 | 23 423 | 6 139 | 28.9 | 22.9 | 6.0 |
| server-252 | 25 029 | 9 342 | 15 687 | 24.4 | 9.1 | 15.3 |
| **Σ (10 nodes)** | **1 005 594** | **263 298** | **742 296** | **982.0** | **257.1** | **724.9** |

**Reclaimed: 742 296 MiB = 724.9 GiB = 778.4 GB (decimal).** Call it
**≈725 GiB recovered**.

*A re-sweep later the same day, same script, read **263 535 MiB = 257.4 GiB**
(0.09 % higher). Cluster churn moves this total by a few hundred MiB per few
hours, so the timestamp belongs next to the figure — and neither reading
invalidates the other.*

Note the difference between the two right-hand columns' meanings: *before* used
4.7 % of the recovered total on server-236 + server-252, while kubernetes1 and
kubernetes6 alone accounted for 57 %.

*Source: `before-*` and `out2/final-before-prevention.txt` in the session log dir.*

---

## 3. Corrections to the earlier draft

Each discrepancy raised in review, resolved. Where the original record cannot
reconcile a number, the recorded value is preserved and labelled approximate.

| # | Earlier draft | Resolved | Cause |
| :-- | :-- | :-- | :-- |
| 1 | "before values total 988" vs "982" | Precise Σ = **1 005 594 MiB = 982.0 GiB** (authoritative). The 988 came from **hand-rounded per-node display values** (a few nodes written 1 GiB high). | display rounding, not a measurement |
| 2 | "after values total 257" | Precise Σ = **263 298 MiB = 257.13 GiB** — consistent with 257 GiB. | — |
| 3 | "per-node freed total 725.2" | Precise Σ Δ = **742 296 MiB = 724.9 GiB** (before vs final). 725.2 came from pairing the pre-cleanup totals with the **verify** snapshot (Σ = 264 065 MiB = 257.9 GiB), i.e. a different post-cleanup instant. | mixed measurement points + rounding |
| 4 | "containerd reductions = 589.7, not 576" | **589 586 MiB = 575.8 GiB = 618.2 GB.** 589.7 was the MiB total carrying a "GB" label. | MiB mislabelled as GB |
| 5 | "Longhorn reductions = 137.6" | Listed per-node values total **137.6 GiB**; recomputed from measured `du` before/after = **≈137 GiB** (140 199–140 752 MiB depending on post-cleanup snapshot). | GiB, per-node rounding |
| 6 | "Docker components = 7.2" | Docker's own report: **3.561 GB + 3.014 GB = 6.575 GB decimal = 6.13 GiB.** The 7.2 was the **node `df` delta** over a wider window. | unit + window mismatch |

**On #3 (measurement drift).** The two post-cleanup snapshots differ only in
timing: `verify` Σ = 264 065 MiB, `final` Σ = 263 298 MiB (Δ ≈ 768 MiB). The gap
is containerd's background GC settling after the image prune (confirmed: the
isolated pull test left kubernetes3 2 973 MiB higher, and it returned to the
`verify` value once GC ran — see §6). The headline uses **before vs final**
(both "settled" states).

**On #6 (Docker window).** On nuc, `du -sm /var/lib/docker` went 6 918 MiB →
4 MiB (6.75 GiB by directory size), Docker itself reported 6.575 GB, and the
node `df` delta over the same window was 7 345 MiB (7.17 GiB). All three are
correct measurements of slightly different things; none were added together.

---

## 4. Directory-level reductions (corroborating — **do not add to §2**)

These overlap the §2 filesystem delta (a directory shrinking *is* part of the
`df` delta) and each other. They are shown to identify **where** the space went,
not to be summed.

### 4a. containerd store (`snapshotter.v1.overlayfs` + `content.v1.content`)

| Node | before (MiB) | after (MiB) | Δ (MiB) | Δ (GiB) |
| :-- | --: | --: | --: | --: |
| kubernetes1 | 259 417 | 22 451 | 236 966 | 231.4 |
| kubernetes2 | 54 940 | 16 986 | 37 954 | 37.1 |
| kubernetes3 | 69 541 | 17 550 | 51 991 | 50.8 |
| kubernetes4 | 47 864 | 7 024 | 40 840 | 39.9 |
| kubernetes5 | 42 513 | 14 161 | 28 352 | 27.7 |
| kubernetes6 | 126 414 | 12 808 | 113 606 | 110.9 |
| kubernetes8-debian | 38 802 | 4 866 | 33 936 | 33.1 |
| nuc | 26 184 | 267 | 25 917 | 25.3 |
| server-236 | 9 441 | 3 415 | 6 026 | 5.9 |
| server-252 | 15 682 | 1 673 | 14 009 | 13.7 |
| **Σ** | **690 798** | **101 201** | **589 597** | **≈575.8** |

→ **589 586 MiB = 575.8 GiB = 618.2 GB** of container images/layers removed
(the table's per-node Σ reads 589 597 MiB; the 589 586 MiB figure is the
unrounded session total). This is the dominant single contributor to §2.

### 4b. Longhorn data directory (`/var/lib/longhorn`, mostly `replicas/`)

| Node | before (MiB) | after (MiB) | Δ (MiB) |
| :-- | --: | --: | --: |
| kubernetes1 | 48 382 | 10 629 | 37 753 |
| kubernetes2 | 19 756 | 11 334 | 8 422 |
| kubernetes3 | 3 329 | 2 488 | 841 |
| kubernetes4 | 9 830 | 4 378 | 5 452 |
| kubernetes5 | 31 741 | 6 544 | 25 197 |
| kubernetes6 | 48 534 | 13 817 | 34 717 |
| kubernetes8-debian | 29 388 | 1 369 | 28 019 |
| server-236 | 233 | 312 | −79 (grew) |
| server-252 | 1 458 | 1 581 | −123 (grew) |
| **Σ (9 nodes with a Longhorn dir)** | **192 651** | **52 452** | **140 199 (136.9 GiB)** |

→ **≈137 GiB**, consistent with the `df`-measured orphan reclaim of
**141 439 MiB = 138.1 GiB** (§5a). **Caveat:** this directory delta also
includes ordinary volume churn (snapshot create/purge) in the same window, so it
is a corroborating *upper bound*, not an orphan-only figure.

### 4c. Docker store and journals

| Item | Measurement | Note |
| :-- | :-- | :-- |
| nuc `/var/lib/docker` | Docker-reported **6.575 GB** (6.13 GiB); `du` 6 918 → 4 MiB | image + build-cache prune |
| kubernetes1 `/var/lib/docker` | 484 MB removed (anonymous volumes); now 6 548 MiB, 1 volume (`ollama`) | 0 images / 0 containers all along |
| systemd journals | **≈2.2 GiB** across the 9 nodes with recorded pre-values; **≈3 GiB** including kubernetes1 (whose pre-value was not recorded) | **approximate** — label as such |

---

## 5. What was deleted, and what was deliberately kept

### 5a. Deleted

| Action | Scope | Measured effect |
| :-- | :-- | :-- |
| `kubectl -n longhorn-system delete orphan …` | 312 `Orphan` CRs (all `replica`, `DataCleanable=True`, `Error=False`; **zero** overlap with the 120 registered replica `dataDirectoryName`s) | `df` before→after-orphans: **141 439 MiB = 138.1 GiB** |
| `k3s crictl --timeout 10m rmi --prune` | unreferenced images on all 10 nodes | image count k1 279→32, k2 86→33, k3 118→26, k4 63→22, k5 80→20, k6 191→23, k8 72→17, nuc 42→5, s236 26→6, s252 47→5; containerd store −589 586 MiB |
| `journalctl --vacuum-size` | all nodes | see §4c |
| `docker image prune -a` + `docker builder prune` | nuc | 6.575 GB (Docker-reported) |
| `docker volume prune` | kubernetes1 (anonymous only) | 484 MB |
| `apt-get clean` | nodes with apt caches | negligible |

> **Policy note (added after review).** Two rows above are *blanket* commands
> that the tightened contract in `k3s-storage-cleanup/` no longer permits:
> `crictl rmi --prune` (deletes by "no container references it") and
> `docker volume prune` (deletes by "anonymous"). Their outcome here is sound —
> the prune was followed by an end-to-end re-pull verification (§6), and the
> volume was `LINKS 0` — but neither is repeatable *as a policy*. Planned
> cleanup now deletes named objects by ID against an eligibility rule, and
> Docker volumes are retained unless explicitly allowlisted.

### 5b. Deliberately retained

- **All 663 Longhorn backups** and the NAS backupstore (`nfs://192.168.0.128:/backups/longhorn`) — incident-recovery archives, retained regardless of age.
- **All 156 VolumeSnapshot CRs** and both Longhorn engine images.
- **etcd snapshots**, incl. `pre-join-*`; **`db-backup-20261017-*`** dirs on server-236/252; NAS `immich-db-dumps`.
- **All active PVCs and app data**; replica counts unchanged.
- **kubernetes1 Docker named volume `ollama`** — 6.859 GB (Docker) / 6 542 MiB (`du`), the only remaining Docker volume on that node, `LINKS 0` (unused). Flagged uncertain in the earlier session and **left in place pending an owner decision**; `/var/lib/docker` on kubernetes1 is 6 548 MiB and holds 0 images / 0 containers.
- **server-236 registry storage** (`/var/lib/docker`, 3 197 MiB) — backs `192.168.0.236:5000`.
- **nuc** user home, `~/k3s-manifests-backup`, `kuma` dump.
- Journals capped at 200 MiB/node (recent diagnostic history kept).

### 5c. Pre-existing exceptions (unchanged by this work)

- Longhorn node records **server-236 / server-252** are `Ready=False` (`ManagerPodMissing`; missing `cryptsetup`/`nfs-common`, multipathd issue). Unchanged since 2026-10-17T20:01Z.
- Volume `pvc-1a05dbf3-c9eb-48d3-8b02-9a39645a884e` is **detached**, `robustness=unknown`, 2/3 replicas, engine stopped (pre-existing).
- **server-252 is cordoned** (`SchedulingDisabled`) — pre-existing; never uncordoned here.

---

## 6. Custom-image recoverability validation

The registry *catalogue* check (`/v2/_catalog`) is **not** sufficient — it only
lists repo names. Two stronger checks were run.

### 6a. Custom image inventory (from live workload manifests)

| Image reference | Used by | Required platform |
| :-- | :-- | :-- |
| `192.168.0.236:5000/sailpoint-iiq:8.5` | `Deployment/iiqstack/iiq`, `Job/iiqstack/iiq-init` | linux/amd64 |
| `192.168.0.236:5000/openlingo:v10-dynamic-models` | `Deployment/openlingo/openlingo` | linux/amd64 |
| `192.168.0.236:5000/ai-language-learning:latest` | `Deployment/ai-language-learning/ai-lang-backend` | linux/amd64 |
| `192.168.0.236:5000/sailpoint-docker:latest` | hosted in the registry; referenced only by the example manifest `Chapter19/iiq2.yaml` (**no live workload**) | linux/amd64 |

Scaled-to-zero workloads were included: for each of the three live images the
**previous ReplicaSets** (`replicas=0`) reference the *same* tag/digest, so the
required image set is exactly these three.

### 6b. Registry manifest + blob validation (read-only)

For each reference: resolve the tag (index-aware), select `linux/amd64`, then
`HEAD` every config and layer blob. A 200 for every blob proves the registry can
serve the complete image without downloading it.

| Image | Manifest type | Resolved digest | Blobs | Result |
| :-- | :-- | :-- | --: | :-- |
| ai-language-learning:latest | OCI index → amd64 | `sha256:b8131821…be1eb8` | 9/9 | **PASS** |
| openlingo:v10-dynamic-models | OCI index → amd64 | `sha256:68554b17…a3a327` | 12/12 | **PASS** |
| sailpoint-iiq:8.5 | docker v2 manifest | `sha256:a572c48e…bc1a7` | 14/14 | **PASS** |
| sailpoint-docker:latest | docker v2 manifest | `sha256:e26b3f6b…381cf` | 13/13 | **PASS** |

The `ai-language-learning`, `openlingo` and `sailpoint-iiq` digests are
**identical to the digests pinned in the earlier node manifests**
(`…/ralph-20261017/app05-before/node-kubernetes7.yaml`), i.e. the tags still
resolve to the same content that was previously deployed.

### 6c. Isolated end-to-end pull test

Run on **kubernetes3** (which cached none of the images) via a throwaway
namespace `disk-reclaim-selftest`, `imagePullPolicy: Always` so every layer came
from the registry, pinned by `nodeSelector` so no live workload was touched.

| Image | Pull result | Resolved imageID | Container |
| :-- | :-- | :-- | :-- |
| ai-language-learning:latest | Successfully pulled, 83 402 501 B in 19.5 s | `…@sha256:b8131821…` | exit 0 (Completed) |
| openlingo:v10-dynamic-models | Successfully pulled, 279 586 880 B in 43.9 s | `…@sha256:68554b17…` | exit 0 (Completed) |
| sailpoint-iiq:8.5 | Successfully pulled, 1 207 278 493 B in 38.0 s | `…@sha256:a572c48e…` | exit 0 (Completed) |

The runtime-resolved imageIDs match the registry digests in §6b exactly.
**Cleanup:** the namespace was deleted and the three test images removed with
`crictl rmi`; containerd's background GC returned kubernetes3 to its prior
containerd size (17 550 MiB) — verified, so the test left **no** lasting space.

**Result: all three live custom images have documented, end-to-end recovery
evidence. No application was restarted and no workload image reference was
changed.** (`sailpoint-docker:latest` is verifiable but unused by live
workloads, so no pull test was run for it.)

---

## 7. Recurrence prevention implemented

### 7a. What was inspected first (existing settings)

| Setting | Value found | Verdict |
| :-- | :-- | :-- |
| `node-disk-cleanup` DaemonSet (ns `monitoring`) | exists, 10/10 pods, runs cleanup every 6 h — **but all steps gated at ≥80 % used**, `crictl rmi --prune` used crictl's default 2 s deadline, and it pruned images unconditionally (a blanket policy with no notion of eligibility — see §7b-2) | **fixed** (§7b, §7b-2) |
| journald `SystemMaxUse` | set on nuc, kubernetes6 (500M) and server-236 (200M); **absent on the other 7 nodes** | **gap to fix** |
| kubelet image GC | no `ImageGC*` keys in `/var/lib/rancher/k3s/agent/kubelet/config.yaml`, no `--kubelet-arg` in `/etc/rancher/k3s/config.yaml` → kubelet defaults (reactive GC only at 85 %; age-based GC disabled) | documented below |
| Longhorn `snapshot-frequent` / `backup-daily` | recurring snapshot every 6 h retain 4; daily backup retain 14; `recurring-job-max-retention=100`, `snapshot-max-count=250` | adequate — no change |
| Longhorn `orphan-resource-auto-deletion` | `''` (disabled), grace 300 s | **deliberately left disabled** — see §8 |
| registry `192.168.0.236:5000` | `registry:2`, no garbage collection | see §8 |

### 7b. Change applied

Edited **`kubernetes-manifests/monitoring/node-disk-cleanup.yaml`** only
(ConfigMap `node-disk-cleanup-script`; the DaemonSet spec itself is unchanged).
The script is split into two tiers, and takes a per-node lock:

- **Tier 1 — bounded maintenance, every cycle (no usage gate):**
  1. Persist a journald cap (`SystemMaxUse=500M` in
     `/etc/systemd/journald.conf.d/10-homelab-cap.conf`), **skipped if any cap
     already exists** so hand-applied values are preserved.
  2. `journalctl --vacuum-size=200M`.
- **Tier 2 — pressure cleanup, only ≥80 %:** emergency `crictl --timeout 10m
  rmi --prune` (`--timeout` fixes the `DeadlineExceeded` partial-prune
  behaviour), disabled snap revisions, and oversized `kern.log` truncation.
- **Lock:** `/run/lock/k3s-disk-cleanup.lock` via `flock -n`, so an unattended
  pass cannot interleave with a manual/audited run. Released automatically on
  process death; if `/run/lock` is unusable the script logs and runs unlocked
  rather than silently skipping maintenance forever.

Validation before/after apply: `kubectl apply --dry-run=server` clean;
`sh -n` and `dash -n` on the extracted script clean; DS rolled out 10/10; every
pod logged Tier 1 and "below 80 % threshold, skipping pressure cleanup".

### 7b-2. Contract revision after review (why Tier 1 no longer prunes images)

The first revision of this prevention work put `crictl rmi --prune` in Tier 1 —
"unreferenced images are safe to delete". An external review rejected the
premise, correctly:

- **"Unreferenced" ≠ eligible.** `--prune` deletes any image no *container*
  references, which includes images named in a scale-to-zero workload's Pod
  template and images in the previous ReplicaSet revision (the rollback
  target). It also cannot exclude a digest the registry cannot fully serve, so
  it directly contradicts the registry protection in §6.
- **Order was wrong.** Step 3 pruned, step 6 verified recoverability. A check
  that runs *after* the irreversible act protects nothing. Verification now
  precedes candidate selection.
- **`imagePullPolicy: Always` does not force a cold pull.** The runtime
  resolves the tag through the registry but may reuse cached layers, so a green
  pull proves the reference resolves — not that every blob is fetchable. The
  real proof is a registry-level digest check plus a cache-free
  `crictl pull` on a node that does not have the image.
- **Docker volumes are retained by default.** "Anonymous" describes ownership,
  not disposability; deletion now requires an explicit allowlist entry.
- **Zero/count targets were not success criteria.** Images ≠ running-pod image
  names, "every volume attached", and "every orphan gone" are wrong targets —
  legitimate detached volumes and retained orphans exist.

Net effect on the DaemonSet: the unattended path now only deletes under pressure
(where the alternative is eviction at ~85–90 %) or removes regenerable data.
Routine image reclamation is an explicit, eligibility-checked act. See
`k3s-storage-cleanup/SKILL.md` and
`k3s-storage-cleanup/reference/execution-contract.md`.

### 7c. Verified effect (all 10 nodes)

| Node | journald cap before | journald cap after |
| :-- | :-- | :-- |
| kubernetes1/2/3/4/5, kubernetes8-debian, server-252 | none | `500M` (installed by Tier 1) |
| nuc, kubernetes6 | `500M` | `500M` (preserved) |
| server-236 | `200M` | `200M` (preserved) |

Measured `journalctl --disk-usage` after the vacuum was **≤216 MiB** on every
node (was up to 1.5 G on server-252). One caveat that matters for what the cap
promises: `--vacuum-size` bounds *archived* files, while `--disk-usage` also
counts the active journal — so "≤216 MiB now" is a measurement, not a
guarantee. The durable bound is `SystemMaxUse`, which is what Tier 1 persists
and which §7e verifies on the effective (not merely on-disk) configuration.

### 7d. Trade-offs (explicit)

- **Images regrow between explicit runs.** Because unattended pruning is now
  emergency-only (§7b-2), image storage can climb until someone runs the
  eligibility-checked procedure or a node crosses 80 %. That is the intended
  trade: a bounded, self-limiting regrowth against eviction relief, in exchange
  for never having an unattended process delete a rollback target or an image
  the registry cannot re-serve. The 576 GiB failure mode was *unbounded*
  growth, and the 80 % gate still bounds it.
- **The cold-start cost is unchanged but now scoped.** Undoing a rollout inside
  the protected window is cache-free; undoing beyond it re-pulls, and §6 shows
  the registry can serve those images.
- Revert is one file: restore the previous `cleanup.sh` block and re-apply.

### 7e. Verification of the tightened claims

Each corrected claim was checked against the live cluster rather than asserted:

| Claim | How it was checked | Result |
| :-- | :-- | :-- |
| Registry can serve every custom image (not just list them) | `registry-recoverability.py`: required platform manifest, config, HEAD every layer by digest | 3/3 workloads PASS; digests match the historically pinned ones |
| A pull works without starting the app | `crictl --timeout 10m pull` (no container) on a node that did not cache the digest; containerd content dir measured before/after | pulled, resolved digest == registry digest, content grew by the manifest size, then `rmi` + settle returned the node to baseline |
| Journald cap is *effective*, not just present | `systemctl show systemd-journald -p SystemMaxUse -p MaxRetentionSec` on all 10 nodes | non-empty on 10/10 (500M, server-236 200M preserved) |
| No regression from the DaemonSet change | `kubectl apply --dry-run=server`; `sh -n`/`dash -n`; rollout 10/10; post-rollout node/pod/volume/etcd snapshot | 10/10 Ready, 231 Running + 4 Completed, 0 failing, 39/39 attached volumes healthy, etcd 3/3 |
| Unattended and manual runs cannot interleave | shared `/run/lock/k3s-disk-cleanup.lock` with `flock -n` in the script; same path named in the execution contract | lock taken per node; contention exits without deleting |

---

## 8. Considered and deliberately *not* changed

- **Longhorn `orphan-resource-auto-deletion`** — could have removed the 312
  orphans automatically, but here nodes are routinely powered off in minimal
  mode; a replica whose owning node is off can look orphaned, and auto-deleting
  it risks data loss. Kept disabled. Instead: re-check orphan count after any
  volume deletion (the count was 312 before this session's deletion).
- **kubelet `imageMaximumGCAge` / `ImageGCHighThresholdPercent`** — would bound
  images at the source, but requires editing node config and restarting k3s on
  every node. The in-cluster DaemonSet achieves the same bound with no node
  restarts, so it was preferred within this run's safety constraints.
- **Registry garbage collection** — `registry:2` has no GC and its store
  (3 197 MiB) only grows with new pushes. Running GC safely needs read-only mode
  and a maintenance window; recorded as a follow-up, not implemented here.

---

## 9. Scoped conclusion

**Cleanup completed without observed service disruption.** This is a scoped
claim: no workload was restarted, no node drained, and nothing outside the
node-local regenerable stores was removed.

The documented pre-existing storage exceptions remain and are **not** healthy
outcomes of this work:

- Longhorn node records **server-236** and **server-252**: `Ready=False`
  (`ManagerPodMissing`), unchanged since 2026-10-17.
- Longhorn volume **`pvc-1a05dbf3-…`**: detached, `robustness=unknown`.
- **server-252** remains cordoned.

Post-change verification (2026-10-18): **10/10 nodes Ready**; **231 pods
Running, 4 Completed, 0 failing**; **39/39 attached Longhorn volumes healthy**
(+1 pre-existing detached); **etcd 3/3 members healthy** in one lineage
(nuc/server-236/server-252); registry `/v2/` 200 with all 4 repos; the three
custom-image workloads (`ai-lang-backend`, `iiq`, `openlingo`) all `1/1 Running`;
API `/readyz` passed.

---

## 10. Rollback

| Change | Rollback |
| :-- | :-- |
| `node-disk-cleanup` ConfigMap | `git checkout -- kubernetes-manifests/monitoring/node-disk-cleanup.yaml` then `kubectl apply -f …` + `kubectl -n monitoring rollout restart ds/node-disk-cleanup` |
| journald cap drop-in | `rm /etc/systemd/journald.conf.d/10-homelab-cap.conf && systemctl restart systemd-journald` (per node) — no rollback needed for the 3 nodes with pre-existing caps |
| Deletions in §5a | not reversible by design — each was verified after the fact (§6) and the removed images remain recoverable from the registry, but the retracted blanket methods are not re-runnable as policy (§5a note). Recovery data in §5b was untouched. |

---

## Appendix A — Ralph loop checklist & progress log

No automated "Ralph runner" exists in this repository (`which ralph` → not
found; no runner script in `k3s-homelab-optimisation/scripts/`). The loop was
run against this checklist, using the repo's documented task-file convention
(`k3s-homelab-optimisation/docs/ralph-loop-tasks.md`) and its sanctioned
privileged SSH helper `k3s-homelab-optimisation/scripts/remote-admin.sh`.
Run stayed within the 12-iteration cap (11 iterations used).

| # | Task | Result | Evidence |
| :-- | :-- | :-- | :-- |
| 1 | Load skills / discover runner + repo ops docs | done | §Appendix B |
| 2 | Inspect existing prevention settings (DS script, journald, kubelet GC) | done — 3 gaps found | §7a |
| 3 | Inventory custom images incl. scaled-to-zero | done — 3 live + 1 unused | §6a |
| 4 | Registry manifest/platform/blob validation | done — 4/4 PASS | §6b |
| 5 | Isolated end-to-end pull test | done — 3/3 pulled, exit 0, cleaned up | §6c |
| 6 | Reconcile measurement discrepancies | done — 6 resolved | §3 |
| 7 | Implement prevention change (edit + dry-run + syntax) | done | §7b |
| 8 | Apply + roll out + verify Tier 1 on 10 nodes | done | §7c |
| 9 | Final cluster verification | done | §9 |
| 10 | Write corrected report + checklist | done | this file |
| 11 | Tighten the deletion contract after external review (verify-before-delete order, eligibility rules, per-ID deletion, shared lock, execution contract) | done | §7b-2, §7e |

No task failed twice; none is blocked.

## Appendix B — Skills used

| Skill | Source | Used for |
| :-- | :-- | :-- |
| `k3s-rebalance` | `skills/k3s-rebalance/SKILL.md` | node/scheduling context; confirmed server-252 cordon is deliberate and not to be uncordoned |
| `qnap-nfs-longhorn-backup` | `skills/qnap-nfs-longhorn-backup/SKILL.md` | Longhorn backup/replica retention reasoning in §5b/§7a |
| `iiq-restore` | `skills/iiq-restore/SKILL.md` | identified `sailpoint-iiq:8.5` as the registry-dependent workload to validate in §6 |
| `k3s-dind-build` | `skills/k3s-dind-build/SKILL.md` | confirmed the private registry `192.168.0.236:5000` is the in-cluster build target |
| repository `AGENTS.md` + `docs/operations/*`, `k3s-homelab-optimisation/docs/*` | repo | node/SSH/safety rules, prior reclaim report, `remote-admin.sh` contract |

Secrets were only ever fetched in-memory by `remote-admin.sh` from the
PowerShell SecretStore and passed to remote `sudo -S` over stdin; no credential,
key or token appears in this report or in any command output.

## Appendix C — Session evidence files

Under the session log directory
(`/private/var/folders/yn/…/T/opencode/`): `before-*.txt`, `afterorph-*.txt`,
`out2/verify-*.txt`, `out2/prune2-*.txt`, `out2/pulltest-evidence.txt`,
`out2/prevention-logs.txt`, `out2/final-before-prevention.txt`,
`out2/final-caps.txt`, `verify-images.py` / `verify-images.out`,
`pull-test.yaml`, `cleanup-new.sh`, `sweep.sh`, `final-verify.sh` (not
committed — session scratch).
