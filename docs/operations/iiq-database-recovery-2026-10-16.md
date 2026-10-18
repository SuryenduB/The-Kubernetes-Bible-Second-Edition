# IIQ restore — 2026-10-16 (minute-detail record)

> Complete, reproducible record of the IdentityIQ (`iiqstack`) outage and restore.
> Supersedes/summarises the DB-only view; see also the earlier 2026-09-06 incident
> (`iiq-database-recovery-2026-09-06.md`), which had the same database failure.
>
> **Secrets note:** no password is recorded here. Commands read the SA/login password
> from the `sailpoint-db-secrets` Secret at runtime. Plaintext creds-in-manifests are a
> deliberate choice in this repo (see `AGENTS.md`); nothing was changed about that.

---

## 1. Summary

IdentityIQ was down for **three stacked reasons**, fixed in order:

| # | Fault | Root signal | Fix |
|---|---|---|---|
| 1 | Container image unreachable | `Init:ImagePullBackOff` — image exists only in registry on `server-236`, which was powered off | powered `server-236` VM on → registry back |
| 2 | **Liveness crash loop** | `exitCode:137`, `reason:Error` at **~4m44s** vs liveness budget 4m30s | added `startupProbe` (900s) + `preStop`/graceful shutdown |
| 3 | **`identityiq` DB `SUSPECT`** | `did not see LOP_END_CKPT` → `Error: 3414` | in-place `DBCC CHECKDB … REPAIR_ALLOW_DATA_LOSS` → `ONLINE` |

Final state: `deployment/iiq` **1/1**, **0 restarts**, `GET /identityiq/login.jsf` → **HTTP 200**.

---

## 2. Environment / identifiers (for exact reproduction)

| Item | Value |
|---|---|
| Cluster | K3s `v1.34.6+k3s1` (11 nodes) |
| Namespace | `iiqstack` |
| Deployment | `iiq` (image `192.168.0.236:5000/sailpoint-iiq:8.5`, replicas 1) |
| Service | `iiq` ClusterIP, `80 → 8080`, port name `http` |
| DB StatefulSet / pod | `db` / `db-0` (MSSQL) |
| DB PVC / PV | `mssql-persistent-storage-db-0` / `pvc-18e786bf-44f5-495c-8179-9febb4d48a3f` |
| DB storage class | `longhorn` (10Gi) |
| DB secret | `sailpoint-db-secrets` (`mssql-sa-password`, `mssql-user-password`) |
| Databases | `identityiq`, `identityiqPlugin`, `identityiqah` |
| Image registry | `192.168.0.236:5000` (insecure; co-hosted on node `server-236`) |
| Longhorn backup target | `nfs://192.168.0.128:/longhorn` |
| Newest pre-incident backup | `backup-afe3d6f259914e6e` @ `2026-10-15T12:59:29Z` |
| Safety snapshot taken | `pre-iiq-repair-20261016` @ `2026-10-16T19:28:28Z` |

---

## 3. Timeline (UTC, 2026-10-16)

| Time | Event |
|---|---|
| `15:14:08`–`15:14:12` | MSSQL restarts; `identityiq` marked `SUSPECT` (`WARNING: did not see LOP_END_CKPT`; `Error: 3414, Severity: 21`). **Latent — IIQ had already been down on fault #1.** |
| `~18:0x` | Operator powers on HP-1 Hyper-V guest `Ubuntu` (= node `server-236`). |
| `~18:1x` | `server-236` answers ping at `192.168.0.236`. |
| `~18:2x` | Registry `HTTP 200`; kubelet pulls the IIQ image (~36.7s, 1.2 GB). |
| `18:22:15` | Init container `wait-for-identityiq-database` completes on pod `iiq-77dfc784c6-w7t6p`. |
| `18:22:17` | App container starts. |
| `18:27:01` | App SIGKILLed — `exitCode:137`, `reason:Error` (ran **4m44s**) → **fault #2 diagnosed**. |
| `18:31:06` | After manifest patch, replacement pod `iiq-84f4dd488b-c7fp5` app starts under the new `startupProbe`. |
| `~18:55` | Diagnosis: `identityiq` = `SUSPECT` → **fault #3 confirmed**. |
| `19:28:28` | Safety snapshot `pre-iiq-repair-20261016` created (`readyToUse=true`). |
| `~19:28:3x` | `deployment/iiq` scaled to `0`. |
| `~19:28:4x`–`19:28:54` | `DBCC CHECKDB REPAIR_ALLOW_DATA_LOSS` runs; `MULTI_USER` restored (`19:28:54`). |
| `19:29:12` | `deployment/iiq` scaled to `1`; pod `iiq-84f4dd488b-mlhgk` starts. |
| `19:31:28` | Pod `Ready=True` (**~132 s** after start). |
| `~19:32` | Verified `GET /identityiq/login.jsf` → **HTTP 200**. |

