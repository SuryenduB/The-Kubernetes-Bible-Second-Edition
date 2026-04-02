# SailPoint IdentityIQ (IIQ) K3s Migration & Hardening Guide

## Executive Summary
This document details the comprehensive, iterative process undertaken to migrate the SailPoint IdentityIQ environment from a Docker Compose stack (`iiqstack`) to a production-grade, highly available Kubernetes architecture on a K3s cluster. The target architecture leverages **Tailscale Operator** for secure remote access via MagicDNS, **NFS-backed Persistent Volumes** for data resilience across nodes, and **Traefik IngressRoutes** for L7 sticky session management.

---

## 1. Initial Architectural Assessment & Baseline
The migration began with an analysis of the existing manifest files (`iiq-deployment.yaml`, `iiq-stateful.yaml`, `live-iiq.yaml`) compared against the baseline `iiqstack` Docker Compose file.

**Findings:**
*   `iiq-stateful.yaml` provided the best foundation, utilizing `StatefulSets` for databases, which is the correct Kubernetes pattern for stable network identifiers and persistent storage.
*   However, it lacked 1:1 parity with the Compose stack (missing `counter` and `ssh` services, incomplete environment variables, different memory limits).
*   It lacked robust Kubernetes governance (no resource requests/limits, insufficient health probes, no PodDisruptionBudgets).
*   It used `local-path` storage instead of the intended centralized NAS (NFS) storage.
*   It relied on traditional Ingress instead of direct Tailscale Operator integration.

---

## 2. Achieving 1:1 Functional Parity
Before hardening the cluster, strict functional parity with the Docker Compose environment was established.

*   **Service Inclusion:** Added the `counter` and `ssh` deployments and services.
*   **Mail Authentication:** Injected the missing `MP_SMTP_AUTH_ACCEPT_ANY=1` and `MP_SMTP_AUTH_ALLOW_INSECURE=1` environment variables into the Mailpit `StatefulSet` to ensure IIQ could send emails.
*   **Initialization Logic:** Expanded the `wait-for-all-dependencies` init container within the `iiq-init` Job. Instead of only checking the databases, it was updated to poll all 5 critical dependencies (MSSQL `1433`, MySQL `3306`, LDAP `389`, Mail `1025`, ActiveMQ `8161`) before attempting schema initialization.
*   **Memory Alignment:** Reverted the IdentityIQ Tomcat `CATALINA_OPTS` from `-Xmx3072M` back to `-Xmx2048M` to perfectly match the Compose baseline.
*   **Restart Policies:** Enforced `restartPolicy: Never` on the `iiq-init` Job to prevent infinite loop executions of the initialization script.

---

## 3. Kubernetes Specialist Hardening & Governance
To ensure the stack behaves reliably in a dynamic Kubernetes environment, several "Specialist" patterns were applied.

### 3.1. Resource Management
*   Applied strict `resources.requests` and `resources.limits` (CPU and Memory) to every container in the stack. This prevents "noisy neighbor" scenarios where a runaway JVM or database query crashes the underlying K3s worker node.

### 3.2. Comprehensive Health Probes (Liveness & Readiness)
*   **Databases:** Implemented deep `readinessProbes` using `exec` commands (`sqlcmd` for MSSQL, `mysqladmin ping` for MySQL) rather than simple TCP socket checks. This ensures Kubernetes only routes traffic when the DB engine is fully initialized.
*   **IdentityIQ:** 
    *   **Startup Probe:** Configured with a long timeout (`failureThreshold: 60`, `periodSeconds: 15` = 15 minutes) to accommodate IIQ's notoriously slow Tomcat boot sequence (XML parsing, cache loading) without premature termination.
    *   **Liveness Probe:** Added with an `initialDelaySeconds: 600` (10 minutes) and `httpGet` checks on port 8080 to detect and restart deadlocked Tomcat processes.
*   **Infrastructure Services:** Added `tcpSocket` liveness probes to LDAP, ActiveMQ, Mailpit, SSH, and Counter to guarantee self-healing capabilities across the entire stack.

### 3.3. High Availability
*   Added a **PodDisruptionBudget (PDB)** (`iiq-pdb`) for the IdentityIQ deployment with `minAvailable: 1`. This guarantees that cluster maintenance or node drains will never take down all IIQ replicas simultaneously.

---

## 4. Networking & Remote Access Architecture

The networking layer was redesigned to support both local cluster routing and secure remote access.

### 4.1. Tailscale Operator Integration
*   Replaced generic ingress rules with Tailscale Service Annotations (`tailscale.com/expose: "true"`, `tailscale.com/hostname: "<name>"`).
*   This provisioned dedicated proxy pods in the `tailscale` namespace, granting each service a unique MagicDNS hostname on the Tailnet (e.g., `iiq-main`, `iiq-db`, `iiq-mq-admin`).

