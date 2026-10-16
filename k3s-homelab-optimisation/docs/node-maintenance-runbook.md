# K3s Homelab Node Maintenance Runbook

This runbook guides platform engineers through node lifecycle tasks, graceful drains, storage migration, hardware maintenance, and reboot management while strictly observing homelab safety constraints.

---

## 1. Node Safety Matrix & Rules of Engagement

| Node | Role | Safety Flags | Restrictions & Notes |
| :--- | :--- | :--- | :--- |
| **`nuc`** | Control Plane | `neverCordon: true` | **DO NOT CORDON OR DRAIN.** The API server and single-voter etcd live here. Draining `nuc` breaks cluster orchestration. |
| **`kubernetes1`** | Worker | Standard | Carries MySQL and Immich replicas. Standard drain permitted. |
| **`kubernetes2`** | Worker | Standard | Primary NVMe storage node. Hosts IIQ DB and Beszel hub. Standard drain permitted. |
| **`kubernetes3`** | Worker | Standard | Standard drain permitted. |
| **`kubernetes4`** | Worker | Standard | Standard drain permitted. |
| **`kubernetes5`** | Worker | Standard | Standard drain permitted. |
| **`kubernetes6`** | Worker | Standard | Currently carries primary CoreDNS pod. Standard drain permitted if CoreDNS HA is active. |
| **`kubernetes7`** | Stale Worker | `neverPowerOff: true` | **DO NOT POWER OFF.** Physical power switch is broken and unrecoverable once off. |

---

## 2. Planned Worker Maintenance Procedure

### Step 1: Pre-Maintenance Storage Check
Before performing any action on worker `$TARGET_NODE`:
```bash
# 1. Verify Longhorn volume health
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness | grep -v healthy || true

# 2. Check replicas residing on target node
kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep "$TARGET_NODE" | head -n 10
```
If any volume is already `degraded`, do **NOT** drain or reboot another storage node until the degraded volume finishes rebuilding.

### Step 2: Cordon Node
Prevent the scheduler from assigning new pods to the target node:
```bash
kubectl cordon "$TARGET_NODE"
```

### Step 3: Graceful Pod Eviction (Drain)
```bash
kubectl drain "$TARGET_NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=300s
```

#### Handling PDB Eviction Failures (`Cannot evict pod as it would violate the pod's disruption budget`)
Several homelab stateful workloads enforce strict PDBs (e.g. `media/audiobookshelf`, `iiqstack/activemq` with `maxUnavailable: 0`).
If the drain is blocked by a single-replica stateful pod:
1. Identify the blocking pod:
   ```bash
   kubectl get pods -A --field-selector spec.nodeName="$TARGET_NODE"
   ```
2. For planned host reboots, either:
   - Temporarily scale down the deployment: `kubectl -n <NS> scale deployment <NAME> --replicas=0`
   - Or force eviction if the application supports immediate rescheduling:
     `kubectl delete pod <POD_NAME> -n <NS> --grace-period=30`

### Step 4: Perform Host Maintenance
Perform OS package upgrades, hardware replacements, or reboot:
```bash
ssh suryendub@<NODE_IP> "sudo apt update && sudo apt upgrade -y && sudo reboot"
```

### Step 5: Post-Reboot Verification & Uncordon
1. Wait for Kubelet to report `Ready`:
   ```bash
   kubectl wait --for=condition=Ready node/"$TARGET_NODE" --timeout=120s
   ```
2. Uncordon the node to allow scheduling:
   ```bash
   kubectl uncordon "$TARGET_NODE"
   ```
3. Monitor Longhorn replica rebuild:
   ```bash
   kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep "$TARGET_NODE"
   ```
   Allow Longhorn replicas to synchronize completely before initiating maintenance on the next node.

---

## 3. Storage Drive Replacement / Expansion Procedure

When replacing a failing hard drive or upgrading to an SSD:
1. In Longhorn UI -> Nodes -> Select Target Node -> Click **Edit Node and Disks**.
2. Mark the target disk as **Scheduling: Disabled** and **Eviction: Enabled**.
3. Wait for all volume replicas on the disk to replicate onto remaining worker nodes.
4. Power off node, swap physical drive, create ext4 filesystem, update `/etc/fstab`.
5. Power on node, re-add mount point in Longhorn UI.
