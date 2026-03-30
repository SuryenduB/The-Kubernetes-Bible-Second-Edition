# MSSQL NFS Permission Fix Guide - Root Cause & Resolution

**Status**: ✅ **RESOLVED**  
**Affected Pod**: `db-5bf44dd44b-sq2nm` (MSSQL 2019)  
**Error**: `Error 5(Access is denied.)` on `/var/opt/mssql/data/master.mdf`  
**Root Cause**: NFS export missing UID mapping (`anonuid`) for non-root user UID 10001  
**Solution**: Updated Synology `/etc/exports` with `anonuid=10001,anongid=0`  
**Resolution Date**: 2026-03-30 19:37 UTC  
**Pod Status**: ✅ **1/1 Running**

---

## Executive Summary

The MSSQL pod crashed after migration from **local node storage** to **NFS storage** because:

1. **Old Setup** (Local Storage): Kubernetes managed permissions directly → ✅ Worked
2. **New Setup** (NFS Storage): Synology NAS enforced permissions server-side → ❌ Failed
3. **The Issue**: NAS export lacked `anonuid=10001` mapping for the MSSQL UID
4. **The Fix**: Updated `/etc/exports` on the NAS to include UID mapping
5. **The Result**: Pod recovered to `1/1 Running` status

**Key Learning**: NFS permissions are **server-side enforced**—Kubernetes security contexts and privileged init containers **cannot override** NAS-level restrictions.

---

## The Problem: Why Did NFS Suddenly Fail?

### Timeline of Events

| Time | Action | Result |
|------|--------|--------|
| Pre-19:20 | Pod running on local node storage | ✅ Working |
| 19:20 | Manifest changed: `mssql-pvc` → `mssql-nas-pvc` + `storageClassName: nfs-nas` | 📦 PVC recreated |
| 19:20+ | NFS provisioner created new PVC directory on NAS | ⚠️ Default permissions applied |
| 19:22 | Pod started and tried to access `/var/opt/mssql/data/master.mdf` | ❌ Access denied |
| 19:22-19:35 | Pod crashed, restarted 7 times (CrashLoopBackOff) | 🔴 Critical |

### Why It Wasn't Sudden—It Was a Configuration Change

The NFS "restriction" wasn't sudden—it was **always there**. The problem was:

```
┌─────────────────────────────────────────────┐
│ Local Storage (Original Manifest)           │
│ - No NFS involved                           │
│ - Kubernetes fsGroup: 10001 works           │
│ - Pod ✅ RUNNING                            │
└─────────────────────────────────────────────┘

                    ↓ (Manifest changed)

┌─────────────────────────────────────────────┐
│ NFS Storage (Updated Manifest)              │
│ - Synology NAS is now the source of truth   │
│ - NFS export lacks anonuid=10001            │
│ - Kubernetes fsGroup: 10001 IGNORED         │
│ - Pod ❌ CrashLoopBackOff                   │
└─────────────────────────────────────────────┘
```

**Other pods don't have this issue** because:
- Most run as UID 0 (root) or UID 100+ (not 10001)
- NFS default UID squashing maps non-root to "nobody"
- Root isn't affected by squashing
- **MSSQL is unique**: runs specifically as UID 10001

---

## Root Cause: UID Squashing vs UID Mapping

### NFS UID Squashing Explained

When NFS doesn't have `anonuid` specified:

```
NFS Server Default Behavior:
├─ Root requests (UID 0) → Mapped to UID 0 (works for root)
└─ Anonymous requests (no UID mapping) → Squashed to UID 65534 "nobody"

Result: UID 10001 request from Kubernetes
├─ NAS: "You're not mapped, squashing you to UID 65534"
├─ UID 65534 tries to read files owned by UID 10001
└─ Permission denied: 65534 ≠ 10001 ❌
```

### NFS UID Mapping (Fixed)

With `anonuid=10001` in export:

```
NFS Server with anonuid=10001:
├─ Root requests (UID 0) → Still UID 0 (no_root_squash)
└─ Anonymous requests → Mapped to UID 10001

Result: UID 10001 request from Kubernetes
├─ NAS: "You're anonymous, mapping you to UID 10001"
├─ UID 10001 tries to read files owned by UID 10001
└─ Permission granted: 10001 = 10001 ✅
```

### Why Kubernetes-Only Fixes Failed

All these fixes were attempted but **couldn't work** because they're client-side:

| Fix | Kubernetes Scope | NFS Server | Result |
|-----|------------------|-----------|--------|
| `fsGroup: 10001` | Pod spec | Ignored | ❌ Doesn't affect NFS |
| Init container `chmod 777` | Pod spec | Ignored | ❌ Doesn't affect NFS |
| Init container `runAsUser: 0` | Pod spec | Ignored | ❌ Root on client doesn't override server |
| `allowPrivilegeEscalation: true` | Pod spec | Ignored | ❌ Still subject to NFS squashing |