### 4.2. Traefik L7 Routing & Session Affinity
*   While Tailscale provides the secure tunnel, IdentityIQ (being a stateful Java web application) requires strict session affinity (Sticky Sessions) to function correctly behind a load balancer.
*   Restored **Traefik IngressRoute** objects for IIQ and ActiveMQ, specifically configuring `sticky: cookie: {}`.
*   Combined with `sessionAffinity: ClientIP` on the Kubernetes `Service` level, this ensures that a user's JSESSIONID remains bound to a single backend pod.

---

## 5. Storage Migration (NFS/NAS) & Troubleshooting

Migrating from `local-path` to the NAS (`192.168.0.128`) presented several challenges.

### 5.1. Restoring the NFS Provisioner
*   **Issue:** PVCs remained in a `Pending` state. Investigation revealed the `nfs-subdir-external-provisioner` had been deleted from the cluster, despite Helm reporting it as deployed.
*   **Resolution:** Re-added the Helm repository and performed a `helm upgrade --install` to restore the provisioner pointing to `/share/CACHEDEV1_DATA/Public`.

### 5.2. NFS Client Missing on Node
*   **Issue:** The restored provisioner pod failed with `exit status 32` (bad option) when attempting to mount the NFS share.
*   **Resolution:** Identified that `kubernetes7` was missing the required NFS client libraries (`nfs-common`). Applied a `nodeSelector` to force all stateful IIQ workloads onto `kubernetes3` and `kubernetes6`, which were verified to support NFS.

### 5.3. NFS Permission Denied (Security Contexts)
*   **Issue:** Pods crash-looped due to `Access is denied` when writing to the NFS share.
*   **Resolution:** Surgically applied specific `securityContext` values to match the expectations of the underlying container images when interacting with NFS:
    *   **MSSQL:** `runAsUser: 0`, `fsGroup: 10001`
    *   **MySQL:** `fsGroup: 999`
    *   **LDAP (Osixia):** `runAsUser: 911`, `runAsGroup: 911`, `fsGroup: 911`
    *   **IdentityIQ:** `fsGroup: 1000`

---

## 6. Database Initialization & Schema Resolution

The `iiq-init` Job handles the initial schema deployment, but it encountered critical failures.

### 6.1. Missing Databases & Login Failures
*   **Issue:** IdentityIQ pods failed to boot, throwing `Login failed for user 'identityiq'` and `Invalid object name 'spt_database_version'`.
*   **Resolution:** 
    *   The `iiq-init` job failed to fully execute due to transient connection issues during the storage migration.
    *   Used `kubectl exec` to manually interface with the `sqlcmd` utility inside the `db-0` pod.
    *   Manually created the required databases: `identityiq`, `identityiqah`, and `identityiqPlugin`.
    *   Manually created the SQL Logins and Users for each, granting `db_owner` roles.

### 6.2. Default Schema Mismatch
*   **Issue:** Even after manual table creation, IIQ could not find its tables because they were created under the `dbo` schema, while the application expected them in the `identityiq` schema.
*   **Resolution:** Executed `ALTER USER [identityiq] WITH DEFAULT_SCHEMA = [identityiq]` (and similarly for `ah` and `Plugin` users) directly in MSSQL to ensure seamless table resolution.
*   Triggered a final manual schema import using the `/opt/tomcat/webapps/identityiq/WEB-INF/database/create_identityiq_tables-8.4.sqlserver` script from within the IIQ pod.

---

## 7. LDAP Stabilization

The `osixia/openldap` image proved highly volatile when combined with Kubernetes Service Links and NFS persistence.

### 7.1. Service Link Injection
*   **Issue:** LDAP crashed with `listen URL parse error=5`.
*   **Resolution:** Kubernetes injects environment variables for all active services (e.g., `LDAP_PORT=tcp://10.43...`). The Osixia startup script attempts to parse these, resulting in a crash. Applied `enableServiceLinks: false` to the `StatefulSet` to prevent this injection.

### 7.2. Address Already in Use
*   **Issue:** LDAP crashed with `errno=98 (Address already in use)`.
*   **Resolution:** This is a known issue with the Osixia image when its config directory on persistent storage becomes corrupted or holds stale lock files after an unclean shutdown.
*   Deployed a temporary `busybox` "Cleanup Pod" to mount the `ldap-persistent-storage-ldap-0` PVC and execute `rm -rf /mnt/ldap/data/* /mnt/ldap/config/*`.
*   Updated the `volumeMounts` to explicitly separate `subPath: data` and `subPath: config`.
*   Re-applied the UID/GID `911` security context.

---

## 8. Final State & Verification

*   **Readiness:** The IdentityIQ application pods successfully connected to the databases, completed their Tomcat initialization cycle, passed the 10-minute liveness delay, and reached the `1/1 READY` state.
*   **Tailscale:** MagicDNS is fully operational. The `tailscale` namespace contains active proxy pods (`ts-iiq`, `ts-db`, etc.) routing traffic.
*   **Access:** The environment is securely accessible remotely via **`http://iiq-main/identityiq`**.
