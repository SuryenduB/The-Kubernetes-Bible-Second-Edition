# Comprehensive Review: LinguaCafe Deployment
# Namespace: linguacafe

## 1. Architectural Overview
- **Setup:** Hybrid deployment with a main pod (Webserver + Python NLP) and separate deployments for Redis and MariaDB.
- **Storage:** Successfully using Longhorn (RWX for app storage, RWO for DB) which ensures high availability and fast performance.
- **Connectivity:** Integrated with Tailscale for secure remote access.

## 2. Security Assessment
- **Status:** MEDIUM RISK
- **Findings:**
    1. **Container Privilege:** All containers (webserver, python, mariadb, redis) are currently running as **root** (UID 0). 
    2. **Filesystem:** The root filesystem is **writable** for all containers.
    3. **Identity:** Using the **default** ServiceAccount which has broad permissions.
    4. **Network Isolation:** **No NetworkPolicies** are applied. All pods can talk to each other and external services without restriction.
- **Recommendations:**
    - Implement `runAsNonRoot: true` and `runAsUser: 1000`.
    - Set `readOnlyRootFilesystem: true` for the webserver (with appropriate emptyDir mounts for /tmp and cache).
    - Create a dedicated ServiceAccount.
    - Apply a default-deny NetworkPolicy with explicit rules for MariaDB and Redis access.

## 3. Stability & Performance
- **Probes:** Good liveness/readiness probes on Webserver and MariaDB. **MISSING** on the Python NLP container.
- **Resources:** Limits are well-defined. Python is capped at 1Gi, which is appropriate for Spacy models.
- **Reliability:** Recent restarts detected (3 restarts in 37m). Likely due to the initial configuration errors I fixed, but should be monitored.

## 4. Maintenance
- **Images:** Successfully pinned to `:latest` for now, but should move to **immutable tags** (e.g., v1.x.x) for production stability.
- **Logs:** Webserver is noisy with Horizon/Supervisor logs, which is normal for Laravel.

---

### Suggested Fixes to Apply:
1. Create `06-network-policies.yaml` to secure the database.
2. Create `07-serviceaccount.yaml`.
3. Update `04-linguacafe.yaml` with securityContext and non-root users.
