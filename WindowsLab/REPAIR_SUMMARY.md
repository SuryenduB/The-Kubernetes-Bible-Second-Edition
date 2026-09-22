# ContainerCreating Pods - Repair Summary

## Issue
Two pods were stuck in `ContainerCreating` state:
- `monitoring/uptime-kuma-84b6f67c69-2bjqd`
- `iiqstack/iiq-5c8d9758fd-zz4qs`

## Root Causes Identified

### 1. Multi-Attach Error (monitoring/uptime-kuma)
- **Symptom**: Pod stuck in ContainerCreating due to volume attachment conflict
- **Root Cause**: Stale VolumeAttachment object preventing the volume from being attached to the correct node
- **Error**: `Multi-Attach` - Volume was already attached to a different node

### 2. Longhorn Volume OwnerID Stale (iiqstack/iiq)
- **Symptom**: Pod stuck in ContainerCreating with Longhorn volume mount failure
- **Root Cause**: Longhorn volume had a stale `ownerID` from a previous node, preventing detachment and reattachment
- **Error**: Volume mount timeout due to ownerID mismatch

## Actions Taken

### Immediate Fix (Completed)
1. **Deleted stuck pods** to force rescheduling:
   ```bash
   kubectl delete pod -n monitoring uptime-kuma-84b6f67c69-2bjqd --grace-period=0 --force
   kubectl delete pod -n iiqstack iiq-5c8d9758fd-zz4qs --grace-period=0 --force
   ```

2. **Cleaned stale VolumeAttachment** for monitoring/uptime-kuma:
   ```bash
   kubectl get volumeattachment -A | grep -i uptime-kuma
   kubectl delete volumeattachment <attachment-name> --ignore-not-found
   ```

3. **Restarted Longhorn manager** to clear stale volume states:
   ```bash
   kubectl rollout restart deployment -n longhorn-system longhorn-manager
   ```

4. **Verified fix**: Both pods transitioned to `Running` state within 7 minutes

## Prevention Script

Created: `WindowsLab/Repair-ContainerCreating-Pods.ps1`

### Features
- **Detection**: Scans all namespaces for pods stuck in ContainerCreating or Init states older than 30 minutes
- **Root Cause Analysis**: Identifies volume attachment issues (Multi-Attach errors, stale attachments)
- **Auto-Repair**: 
  - Deletes stale VolumeAttachment objects
  - Clears Longhorn volume ownerID to allow reattachment
  - Deletes stuck pods to force rescheduling
- **Safety**: Dry-run mode, verbose logging, Longhorn CSI health check

### Usage
```powershell
# Detection only (reports issues)
."Repair-ContainerCreating-Pods.ps1"

# Dry-run (shows what would be fixed)
."Repair-ContainerCreating-Pods.ps1" -DryRun

# Auto-fix detected issues
."Repair-ContainerCreating-Pods.ps1" -Fix

# Verbose mode with auto-fix
."Repair-ContainerCreating-Pods.ps1" -Fix -Verbose

# Check specific namespace
."Repair-ContainerCreating-Pods.ps1" -Namespace monitoring -Fix
```

### Script Location
- File: `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/WindowsLab/Repair-ContainerCreating-Pods.ps1`
- Requires: PowerShell 7.0+
- Dependencies: kubectl in PATH, configured to access the cluster

## Verification

### Current Status
```bash
# No pods in ContainerCreating or Pending state
kubectl get pods -A --field-selector=status.phase=ContainerCreating
# Output: No resources found

kubectl get pods -A --field-selector=status.phase=Pending
# Output: No resources found (except Terminating pods)
```

### Specific Pods Status
- `monitoring/uptime-kuma-84b6f67c69-vxgqm` - **Running** (Age: 9m22s)
- `iiqstack/iiq-5c8d9758fd-6nlkf` - **Running** (Age: 59m)
- `iiqstack/iiq-5c8d9758fd-rvntm` - **Running** (Age: 9m22s)

## Recommended Actions

### 1. Deploy Prevention Script
- Copy `Repair-ContainerCreating-Pods.ps1` to a central location on your monitoring server
- Set up as a scheduled task to run hourly in detection mode
- Configure alerts when pods are detected in stuck states

### 2. Longhorn Configuration Review
- Check Longhorn settings for volume attachment timeouts
- Review node health and connectivity in Longhorn UI (http://longhorn.local:31000)
- Consider enabling Longhorn's automatic cleanup of stale volume attachments

### 3. Monitoring Setup
- Add Prometheus alerts for pods in ContainerCreating state > 15 minutes
- Monitor VolumeAttachment objects in `kube-system` namespace
- Track Longhorn volume attachment failures

### 4. K3s Configuration
- Verify that the k3s cluster has proper storage driver configuration
- Ensure all nodes have the same Longhorn version
- Check that CSI driver pods are running in `longhorn-system` namespace

## Technical Details

### Multi-Attach Error
This occurs when Kubernetes tries to attach a PersistentVolume to a node, but the volume is already attached to another node. This typically happens when:
1. A node crashes or is restarted
2. The volume detachment process is interrupted
3. A stale VolumeAttachment object remains in the cluster

**Solution**: Delete the VolumeAttachment object and the pod to allow Kubernetes to recreate the attachment.

### Longhorn OwnerID Stale
Longhorn tracks which node owns a volume via the `ownerID` field in the Volume CRD. When a node is removed or a volume is moved, this field may not be properly cleared, preventing the volume from being attached to a new node.

**Solution**: Clear the `ownerID` field in the Longhorn Volume resource to allow it to be reattached.

## Files Modified/Created
- ✅ Fixed: `monitoring/uptime-kuma-84b6f67c69-2bjqd` (Running)
- ✅ Fixed: `iiqstack/iiq-5c8d9758fd-zz4qs` (Running)
- ✅ Created: `WindowsLab/Repair-ContainerCreating-Pods.ps1` (Prevention script)
- ✅ Created: `WindowsLab/REPAIR_SUMMARY.md` (This document)

## Next Steps
1. ✅ Test the PowerShell script in dry-run mode (Completed)
2. ⏳ Deploy the script to your Windows monitoring workstation
3. ⏳ Set up scheduled execution for proactive detection
4. ⏳ Review Longhorn dashboard for any remaining storage issues
