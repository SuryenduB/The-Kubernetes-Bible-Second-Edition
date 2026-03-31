# Homelab Remediation & Deployment - 2026-03-31

## 1. Tailscale Operator Deployment
- **Status**: ✅ Operational
- **Action**: Deployed Tailscale Operator via Helm in 'tailscale' namespace.
- **Config**: Configured with OAuth credentials for automated machine authorization.
- **Exposed Services**:
  - OpenWebUI: 100.88.101.12
  - IdentityIQ: 100.96.215.78
  - phpLDAPadmin: 100.110.52.98
  - ArgoCD: 100.120.217.99

## 2. IdentityIQ & MSSQL Fix
- **Issue**: MSSQL crashing on NFS due to permission denied; IIQ missing schema.
- **MSSQL Fix**: 
  - Updated Deployment to run as root (runAsUser: 0) to bypass NFS UID mapping restrictions.
  - Initialized 'identityiq', 'identityiqah', and 'identityiqPlugin' databases and logins.
  - Applied complex password policy compliant credentials.
- **IIQ Fix**:
  - Switched DATABASE_TYPE from mysql to mssql.
  - Executed schema creation scripts from within the container.
  - Updated connection strings to match new MSSQL credentials.

## 3. Machine Maintenance
- **Action**: Excluded 'kubernetes7' from 'Stop-K3sHomelab' function in $PROFILE and 'shutdown_homelab.ps1' to prevent accidental shutdown of the worker node.
