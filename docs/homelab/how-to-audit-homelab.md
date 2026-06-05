# How to Audit and Recover the K3s Homelab

This guide explains how to run cluster-wide audits, verify SSL/TLS certificate compliance, manage database backups, and recover remote access if Tailscale connectivity is lost.

---

## How to Run a Cluster Audit

The homelab cluster undergoes periodic health and compliance audits via parallel SSH execution.

### 1. Execute the Audit Script
Run the PowerShell audit orchestrator from your local workstation:
```powershell
# Triggers parallel collection across all 9 nodes
.\WindowsLab/Run-K3sAudit.ps1
```

### 2. Verify Output Tarballs
The orchestrator copies node-level logs into the local directory. Verify the audit packages:
```bash
ls -lh k3s-audits/
```
Each node produces a `.tar.gz` bundle containing system logs, service statuses, routing tables, and configuration validation checks.

### 3. Clean Up Historical Audits
To conserve disk space, rotate local audit packages monthly:
```bash
# Example to delete audits older than 30 days
find k3s-audits/ -name "*.tar.gz" -mtime +30 -delete
```

---

## How to Track TLS Certificate Validity

Internal Kubernetes communication and admin access depend on client/server TLS certificates. 

### 1. View Expiry Dates
Check the certificate status output from your latest audit report or run the following command on the Master NUC:
```bash
sudo k3s certificates check
```

### 2. Standard Certificate Lifespans
* **Kube API Server / Admin Client**: Valid for 1 year (automatically renewed by K3s on service restart if within 90 days of expiry).
* **Server CA**: Valid for 10 years.

---

## How to Verify Local Registry Connectivity

All nodes must be capable of pulling custom images from the local registry (`192.168.0.236:5000`).

### 1. Test Registry Access from a Worker Node
SSH into a worker and query the registry catalog:
```bash
curl -s http://192.168.0.236:5000/v2/_catalog
```

### 2. Check registries.yaml Configuration
Ensure `/etc/rancher/k3s/registries.yaml` is correctly configured on each node to mark the local registry as trusted (insecure http endpoint):
```yaml
mirrors:
  "192.168.0.236:5000":
    endpoint:
      - "http://192.168.0.236:5000"
```

---

## How to Manage Database Backup Rotation

Database dumps are synced daily to a local Minio/S3 bucket.

### 1. Verify Backup Status
Log into the Minio Console or check via the Minio Client (`mc`):
```bash
mc ls play/iiq-backups/
```

### 2. Review Lifecycle Policies
A 30-day retention policy is enforced at the bucket level. You can check the active policy using:
```bash
mc ilm ls play/iiq-backups
```

---

## How to Recover Tailscale Remote Access

If you lose connection to the homelab through Tailscale:

### 1. Connect via Local LAN
Establish an SSH connection using the node's physical IP address (documented in the reference sheet):
```bash
ssh suryendub@192.168.0.21
```

### 2. Verify Tailscale daemon status
Check the status of the local Tailscale agent:
```bash
sudo tailscale status
```

### 3. Restart Tailscale if necessary
If the service is stopped, restart it:
```bash
sudo systemctl restart tailscaled
```

### 4. Re-authenticate the node
If the authentication key has expired:
```bash
sudo tailscale up --auth-key <YOUR-TAILSCALE-AUTH-KEY> --force-reauth
```
