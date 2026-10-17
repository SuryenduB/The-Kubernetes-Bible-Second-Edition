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
| T-05 | End-to-end backup heartbeat: push from the backup script itself on successful NAS publish (Kuma push monitor) | Phase 2 | P1 | authorized | TODO | — | remove monitor + revert script | — |
| T-06 | `languard` CrashLoopBackOff (backend 96 + scheduler 103 restarts, migration-lock waiting) | pod status; "Waiting for another LanGuard container to finish startup migrations…" | P2 | authorized (repair existing monitoring) | TODO | — | git revert | — |
| T-07 | Extend backup checker with Longhorn volume robustness counts (degraded/faulted → down; unknown held distinct) | Phase 5 detection gap | P2 | authorized | TODO | — | revert | — |
| T-08 | metrics-server HA (2 replicas + PDB) per upstream HA guidance | 1 replica on kubernetes4; metrics-server supports HA | P2 | authorized | TODO | — | revert manifest | — |
| T-09 | Node-down detection via existing Kuma sync (port monitors per active node) | detection Phase 6 | P2 | authorized | TODO | — | revert monitors.yaml | — |
| T-10 | registry-fixer pods stuck Terminating on NotReady server-236/252 | pods Terminating 11 d (nodes offline) | P3 | NOT authorized (nodes retained; pods clear when nodes return) | — | — | — | recorded only |
| T-11 | uptime-kuma-sync hourly failures → watch next cycles; caused by Kuma redeploy windows | last 3 succeeded after Kuma 8 h ago | P3 | authorized | monitor-only | observed | — | — |
| T-12 | Approval-required register refresh (server HA, restore test, etc.) | docs/approval-required.md | P2 | doc update | TODO | — | — | — |

## Loop log

- Iteration 1 (2026-10-17 ~01:35–02:10 CEST): baseline reconciled (T-01). T-02+T-03 implemented & validated (change-set 1: backup detection repair + etcd-snapshot freshness). Commit 877ecc1.
- Iteration 2 (2026-10-17 ~02:20–02:35 CEST): T-04 script hardening implemented & fixture-validated (A/B/D + interim real publish `20261017-023018`). ShellCheck NOT RUN locally (brew build failure); bash -n passed locally and remotely. Post-06:00 cron run to be verified for the `.tmp-*` prune path.
