# IdentityIQ 8.5 K3s Production Specification

## 1. Architecture Overview
The deployment uses a high-availability, hardened stack on K3s, migrated from legacy NFS to **Longhorn Block Storage** to resolve locking and performance issues.

### Components
- **App:** IdentityIQ 8.5 (2 Replicas, Rolling Update)
- **Primary DB:** MSSQL 2019-CU28 (StatefulSet, Longhorn RWO)
- **Plugin DB:** MySQL 8.0 (StatefulSet, Longhorn RWO)
- **Directory:** OpenLDAP 1.5.0
- **Middleware:** ActiveMQ 2.31.0
- **E-Mail:** Mailpit

## 2. Storage Strategy
- **`iiq-nas-pvc` (Longhorn RWX):** Shared volume for `/opt/tomcat/webapps`.
- **Sentinels:** Uses `.unpacked` to prevent redundant WAR extraction and `.lock` for atomic multi-replica initialization.

## 3. Hardening & Security
- **Namespace:** `iiqstack` with `ResourceQuota` and `LimitRange` enforced.
- **NetworkPolicy:** Default deny with explicit allows for internal traffic, DNS, Tailscale, and the Kubernetes API (port 443).
- **UIDs:**
  - MSSQL: `10001`
  - IdentityIQ: `1000`
  - MySQL/phpLDAPadmin: Root entrypoint allowed for internal initialization.

## 4. Initialization Logic (Init Container)
The `wait-and-prep-nas` container performs:
1. **Job Polling:** Waits for `iiq-init` Job to succeed (Schema creation).
2. **Smart Unpack:** Only unzips if the volume is empty or the image WAR is newer.
3. **Surgical Patching:** Automatically updates `iiq.properties` for all three data sources (Primary, Plugins, Access History).
4. **Driver Injection:** Forcibly copies JDBC drivers to Tomcat lib.

## 5. Maintenance Commands
### Restart Application
```bash
kubectl rollout restart deployment iiq -n iiqstack
```

### Force Configuration Re-patch
To force a re-extract and re-patch of `iiq.properties`:
```bash
kubectl run volume-cleaner --image=busybox --restart=Never -n iiqstack \
  --rm -it -- sh -c "rm -f /opt/tomcat/webapps/.unpacked /opt/tomcat/webapps/.lock"
```

### View Logs
```bash
kubectl logs -f -n iiqstack -l app=iiq -c iiq
```

## 6. Access Endpoints
- **Internal:** `http://iiq.iiqstack.svc.cluster.local/identityiq`
- **Tailscale:** `http://iiq-main/identityiq`
- **Traefik Ingress:** `http://<NODE_IP>/identityiq`
