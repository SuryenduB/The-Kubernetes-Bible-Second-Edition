# Cull final verification

Date: 2026-10-18 (all times UTC). Cluster: `https://192.168.0.21:6443`.
This record captures the closing evidence for the seven-phase homelab
simplification cull (`cull-start` .. `cull-complete` tags). Every claim below was
re-checked live on 2026-10-18 after the last removal (`6299733`, phase 7b).

## Done-criteria evidence

### 1. All planned removals executed, one commit per removal

`git log --oneline` shows 26 dedicated removal commits (phases 1-7), each pushed
to `github.com:SuryenduB/The-Kubernetes-Bible-Second-Edition.git` (`main`) before
the next removal started. No history was rewritten; corrections were made with
follow-up commits (`f3e8bb9`, `736cb7c`, `ea92db3`) or `--amend` while unpushed.

| Phase | Removed | Commit(s) | Tag |
|---|---|---|---|
| 1 | argocd bootstrap secret, legacy default iiq/phpldapadmin Services+proxies, duplicate argocd-1/openwebui-1 proxies, pgweb, iiqstack NetworkPolicies, server-252 scheduling disabled | `aa42c6c` `f23f62f` `8f29d16` `c4f7b97` `b0801be` (+`52153a7` KEEP record) | `cull-phase-1-done` |
| 2 | Kuvasz, Trove, LAN Sheriff, LanGuard, Lantern, Homelab Monitor, OmniSight, PooML, LogChef, Apprise, orphaned monitor reconciliation | `733f971` `bd0806a` `27bd771` `170c784` `ec8f97a` `d3ee311` `c035249` `659ec48` `44446b6` `01b7924` `30a9359` | `cull-phase-2-done` |
| 3 | Homarr, Cairn (+ hash record) | `2614c8a` `d53d427` `736cb7c` | `cull-phase-3-done` |
| 4 | BookHoarder, Booklogr, BookOrbit, LibrisLog | `ad1a711` `6f14e82` `9d95174` `c57dc74` (+`f3e8bb9`) | `cull-phase-4-done` |
| 5 | OpenLingo (+PostgreSQL), AI Language Tutor (+PostgreSQL, +src gitlink) | `8f88e5e` `5fb6387` | `cull-phase-5-done` |
| 6 | Homelab Manager (`homelab-manger`) | `3338475` | `cull-phase-6-done` |
| 7 | db-mysql (evidence-gated), iiq-ssh (evidence-gated) | `40d6ec4` `6299733` | `cull-phase-7-done` |

### 2. Live cluster free of every removed app

Sweep `kubectl get all,pvc,cm,ingress -A | grep -i <app>` returned nothing for
all 26 removed apps (kuvasz, trove, lan-sheriff, languard, lantern,
homelab-monitor, omnisight, pooml, logchef, apprise, homarr, cairn,
bookhoarder, booklogr, bookorbit, librislog, openlingo, ai-lang, homelab-mang,
db-mysql, iiq-mysql, ssh/iiq-ssh, pgweb, argocd-1, openwebui-1, legacy default
iiq/phpldapadmin). Namespaces `openlingo`, `ai-language-learning`, `dashboard`,
`books` are gone. Tailscale proxies for every removed Service auto-removed with
their Services (current proxy list contains only retained apps).

### 3. Retained workloads healthy after every phase and at close

All namespaces (`media`, `monitoring`, `ai`, `linguacafe`, `homepage`,
`server-management`, `longhorn-system`, `iiqstack`, `argocd`) report every
Deployment/StatefulSet fully available. `calibre-library-pvc` (500Gi, shared by
Calibre-Web) is Bound. RemotePower verified 1/1 Ready on its original data
volume after the phase-6 namespace-cascade incident (see progress.md row 6) and
its Uptime Kuma monitor is UP.

### 4. Uptime Kuma -> Gotify direct alerting proven before Apprise removal

Phase 2 precondition: Uptime Kuma's Gotify channel configured (notification id 1,
isDefault), test notification sent and confirmed arrived in Gotify twice before
Apprise was deleted. Live monitor set now equals the desired ConfigMap
(`uptime-kuma-monitors.yaml`, 40 monitors) plus only the manually added
`etcd-nas-backup`.

### 5. Storage ownership proven before every PVC/PV delete; no orphans left

- Reclaim-policy behavior handled per PV: `Delete`-reclaim volumes were
  auto-cleaned (openlingo 5Gi, homelab-manger 2Gi, bookorbit db 5Gi stub);
  `Retain`-reclaim volumes had PV + Longhorn volume deleted manually after
  ownership proof (librislog 2Gi, booklogr 2Gi, bookhoarder 5Gi, db-mysql 10Gi).
- Orphan `mysql-pvc` (2Gi NFS) proved mounted by no pod before deletion; NAS
  data directory retained on Synology (path recorded in progress.md row 7a).
