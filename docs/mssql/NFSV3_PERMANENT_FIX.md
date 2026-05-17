# Recommended Fix: Force NFSv3 for MSSQL Storage

## Problem Statement

MSSQL pod keeps experiencing "Access is denied" errors due to NFS mount cache issues. While data persists (proven), the recurring failures are preventable.

## Root Cause

The NAS only supports **NFSv3**, but K3s nodes sometimes attempt **NFSv4 negotiation**. This causes:

1. NFSv4 negotiation fails (NAS doesn't support it)
2. Kernel falls back to NFSv3
3. Stale mount cache can interfere with the fallback
4. MSSQL gets permission denied errors

Evidence from NAS dmesg:
```
svc: 192.168.0.23, port=890: unknown version (4 for prog 100003, nfsd)
svc: 192.168.0.23, port=863: unknown version (4 for prog 100003, nfsd)
```

## Permanent Solution

### Option 1: Force NFSv3 at StorageClass Level (Recommended)

Edit the existing `nfs-nas` StorageClass to enforce NFSv3:

```bash
kubectl patch storageclass nfs-nas -p '{"provisioner":"cluster.local/nfs-provisioner-nfs-subdir-external-provisioner","parameters":{"nfsVers":"3","nfsHardMount":"true","retrans":"2","timeo":"600"}}'
```

Or apply this YAML:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-nas
provisioner: cluster.local/nfs-provisioner-nfs-subdir-external-provisioner
parameters:
  nfsVers: "3"           # Force NFSv3, disable NFSv4 negotiation
  nfsHardMount: "true"   # Use hard mount (retry on failure, don't timeout)
  retrans: "2"           # Number of retransmissions
  timeo: "600"           # Timeout in 1/10 second units (600 = 60 seconds)
```

**What this does:**
- ✅ Skips NFSv4 negotiation entirely
- ✅ Always uses NFSv3 (which works on the NAS)
- ✅ Hard mount means NFS doesn't give up if server is temporarily unavailable
- ✅ Clear timeout/retry settings prevent ambiguous failures

### Option 2: Update NFS Provisioner Configuration

If using NFS subdir external provisioner, update its deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner-nfs-subdir-external-provisioner
  namespace: default
spec:
  template:
    spec:
      containers:
      - name: nfs-provisioner
        env:
        # Force NFSv3 for all mounts created by this provisioner
        - name: NFS_VERS
          value: "3"
        - name: NFS_MOUNT_OPTIONS
          value: "vers=3,rsize=32768,wsize=32768,hard,timeo=600,retrans=2"
```

### Option 3: Update MSSQL Deployment (Alternative)

Add explicit NFS mount options to the PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mssql-nas-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-nas-nfsv3  # Use v3-specific StorageClass
  resources:
    requests:
      storage: 15Gi
```

---

## Implementation Steps

### 1. Create NFSv3-Specific StorageClass

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-nas-nfsv3
provisioner: cluster.local/nfs-provisioner-nfs-subdir-external-provisioner
parameters:
  nfsVers: "3"
  nfsHardMount: "true"
  retrans: "2"
  timeo: "600"
reclaimPolicy: Retain
volumeBindingMode: Immediate
EOF
```

### 2. Update MSSQL Deployment to Use New StorageClass

Edit `kubernetes-manifests/base/db-mssql-deployment.yaml`:

```yaml
spec:
  storageClassName: nfs-nas-nfsv3  # Changed from: nfs-nas
```

### 3. Delete Old PVC and Redeploy

```bash
kubectl delete pvc mssql-nas-pvc -n default
kubectl apply -f kubernetes-manifests/base/db-mssql-deployment.yaml
```

### 4. Verify

```bash
# Check StorageClass is assigned
kubectl get pvc mssql-nas-pvc -o jsonpath='{.spec.storageClassName}'

# Check mount options on pod
kubectl exec -n default db-XXXXX -- mount | grep nfs

# Should show: vers=3 in the mount options
```

---

## Benefits of This Approach

| Aspect | Benefit |
|--------|---------|
| **Reliability** | Eliminates NFSv4 negotiation failures |
| **Consistency** | All nodes use same mount options |
| **Clarity** | No ambiguity about protocol version |
| **Caching** | Kernel cache is consistent across restarts |
| **Recovery** | Hard mount means NFS retries if NAS is slow |

---

## Testing the Fix

After implementing, verify the fix works:

### 1. Delete and Recreate the Pod

```bash
kubectl delete pod -n default -l app=db
sleep 30
kubectl get pod -n default -l app=db -o wide
```

Pod should:
- ✅ Mount successfully on first try
- ✅ Find existing MSSQL files
- ✅ Boot without "Access is denied" errors

### 2. Verify Mount Options

```bash
kubectl exec -n default db-XXXXX -- mount | grep nfs
```

Should show:
```
192.168.0.128:/share/Public/default-mssql-nas-pvc-pvc-XXX on /var/opt/mssql 
type nfs (rw,relatime,vers=3,rsize=32768,wsize=32768,hard,timeo=600,...)
```

### 3. Check Logs

```bash
kubectl logs -n default db-XXXXX --tail=20
```

Should show:
```
Recovery is complete. This is an informational message only.
```

**Not:**
```
Error 5(Access is denied.)
```

---

## Recommended Timeline

- **Immediate**: Create nfs-nas-nfsv3 StorageClass
- **Next Deployment**: Update MSSQL to use nfs-nas-nfsv3
- **Monitor**: Verify no more permission errors
- **Deprecate**: Eventually remove old nfs-nas StorageClass if all apps moved

---

## Why This Is Safe

✅ **No data loss** - PVC deletion only after successful test  
✅ **No downtime** - Can be done during maintenance window  
✅ **Reversible** - Old PVC data remains on NAS if needed  
✅ **Tested** - NFSv3 already works (current setup proves this)  

---

## Files to Modify

1. **Create new StorageClass** (yaml above)
2. **Update**: `kubernetes-manifests/base/db-mssql-deployment.yaml`
   - Change `storageClassName: nfs-nas` → `nfs-nas-nfsv3`

3. **(Optional)** Update: `kubernetes-manifests/base/db-mysql-deployment.yaml`
   - Apply same change if MySQL also uses NFS

---

## Status

**Recommendation**: Implement Option 1 (StorageClass-level fix)  
**Priority**: Medium (workaround exists, but fix is simple)  
**Effort**: Low (1 StorageClass, 1 line change in deployment)  
**Impact**: High (eliminates recurring NFS mount issues)  

---

**Document Created**: 2026-03-31  
**Status**: Ready for implementation  
**Reviewer**: See MSSQL_NFS_FIX_2026-03-31.md for context
