# Calibre-Web Performance Optimization Plan

## Objective
Migrate the Calibre `metadata.db` SQLite database off the NFS storage and onto the local Longhorn-backed `/config` PVC to solve severe performance degradation and lock contention issues. The actual e-book files will remain on the high-capacity NFS share (`/library`).

## Proposed Changes

### 1. `kubernetes-manifests/media/calibre-web.yaml`
- **Init Container (`init-library`) Update:**
  - Mount both the `/config` (Longhorn) and `/library` (NFS) volumes.
  - Implement a migration script: If `/config/metadata.db` doesn't exist but `/library/metadata.db` does, safely copy it over to preserve all existing data.
  - Ensure the `/library/metadata.db` file exists (even as an empty placeholder) so Kubernetes `subPath` mounting doesn't fail.
  - Apply correct ownership (`chown`) to both locations.
- **Main Container (`calibre-web`) Update:**
  - Mount `/config/metadata.db` directly onto `/library/metadata.db` using Kubernetes `subPath`. This effectively overlays the fast local database file over the NFS mount.
  - Increase CPU requests/limits to ensure the application isn't throttled during heavy operations (from `100m/1` to `500m/2`).
  - Set the Deployment strategy to `Recreate` to ensure the `ReadWriteOnce` config volume detaches cleanly before the new pod attaches it.

### 2. `homelab-media-deployment-plan.md`
- Update the documentation to reflect the new `metadata.db` overlay volume mounts and the increased resource limits, preventing future configuration drift.

## Validation & Data Safety
- **Data Preservation**: The `init-library` script will explicitly check for existing data on NFS and migrate it locally *before* the application starts. No existing books or metadata will be lost.
- **Execution**: I will use `kubectl apply -f` to deploy the updated manifest to the cluster and verify the pod starts successfully and mounts the new overlay.
