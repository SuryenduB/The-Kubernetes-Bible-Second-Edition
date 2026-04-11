# 📚 Homelab Media Deployment Plan: AudioBookShelf + Calibre-Web

**Target Cluster**: K3s v1.34.5+k3s1 (8 nodes + Longhorn + Tailscale)
**Date**: 2026-04-05

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale Network                         │
│  Access: http://audiobookshelf | http://calibre-web          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  k3s Cluster (7 workers + 1 control-plane)                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Traefik Ingress Controller (built-in)                 │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────┐  ┌───────────────────────────┐ │
│  │  AudioBookShelf Pod     │  │  Calibre-Web Pod          │ │
│  │  - Config: 2Gi Longhorn │  │  - Config: 1Gi Longhorn   │ │
│  │  - Books: NAS NFS       │  │  - Library: NAS NFS       │ │
│  └─────────────────────────┘  └───────────────────────────┘ │
│                                                             │
│  ┌──────────────┐          ┌─────────────────────────────┐ │
│  │ Longhorn CSI │          │ NAS: 192.168.0.128          │ │
│  │ (app configs)│          │ NFS v3: /share/Public/      │ │
│  │ 3GiB total   │          │ /audiobooks/ /calibre-lib/  │ │
│  └──────────────┘          └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Storage Strategy: Hybrid (Longhorn + NAS)

| Data Type | Storage | Why |
|-----------|---------|-----|
| **App configs** (databases, settings) | Longhorn RWO | Small, need persistence across pod restarts |
| **Media files** (audiobooks, ebooks) | NAS NFS | Bulk data, already accessible via SMB, no replication overhead |

**Why not Longhorn for media?**
- 103 GiB × 3 replicas = ~309 GiB actual disk usage
- Media files don't need high IOPS or synchronous replication
- NAS already has 423 GB available and is SMB-accessible from Windows
- No RWO Multi-Attach conflicts — NAS is external shared storage

---

## Prerequisites

### 1. Tailscale Operator Setup

Your cluster already has the Tailscale operator deployed. You just need to configure authentication.

**Option A: Auth Key (Simpler for homelab)**
```bash
# 1. Generate auth key at https://login.tailscale.com/admin/settings/keys
#    - Ephemeral: No
#    - Reusable: Yes
#    - Tags: tag:k8s, tag:k8s-operator

# 2. Create secret
kubectl create secret generic tailscale-operator \
  --namespace=tailscale \
  --from-literal=client_id=<your-auth-key>
```

**Option B: OAuth Client (More secure)**
```bash
# 1. Create OAuth client at https://login.tailscale.com/admin/settings/oauth
#    - Scopes: devices, devices:write, dns

# 2. Create secret
kubectl create secret generic ts-oauth \
  --namespace=tailscale \
  --from-literal=client_id=<client-id> \
  --from-literal=client_secret=<client-secret> \
  --from-literal=oauth_relay_secret=<relay-secret>
```

### 2. Prepare NAS Directories

```bash
# SSH to NAS
ssh admin@192.168.0.128

# Create media directories
mkdir -p /share/Public/audiobooks
mkdir -p /share/Public/calibre-library

# Set permissions to match container UID/GID (1000:1000)
# This prevents "Permission Denied" errors during library scanning
chmod 777 /share/Public/audiobooks
chmod 777 /share/Public/calibre-library

# If your NAS supports ACLs, set them explicitly:
# chown -R 1000:1000 /share/Public/audiobooks
# chown -R 1000:1000 /share/Public/calibre-library
```

> **Note**: The init container in Calibre-Web runs `chown -R 1000:1000 /library` as root to fix permissions on first mount. If the NAS enforces its own UID/GID mapping (common on QNAP), you may need to adjust the NAS export settings to allow UID 1000 access, or set `all_squash,anonuid=1000,anongid=1000` in the NFS export options.

Or from Windows Explorer:
```
\\192.168.0.128\Public\ → Create folders: audiobooks, calibre-library
```

### 3. Image Registry Note

Your cluster uses a local registry (`192.168.0.236:5000`) for SailPoint images, but **worker nodes have direct internet access**. The media images (`ghcr.io/advplyr/audiobookshelf` and `ghcr.io/linuxserver/calibre-web`) will pull directly from GHCR/LinuxServer without needing to be mirrored.

