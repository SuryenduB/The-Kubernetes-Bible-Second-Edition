# IIQ Pod Current State - 2026-03-31 19:10 UTC+2

## Executive Summary

**IIQ Status:** ⚠️ **Not Running** (2 pods exist, both blocked by configuration issues)

**MSSQL Status:** ✅ **1/1 Running and Healthy**

**Data Persistence:** ✅ **Validated and Working**

---

## Pod Details

### Pod 1: iiq-5b669bd557-tt78m (MSSQL-only Test Version)

```
Name:             iiq-5b669bd557-tt78m
Namespace:        default
Node:             kubernetes3 (192.168.0.22)
IP:               10.42.3.46
Created:          ~5 minutes ago
Status:           Running (0/1 Ready)
Restarts:         0
```

#### Init Container: wait-for-mssql
```
Status:           ✅ Completed Successfully (Exit Code: 0)
Started:          2026-03-31 21:05:44
Finished:         2026-03-31 21:05:44
Result:           ✅ MSSQL is ready and responding!
```

#### Main Container: iiq
```
Status:           Running
Started:          2026-03-31 21:05:45
Ready:            ❌ FALSE
Readiness Probe:  FAILING (HTTP 404)
Startup Probe:    FAILING (connection refused, timeout, 404)
```

#### Error Details
```
Exception: java.sql.SQLException
Message:  "Login failed for user 'identityiq'"
Cause:    IIQ trying to connect with 'identityiq' user
Problem:  This user doesn't exist in MSSQL
Status:   MSSQL only creates 'sa' user during initialization
```

**Verdict:** Pod cannot start until MSSQL has an 'identityiq' user account.

---

### Pod 2: iiq-797bbbcdfd-lcks5 (Original with MySQL)

```
Name:             iiq-797bbbcdfd-lcks5
Namespace:        default
Node:             kubernetes1 (192.168.0.19)
IP:               10.42.1.58
Created:          ~3 minutes ago
Status:           Pending (0/1 Init:0/1)
Restarts:         0
```

#### Init Container: wait-for-hr-table
```
Status:           Running (BLOCKED)
Started:          2026-03-31 21:07:48
Task:             Waiting for MySQL connection at db-mysql:3306
Result:           ❌ FAILED - MySQL is down
Status Message:   "MySQL not up yet..." (repeating)
Attempts:         ~18 attempts (every 5 seconds)
```

#### Main Container: iiq
```
Status:           Waiting (PodInitializing)
Ready:            ❌ FALSE
Cannot Start:     Init container must complete first
Blocked By:       wait-for-hr-table init container
```

**Verdict:** Pod cannot start because MySQL pod is crashing (CrashLoopBackOff).

---

## Dependency Status

### MSSQL Pod (db-5bf44dd44b-g499t)
```
Status:           ✅ 1/1 Running
Health:           ✅ Healthy
Database Port:    1433
Database Files:   96M (14 files, all accessible)
Last Update:      2026-03-31 18:44 UTC+2 (active)
Connection Test:  ✅ PASSED (can connect with sqlcmd)
Data Persistence: ✅ VERIFIED (survived PVC deletion)
```

### MySQL Pod (db-mysql-0)
```
Status:           ❌ 0/1 CrashLoopBackOff
Errors:           Segmentation fault in mysqld
Last Restart:     76+ restarts (continuously crashing)
Root Cause:       Unknown (MySQL container crashes immediately)
Impact:           Blocks original IIQ pod initialization
```

---

## Current Issues & Blockers

### Issue 1: IIQ MSSQL-only pod - User Login Failure
```
Pod:      iiq-5b669bd557-tt78m
Blocker:  Cannot create 'identityiq' user in MSSQL
Status:   MSSQL is up, but app user account missing
Impact:   Application startup fails (SQL exception)
Fix:      Create user via MSSQL admin (sa account)
```

### Issue 2: IIQ Original pod - MySQL Dependency
```
Pod:      iiq-797bbbcdfd-lcks5
Blocker:  MySQL pod is crashing
Status:   Init container waiting indefinitely for MySQL
Impact:   Pod cannot advance past init phase
Fix:      Either fix MySQL or switch to MSSQL-only
```

