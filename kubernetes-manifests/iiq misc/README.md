# IdentityIQ (iiqstack) — Deployment & Recovery Guide

## Status (2026-09-22 — after live↔repo drift reconciliation, commit 21523d7)

| Component | Status | Notes |
|---|---|---|
| `deployment/iiq` | ✅ 1/1 Ready | `sailpoint-docker:latest`, 4Gi / `-Xmx3072M`; spec matches `iiq misc/iiq-deployment.yaml` |
| `pod/iiq-*` | ✅ Running | Spring context up — `/identityiq/` returns **HTTP 200**, VersionChecker passed |
| `service/iiq` | ✅ ClusterIP | :80 → :8080, port name `http`, session affinity 10800s, Tailscale exposed |
| `iiq-pdb` | ✅ Created | `minAvailable: 1` (added from code during reconciliation) |
| `db-0` (MSSQL) | ✅ Running | 3 databases; `identityiq` full schema + version row `8.4-107` / `8.4-88`; `identityiqPlugin` login/user ready |
| `identityiqah` | ⚠️ **14/32 tables** | Version row seeded (`8.4-107` / `8.4-88`) so startup passes, but runtime access-history writes to the 18 missing tables will error → finish with **Option A** |
| `db-mysql-0` | ✅ Running | MySQL 8.0 (not used by IIQ) |
| `ldap-0` / `mail-0` / `activemq-0` | ✅ Running | OpenLDAP / Mailpit / ActiveMQ Artemis |
| `iiq-init` job | ✅ Completed | Original pre-fix run; corrected script not yet re-applied (Job spec is immutable while the job exists) |
| stack YAML vs live | ✅ In sync | `kubectl diff` clean for `iiq-stateful.yaml` and `iiq misc/*.yaml` |

## Files in This Directory

| File | Purpose | Applied to cluster? |
|---|---|---|
| `../iiq-stateful.yaml` | **Canonical full stack**: namespace, quota, netpols, SA/RBAC, secret, all dependencies (db/ldap/activemq/mail/counter/ssh/phpldapadmin), Deployment+Service `iiq`, PDBs, IngressRoutes, NFS PVCs | ✅ |
| `iiq-deployment.yaml` | Deployment + Service `iiq` only — spec identical to the canonical file; use for iiq-only updates | ✅ |
| `iiq-init-job.yaml` | DB bootstrap: databases, logins/users, default schemas, full AH DDL hard-gated at **32 tables** | ⚠️ delete job first (immutable while it exists) |
| `iiq-deployment-ha-nas.yaml` | HA/NAS variant (replicas 2, `sailpoint-iiq:8.5`, NAS initContainer) | ❌ reference only |
| `fix-db-corruption-job.yaml` | Emergency recovery — **drops and recreates the `identityiq` database**; kept suspended | ❌ emergency only |
| `iiq-mssql-setup.sql` | Manual SQL fallback (Option B, via **stdin**). Behind the init job: no `identityiqPlugin` login, stub AH table, legacy `dbo` synonym that collides with the real AH DDL | manual only |
| `README.md` | This file | — |

## Recreate from Scratch

Prerequisites (cluster level): k3s, Traefik CRDs (`IngressRoute`), Tailscale operator + `../tailscale-proxyclass.yaml`, and registry `192.168.0.236:5000` reachable from the nodes.

```bash
# 1) Full stack first — ns, secret, netpols, SA/RBAC, dependencies, Deployment+Service iiq
kubectl apply -f kubernetes-manifests/iiq-stateful.yaml
kubectl -n iiqstack wait --for=condition=ready pod/db-0 --timeout=300s

# 2) DB bootstrap with the init Job (canonical path — creates everything VersionChecker
#    needs and exits 1 if identityiqah has fewer than 32 base tables)
kubectl -n iiqstack delete job iiq-init --ignore-not-found
kubectl apply -f "kubernetes-manifests/iiq misc/iiq-init-job.yaml"
kubectl -n iiqstack logs job/iiq-init -f

# 3) (Re)start IIQ against the finished schema
kubectl -n iiqstack rollout restart deploy/iiq
kubectl -n iiqstack rollout status deploy/iiq --timeout=300s

# 4) Verify: 404 -> 200
kubectl -n iiqstack exec deploy/iiq -- curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/identityiq/
curl -sk https://iiq-main.tail35421d.ts.net/identityiq/   # from a tailnet client
```

> **Don't start with `iiq-deployment.yaml` alone** — it declares only the Deployment/Service and assumes namespace `iiqstack`, secret `sailpoint-db-secrets`, ServiceAccount `iiq-sa`, and every dependency already exist. Never `sqlcmd -i <local-path>` inside `kubectl exec` — the file isn't in the pod; pipe it via stdin (Option B).

## Recovery Steps

