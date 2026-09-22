# IdentityIQ (iiqstack) — Deployment & Recovery Guide

## Status (2026-09-22 — after IIQ 8.5 upgrade from local registry)

| Component | Status | Notes |
|---|---|---|
| `deployment/iiq` | ✅ 1/1 Ready | `192.168.0.236:5000/sailpoint-iiq:8.5` (IIQ 8.5, local registry, digest-pinned), 4Gi / `-Xmx3072M`; spec matches `iiq misc/iiq-deployment.yaml` |
| `pod/iiq-*` | ✅ Running | 8.5 boot on upgraded schema — `/identityiq/` returns **HTTP 200**, VersionChecker passed (system `8.5-19` / schema `8.5-15`) |
| `service/iiq` | ✅ ClusterIP | :80 → :8080, port name `http`, session affinity 10800s, Tailscale exposed |
| `iiq-pdb` | ✅ Created | `minAvailable: 1` (added from code during reconciliation) |
| `db-0` (MSSQL) | ✅ Running | 3 databases; `identityiq` upgraded **8.4→8.5** (official `upgrade_identityiq_tables.sqlserver`, 220 tables); version rows **`8.5-19` / `8.5-15`**; `identityiqPlugin` login/user ready |
| `identityiqah` | ✅ **32/32 tables** | 8.5 fragment completed the 18 missing tables (must run with `-d identityiqah`); version row `8.5-19` / `8.5-15`; legacy `dbo` synonym dropped |
| `db-mysql-0` | ✅ Running | MySQL 8.0 (not used by IIQ) |
| `ldap-0` / `mail-0` / `activemq-0` | ✅ Running | OpenLDAP / Mailpit / ActiveMQ Artemis |
| `iiq-init` job | ✅ Completed | Recreated with the fixed 8.5 script (image `sailpoint-iiq:8.5`, version-row seed step) — runs clean end-to-end: "Access History schema OK (32 tables)." |
| stack YAML vs live | ✅ In sync | `kubectl diff` clean for `iiq-stateful.yaml` and `iiq misc/*.yaml` |

## Files in This Directory

| File | Purpose | Applied to cluster? |
|---|---|---|
| `../iiq-stateful.yaml` | **Canonical full stack**: namespace, quota, netpols, SA/RBAC, secret, all dependencies (db/ldap/activemq/mail/counter/ssh/phpldapadmin), Deployment+Service `iiq`, PDBs, IngressRoutes, NFS PVCs | ✅ |
| `iiq-deployment.yaml` | Deployment + Service `iiq` only — spec identical to the canonical file; use for iiq-only updates | ✅ |
| `iiq-init-job.yaml` | DB bootstrap: databases, logins/users, default schemas, full AH DDL hard-gated at **32 tables**, version-row seed (`8.5-19`/`8.5-15`) | ⚠️ delete job first (immutable while it exists) |
| `iiq-deployment-ha-nas.yaml` | HA/NAS variant (replicas 2, `sailpoint-iiq:8.5`, NAS initContainer) | ❌ reference only |
| `fix-db-corruption-job.yaml` | Emergency recovery — **drops and recreates the `identityiq` database**; kept suspended | ❌ emergency only |
| `iiq-mssql-setup.sql` | Manual SQL fallback (Option B, via **stdin**). Behind the init job: no `identityiqPlugin` login, stub AH table, legacy `dbo` synonym that collides with the real AH DDL | manual only |
| `README.md` | This file | — |

## Recreate from Scratch

Prerequisites (cluster level — nothing in this folder installs them, verified by audit 2026-09-22):

- **k3s** cluster (see `docs/homelab/K3s_Homelab_Template.md`) with Traefik CRDs (`IngressRoute` — ships with k3s); Tailscale operator + `../tailscale-proxyclass.yaml` only if you want the tailnet URL.
- **Registry** `192.168.0.236:5000` running on host `server-236` with `sailpoint-iiq:8.5` pushed, **and** `../registry-fixer.yaml` applied first (writes the mirror into `/etc/rancher/k3s/registries.yaml` on every node; restart k3s on a node if pulls from the HTTP registry fail). The registry lives on the host, not in the cluster — it survives a cluster wipe only if `server-236` is not re-imaged.
- **StorageClasses `longhorn` and `nfs-nas` must exist BEFORE applying** — every `iiqstack` PVC binds to `longhorn` (db/ldap/activemq/mail/mysql data, `iiq-nas-pvc`) except `iiq-nas-pvc-nfs` → `nfs-nas` (NFS subdir provisioner + NAS reachable). Longhorn and the NFS provisioner are platform installs (out of scope of this folder). Without them every PVC stays Pending and nothing starts.

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

## Upgrading IIQ 8.4 → 8.5 (2026-09-22)

Local registry `192.168.0.236:5000` hosts `sailpoint-iiq:8.5`; the app was switched from `sailpoint-docker:latest` (8.4) and both IIQ databases were upgraded in place:

1. **Back up all three DBs** — `BACKUP DATABASE … TO DISK='/var/opt/mssql/data/pre85-*.bak'` as `sa`.
2. **Official schema upgrade** — extract from the 8.5 WAR and run as `sa` **without `-b`** (it continues past missing-object errors):
   ```bash
   # inside a 192.168.0.236:5000/sailpoint-iiq:8.5 pod
   unzip -p /opt/iiq/identityiq.war WEB-INF/database/upgrade_identityiq_tables.sqlserver > /tmp/u.sql
   /opt/mssql-tools18/bin/sqlcmd -C -N o -U sa -P "$SA" -S db -i /tmp/u.sql
   ```
   Sets `schema_version='8.5-15'` in **both** `identityiq.spt_database_version` and `identityiqah.spt_hist_database_version`, and applies AH column/index deltas to the AH tables that exist. Expected errors: statements against AH tables that don't exist yet (next step fixes them) and duplicate index creates (idempotent).