---

## 4. Phase 1 — registry / `server-236`

IIQ's image (`192.168.0.236:5000/sailpoint-iiq:8.5`) lives **only** in the insecure
registry co-hosted on `server-236`, an HP-1 Hyper-V guest. With that guest powered off,
every IIQ pod sat in `Init:ImagePullBackOff` and no node had the image cached.

The host process (registry) comes back **as soon as the VM boots** — it does **not**
require the k3s node to be `Ready`.

Confirmations used:

```bash
# reachability of the registry (expect 200)
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.0.236:5000/v2/

# was the image cached anywhere?
kubectl get pods -A -o wide | awk '$7=="server-236"{print $1,$2}'
```

> `server-236`'s `k3s.service` stayed `activating` the whole time and the node never
> re-joined (`EtcdIsVoter=NotAMember`). **This does not block IIQ** — only the registry
> matters. See Follow-ups.

---

## 5. Phase 2 — liveness crash loop (manifest fix)

**Diagnosis.** The pulled image started, but the app container was killed by the
*liveness probe* (not OOM — same exit code 137, different cause):

```
lastState: terminated exitCode=137 reason=Error
           startedAt=2026-10-16T18:22:17Z  finishedAt=2026-10-16T18:27:01Z   # 4m44s
livenessProbe: initialDelaySeconds=180 + 3 x periodSeconds=30  => ~4m30s budget
event: Readiness probe failed: HTTP probe failed with statuscode: 404
```

IIQ's JVM + Tomcat + WAR deploy exceeds the liveness budget, so kubelet killed it
mid-startup → infinite loop. Fix = a `startupProbe` that gates liveness/readiness
until the login page is served.

**Validated before applying** (caught a trap — the repo file was stale and lacked the
`wait-for-identityiq-database` init container, so applying it verbatim would have
**deleted** the init container):

```bash
kubectl apply --dry-run=server -f "kubernetes-manifests/iiq misc/iiq-deployment.yaml"
kubectl diff        -f "kubernetes-manifests/iiq misc/iiq-deployment.yaml"
```

The file was reconciled to match live, then applied:

```bash
kubectl apply -f "kubernetes-manifests/iiq misc/iiq-deployment.yaml"
```

**Exact change** (applied identically to `kubernetes-manifests/iiq-stateful.yaml`):

```diff
     spec:
+      terminationGracePeriodSeconds: 90
+      initContainers:            # <-- reconciled (was missing from the stale repo file)
+        - name: wait-for-identityiq-database
+          ...
       containers:
         - name: iiq
@@
             limits:
               memory: "4Gi"
               cpu: "2000m"
+          startupProbe:
+            httpGet:
+              path: /identityiq/login.jsf
+              port: 8080
+              scheme: HTTP
+            periodSeconds: 15
+            timeoutSeconds: 10
+            failureThreshold: 60          # 60 x 15s = 900s startup budget
           readinessProbe:
             ...
+          lifecycle:
+            preStop:
+              exec:
+                command: ["sh", "-c", "sleep 10"]
           terminationMessagePath: /dev/termination-log
```

---

## 6. Phase 3 — database corruption diagnosis

The startupProbe did its job (no more tight loop); with the extra time, the real
application error surfaced:

```
VersionChecker: Unable to connect to jdbc:sqlserver://db:1433;databaseName=identityiq
Caused by: com.microsoft.sqlserver.jdbc.SQLServerException:
  Cannot open database "identityiq" requested by the login. The login failed.
```