If you ever air-gap the cluster, mirror them first:
```bash
docker pull ghcr.io/advplyr/audiobookshelf:2.19.6
docker tag ghcr.io/advplyr/audiobookshelf:2.19.6 192.168.0.236:5000/audiobookshelf:2.19.6
docker push 192.168.0.236:5000/audiobookshelf:2.19.6
```

---

## Manifest Structure

```
kubernetes-manifests/
├── audiobookshelf.yaml     # Namespace + PVC + NFS volumes + Deployment + Service + PDB
├── calibre-web.yaml        # PVC + NFS volumes + Deployment + Service + PDB
└── kustomization.yaml      # Deploy both at once
```

---

## Manifest 1: AudioBookShelf

**File**: `kubernetes-manifests/audiobookshelf.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: media
  labels:
    name: media

---
# AudioBookShelf Config PVC (Longhorn RWO)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: audiobookshelf-config
  namespace: media
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: longhorn
  resources:
    requests:
      storage: 2Gi

---
# AudioBookShelf Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: audiobookshelf
  namespace: media
spec:
  replicas: 1
  selector:
    matchLabels:
      app: audiobookshelf
  template:
    metadata:
      labels:
        app: audiobookshelf
    spec:
      securityContext:
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: audiobookshelf
        image: ghcr.io/advplyr/audiobookshelf:2.19.6
        ports:
        - containerPort: 80
        resources:
          requests: { cpu: 100m, memory: 256Mi }
          limits: { cpu: "1", memory: 1Gi }
        env:
        - name: TZ
          value: "Europe/Berlin"
        - name: ABS_METADATA_PATH
          value: "/audiobooks/metadata"
        livenessProbe:
          httpGet: { path: /healthcheck, port: 80 }
          initialDelaySeconds: 30
          periodSeconds: 60
        readinessProbe:
          httpGet: { path: /healthcheck, port: 80 }
          initialDelaySeconds: 10
          periodSeconds: 30
        volumeMounts:
        - name: config
          mountPath: /config
        - name: books
          mountPath: /audiobooks
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: audiobookshelf-config
      - name: books
        nfs:
          server: 192.168.0.128
          path: /share/Public/audiobooks

---
# AudioBookShelf Service
apiVersion: v1
kind: Service
metadata:
  name: audiobookshelf
  namespace: media
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "audiobookshelf"
spec:
  selector:
    app: audiobookshelf
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80

---
# AudioBookShelf PodDisruptionBudget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: audiobookshelf-pdb
  namespace: media
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app: audiobookshelf
```

---

## Manifest 2: Calibre-Web

**File**: `kubernetes-manifests/calibre-web.yaml`

```yaml
---
# Calibre-Web Config PVC (Longhorn RWO)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: calibre-web-config
  namespace: media
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi

---
# Calibre-Web Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: calibre-web
  namespace: media
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: calibre-web
  template:
    metadata:
      labels:
        app: calibre-web
    spec:
      securityContext:
        runAsUser: 1000
        fsGroup: 1000
      initContainers:
      - name: init-library
        image: alpine:3.21
        securityContext:
          runAsUser: 0
        command: ["sh", "-c"]
        args:
          - |
            mkdir -p /library /config
            if [ ! -f /config/metadata.db ]; then
              if [ -f /library/metadata.db ]; then
                echo "Migrating existing metadata.db from NFS to local Longhorn storage..."
                cp -p /library/metadata.db /config/metadata.db
              else
                echo "metadata.db not found, seeding from GitHub to local storage..."
                apk add --no-cache wget sqlite
                wget https://github.com/janeczku/calibre-web/raw/master/library/metadata.db -O /config/metadata.db
                sqlite3 /config/metadata.db "ALTER TABLE books ADD COLUMN isbn TEXT DEFAULT '';" || true
                sqlite3 /config/metadata.db "ALTER TABLE books ADD COLUMN flags INTEGER DEFAULT 0;" || true
              fi
            fi
            # Create placeholder on NFS if it doesn't exist so subPath mount doesn't fail
            if [ ! -f /library/metadata.db ]; then
              touch /library/metadata.db
            fi
            chown -R 1000:1000 /library
            chown 1000:1000 /config/metadata.db
        volumeMounts:
        - name: config
          mountPath: /config
        - name: library
          mountPath: /library
      containers:
      - name: calibre-web
        image: ghcr.io/linuxserver/calibre-web:1.1.0
        ports:
        - containerPort: 8083
        resources:
          requests: { cpu: 500m, memory: 256Mi }
          limits: { cpu: "2", memory: 1Gi }
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "Europe/Berlin"
        # DOCKER_MODS removed — adds ~1-2 min cold start.
        # Add back only if you need ebook format conversion (Kindle, etc).
        livenessProbe:
          httpGet: { path: /admin, port: 8083 }
          initialDelaySeconds: 60
          periodSeconds: 60
        readinessProbe:
          httpGet: { path: /admin, port: 8083 }
          initialDelaySeconds: 10
          periodSeconds: 30
        volumeMounts:
        - name: config
          mountPath: /config
        - name: library
          mountPath: /library
        - name: config
          mountPath: /library/metadata.db
          subPath: metadata.db
        volumes:
        - name: config        persistentVolumeClaim:
          claimName: calibre-web-config
      - name: library
        nfs:
          server: 192.168.0.128
          path: /share/Public/calibre-library

---
# Calibre-Web Service
apiVersion: v1
kind: Service
metadata:
  name: calibre-web
  namespace: media
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "calibre-web"
spec:
  selector:
    app: calibre-web
  ports:
  - protocol: TCP
    port: 8083
    targetPort: 8083

---
# Calibre-Web PodDisruptionBudget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: calibre-web-pdb
  namespace: media
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app: calibre-web
```