### Option A: Re-run Init Job (Recommended — also finishes the AH schema)
```bash
# Jobs are immutable: delete first, then apply the fixed script
kubectl delete job iiq-init -n iiqstack
kubectl apply -f "iiq misc/iiq-init-job.yaml"   # from repo root; from this dir: kubectl apply -f iiq-init-job.yaml

# Watch completion — must end with "Access History schema OK (32 tables)."
kubectl logs -n iiqstack job/iiq-init -f

# Restart IIQ and verify (404 -> 200)
kubectl -n iiqstack rollout restart deploy/iiq
kubectl -n iiqstack exec deploy/iiq -- curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/identityiq/
```
The non-idempotent AH statements are tolerated on re-run (sqlcmd continues past "already exists" — no `-b`), then the script **hard-gates on the 32-table count** and aborts if incomplete.

### Option B: Manual SQL (debug/fallback only)
```bash
SA_PASS=$(kubectl get secret sailpoint-db-secrets -n iiqstack -o jsonpath='{.data.mssql-sa-password}' | base64 -d)

# Pipe via STDIN — sqlcmd runs INSIDE the db-0 pod, it cannot see local paths.
# (kubectl exec ... -i path/to/file.sql fails: file not found in the pod)
kubectl exec -i -n iiqstack db-0 -- /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASS" -C \
    < "kubernetes-manifests/iiq misc/iiq-mssql-setup.sql"
```
Prefer Option A: `iiq-mssql-setup.sql` is behind the init job (no `identityiqPlugin` login, stub AH table, poison `dbo.spt_hist_database_version` synonym).

### Option C: Verify & Restart IIQ
```bash
kubectl -n iiqstack rollout restart deploy/iiq
kubectl -n iiqstack rollout status deploy/iiq --timeout=300s

kubectl get ep -n iiqstack iiq                              # must show an IP:8080
kubectl -n iiqstack exec deploy/iiq -- curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/identityiq/
curl -sk http://iiq.iiqstack.svc/identityiq/                # in-cluster service URL
curl -sk https://iiq-main.tail35421d.ts.net/identityiq/     # from a tailnet client (TLS by Tailscale)
```

## Root Causes Fixed (2026-09-22)

1. **AH DDL pointed at a nonexistent file, errors swallowed** — `database/create_identityiq_ah_tables.sql` doesn't exist; the real file is `WEB-INF/database/fragments/ah-create_hibernate_tables-8.4.sqlserver`. The job hid failures behind `2>/dev/null || echo skipped`, silently leaving `identityiqah` empty → `Invalid object name 'spt_hist_database_version'` → VersionChecker failure → HTTP 404. **Root cause of the outage.**
2. **`pluginsDataSource.username` mismatch** — now `identityiqPlugin`, with its own login/user/default schema.
3. **Missing default schemas** — `ALTER USER … WITH DEFAULT_SCHEMA` requires the schema to exist first; all schemas are pre-created.
4. **OOM kill (exit 137)** — 2Gi → 4Gi, `-Xmx3072M`.
5. **Wrong DB type** — MySQL config replaced with MSSQL (`SQLServerPagingDialect`, `MSSQLDelegate`).
6. **Schema-owner/synonym legacy issues** — `identityiq` default schema, `spt_database_version` synonym, AH user + `db_owner`.

## Remaining Work

- `identityiqah` is at **14/32** base tables. Startup passes on the seeded version row, but access-history persistence will fail at runtime — finish with **Option A** (the job's 32-table gate verifies the result).
- The corrected init script has never run end-to-end (the live Job is immutable) — review its logs once after the first delete+recreate.

## Secret Reference

All env vars reference `sailpoint-db-secrets` in namespace `iiqstack`:
```bash
kubectl get secret sailpoint-db-secrets -n iiqstack -o yaml
```

Keys:
- `mssql-sa-password` — SA password
- `mssql-user-password` — identityiq user password
- `mysql-root-password` — MySQL root (unused by IIQ)
- `mysql-user-password` — MySQL user (unused by IIQ)
- `ldap-admin-password` — LDAP admin
- `ssh-password` — SSH host password

## Tailscale Exposure

The `iiq` service is exposed via Tailscale:
- Hostname: `iiq-main.tail35421d.ts.net`
- Port: 443 (TLS terminated by Tailscale)
- Path: `/identityiq/`

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Exit 137 / OOM | Memory limit too low | Ensure 4Gi limit, `-Xmx3072M` |
| `spt_database_version` not found | Default schema wrong | `ALTER USER identityiq WITH DEFAULT_SCHEMA = identityiq` |
| `spt_hist_database_version` not found | AH schema missing/stub | Re-run init Job (Option A); real file is `fragments/ah-create_hibernate_tables-8.4.sqlserver` |
| Startup OK but AH writes error at runtime | `identityiqah` only partially populated (14/32) | Complete DDL via Option A (32-table gate) |
| `Login failed for identityiqah` / `identityiqPlugin` | User/login missing | Init Job creates logins, users, default schemas |
| 404 on `/identityiq/` | Spring context failed | Check pod logs for DB errors — usually VersionChecker/AH (rows above) |
| `field is immutable` on apply | Live `Job/iiq-init` conflicts with edited file | `kubectl -n iiqstack delete job iiq-init` first — Job specs are immutable |
| Image pull failed | Registry unreachable | Ensure `192.168.0.236:5000` is reachable from cluster |