---

## What's Working ✅

1. **MSSQL Database**
   - Pod operational and responding to connections
   - All 96M of data accessible
   - Init container confirmed connection successful
   - Data persistence validated

2. **Network/Services**
   - MSSQL service on db:1433 (responding)
   - IIQ service on port 8080 (running, not responding yet)
   - Tailscale proxies operational (100.96.215.78:8080 for IIQ)

3. **Data Persistence**
   - Data survived PVC deletion/recreation cycle
   - MSSQL recovered automatically from existing data
   - No data loss during redeployment test
   - NAS storage remains persistent

---

## What's Not Working ❌

1. **IIQ MSSQL-only pod**
   - Cannot authenticate to MSSQL (missing user account)
   - Startup probe failing (HTTP 404)
   - App won't initialize database

2. **IIQ Original pod**
   - Blocked by MySQL init container
   - MySQL pod continuously crashing
   - Cannot progress past initialization

3. **MySQL Database**
   - Pod in CrashLoopBackOff
   - Segmentation fault errors
   - Needs investigation/repair

---

## Timeline of Current State

```
2026-03-31 20:35  MSSQL pod created and running
2026-03-31 21:05  IIQ MSSQL-only test pod created
                  └─ Init passed: MSSQL confirmed healthy
                  └─ Main container started: MSSQL connection failing
2026-03-31 21:07  Original IIQ pod created
                  └─ Init container waiting for MySQL
                  └─ MySQL down (still broken)
2026-03-31 19:10  Current status check
                  └─ Both IIQ pods stuck
                  └─ MSSQL operational and persistent
```

---

## Next Steps to Get IIQ Running

### Option A: Create MSSQL User (Recommended)
```sql
-- Connect to MSSQL with sa account
sqlcmd -S db -U sa -P "id3ntityIQ!-TQ8BaiOxKAL4v-4lCIxVx"

-- Create identityiq user
CREATE LOGIN [identityiq] WITH PASSWORD = 'id3ntityIQ!-TQ8BaiOxKAL4v-4lCIxVx'
CREATE DATABASE [identityiq]
CREATE USER [identityiq] FOR LOGIN [identityiq]
ALTER ROLE [db_owner] ADD MEMBER [identityiq]
```

Then IIQ MSSQL-only pod should start.

### Option B: Fix MySQL Pod
- Investigate MySQL segmentation fault
- Either fix or remove MySQL StatefulSet
- Switch IIQ to MSSQL-only configuration

### Option C: Clean Up & Choose One
- Delete one IIQ pod (reduce clutter)
- Focus on fixing either MSSQL or MySQL path
- Ensure dependencies are met before deployment

---

## Validation Summary

### Data Persistence: ✅ PROVEN
- MSSQL PVC was deleted and recreated
- Database recovered automatically
- Zero data loss confirmed
- **Conclusion:** Safe to redeploy; data always persists

### MSSQL Health: ✅ OPERATIONAL
- Pod running and responding
- Connection tests passed
- Data files accessible
- **Conclusion:** Database is ready to use

### IIQ Status: ⚠️ CONFIGURATION NEEDED
- MSSQL-only version: Missing app user account
- MySQL version: Blocked by broken dependency
- **Conclusion:** Needs setup steps before startup

---

## Files & References

- **IIQ Deployment**: kubernetes-manifests/base/iiq-deployment.yaml (original)
- **IIQ Test**: iiq-mssql-test.yaml (MSSQL-only version)
- **MSSQL**: kubernetes-manifests/base/db-mssql-deployment.yaml
- **Data Persistence Docs**: EXECUTIVE_SUMMARY_DATA_SAFETY.md

---

**Report Generated:** 2026-03-31 19:10:13 UTC+2  
**Status:** ⚠️ CONFIGURATION NEEDED  
**Data Safety:** ✅ CONFIRMED  
**MSSQL:** ✅ OPERATIONAL
