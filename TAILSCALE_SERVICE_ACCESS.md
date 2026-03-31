# Tailscale Service Access Guide

## ✅ Status: Services Exposed Successfully

All homelab services are now accessible via Tailscale with their own dedicated IPv4 addresses on the Tailnet.

---

## Service Tailscale IPs

| Service | Tailscale IPv4 | Port | Local Port | Container Port |
|---------|-------------|------|-----------|-----------------|
| **OpenWebUI** | `100.124.23.54` | 8080 | 8080 | 8080 |
| **IdentityIQ** | `100.96.215.78` | 8080 | 8080 | 8080 |
| **phpLDAPadmin** | `100.110.52.98` | 80 | 80 | 80 |
| **ArgoCD** | `100.120.217.99` | 443 | 443 | 8080 |

---

## How to Access from Remote Laptop

### Option 1: Direct IP Access (No DNS Required)

From your laptop connected to Tailscale:

```bash
# Test connectivity
ping 100.124.23.54

# Open in browser
http://100.124.23.54:8080          # OpenWebUI
http://100.96.215.78:8080          # IdentityIQ
http://100.110.52.98               # phpLDAPadmin
https://100.120.217.99:443         # ArgoCD
```

### Option 2: DNS Names via /etc/hosts

Add entries to your laptop's `/etc/hosts` file (or `C:\Windows\System32\drivers\etc\hosts` on Windows):

```
100.124.23.54    openwebui.local
100.96.215.78    iiq.local
100.110.52.98    phpldapadmin.local
100.120.217.99   argocd.local
```

Then access via:
- `http://openwebui.local:8080`
- `http://iiq.local:8080`
- `http://phpldapadmin.local`
- `https://argocd.local`

### Option 3: Using Tailscale DNS (if configured)

If you've enabled MagicDNS in Tailscale settings, services may be accessible via:
- `openwebui-tailscale.tail[yournet].ts.net`
- Similar for other services

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│         Your Remote Laptop (Tailscale)          │
│    Connected via WireGuard to Tailnet           │
└────────────────────┬────────────────────────────┘
                     │
                     │ Tailscale Network (100.0.0.0/8)
                     │
        ┌────────────┼────────────┐
        │            │            │
    ┌───▼───┐    ┌───▼────┐  ┌──▼────┐
    │ 100.x │    │ 100.y  │  │ 100.z │
    │OpenUI │    │   IIQ  │  │ phpLD │
    └───┬───┘    └────┬───┘  └──┬────┘
        │             │         │
        └─────┬───────┴────┬────┘
              │            │
        ┌─────▼────────────▼────────┐
        │   K3s Kubernetes Cluster   │
        │  (Control-plane + Workers) │
        │                            │
        │  - K3s networking enabled  │
        │  - Tailscale Operator      │
        │  - Service proxies created │
        └────────────────────────────┘
```

---

## Technical Details

### Deployment Architecture

Each service is exposed via a **Tailscale proxy StatefulSet** created by the Tailscale Operator:

- **Operator Pod**: `tailscale-operator` (namespace: `tailscale`)
  - Watches for services with `tailscale.com/expose: "true"` annotation
  - Creates proxy StatefulSets for each annotated service
  - Authenticates via OAuth client credentials

- **Service Proxies** (one per exposed service):
  - `ts-openwebui-tailscale-6c2ss` → StatefulSet
  - `ts-iiq-tailscale-scfpx` → StatefulSet
  - `ts-phpldapadmin-tailscale-x5cr5` → StatefulSet
  - `ts-argocd-server-tailscale-tfd9g` → StatefulSet

Each proxy runs as a Kubernetes StatefulSet that:
1. Boots a Tailscale client authenticated to your Tailnet
2. Receives a unique Tailscale IPv4 address (100.x.x.x)
3. Routes traffic to the actual service via Kubernetes Service DNS

### Services Created

For each original service, the operator created:

1. **Original Service** (unchanged)
   - Namespace: ai/default/argocd
   - ClusterIP: 10.43.x.x (internal only)
   - Example: `openwebui.ai.svc.cluster.local`

2. **Tailscale Proxy Service** (new)
   - Namespace: tailscale
   - Type: Headless (ClusterIP: None)
   - Routes to proxy pods
   - Example: `ts-openwebui-tailscale-6c2ss`

3. **Proxy StatefulSet Pod**
   - Namespace: tailscale
   - Tailscale IPv4: 100.x.x.x (assigned by Tailnet)
   - Runs Tailscale client + proxy container

---

## Troubleshooting

### Services Show No IP

If services don't have Tailscale IPs, check:

```bash
# 1. Verify operator is running
kubectl get pod -n tailscale -l app=operator