---

## Manifest 3: Kustomization

**File**: `kubernetes-manifests/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - audiobookshelf.yaml
  - calibre-web.yaml
```

---

## Deployment Steps

### Step 1: Configure Tailscale Operator (One-Time)

```bash
kubectl create secret generic tailscale-operator \
  --namespace=tailscale \
  --from-literal=client_id=tskey-auth-<your-key>
```

### Step 2: Deploy Applications

```bash
kubectl apply -k kubernetes-manifests/
kubectl get pods -n media -w
```

### Step 3: Wait for Tailscale IPs

```bash
kubectl get svc -n media
```

### Step 4: Access Applications

| App | URL | Default Credentials |
|-----|-----|---------------------|
| **AudioBookShelf** | `http://audiobookshelf` (Tailscale MagicDNS) | Create admin on first visit |
| **Calibre-Web** | `http://calibre-web:8083` | **⚠️ admin / admin123 — CHANGE IMMEDIATELY** |

> **⚠️ SECURITY WARNING**: Calibre-Web ships with default credentials. Change the password on first login.

### Step 5: Initial Setup

**AudioBookShelf:**
1. Open `http://audiobookshelf`
2. Create admin account
3. Add library → Type: Audiobooks → Path: `/audiobooks`
4. Scan library

**Calibre-Web:**
1. Open `http://calibre-web:8083`
2. Login: admin / admin123 → **change password immediately**
3. Go to Admin → Edit Basic Configuration
4. Set Calibre Database location: `/library`
5. Save and restart

---

## Library Management

### Uploading Existing Ebooks & Audiobooks

#### Method 1: Direct NAS Copy (Recommended — Fastest)

```bash
# From Windows Explorer:
# \\192.168.0.128\Public\audiobooks\     → Drop audiobook files here
# \\192.168.0.128\Public\calibre-library\ → Drop ebook files here

# Or from PowerShell:
Copy-Item -Path "C:\Users\DEBESURBHA\Documents\Audiobooks\*" -Destination "\\192.168.0.128\Public\audiobooks\" -Recurse
Copy-Item -Path "C:\Users\DEBESURBHA\Documents\Ebooks\*" -Destination "\\192.168.0.128\Public\calibre-library\" -Recurse
```

**Why this works perfectly:**
- NAS is external shared storage — no RWO conflicts
- Files appear instantly in running pods (NFS mount)
- No need to scale down deployments
- No upload pod needed
- SMB drag-and-drop from Windows

#### Method 2: kubectl cp (Small batches)

```bash
# Copy directly to the running pod
kubectl cp "C:\path\to\book.epub" media/calibre-web-<pod-id>:/library/
kubectl cp "C:\path\to\audiobook\" media/audiobookshelf-<pod-id>:/audiobooks/
```

### Managing Calibre Library (Full Desktop Access)

When you need to add/edit books with the full Calibre desktop:

```bash
# Step 1: Create the admin pod (mounts NAS directly)
kubectl run calibre-admin \
  --image=lscr.io/linuxserver/calibre:latest \
  --rm \
  --namespace=media \
  --env="PUID=1000" \
  --env="PGID=1000" \
  --env="TZ=Europe/Berlin" \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "calibre",
        "image": "lscr.io/linuxserver/calibre:latest",
        "ports": [{"containerPort": 3000}],
        "volumeMounts": [{"name": "library", "mountPath": "/library"}]
      }],
      "volumes": [{
        "name": "library",
        "nfs": {
          "server": "192.168.0.128",
          "path": "/share/Public/calibre-library"
        }
      }]
    }
  }'

# Step 2: In a separate terminal, port-forward
kubectl port-forward -n media pod/calibre-admin 3000:3000

# Step 3: Access noVNC at http://localhost:3000
# Step 4: When done, Ctrl+C the port-forward, then delete the pod:
kubectl delete pod calibre-admin -n media
```

> **Note**: This pod mounts the NAS directly via NFS — no PVC conflicts, works regardless of which node it's scheduled on.

---

## Storage Summary

| Volume | Size | Type | Purpose | Actual Disk |
|--------|------|------|---------|-------------|
| `audiobookshelf-config` | 2Gi | Longhorn RWO | App config, database | 6 GiB (3 replicas) |
| `calibre-web-config` | 1Gi | Longhorn RWO | Calibre-Web config | 3 GiB (3 replicas) |
| NAS `/audiobooks/` | Unlimited | NFS v3 | Audiobook files | 0 GiB (on NAS) |
| NAS `/calibre-library/` | Unlimited | NFS v3 | Book database, files | 0 GiB (on NAS) |

**Longhorn usage**: 3 GiB total (9 GiB with replicas) — minimal
**NAS usage**: Depends on your media library size

> **Key benefit**: Media files live on the NAS, not in Longhorn. No replication overhead, no RWO conflicts, and you can manage files directly via SMB from Windows.

---

## Image Versions

| Application | Image | Pinned Version | Why Pinned |
|-------------|-------|---------------|------------|
| AudioBookShelf | `ghcr.io/advplyr/audiobookshelf` | `2.19.6` | Prevents unexpected breaking changes |
| Calibre-Web | `ghcr.io/linuxserver/calibre-web` | `1.1.0` | Config schema changes between versions |

To update, change the tag in the manifest and `kubectl apply -k kubernetes-manifests/`.

---

## Troubleshooting

### Tailscale IP Not Assigned

```bash
kubectl logs -n tailscale deploy/operator --tail=20
kubectl get secret tailscale-operator -n tailscale
```

### NFS Mount Fails (Protocol not supported)

```bash
# If you see "mount.nfs: Protocol not supported" errors,
# the kernel is defaulting to NFSv4 but the NAS expects NFSv3.
# Inline NFS volumes in pod specs don't support mountOptions directly.
# You must create a PersistentVolume with mountOptions:

# 1. Create a PV with nfsvers=3
apiVersion: v1
kind: PersistentVolume
metadata:
  name: audiobookshelf-books-pv
spec:
  capacity:
    storage: 50Gi
  accessModes: ["ReadWriteOnce"]
  storageClassName: ""
  mountOptions:
    - nfsvers=3
    - noatime
    - nodiratime
  nfs:
    server: 192.168.0.128
    path: /share/Public/audiobooks

# 2. Update the PVC to bind to this PV (remove storageClassName)
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ""
  volumeName: audiobookshelf-books-pv
  resources:
    requests:
      storage: 50Gi

# Or verify NFS connectivity from a worker:
ssh suryendub@kubernetes1 "showmount -e 192.168.0.128"
```

### Calibre-Web Can't Find metadata.db

```bash
kubectl exec -n media deploy/calibre-web -- ls -la /library/
# Calibre-Web creates metadata.db itself on first run.
kubectl logs -n media deploy/calibre-web --tail=50
```

### AudioBookShelf Can't See Books

```bash
kubectl exec -n media deploy/audiobookshelf -- ls -la /audiobooks/
# If empty, copy files to \\192.168.0.128\Public\audiobooks\ via SMB
```

---

## Cleanup

```bash
# Remove all media apps
kubectl delete -k kubernetes-manifests/

# Remove namespace
kubectl delete namespace media

# Optional: Clean up NAS directories
ssh admin@192.168.0.128 "rm -rf /share/Public/audiobooks /share/Public/calibre-library"
```