MSSQL errorlog at the last restart (`2026-10-16 15:14`):

```
WARNING: did not see LOP_END_CKPT.
Error: 3414, Severity: 21, State: 3.
Error: 3414, Severity: 21, State: 4.
```

Database state:

```bash
SA=$(kubectl get secret sailpoint-db-secrets -n iiqstack \
       -o jsonpath='{.data.mssql-sa-password}' | base64 -d)
kubectl exec -n iiqstack db-0 -c mssql -- \
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA" -No -C \
  -Q "SET NOCOUNT ON; SELECT name, state_desc FROM sys.databases
      WHERE name='identityiq'"
# => identityiq | SUSPECT
```

Same failure mode as the documented 2026-09-06 incident (torn transaction log from an
unclean shutdown).

**Restore-point survey** before choosing a path:

```bash
VOL=pvc-18e786bf-44f5-495c-8179-9febb4d48a3f
kubectl -n longhorn-system get snapshots.longhorn.io    | grep "$VOL"
kubectl -n longhorn-system get backups.longhorn.io -o json | \
  jq -r --arg v "$VOL" '.items[]
    | select(.status.volumeName==$v)
    | [.metadata.name, .status.state, .metadata.creationTimestamp] | @tsv'
kubectl -n longhorn-system get backuptargets.longhorn.io default -o jsonpath='{.spec.backupTargetURL} {.status.available}{"\n"}'
```

Findings: backup target **Available**; newest backup = `2026-10-15T12:59:29Z`
(**~26 h gap**); a local snapshot existed from `2026-10-16T15:07` (uncertain
consistency). Decision (operator delegated): **repair in place, backup as fallback.**

---

## 7. Phase 4 — database repair

### 7.1 Safety snapshot (before touching anything)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: pre-iiq-repair-20261016
  namespace: longhorn-system
spec:
  volume: pvc-18e786bf-44f5-495c-8179-9febb4d48a3f
  createSnapshot: true
  labels:
    longhornvolume: pvc-18e786bf-44f5-495c-8179-9febb4d48a3f
EOF
# verify: readyToUse=true
kubectl -n longhorn-system get snapshots.longhorn.io pre-iiq-repair-20261016
```

### 7.2 Quiesce the application

```bash
kubectl -n iiqstack scale deployment iiq --replicas=0
```

### 7.3 Repair (the 2026-09-06 procedure)

```bash
SA=$(kubectl get secret sailpoint-db-secrets -n iiqstack \
       -o jsonpath='{.data.mssql-sa-password}' | base64 -d)

kubectl exec -i -n iiqstack db-0 -c mssql -- \
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA" -No -C <<'SQL'
ALTER DATABASE identityiq SET EMERGENCY;
GO
ALTER DATABASE identityiq SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
DBCC CHECKDB('identityiq', REPAIR_ALLOW_DATA_LOSS);
GO
ALTER DATABASE identityiq SET MULTI_USER;
GO
SQL
```

Result (verbatim summary lines):

```
CHECKDB found 19 allocation errors and 172 consistency errors in database 'identityiq'.
CHECKDB fixed 19 allocation errors and 172 consistency errors in database 'identityiq'.
DBCC execution completed.
```

Repaired objects included `sys.sysobjvalues`, `identityiq.spt_server`,
`identityiq.spt_server_statistic`, `identityiq.spt_syslog_event`,
`identityiq.spt_task_result` (index rebuilds + deallocated corrupt pages).

### 7.4 Verification

```bash
# state ONLINE
kubectl exec -n iiqstack db-0 -c mssql -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$SA" -No -C \
  -Q "SET NOCOUNT ON; SELECT name, state_desc, user_access_desc FROM sys.databases WHERE name LIKE 'identityiq%'"

# IIQ schema version intact
kubectl exec -n iiqstack db-0 -c mssql -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$SA" -No -C -d identityiq -Q "SET NOCOUNT ON; SELECT * FROM spt_database_version"

# app login can open the DB
IQUP=$(kubectl get secret sailpoint-db-secrets -n iiqstack -o jsonpath='{.data.mssql-user-password}' | base64 -d)
kubectl exec -n iiqstack db-0 -c mssql -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U identityiq -P "$IQUP" -No -C -d identityiq \
  -Q "SET NOCOUNT ON; SELECT DB_NAME() db, COUNT(*) tables_visible FROM sys.tables"