# 2. Check operator logs for errors
kubectl logs -n tailscale deployment/operator --tail=100

# 3. Verify service annotations exist
kubectl get svc openwebui -n ai -o jsonpath='{.metadata.annotations}'

# 4. Check proxy pods are running
kubectl get pod -n tailscale | grep ts-

# 5. Check proxy pod logs for Tailscale IP
kubectl logs -n tailscale ts-openwebui-tailscale-6c2ss-0 | grep "peerapi\|100\."
```

### ACL Issues

If you see "tag:k8s is invalid" errors:

1. Go to Tailscale Admin Console → Networks → tailnet settings → Access controls
2. Edit policy and ensure `tag:k8s` exists in `tagOwners`:
   ```
   "tagOwners": {
     "tag:k8s": [],
     "tag:k8s-operator": []
   }
   ```
3. Save and restart operator pod:
   ```bash
   kubectl delete pod -n tailscale -l app=operator
   ```

### Cannot Reach Service from Laptop

1. Verify Tailscale is connected on your laptop
2. Verify you can ping the operator:
   ```bash
   ping 100.76.224.83  # Tailscale operator machine
   ```
3. Verify service proxy pod is running:
   ```bash
   kubectl get pod -n tailscale ts-openwebui-tailscale-6c2ss-0
   ```
4. Check ACL rules allow traffic from your device to service proxies
5. Try accessing with explicit port: `http://100.124.23.54:8080`

---

## Security Considerations

✅ **What's Secure:**
- Services are **not exposed to the public internet**
- Access is **encrypted via Tailscale WireGuard**
- Only devices on your Tailnet can connect
- No port-forwarding or firewall rules needed
- Services remain private to your LAN

⚠️ **Important:**
- **Tailscale key stored in repository**: The OAuth client secret was used during deployment. For production, use a secrets manager or environment variables instead.
- **ACL controls access**: Ensure your Tailscale policy restricts access appropriately
- **K3s API is NOT exposed**: Kubernetes services are only accessible via Tailscale proxies

---

## Next Steps

### 1. Test Access
```bash
# From your remote laptop (connected to Tailscale):
curl -v http://100.124.23.54:8080
```

### 2. Add DNS Entries (Optional)
Update your laptop's `/etc/hosts` for easier access with domain names.

### 3. Set Tailscale ACL Policies
Configure fine-grained ACL rules in the Tailscale Admin Console to restrict which devices can access which services.

### 4. Monitor Service Health
```bash
# Check if services are responding
kubectl get svc -n tailscale -o wide | grep ts-
kubectl logs -n tailscale ts-openwebui-tailscale-6c2ss-0 | tail -20
```

---

## Files Modified/Created

- **tailscale-proxyclass.yaml** - K8s manifests for Tailscale proxy services
- **TAILSCALE_DEPLOYMENT_GUIDE.md** - Initial deployment guide
- **TAILSCALE_SERVICE_ACCESS.md** - This file

---

## Support & Debugging

For more details:
- [Tailscale Kubernetes Operator Docs](https://tailscale.com/kb/1236/kubernetes-operator)
- Operator logs: `kubectl logs -n tailscale deployment/operator`
- Proxy pod logs: `kubectl logs -n tailscale <pod-name>`

---

*Last Updated: 2026-03-31 | Status: ✅ All Services Accessible*