**The NAS server is the authority.** Only NAS-level configuration matters.

---

## Solution: NFS Export Configuration

### The Fix Applied

**Location**: `/etc/exports` on NASECDE55 (192.168.0.128)

**Before:**
```
"/share/CACHEDEV1_DATA/Public" *(rw,async,no_subtree_check,insecure,no_root_squash,fsid=187f07688af237f648d8f7126f908066)
```

**After:**
```
"/share/CACHEDEV1_DATA/Public" *(rw,async,no_subtree_check,insecure,no_root_squash,anonuid=10001,anongid=0,fsid=187f07688af237f648d8f7126f908066)
```

**What Changed:**
- `anonuid=10001` → Map all anonymous (Kubernetes) client requests to UID 10001
- `anongid=0` → Map to GID 0 (administrators group on NAS)
- `no_root_squash` → Keep root as root (preserved from original)

### Execution Steps

```bash
# 1. SSH to NAS
ssh admin@192.168.0.128

# 2. Update /etc/exports with new UID mapping
sudo bash -c 'echo "/share/CACHEDEV1_DATA/Public *(rw,async,no_subtree_check,insecure,no_root_squash,anonuid=10001,anongid=0,fsid=187f07688af237f648d8f7126f908066)" > /etc/exports'

# 3. Reload NFS exports
sudo exportfs -ra

# 4. Verify configuration
cat /etc/exports

# 5. Exit NAS
exit
```

### Kubernetes Recovery

After NAS export is fixed, the NFS mount will automatically remount with new settings:

```bash
# Delete old pod to trigger NFS remount
kubectl delete pod -n default -l app=db

# Verify new pod is ready
kubectl wait --for=condition=Ready pod -n default -l app=db --timeout=120s

# Check logs show successful MSSQL startup
kubectl logs -n default -l app=db | tail -3
```

**Expected Output:**
```
SQL Server 2019 will run as non-root by default.
This container is running as user mssql.
Your master database file is owned by mssql.
```

---

## Why This Only Affected MSSQL

### UID 10001 is MSSQL-Specific

```bash
# Check MSSQL container's UID
docker run --rm mcr.microsoft.com/mssql/server:2019-latest id
# uid=10001(mssql) gid=0(root) groups=0(root)
```

| Workload | UID | NFS Squashing Impact |
|----------|-----|---------------------|
| MSSQL | 10001 | ❌ **Squashed to 65534** (no anonuid) |
| Keycloak | 0 | ✅ Root not squashed (no_root_squash) |
| ActiveMQ | 0 | ✅ Root not squashed |
| Ollama | 0 | ✅ Root not squashed |
| MySQL | 999 | ⚠️ Would have same issue if run as 999 |

**MSSQL is the only container explicitly requiring a non-root, non-0 UID.**

---

## Prevention: Ensuring This Doesn't Happen Again

### 1. Permanent NAS Configuration

The updated `/etc/exports` now includes `anonuid=10001`. **Keep this permanently** because:

```
✅ Benefits:
   - Any future MSSQL deployments will have correct permissions
   - No manual NAS fix needed in future
   - Aligns with MSSQL's UID requirement

⚠️ Considerations:
   - Non-root clients now map to UID 10001 (MSSQL UID)
   - Other workloads on NFS won't be affected (they use UID 0)
   - Can be reverted if MSSQL is removed permanently
```

### 2. Documentation in Code

Add to `K3s_Homelab_Template.md` under "MSSQL Deployment":

```markdown
### MSSQL Storage Requirements

MSSQL 2019 container runs as UID 10001 and requires:

1. **NFS Export Configuration**: The NAS export MUST include:
   ```
   anonuid=10001,anongid=0
   ```
   Without this, pod will crash with "Error 5(Access is denied.)"

2. **Kubernetes Manifest**: PVC must use:
   ```yaml
   storageClassName: nfs-nas
   accessModes: [ ReadWriteMany ]
   ```

3. **Init Container**: Include for defensive permission fixing:
   ```yaml
   initContainers:
   - name: fix-permissions
     image: busybox:latest
     securityContext:
       runAsUser: 0
     command:
       - sh
       - -c
       - chmod -R 777 /var/opt/mssql
   ```

This is a **fundamental NFS constraint**, not a Kubernetes bug.
```

### 3. Operational Playbook

**Troubleshooting Checklist for MSSQL NFS Issues:**

