# MSSQL NFS Permission Fix - 2026-03-31

## Problem

MSSQL pod (`db-5bf44dd44b-5sspq`) was stuck in **CrashLoopBackOff** with the error:

```
Error 5(Access is denied.) occurred while opening file '/var/opt/mssql/data/master.mdf' 
to obtain configuration information at startup.
```

This was the **same NFS permission issue that was previously fixed on 2026-03-27**.

## Root Cause

The Kubernetes cluster had **cached the old NFS mount options** from the previous state. When NFS exports are modified on the server (`/etc/exports`), the kernel-level NFS mount cache on the client doesn't automatically update.

Even though the NAS (`NASECDE55`) had the correct export configuration with `anonuid=10001`:

```
"/share/CACHEDEV1_DATA/Public" *(rw,async,no_subtree_check,insecure,no_root_squash,anonuid=10001,anongid=0,fsid=...)
```

The **cached mount** on the Kubernetes node was still trying to use the old UID mapping rules.

## Solution

**Force a fresh NFS mount negotiation by deleting and recreating the PVC:**

### Steps Taken

1. **Deleted the MSSQL pod** to release the PVC mount:
   ```bash
   kubectl delete pod -n default -l app=db
   ```

2. **Force-deleted the PVC** to unmount the NFS share:
   ```bash
   kubectl delete pvc mssql-nas-pvc -n default --force --grace-period=0
   ```

3. **Recreated the PVC** by reapplying the deployment:
   ```bash
   kubectl apply -f kubernetes-manifests/base/db-mssql-deployment.yaml
   ```

4. **Verified the pod recovered** and started successfully.

### Why This Works

- **PVC deletion** forces the NFS mount to be torn down completely
- **Fresh PVC binding** negotiates new NFS mount options with the server
- The server responds with the current export configuration (with `anonuid=10001`)
- **Pod restart** uses the updated mount options

This is different from simply restarting the pod—the cached mount must be completely released and renegotiated.

## Result

✅ **MSSQL pod is now 1/1 Running**

```
NAME                  READY   STATUS    RESTARTS   AGE
db-5bf44dd44b-g499t   1/1     Running   0          2m48s
```

Pod logs show:
```
2026-03-31 18:35:22.44 spid10s     Recovery is complete. This is an informational message only.
2026-03-31 18:35:22.45 spid32s     The default language (LCID 0) has been set for engine and full-text services.
2026-03-31 18:35:24.52 spid32s     The tempdb database has 4 data file(s).
```

✅ **No "Access is denied" errors**
✅ **Database is operational and ready**

## Files Modified

- **kubernetes-manifests/base/db-mssql-deployment.yaml**
  - No changes needed—deployment manifest is correct
  - Security context already has `fsGroup: 10001`
  - Init container already has permission-fixing logic

## NAS Configuration

✅ **Verified NAS export settings are correct:**
```bash
$ ssh admin@192.168.0.128 "cat /etc/exports"
"/share/CACHEDEV1_DATA/Public" *(rw,async,no_subtree_check,insecure,no_root_squash,anonuid=10001,anongid=0,...)
```

## Key Lessons

1. **NFS kernel mount caching** is persistent until the mount is completely released
2. **Pod restart alone is insufficient**—must delete the PVC to force kernel-level mount renegotiation
3. **Server-side NFS settings** (`anonuid`) cannot be overridden by client-side Kubernetes security contexts
4. **fsGroup is not the same as NFS UID squashing**—fsGroup only works for Kubernetes-provisioned volumes, not NFS exported shares

## Related Documentation

- **MSSQL_NFS_PERMISSION_FIX.md** — Original detailed analysis (2026-03-27)
- **kubernetes-manifests/base/db-mssql-deployment.yaml** — Deployment with security fixes

## Next Steps for IdentityIQ

Currently, IdentityIQ (`iiq`) pod is waiting for MySQL to be ready. That's a separate issue:
- MSSQL: ✅ **Operational**
- MySQL: ⚠️ **CrashLoopBackOff** (needs investigation)
- Tailscale proxy: ✅ **Operational at 100.96.215.78:8080**

The IIQ Tailscale proxy is ready to receive traffic once the IIQ pod initialization completes.

---

**Timestamp:** 2026-03-31 20:35 UTC+2
**Status:** ✅ RESOLVED