3. **Finish incomplete AH** (was 14/32): run `fragments/ah-create_hibernate_tables-8.5.sqlserver` **with `-d identityiqah`** — without it every `identityiqah.*` name resolves in `master`, fails with `Msg 1088 (schema does not exist)`, and *nothing is created* while sqlcmd still exits 0. Gate at 32 base tables.
4. **Bump `system_version` manually** — the upgrade script only touches `schema_version`. The 8.5 app refuses to start with
   `DatabaseVersionException: IdentityIQ expected system version [8.5-19] does not match current database value [8.4-107]`
   until both rows are updated: `UPDATE … SET system_version='8.5-19' WHERE name='main'` (in `identityiq` and `identityiqah`).
5. **Swap the image** — `iiq-stateful.yaml` + `iiq misc/iiq-deployment.yaml` → `192.168.0.236:5000/sailpoint-iiq:8.5` (`imagePullPolicy: IfNotPresent`), then `kubectl -n iiqstack rollout restart deploy/iiq`. Same entrypoint/env as before (`DATABASE_TYPE=mssql`, `MSSQL_*`); the 8.5 image runs Tomcat 9.0.117 on JDK 17. Note: `IfNotPresent` won't re-pull a moved `:8.5` tag — pin the digest or use `Always` if you re-push the tag.
6. **Verify** — pod Ready, `/identityiq/` → HTTP 200, version rows `8.5-19` / `8.5-15` in both DBs.

> Gotcha: `sqlcmd -i <local path>` inside `kubectl exec` doesn't work — extract the SQL **inside** a pod (or pipe it via stdin).

## Root Causes Fixed (2026-09-22)

1. **AH DDL pointed at a nonexistent file, errors swallowed** — `database/create_identityiq_ah_tables.sql` doesn't exist; the real file is `WEB-INF/database/fragments/ah-create_hibernate_tables-8.4.sqlserver`. The job hid failures behind `2>/dev/null || echo skipped`, silently leaving `identityiqah` empty → `Invalid object name 'spt_hist_database_version'` → VersionChecker failure → HTTP 404. **Root cause of the outage.**
2. **`pluginsDataSource.username` mismatch** — now `identityiqPlugin`, with its own login/user/default schema.
3. **Missing default schemas** — `ALTER USER … WITH DEFAULT_SCHEMA` requires the schema to exist first; all schemas are pre-created.
4. **OOM kill (exit 137)** — 2Gi → 4Gi, `-Xmx3072M`.
5. **Wrong DB type** — MySQL config replaced with MSSQL (`SQLServerPagingDialect`, `MSSQLDelegate`).
6. **Schema-owner/synonym legacy issues** — `identityiq` default schema, `spt_database_version` synonym, AH user + `db_owner`.
7. **Init-job image version mismatch** — job and app images must be in lockstep: the SQL files are version-suffixed (`create_identityiq_tables-<ver>.sqlserver`, `ah-create_hibernate_tables-<ver>.sqlserver`), so an `8.5` image running `8.4` paths (or vice versa) fails with file-not-found. Since the 8.5 upgrade both the Deployment and the job use `192.168.0.236:5000/sailpoint-iiq:8.5`, and every path in the script is `8.5`-suffixed (verified: bash, unzip, `/opt/mssql-tools18/bin/sqlcmd`, `/opt/iiq/identityiq.war` all present).
8. **VersionChecker needs both version rows to match the image** — `system_version` (app build, e.g. `8.5-19`) *and* `schema_version` (DB schema, `8.5-15`). The create scripts INSERT neither row, and the official upgrade script updates only `schema_version` — so the init job now seeds both (step 8), and image upgrades must bump `system_version` by hand (see the Upgrading section).

## Remaining Work

- **None for the 8.5 upgrade** — `identityiqah` is at **32/32**, both version rows are `8.5-19` / `8.5-15`, and the corrected init script has run end-to-end ("Access History schema OK (32 tables)." → "Version rows OK.").
- Optional cleanup: pre-upgrade backups (`pre85-identityiq*.bak`, `pre85-identityiqPlugin.bak`) in `/var/opt/mssql/data` can be removed once 8.5 is trusted.

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
| `spt_hist_database_version` not found | AH schema missing/stub | Re-run init Job (Option A); real file is `fragments/ah-create_hibernate_tables-8.5.sqlserver` (run with `-d identityiqah`) |
| Startup OK but AH writes error at runtime | `identityiqah` only partially populated | Re-run init Job — the 32-table gate enforces completeness before it reports success |
| `DatabaseVersionException: expected system version […] does not match` | `system_version` row stale after an image upgrade (upgrade script only bumps `schema_version`) | `UPDATE identityiq.dbo.spt_database_version SET system_version='<image build>' WHERE name='main'` (and the AH row), then restart — see Upgrading section |
| `Login failed for identityiqah` / `identityiqPlugin` | User/login missing | Init Job creates logins, users, default schemas |
| 404 on `/identityiq/` | Spring context failed | Check pod logs for DB errors — usually VersionChecker/AH (rows above) |
| `field is immutable` on apply | Live `Job/iiq-init` conflicts with edited file | `kubectl -n iiqstack delete job iiq-init` first — Job specs are immutable |
| Image pull failed | Registry unreachable | Ensure `192.168.0.236:5000` is reachable from cluster |
