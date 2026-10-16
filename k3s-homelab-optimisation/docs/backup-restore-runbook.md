# K3s Homelab Backup & Disaster Recovery Runbook

This runbook documents the complete end-to-end backup, off-node synchronization, verification, and disaster recovery procedures for the K3s homelab cluster.

---

## 1. Backup Inventory & Assets

| Asset | Location on `nuc` | Backup Mechanism | Destination | Frequency |
| :--- | :--- | :--- | :--- | :--- |
| **Embedded etcd Datastore** | `/var/lib/rancher/k3s/server/db/etcd` | `k3s etcd-snapshot save` (Online, atomic) | Local `/var/lib/.../snapshots/` & NAS (`192.168.0.128`) | Every 6 hours |
| **K3s Server Token** | `/var/lib/rancher/k3s/server/token` | Tar archive (`k3s-identity.tar.gz`) | NAS NFS `/share/Public/backups/k3s/` | Every 6 hours (with each snapshot) |
| **K3s TLS Certificates & Keys** | `/var/lib/rancher/k3s/server/tls/` | Tar archive (`k3s-identity.tar.gz`) | NAS NFS `/share/Public/backups/k3s/` | Every 6 hours (with each snapshot) |
| **K3s Configuration** | `/etc/rancher/k3s/` | Tar archive (`k3s-config.tar.gz`) | NAS NFS `/share/Public/backups/k3s/` | Every 6 hours (with each snapshot) |
| **Longhorn Volume Data** | Distributed block storage across workers | Longhorn Recurring Backup Jobs | NAS NFS `nfs://192.168.0.128:/longhorn` | Recurring (Daily/Frequent) |
| **Kubernetes GitOps Manifests** | Git repository | Git push to origin | Remote Git repository | On commit |

---

## 2. Online etcd Backup Procedure (Zero Downtime)

> [!IMPORTANT]
> Never stop K3s to take an etcd snapshot. K3s provides a native online snapshot command that guarantees transaction consistency without pausing the control plane.

> [!NOTE]
> Since 2026-10-17 this procedure is automated on `nuc` by `/usr/local/bin/k3s-etcd-safe-backup.sh` (root cron, every 6 hours; execution proof in `docs/change-log.md` §7). The manual steps below remain for ad-hoc snapshots and verification.

### Step 1: Execute Online Snapshot
On the control-plane node (`nuc`):
```bash
sudo k3s etcd-snapshot save --name "etcd-snapshot-manual-$(date +%Y%m%d_%H%M%S)"
```

### Step 2: Verify Local Snapshot
```bash
sudo k3s etcd-snapshot list
```
Check that the snapshot is registered and that its file size matches expectations (~200MB–250MB).

### Step 3: Archive Identity and Config
```bash
sudo tar -czf "/tmp/k3s-identity-$(date +%Y%m%d).tar.gz" \
  -C / var/lib/rancher/k3s/server/token \
       var/lib/rancher/k3s/server/tls \
       var/lib/rancher/k3s/server/cred
```

### Step 4: Synchronize to NAS
Mount the NAS NFS export and copy the snapshot and identity archive:
```bash
sudo mkdir -p /mnt/k3s-nas-backup
sudo mount -t nfs 192.168.0.128:/share/Public/backups/k3s /mnt/k3s-nas-backup

DEST_DIR="/mnt/k3s-nas-backup/$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$DEST_DIR"
LATEST_SNAP=$(sudo ls -t /var/lib/rancher/k3s/server/db/snapshots/ | head -n 1)

sudo cp "/var/lib/rancher/k3s/server/db/snapshots/${LATEST_SNAP}" "${DEST_DIR}/etcd-snapshot"
sudo cp "/tmp/k3s-identity-$(date +%Y%m%d).tar.gz" "${DEST_DIR}/"
sudo cp -r /etc/rancher/k3s "${DEST_DIR}/k3s-config"

sudo umount /mnt/k3s-nas-backup
```

---

## 3. Disaster Recovery & etcd Restore Procedure

> [!CAUTION]
> Do NOT execute an etcd restore on a functioning, healthy cluster. A restore rewinds cluster state to the timestamp of the snapshot. Only perform this procedure during total control plane failure or disaster recovery.

### Scenario A: Restoring on Existing `nuc` Node
If the etcd datastore is corrupted but the node is intact:

1. **Stop K3s on all nodes:**
   ```bash
   # On nuc
   sudo systemctl stop k3s

   # On workers (kubernetes1-6)
   sudo systemctl stop k3s-agent
   ```

2. **Execute Cluster Reset & Snapshot Restore on `nuc`:**
   ```bash
   sudo k3s server \
     --cluster-reset \
     --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<SNAPSHOT_NAME>
   ```

3. **Verify the Reset Output:**
   Ensure the output logs conclude with:
   `Managed etcd cluster has been reset... restart K3s with --cluster-reset flag removed.`

4. **Start the Control Plane:**
   ```bash
   sudo systemctl start k3s
   sudo kubectl get nodes
   ```

5. **Start Agents:**
   ```bash
   # On each worker node
   sudo systemctl start k3s-agent
   ```

---

### Scenario B: Restoring to a Re-Imaged or Replacement Node
If `nuc` suffered catastrophic hardware failure and Ubuntu has been freshly installed:

1. **Install Matching K3s Version:**
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.34.6+k3s1" sh -s - server --cluster-init
   sudo systemctl stop k3s
   ```

2. **Restore Identity Archive (CRITICAL):**
   Without the original server token and TLS certificate authority (`tls/`), existing worker nodes will reject the new master and fail TLS handshake.
   ```bash
   sudo tar -xzf <BACKUP_PATH>/k3s-identity.tar.gz -C /
   sudo tar -xzf <BACKUP_PATH>/k3s-config.tar.gz -C /
   ```

3. **Restore etcd Snapshot:**
   ```bash
   sudo k3s server \
     --cluster-reset \
     --cluster-reset-restore-path=<BACKUP_PATH>/etcd-snapshot
   ```

4. **Start K3s Service:**
   ```bash
   sudo systemctl start k3s
   kubectl get nodes
   ```
   Workers will reconnect automatically without re-registration because the token and CA match.

---

## 4. Longhorn Volume Recovery from NAS Backup

If a Longhorn volume is corrupted or lost due to disk failure:

1. Open Longhorn UI or inspect via `kubectl`:
   ```bash
   kubectl -n longhorn-system get backups.longhorn.io
   ```
2. In Longhorn UI -> **Backup** -> Select Volume -> Choose Snapshot -> Click **Restore Latest Backup**.
3. Point the target workload PVC to the newly restored Longhorn volume.
