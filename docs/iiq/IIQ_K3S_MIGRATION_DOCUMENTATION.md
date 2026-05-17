# SailPoint IdentityIQ (IIQ) K3s Migration & Hardening Guide

## Executive Summary
This document details the comprehensive, iterative process undertaken to migrate the SailPoint IdentityIQ environment from a Docker Compose stack (`iiqstack`) to a production-grade, highly available Kubernetes architecture on a K3s cluster. The target architecture leverages **Tailscale Operator** for secure remote access via MagicDNS, **NFS-backed Persistent Volumes** for data resilience across nodes, and **Traefik IngressRoutes** for L7 sticky session management.

---

## 1. Initial Architectural Assessment & Baseline
The migration began with an analysis of the existing manifest files compared against the baseline `iiqstack` Docker Compose file.

**Findings:**
*   `iiq-stateful.yaml` was identified as the best foundation but lacked 1:1 parity with the Compose stack (missing `counter` and `ssh` services, incomplete environment variables, different memory limits).
*   It lacked robust Kubernetes governance (no resource requests/limits, insufficient health probes, no PodDisruptionBudgets).
*   It used `local-path` storage instead of the intended centralized NAS (NFS) storage.

---

## 2. Achieving 1:1 Functional Parity
Before hardening the cluster, strict functional parity with the Docker Compose environment was established.

*   **Service Inclusion:** Added the `counter` and `ssh` deployments and services.
*   **Mail Authentication:** Injected `MP_SMTP_AUTH_ACCEPT_ANY=1` and `MP_SMTP_AUTH_ALLOW_INSECURE=1` into Mailpit.
*   **Initialization Logic:** Expanded the `wait-for-all-dependencies` init container to poll all 5 critical dependencies (MSSQL, MySQL, LDAP, Mail, ActiveMQ).
*   **Memory Alignment:** Synchronized Tomcat `CATALINA_OPTS` to `-Xmx2048M`.

---

## 3. Kubernetes Specialist Hardening & Governance
Applied "Specialist" patterns to ensure reliability in a dynamic environment.

### 3.1. Resource Management
*   Applied strict `resources.requests` and `resources.limits` to every container to prevent "noisy neighbor" scenarios.

### 3.2. Comprehensive Health Probes
*   **Databases:** Implemented deep `readinessProbes` using `exec` commands (`sqlcmd`, `mysqladmin ping`).
*   **IdentityIQ:** 
    *   **Startup Probe:** Configured with a 15-minute window to accommodate IIQ's slow boot sequence.
    *   **Liveness Probe:** Added with an `initialDelaySeconds: 600` (10 minutes) to detect deadlocked processes.

### 3.3. High Availability
*   Added **PodDisruptionBudget (PDB)** (`iiq-pdb`) with `minAvailable: 1`.

---

## 4. Networking & Remote Access Architecture

### 4.1. Tailscale Operator Integration
*   Replaced generic ingress with Tailscale Service Annotations (`tailscale.com/expose: "true"`).
*   This provisioned unique MagicDNS hostnames (e.g., `iiq-main`, `iiq-db`) on the Tailnet.

### 4.2. Traefik L7 Routing & Session Affinity
*   Restored **Traefik IngressRoute** objects with `sticky: cookie: {}` to ensure Java sticky sessions.

---

## 5. Storage Migration (NFS/NAS)

### 5.1. NFS Permission Denied (Security Contexts)
*   **Resolution:** Applied specific `securityContext` values:
    *   **MSSQL:** `runAsUser: 0`, `fsGroup: 10001`
    *   **MySQL:** `fsGroup: 999`
    *   **LDAP (Osixia):** `runAsUser: 911`, `fsGroup: 911`
    *   **IdentityIQ:** `fsGroup: 1000`

---

## 6. Database Initialization & Schema Resolution

### 6.1. Missing Databases & Login Failures
*   **Resolution:** Manually created `identityiq`, `identityiqah`, and `identityiqPlugin` databases.
*   Fixed `Login failed for user 'identityiq'` by resetting the password to match the Kubernetes secret.

### 6.2. Default Schema Mismatch
*   **Resolution:** Tables were landing in `dbo` instead of `identityiq`.
*   Executed `ALTER USER [identityiq] WITH DEFAULT_SCHEMA = [identityiq]` to ensure the application could see its tables.

