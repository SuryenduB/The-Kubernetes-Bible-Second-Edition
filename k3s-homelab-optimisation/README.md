# K3s Homelab Optimisation & Platform Engineering Suite

This repository module contains the production audit, architecture documentation, automation scripts, Ansible playbooks, and runbooks for the **seven-node K3s Ubuntu homelab cluster**.

## Quick Start

### 1. Collect Sanitised Diagnostics
```bash
make collect
```
Runs `scripts/collect-cluster-state.sh` and `scripts/collect-node-state.sh`, saving redacting diagnostics to `reports/`.

### 2. Run Comprehensive Validation
```bash
make validate
```
Validates:
- Node Ready conditions across all 7 Ubuntu nodes
- Control-plane and API server health
- Embedded etcd snapshot presence and validity
- CoreDNS replica availability and latency
- Non-destructive cross-node overlay networking and MTU
- Longhorn volume health and replica distribution
- Failed and crashlooping pod detection

### 3. Test DNS & Networking
```bash
make test-dns
make test-network
```

### 4. Verify Server-Side Manifest Dry-Run
```bash
make dry-run-manifests
```

## Directory Structure

```text
k3s-homelab-optimisation/
├── README.md                          # Platform documentation and usage
├── Makefile                           # Unified automation targets
├── .gitignore                         # Secret, key, and raw log exclusion rules
├── docs/
│   ├── current-state.md               # Measured live state of all 7 nodes & workloads
│   ├── architecture.md                # Topology, data flows, storage, and networking (Mermaid)
│   ├── findings.md                    # Prioritised findings (P0–P3) with evidence
│   ├── optimisation-plan.md           # Phased optimisation and remediation plan
│   ├── risk-register.md               # Risk register with impact and mitigations
│   ├── backup-restore-runbook.md      # Disaster recovery and etcd restore runbook
│   ├── upgrade-runbook.md             # Safe K3s and Ubuntu maintenance procedures
│   ├── node-maintenance-runbook.md    # Cordon, drain, and hardware lifecycle steps
│   ├── validation-report.md           # Baseline and post-audit validation results
│   ├── approval-required.md           # Explicit boundary changes requiring user approval
│   └── change-log.md                  # Detailed chronological audit and change record
├── inventory/
│   ├── nodes.example.yaml             # Sanitised inventory template
│   └── generated/
│       └── cluster-nodes.yaml         # Live-discovered node hardware & role inventory
├── scripts/
│   ├── collect-cluster-state.sh       # Read-only Kubernetes cluster state collector
│   ├── collect-node-state.sh          # Per-node Linux diagnostic collector
│   ├── validate-cluster.sh            # Complete automated health validation runner
│   ├── verify-etcd-snapshot.sh        # Embedded etcd snapshot verifier
│   ├── validate-network.sh            # Cross-node pod-to-pod network test
│   ├── validate-dns.sh                # In-cluster CoreDNS and public DNS tester
│   └── redact-output.sh               # Secret and token redaction filter
├── ansible/
│   ├── ansible.cfg                    # Hardened Ansible configuration
│   ├── inventory.example.yaml         # Example Ansible hosts inventory
│   ├── group_vars/all.yaml            # Cluster tuning variables
│   ├── roles/
│   │   ├── common/                    # Sysctl, limits, and module loading
│   │   ├── k3s_server/                # Server & etcd management
│   │   └── k3s_agent/                 # Worker node verification
│   └── playbooks/
│       ├── audit.yaml                 # Non-destructive system audit
│       ├── node-tune.yaml             # Kernel parameter tuning
│       └── etcd-snapshot.yaml         # Online etcd snapshot execution
├── kubernetes/
│   ├── namespaces/                    # Namespace standards
│   ├── policies/                      # Pod Security Admission audit rules
│   ├── monitoring/                    # CoreDNS HA patch and PDB
│   ├── storage/                       # StorageClass default fix
│   └── tests/                         # Production-grade smoke test deployment
└── reports/                           # Sanitised audit and diagnostic logs
```

## Security & Secret Redaction
All scripts automatically route sensitive outputs through `scripts/redact-output.sh`. Tokens, keys, passwords, and sensitive certificates are never committed to Git or printed in plaintext.