- Shared `calibre-library-pvc` never touched. Final PV inventory contains only
  Bound volumes owned by retained apps (34 PVs, all Bound).
- Only detached Longhorn volume is the pre-existing baseline one
  (`pvc-1a05dbf3`, recorded in baseline.md) - not a cull regression.

### 6. Health gate passed after every removal

Nodes: 9 Ready + `server-252` Ready,SchedulingDisabled (intentional, unchanged).
etcd: `endpoint health --cluster` reports 3/3 healthy (nuc .21, server-236 .236,
server-252 .252) - re-run at every gate and at close. No faulted Longhorn
volumes. Pre-existing problems (baseline detached volume; iiq-app pod-to-pod
dataplane DOWN documented in progress.md row 7a) are not regressions and were
left for the IIQ runbook.

### 7. Git is the ledger; progress record complete

`docs/operations/cull/progress.md` records every item with REMOVE/KEEP/BLOCKED
decision, reason, dependency check, resources removed, storage freed, real
commit hash (all placeholders back-filled in `ea92db3`) and validation evidence.
Working tree clean; everything pushed. Tags `cull-start`, `cull-phase-1-done` ..
`cull-phase-7-done`, `cull-complete` all pushed.

### 8. Documentation synced with every removal

Per removal: `kubernetes-manifests/README.md` (file tree, namespace table,
app tables), `docs/homelab/K3s_Homelab_Template.md` (exposure tables,
credential register, image-version notes, internal-backend tables),
`kubernetes-manifests/monitoring/uptime-kuma-monitors.yaml` (applied),
`kubernetes-manifests/homepage/homepage.yaml` (tile removed + checksum rotated
from live ConfigMap hash after each edit; Homepage rolled out 1/1 each time),
longhorn-backup duration comment, cloudflare "never publish" lists.
Exposure-table hostname diff vs `cull-start` equals exactly the 26 removed
hostnames, with no unintended additions. Historical/dated records
(`docs/homelab/backups/*`, `docs/iiq/IIQ_POD_CURRENT_STATE.md`,
`kubernetes-manifests/docker-compose.yaml` upstream reference copy) were
intentionally left as written.

### 9. Kustomize buildable

`kubectl kustomize kubernetes-manifests` exits 0 (verified after every removal
and at close). `server-management/kustomization.yaml` no longer references the
removed manifest; the `server-management` Namespace object now lives in
`remotepower.yaml` (with the Retain-reclaim volume pinned via `volumeName`).

### 10. Apprise-replacement notification path live

Uptime Kuma Gotify channel -> `gotify.monitoring.svc.cluster.local`, default
channel, test messages confirmed received (phase 2 evidence, commit `01b7924`).

### 11. No forbidden operations performed

Never ran `kubectl apply -k kubernetes-manifests` on the full tree (only
per-file applies plus read-only `kustomize` builds); kubeconfigs untouched;
removals were `kubectl delete -f <file>` for whole-manifest apps and explicit
named deletes for sub-objects of the retained `iiq-stateful.yaml`.

### 12. Failed approaches bounded

Three transient hiccups, each resolved within retry limits and documented:
Uptime Kuma API pod timing (retried with longer waits, then succeeded);
dynamic-provisioning race during RemotePower PV rebind (resolved by
claimRef clear + `volumeName` pin); kubectl multi-resource delete parsing
(service names interpreted as deployments; corrected immediately).

### 13. Storage freed summary

Phase 2: Kuvasz 10Gi + others per rows. Phase 3: 2Gi. Phase 4: 19Gi
(5+2+10+2). Phase 5: 5Gi (openlingo) + 0Gi (ai-lang, no PVC). Phase 6: 2Gi.
Phase 7: 12Gi (db-mysql 10Gi + orphan mysql-pvc 2Gi). All reclaimed through the
documented policy paths; no Longhorn volume of a removed app remains.

### 14. Final etcd snapshot

`pre-shutdown-cull` snapshot created on `nuc` before shutdown (see final action
record below).

### 15. Homelab shut down per documented procedure

Executed `WindowsLab/shutdown_homelab.ps1 -Force` detached per
`docs/homelab/how-to-manage-homelab-power.md`; TCP 6443 and SSH 22 probes on all
node IPs confirmed closed after shutdown (evidence in the final-action section
of progress.md). Cluster not restarted afterwards.

## Final state at close

- 10 namespaces with workloads: ai, argocd, iiqstack, linguacafe, media,
  monitoring, homepage, server-management, longhorn-system, tailscale (+ system).
- Monitoring: beszel-hub, dozzle, gotify, uptime-kuma, kuma-auth-proxy.
- Books/media: abs-auth-proxy, audiobookshelf, calibre-web, chaptarr, flick,
  immich, reactive-resume.
- Language: ollama, openwebui, linguacafe. Server mgmt: remotepower.
- Uptime Kuma: 40 ConfigMap monitors + manually added etcd-nas-backup.
- Homepage: 1/1, 21 tiles, all pointing at live apps.
