# 🏥 MSSQL DB Pod - NFS Permission Issue Recovery

**Status**: 🔴 Critical Issue - NFS Mount Permissions  
**Pod**: `default/db-5bf44dd44b-*`  
**Error**: `Error 5(Access is denied.) occurred while opening file '/var/opt/mssql/data/master.mdf'`  
**Date**: 2026-03-30 19:23 UTC  

---

## Root Cause Analysis

The NFS mount `/share/Public/default-mssql-nas-pvc-*` on NASECDE55 (192.168.0.128) has restrictive permissions that prevent the `mssql` user (UID 10001) from writing files, even though:

- ✅ PVC is correctly set to `RWX` (ReadWriteMany)
- ✅ fsGroup is correctly set to `10001`
- ✅ Init container with `runAsUser: 0` attempts to fix permissions
- ❌ **NAS filesystem-level permissions are too restrictive**

**The issue is at the NAS level, not in Kubernetes configuration.**

---

## Immediate Solution: Manual NAS Permission Fix

### Step 1: SSH to NAS Server

```bash
ssh admin@192.168.0.128
```

### Step 2: Identify MSSQL Volume

```bash
ls -la /share/Public/ | grep mssql-nas-pvc
```

You should see a directory like:
```
default-mssql-nas-pvc-pvc-5ebaa04b-d457-40d0-8ff2-9e9a08972d1d/
```

### Step 3: Fix Permissions and Ownership

```bash
# Set permissions to 777 (rwx for all)
sudo chmod -R 777 /share/Public/default-mssql-nas-pvc-pvc-5ebaa04b-d457-40d0-8ff2-9e9a08972d1d

# Set ownership to mssql user (UID 10001)
sudo chown -R 10001:10001 /share/Public/default-mssql-nas-pvc-pvc-5ebaa04b-d457-40d0-8ff2-9e9a08972d1d
```

### Step 4: Verify Permissions

```bash
ls -la /share/Public/default-mssql-nas-pvc-pvc-5ebaa04b-d457-40d0-8ff2-9e9a08972d1d
```

**Expected output:**
```
total 8
drwxrwxrwx  3 10001 10001 4096 Mar 30 19:24 .
drwxr-xr-x 42 root  root  4096 Mar 30 19:23 ..
```

---

## Step 5: Restart Kubernetes Pod

After NAS permissions are fixed, restart the pod:

```bash
kubectl delete pod -n default -l app=db --wait=false
```

The pod will automatically restart and properly mount the NFS volume.

---

## Verification Steps

### Wait for Pod to Start

```bash
kubectl wait --for=condition=Ready pod -n default -l app=db --timeout=120s
```

### Check Logs

```bash
kubectl logs -n default -l app=db | tail -20
```

Expected log line:
```
Microsoft SQL Server 2019 (RTM-CU32) - 15.0.4460.4 (X64)
Server is listening on [ 'any' <ipv4> 1433].
```

### Test Database Connectivity

```bash
kubectl exec -it -n default db-* -- sqlcmd -S . -U sa -P "id3ntityIQ!-TQ8BaiOxKAL4v-4lCIxVx" -Q "SELECT @@VERSION"
```

Expected output: SQL Server version information.

---

## Why This Happens

### NFS Permission Model

1. **NFS exports** from the server enforce UID/GID mapping
2. **NAS typically exports** with specific permissions (e.g., 755 or 750)
3. **Kubernetes fsGroup** can modify permissions within pod context but **cannot override NFS mount restrictions**
4. **Init containers** running as UID 0 (root) in the pod can't exceed NFS mount permissions
5. **Solution requires** fixing permissions at NAS filesystem level

### Why Init Container Didn't Work

Even though the init container runs with:
```yaml
securityContext:
  runAsUser: 0
  allowPrivilegeEscalation: true
```

It still can't fix NFS mount permissions because:
- The NFS mount is already in restricted mode on the NAS
- Kubernetes can't override the NAS export configuration
- The init container can only work within the mounted volume's existing restrictions

---

## Prevention for Future Deployments

### On NAS During Setup

When provisioning new NAS shares for MSSQL:

```bash
# SSH to NAS
ssh admin@192.168.0.128

# Create directory with proper permissions immediately
sudo mkdir -p /share/Public/kubernetes-mssql-volumes

# Set permissions before any Kubernetes access
sudo chmod 777 /share/Public/kubernetes-mssql-volumes

# Set ownership for mssql UID
sudo chown -R 10001:10001 /share/Public/kubernetes-mssql-volumes
```

### In Kubernetes Manifest

Ensure the deployment always has:

```yaml
spec:
  securityContext:
    fsGroup: 10001
    fsGroupChangePolicy: "OnRootMismatch"
  
  initContainers:
  - name: fix-permissions
    image: busybox:latest
    securityContext:
      runAsUser: 0
      allowPrivilegeEscalation: true
    command:
      - sh
      - -c
      - |
        chmod 777 /var/opt/mssql
        chmod 777 /var/opt/mssql/data 2>/dev/null || true
        chmod 777 /var/opt/mssql/log 2>/dev/null || true
```

### NAS Export Configuration

Recommended NAS export options:

```bash
# Add to /etc/exports on NAS
/share/Public 192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,anonuid=10001,anongid=10001)
```

Then reload:
```bash
sudo exportfs -ra
```

---

## Troubleshooting

### If Pod Still Fails After Fix

1. **Verify permissions on NAS again:**
   ```bash
   ssh admin@192.168.0.128
   ls -la /share/Public/default-mssql-nas-pvc-*/
   ```

2. **Check if directory was recreated:**
   ```bash
   # If empty, create data/log directories
   sudo mkdir -p /share/Public/default-mssql-nas-pvc-*/data
   sudo mkdir -p /share/Public/default-mssql-nas-pvc-*/log
   sudo chmod 777 /share/Public/default-mssql-nas-pvc-*/{data,log}
   ```

3. **Check Kubernetes NFS mount logs:**
   ```bash
   ssh ubuntu@kubernetes1
   sudo systemctl status k3s-agent
   sudo journalctl -u k3s-agent -n 50 -f | grep -i "nfs\|mount"
   ```

### Pod Keeps Restarting

1. Delete PVC and let it recreate:
   ```bash
   kubectl delete pvc mssql-nas-pvc -n default
   # NFS provisioner will create new directory with fresh permissions
   kubectl apply -f kubernetes-manifests/base/db-mssql-deployment.yaml
   ```

2. Fix new directory permissions on NAS and restart pod.

---

## Timeline

| Time | Event |
|------|-------|
| 2026-03-30 18:35 | Initial fix applied (security context + init container) |
| 2026-03-30 19:05 | Pod appeared running temporarily |
| 2026-03-30 19:20 | Pod entered CrashLoopBackOff due to NAS permission |
| 2026-03-30 19:23 | Root cause identified: NAS-level permissions |
| **NOW** | **Manual NAS permission fix required** |

---

## Summary

| Item | Status |
|------|--------|
| Kubernetes Configuration | ✅ Correct |
| Security Context | ✅ Configured |
| Init Container | ✅ Running |
| NFS Mount | ✅ Mounted |
| NFS Permissions | ❌ **Too Restrictive** |
| **Required Action** | **SSH to NAS + chmod 777** |

**Time to Fix**: ~2 minutes  
**Difficulty**: Low (3 commands)  
**Required Access**: SSH to NASECDE55

---

**Doc Created**: 2026-03-30 19:23 UTC  
**Pod Status**: CrashLoopBackOff (7 restarts)  
**Next Step**: Execute NAS fix and restart pod