---

## 7. Final Stabilization & Deep Orchestration (The 2026-04-03 Fixes)

This section details the critical interventions required to move the stack from "Running" to "Stable & Accessible."

### 7.1. The IdentityIQ Synchronization Barrier (Persistence-Aware Startup)
*   **Problem:** IdentityIQ application pods and the `iiq-init` Job ran in parallel. App pods crashed with "Invalid object name" if they connected before the Job finished. Simultaneously, multiple pods attempting to unzip the WAR onto the same NAS volume caused `Permission Denied` race conditions.
*   **Solution:** Implemented the `wait-and-prep-nas` init container in the `iiq` Deployment.
    *   **Orchestration:** Uses `curl` to query the Kubernetes API, holding the pod in `Init:0/1` until the `iiq-init` Job reports `succeeded: 1`.
    *   **Atomicity:** Centralized WAR unpacking and configuration patching into this single container to ensure only one pod manages the NAS filesystem at a time.

### 7.2. MSSQL Quartz Locking & Hibernate Fixes
*   **Problem:** Application failed with `EntityManagerFactory is closed` and `FOR UPDATE clause allowed only for DECLARE CURSOR`.
*   **Solution:** Surgically patched `iiq.properties` during the `wait-and-prep-nas` phase to inject MSSQL-specific locking syntax:
    *   `org.quartz.jobStore.driverDelegateClass=org.quartz.impl.jdbcjobstore.MSSQLDelegate`
    *   `org.quartz.jobStore.selectWithLockSQL=SELECT * FROM {0}LOCKS UPDLOCK WHERE LOCK_NAME = ?`

### 7.3. NetworkPolicy Hardening for Tailscale Proxying
*   **Problem:** IIQ pods were healthy internally but timed out via Tailscale MagicDNS.
*   **Solution:** Identified that the strict `default-deny` policy was blocking ingress traffic from the `tailscale` namespace where the operator's proxy pods reside.
    *   Updated `iiqstack-allow-internal` to explicitly allow `Ingress` from the `tailscale` and `kube-system` namespaces.

---

## 8. Artifact & File Inventory

The following files were created or modified during the migration and stabilization process:

### 8.1. Master Kubernetes Manifests
*   **`iiq-stateful.yaml`**: The primary, hardened manifest containing the entire portable IdentityIQ stack (Namespaces, RBAC, Quotas, NetworkPolicies, StatefulSets, Deployments, and PVCs).
*   **`registry-fixer.yaml`**: A DaemonSet used to automate the configuration of `/etc/rancher/k3s/registries.yaml` across all nodes to trust the local insecure registry (`192.168.0.236:5000`).

### 8.2. Troubleshooting & Remediation Scripts
*   **`mssql-wipe.yaml`**: A specialized job used to completely drop and recreate the `identityiq` databases to ensure a clean slate for schema initialization.
*   **`cleanup.yaml`**: A utility pod used to perform non-destructive state resets on the NAS storage (e.g., clearing stale LDAP lock files).
*   **`nas-unpacker.yaml`** (Temp): A root-privileged pod used to perform the initial manual extraction of the SailPoint WAR into the NAS volume.
*   **`nas-fixer.yaml`** (Temp): A root-privileged pod used to recursively correct ownership (`chown 1000:1000`) on the NAS storage after provisioner errors.

### 8.3. Architectural Visualization
*   **`generate_hardened_diagram.py`**: A Python utility developed to generate `.drawio` files with embedded local SVG icons, bypassing headless rendering limitations.
*   **`iiqstack_architecture.png`**: High-fidelity architectural diagram rendered via Chrome DevTools, visualizing the relationship between Tailscale, Traefik, and the K3s workload.
*   **`iiqstack_architecture.drawio`**: The editable source file for the cluster architecture.

---

## 9. Final State & Verification

*   **Readiness:** Verified both IIQ replicas are `1/1 READY`.
*   **Deterministic Validation:** Confirmed success via PowerShell:
    *   `Invoke-RestMethod -Uri "http://iiq-main/identityiq/login.jsf" -UseBasicParsing`
    *   **Result:** `200 OK` (Parsed as `XmlDocument`).
*   **Access:** Environment fully operational at **`http://iiq-main/identityiq`**.