```bash
# 1. Check NAS has correct export settings
ssh admin@192.168.0.128 "grep 'CACHEDEV1_DATA' /etc/exports | grep anonuid=10001"
# Expected: Shows anonuid=10001 in output

# 2. Check PVC directory exists and has right ownership
ssh admin@192.168.0.128 "ls -la /share/Public/ | grep mssql"
# Expected: Shows directory with UID 10001 or 65534

# 3. Check Kubernetes pod status
kubectl get pod -l app=db -o wide
# Expected: READY 1/1, STATUS Running

# 4. If still failing, check pod logs
kubectl logs -l app=db | grep -i "error\|denied"
```

---

## Lessons Learned & Architecture Insights

### Local vs. Remote Storage

| Aspect | Local Storage | NFS Storage |
|--------|---------------|------------|
| **Authority** | Kubernetes (pod) | NAS Server |
| **UID Mapping** | Kubernetes fsGroup | NFS export anonuid |
| **Security Context** | **Works** ✅ | Ignored ❌ |
| **Troubleshooting** | Look in pod → `kubectl logs` | Look at NAS → `/etc/exports` |

### NFS Permission Model (Critical Understanding)

```
Layer 1: NFS Export (/etc/exports)
    ├─ anonuid=10001,anongid=0
    └─ ✅ Maps Kubernetes UID to MSSQL UID
        (This is what was missing)

Layer 2: Directory Permissions
    ├─ /share/Public/default-mssql-nas-pvc-*
    └─ 777 (all users can access)
        (This wasn't the primary issue)

Layer 3: Kubernetes SecurityContext
    ├─ fsGroup: 10001
    └─ ❌ Ignored (client-side only)
        (This doesn't help with NFS)
```

### Key Insight: Layered Security

When using NFS storage, **ALL three layers must align**:

1. ✅ NFS export: `anonuid=10001` (server-side)
2. ✅ Directory permissions: `777` or owner=10001 (server-side)
3. ✅ Kubernetes security context: `fsGroup: 10001` (client-side, defensive)

If ANY layer fails, the pod fails. The NAS export is the most critical (it's the authority).

---

## Git Commit Record

This issue and fix were documented across multiple commits:

```bash
# Initial manifest changes (added fsGroup and init container)
git show 5b2a4e7 -- kubernetes-manifests/base/db-mssql-deployment.yaml

# Documented the issue
git show d60bb86 -- MSSQL_NFS_PERMISSION_FIX.md

# Root cause investigation shows NFS export was the actual issue
# (Not file permissions, not Kubernetes config)
```

**Important**: The init container and fsGroup from commit `5b2a4e7` are still valuable:
- They ensure directory permissions are at least `777`
- They provide a safety net if NAS permissions change
- But **they cannot fix the core NFS export configuration**

---

## Related Documentation

- **CLUSTER_FIXES_2026-03-30.md** - Overview of 3 cluster issues (MSSQL, IIQ, Ollama)
- **REMEDIATION_COMPLETE_2026-03-30.md** - Executive summary with metrics
- **K3s_Homelab_Template.md** - Operational reference guide (includes NFS/MSSQL notes)
- **kubernetes-manifests/base/db-mssql-deployment.yaml** - Current manifest with init container
- **Kubernetes commit 5b2a4e7** - Initial MSSQL manifest updates
- **Kubernetes commit d60bb86** - Original issue documentation

---

## FAQ

**Q: Why did this only happen after changing the PVC name from `mssql-pvc` to `mssql-nas-pvc`?**

A: Changing the PVC name forced the provisioner to create a **new** NFS directory. The old `mssql-pvc` used local node storage (no NFS), so there was no UID squashing. The new `mssql-nas-pvc` triggered NFS provisioning, which created a directory with default export settings (no `anonuid` mapping).

**Q: Could this have been prevented?**

A: Yes, by keeping `anonuid=10001` in the NAS export **before** the migration. Or by documenting the MSSQL UID requirement in the setup guide.

**Q: Will this fix affect other workloads?**

A: No. Other containers run as UID 0 (root) or use UID 0 explicitly. The `anonuid=10001` mapping only affects clients that are not explicitly authenticated. Root requests (UID 0) still use `no_root_squash` behavior.

**Q: Can Kubernetes security context fix this in future?**

A: **No, not alone.** NFS export configuration must be correct at the NAS. Kubernetes config is a defensive layer, not the primary solution.

**Q: Should we update the NAS export permanently?**

A: **Yes.** Keeping `anonuid=10001` is beneficial for any MSSQL deployment and has no negative side effects on other workloads.

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-03-30 | Initial documentation - issue resolved |
| 1.0 | 2026-03-30 19:37 | Pod recovered to 1/1 Running |

---

**Last Updated**: 2026-03-30 19:37 UTC
**Status**: ✅ Issue Resolved - Pod Running
**Next Review**: Monitor for 48 hours to ensure stability