```

| Check | Result |
|---|---|
| `identityiq` | **ONLINE**, `MULTI_USER` |
| `identityiqPlugin` / `identityiqah` | `ONLINE` |
| `spt_database_version` | `main` = **8.5-19 / 8.5-15** |
| login `identityiq` opens DB | **220** tables |
| Longhorn volume | `healthy`, 3 replicas |

---

## 8. Phase 5 — bring-up & verification

```bash
kubectl -n iiqstack scale deployment iiq --replicas=1
kubectl -n iiqstack rollout status deployment/iiq --timeout=10s

# app actually serving?
POD=$(kubectl -n iiqstack get pods -l app=iiq --no-headers | awk '{print $1; exit}')
kubectl exec -n iiqstack "$POD" -c iiq -- \
  bash -c 'curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080/identityiq/login.jsf'
```

| Check | Result |
|---|---|
| `deployment/iiq` | **1/1**, rollout complete |
| Pod | `iiq-84f4dd488b-mlhgk`, **Ready=True**, **0 restarts** |
| Ready transition | `2026-10-16T19:31:28Z` (~132 s after start) |
| `GET /identityiq/login.jsf` (in-pod) | **HTTP 200** |
| MSSQL errorlog after repair | quiet (last line `Setting database option MULTI_USER to ON`) |

Pod condition snapshot: `PodReadyToStartContainers=True Initialized=True Ready=True ContainersReady=True PodScheduled=True`.

---

## 9. Rollback / fallback (if a repeat repair fails)

If a future `DBCC … REPAIR_ALLOW_DATA_LOSS` returns errors, or the app does not validate:

1. **Restore from backup** (clean, but loses data since the backup):
   scale `db` down, restore Longhorn volume from `backup-afe3d6f259914e6e`
   (or the newest available), rebind `mssql-persistent-storage-db-0`, then scale up.
2. **Revert the volume** to a local snapshot (e.g. `pre-iiq-repair-*`) — the closest
   point in time, but consistency is not guaranteed.
3. Nothing here is destructive to the IIQ Deployment — Phase 2's manifest change can be
   reverted with `kubectl rollout undo deployment/iiq -n iiqstack`.

---

## 10. Files changed in this restore

| File | Change |
|---|---|
| `kubernetes-manifests/iiq misc/iiq-deployment.yaml` | `startupProbe`, `preStop`, `terminationGracePeriodSeconds: 90`; reconciled missing `wait-for-identityiq-database` init container |
| `kubernetes-manifests/iiq-stateful.yaml` | same probes/grace/lifecycle, kept in sync |
| `docs/operations/iiq-database-recovery-2026-10-16.md` | this record |

No SQL/data files, Secrets, or other workloads were modified. The DB was changed only
by the in-place `DBCC` repair.

---

## 11. Follow-ups (open)

1. **Regenerate a SQL-level backup now that the DB is ONLINE**, and fix Longhorn backup
   reliability for this volume. The `2026-10-16T15:03` daily run **failed** with:
   ```
   volume pvc-18e786bf-44f5-495c-8179-9febb4d48a3f is in an invalid state for
   recurring job: attaching. Volume must be in state Attached or Detached
   ```
   so the newest backup was ~26 h stale, and history has multi-day gaps
   (e.g. Sep 24 → Oct 6). Volumes caught `attaching` are silently skipped.
2. **Remove the registry SPOF** — `192.168.0.236:5000` rides on a control-plane node
   that vanished. See `docs/homelab/homelab-control-plane-ha-plan.md`.
3. **`server-236` did not re-join** the cluster (`k3s.service` stuck `activating`,
   `EtcdIsVoter=NotAMember`). Independent of IIQ; repair with
   `docs/operations/k3s-control-plane-ha-runbook.md`.
4. Keep `pre-iiq-repair-20261016` and the Longhorn backup until the app has been
   validated over time.
5. Long-standing (accepted) deviation: `iiq misc/fix-db-corruption-job.yaml` and the
   init Job embed credentials in plaintext — intentional per `AGENTS.md`.
