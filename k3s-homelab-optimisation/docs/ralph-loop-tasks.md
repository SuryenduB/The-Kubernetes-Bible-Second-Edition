# Ralph Loop — K3s Reliability Task File

Persistent working state for the reliability loop. Update every iteration.
Baseline reconciled 2026-10-17 ~01:40 CEST against commit `0c045e7`.

## Reconciled baseline (Phase 1)

| Report claim | Live check | Result |
| :--- | :--- | :--- |
| 7 active nodes Ready | `kubectl get nodes` | OK — nuc + kubernetes1–6 Ready; server-236/252 retained NotReady |
| CoreDNS 2 replicas, distinct nodes, hard spread, PDB | live objects | OK — kubernetes3 + kubernetes6, PDB `coredns-pdb` minAvailable 1 |
| Longhorn sole default SC | `kubectl get sc` | OK — `longhorn (default)` |
| All PVCs Bound | `kubectl get pvc -A` | OK — 52/52 Bound (PVC count grew since session) |
| Longhorn 39 healthy + 1 detached/unknown | volume list | OK — 40 volumes; only `pvc-1a05dbf3…` (iiqstack/iiq-nas-pvc) detached/unknown |
| Backup cron 0 */6, script installed | nuc crontab + sha256 | OK — hash 20a74f2e… matches repo script |
| K3s uptime unchanged | systemd ActiveEnterTimestamp | OK — Fri 2026-10-16 16:32:27 CEST |
| Scripts/runbooks match deployed config | hash + manifest comparison | OK at baseline (check.py updated during loop, see T-03) |

## Task table

| ID | Task | Evidence | Pri | Auth | Impl | Validation | Rollback | Blocker |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| T-01 | Phase-1 baseline reconciliation | see table above | P0 | — | DONE | live checks above | — | — |
| T-02 | Repair `backup-daily-check`: Kuma push 404 since 2026-09-17 (monitor token rotated vs stale Secret) — failed daily for a month | test push 404 from check job; Kuma DB monitor id=25 token sha cd50a4a2… ≠ Secret sha 27a70cda…; Secret re-patched to live token; manual Job → `{'ok': True}`, job exit 0, Kuma heartbeat status=1 | P1 | authorized | DONE | push {'ok':True}; heartbeat id 201778 status=1 00:16 UTC | restore previous token (git history of Secret not stored — Secret stays as-is) | — |
| T-03 | Extend `backup-daily-check` to etcd-NAS backup freshness (etcdsnapshotfiles, 13 h), mask push token in logs, 404 remediation hint, ClusterRole rule | repo `kubernetes-manifests/monitoring/longhorn-backup-monitor.yaml`; py_compile + server dry-run + live apply + manual Job exit 0 (`longhorn: OK 9.0h \| etcd: OK 1.0h`) | P1 | authorized | DONE | expanded-check Job output (above) | git revert of file + re-apply | — |
| T-04 | Harden `k3s-etcd-safe-backup.sh` (bounded mount, identity check, phase tags, signal exits, tmp pruning, --manual-test) | fixtures A/B/D live on nuc + interim real run published 20261017-023018 | P1 | authorized | DONE | exit 1 fail-fast on unreachable NAS; foreign mount refused; manual-test exit 0 no publish; real run exit 0 | `git revert` script + reinstall from `/root/k3s-etcd-safe-backup.sh.pre-iter2` | — |
| T-05 | End-to-end backup heartbeat: push from the backup script on successful NAS publish (Kuma push monitor `etcd-nas-backup`) | manual run `20261017-024141` published & pushed; Kuma heartbeat id 202382 status=1; script sha256 2d9993ce… | P1 | authorized | DONE | exit 0 + heartbeat row in Kuma | remove monitor + revert script (keep old: /root/k3s-etcd-safe-backup.sh.iter2) | — |
| T-06 | `languard` CrashLoopBackOff (223 restarts over ~9 h; backend blocked forever on migration lock; scheduler `no such table: core_schedulerruntimestate`) | root cause verified in-image: `/entrypoint.sh` `mkdir`-locks `/data/.startup-lock`; an empty stale lock dir (mtime Oct 14) left by a killed container deadlocked every new backend, migrations never ran; scheduler's k8s `command` overrides image ENTRYPOINT so it skips migrations → crash | P2 | authorized (repair existing monitoring) | DONE | `db-init` initContainer clears stale lock + runs migrations first (`core.0051` + `core.0052` applied); new pod `languard-6fbbf9bbb6-l4c64` 3/3 ready, 0 restarts (backend/scheduler/frontend), >90 s stable; Mac→kubernetes3 `:8000/api/v1/health/` → `200 {"status":"ok"}`, `:8080` → 200; scheduler banner normal; lock dir absent after startup | `git revert` `languard.yaml` + `kubectl rollout undo deploy/languard -n monitoring` (live pre-fix spec snapshot: scratch `languard/deploy-pre-fix.yaml`; rollout history rev 14) | — |
| T-07 | Extend backup checker with Longhorn volume robustness counts (degraded/faulted → down; unknown held distinct) | Phase 5 detection gap | P2 | authorized | TODO | — | revert | — |
| T-08 | metrics-server HA (2 replicas + PDB) per upstream HA guidance | 1 replica on kubernetes4; metrics-server supports HA | P2 | authorized | TODO | — | revert manifest | — |
| T-09 | Node-down detection via existing Kuma sync (port monitors per active node) | detection Phase 6 | P2 | authorized | TODO | — | revert monitors.yaml | — |
| T-10 | registry-fixer pods stuck Terminating on NotReady server-236/252 | pods Terminating 11 d (nodes offline) | P3 | NOT authorized (nodes retained; pods clear when nodes return) | — | — | — | recorded only |
| T-11 | uptime-kuma-sync hourly failures → watch next cycles; caused by Kuma redeploy windows | last 3 succeeded after Kuma 8 h ago | P3 | authorized | monitor-only | observed | — | — |
| T-12 | Approval-required register refresh (server HA, restore test, etc.) | docs/approval-required.md | P2 | doc update | TODO | — | — | — |

## Loop log

- Iteration 1 (2026-10-17 ~01:35–02:10 CEST): baseline reconciled (T-01). T-02+T-03 implemented & validated (change-set 1: backup detection repair + etcd-snapshot freshness). Commit 877ecc1.
- Iteration 2 (2026-10-17 ~02:20–02:35 CEST): T-04 script hardening implemented & fixture-validated (A/B/D + interim real publish `20261017-023018`). ShellCheck NOT RUN locally (brew build failure); bash -n passed locally and remotely. Post-06:00 cron run to be verified for the `.tmp-*` prune path. Commit 71af38f.
- Iteration 3 (2026-10-17 ~02:36–02:45 CEST): T-05 end-to-end heartbeat implemented & validated (monitor etcd-nas-backup, script pushes on success; run `20261017-024141` proven by Kuma heartbeat). Pending: 06:00 real cron run confirmation.
- Iteration 4 (2026-10-17 ~02:45–03:05 CEST): T-06 languard repair implemented & live-validated (initContainer `db-init`: stale `/data/.startup-lock` removal + upfront migrations; `terminationGracePeriodSeconds: 60`). First apply caught a real gap — init env needed the full backend env (Django `validate_production_settings` rejects missing `ALLOWED_HOSTS`); fixed and re-applied. During rollout the pod re-scheduled kubernetes6 → kubernetes3 (affinity excludes only kubernetes4). See change-log §10 and finding F-08.
