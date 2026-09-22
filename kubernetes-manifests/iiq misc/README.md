# IdentityIQ (iiqstack) — Current State & Recovery Guide

## Status (2026-09-22)

| Component | Status | Notes |
|---|---|---|
| `service/iiq` | ✅ Running | ClusterIP:10.43.220.51:80 → :8080, Tailscale exposed |
| `deployment/iiq` | ⚠️ Created | 0/1 ready — pod exists but Spring context fails at startup |
| `pod/iiq-*` | 🔴 Failing | OOM killed (exit 137), now 4Gi — still failing on DB schema |
| `db-0` (MSSQL) | ✅ Running | 3 databases created, schema partially populated |
| `db-mysql-0` | ✅ Running | MySQL 8.0 (not used by IIQ) |
| `ldap-0` | ✅ Running | OpenLDAP |
| `mail-0` | ✅ Running | Mailpit |
| `activemq-0` | ✅ Running | ActiveMQ Artemis |
| `iiq-init` job | ✅ Completed | Ran 47h ago, created databases/users/schema |

## Root Causes Fixed

1. **Deployment missing** — Recreation with correct MSSQL config, 4Gi memory
2. **OOM Kill (exit 137)** — Bumped from 2Gi → 4Gi, `-Xmx3072M`
3. **Wrong DB type** — Was MySQL config, fixed to MSSQL
4. **Schema owner mismatch** — Default schema `dbo` → `identityiq`
5. **Missing synonym** — `spt_database_version` synonym created
6. **Missing `identityiqah` user** — Created in `identityiqah` database

## Remaining Blocker

IIQ fails with:
```
Unable to check AccessHistory database version: 
Invalid object name 'spt_hist_database_version'
```

The `identityiqah` database has **no tables**. The init job should have created them via:
```
/opt/tomcat/webapps/identityiq/WEB-INF/database/create_identityiq_ah_tables.sql
```

But this may have silently failed (the init job logs are empty/timed out).

## Files in This Directory

| File | Purpose |
|---|---|
| `iiq-deployment.yaml` | **Current deployment** — apply with `kubectl apply -f` |
| `iiq-init-job.yaml` | Init job — creates DBs, users, schema, synonym |
| `iiq-mssql-setup.sql` | Standalone SQL — run BEFORE applying manifests |
| `README.md` | This file |

## Recovery Steps

### Option A: Re-run Init Job (Recommended)
```bash
# Delete old job and re-apply
kubectl delete job iiq-init -n iiqstack
kubectl apply -f iiq-init-job.yaml

# Watch for completion
kubectl get job iiq-init -n iiqstack -w
kubectl logs -n iiqstack job/iiq-init -f
```

### Option B: Manual Schema Creation
```bash
# Connect to MSSQL and run schema scripts
SA_PASS=$(kubectl get secret sailpoint-db-secrets -n iiqstack -o jsonpath='{.data.mssql-sa-password}' | base64 -d)
IIQ_PASS=$(kubectl get secret sailpoint-db-secrets -n iiqstack -o jsonpath='{.data.mssql-user-password}' | base64 -d)

# Check if schema scripts exist in the pod
POD=$(kubectl get pod -n iiqstack db-0 -o jsonpath='{.metadata.name}')
kubectl exec -n iiqstack $POD -- ls /opt/mssql-tools18/bin/  # sqlcmd available

# Run schema creation (you'll need the SQL files from the IIQ image)
# Option: copy from a running IIQ container or extract from WAR
```

### Option C: Verify & Restart IIQ
```bash
# After init job completes, restart IIQ
kubectl delete pod -n iiqstack -l app=iiq

# Wait for readiness (120s+ for Spring to initialize)
kubectl wait --for=condition=ready pod -l app=iiq -n iiqstack --timeout=300s

# Verify
kubectl get ep -n iiqstack iiq  # Should show IP
curl -s http://iiq-main.tail35421d.ts.net/identityiq/login.jsf
```

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

## Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| Exit 137 / OOM | Memory limit too low | Ensure 4Gi limit, `-Xmx3072M` |
| `spt_database_version` not found | Default schema wrong | `ALTER USER identityiq WITH DEFAULT_SCHEMA = identityiq` |
| `spt_hist_database_version` not found | AH schema missing | Re-run init job or run `create_identityiq_ah_tables.sql` |
| Login failed for `identityiqah` | User missing in AH DB | Create user + db_owner role in `identityiqah` |
| 404 on `/identityiq/` | Spring context failed | Check logs for DB errors above |
| Image pull failed | Registry unreachable | Ensure `192.168.0.236:5000` is reachable from cluster |
