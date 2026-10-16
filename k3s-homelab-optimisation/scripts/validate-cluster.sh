#!/usr/bin/env bash
# validate-cluster.sh: Comprehensive cluster validation runner.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"
OUT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
REPORT_FILE="${OUT_DIR}/validation-run-${TIMESTAMP}.txt"

echo "========================================================" | tee "${REPORT_FILE}"
echo "   K3S SEVEN-NODE HOMELAB CLUSTER HEALTH VALIDATION     " | tee -a "${REPORT_FILE}"
echo "   Date: $(date)                                        " | tee -a "${REPORT_FILE}"
echo "========================================================" | tee -a "${REPORT_FILE}"

ERRORS=0
WARNINGS=0

log_pass() { echo "[PASS] $1" | tee -a "${REPORT_FILE}"; }
log_warn() { echo "[WARN] $1" | tee -a "${REPORT_FILE}"; WARNINGS=$((WARNINGS + 1)); }
log_fail() { echo "[FAIL] $1" | tee -a "${REPORT_FILE}"; ERRORS=$((ERRORS + 1)); }

echo -e "\n--- Step 1: Checking Node Ready Status ---" | tee -a "${REPORT_FILE}"
EXPECTED_NODES=("nuc" "kubernetes1" "kubernetes2" "kubernetes3" "kubernetes4" "kubernetes5" "kubernetes6")
for node in "${EXPECTED_NODES[@]}"; do
  STATUS=$(kubectl get node "${node}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
  if [ "${STATUS}" == "True" ]; then
    log_pass "Active node ${node} is Ready."
  else
    log_fail "Active node ${node} is NOT Ready (Status: ${STATUS})."
  fi
done

echo -e "\n--- Step 2: Checking Control Plane & API Server ---" | tee -a "${REPORT_FILE}"
if kubectl cluster-info >/dev/null 2>&1; then
  log_pass "Kubernetes API Server is responsive."
else
  log_fail "Kubernetes API Server failed cluster-info check."
fi

echo -e "\n--- Step 3: Checking Embedded etcd Snapshots ---" | tee -a "${REPORT_FILE}"
if "${SCRIPT_DIR}/verify-etcd-snapshot.sh" >> "${REPORT_FILE}" 2>&1; then
  log_pass "Embedded etcd snapshot verification passed."
else
  log_warn "Embedded etcd snapshot check reported warnings."
fi

echo -e "\n--- Step 4: Checking CoreDNS Availability ---" | tee -a "${REPORT_FILE}"
COREDNS_READY=$(kubectl -n kube-system get deployment coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "${COREDNS_READY}" -ge 2 ]; then
  log_pass "CoreDNS has ${COREDNS_READY} ready replicas (High Availability)."
elif [ "${COREDNS_READY}" -eq 1 ]; then
  log_warn "CoreDNS has only 1 ready replica (Single Point of Failure)."
else
  log_fail "CoreDNS has NO ready replicas!"
fi

echo -e "\n--- Step 5: Validating Cluster DNS Resolution ---" | tee -a "${REPORT_FILE}"
if "${SCRIPT_DIR}/validate-dns.sh" >> "${REPORT_FILE}" 2>&1; then
  log_pass "Cluster DNS resolution test succeeded."
else
  log_fail "Cluster DNS resolution test failed."
fi

echo -e "\n--- Step 6: Validating Cluster Overlay Network ---" | tee -a "${REPORT_FILE}"
if "${SCRIPT_DIR}/validate-network.sh" >> "${REPORT_FILE}" 2>&1; then
  log_pass "Cluster overlay network test succeeded."
else
  log_fail "Cluster overlay network test failed."
fi

echo -e "\n--- Step 7: Checking Longhorn Volume Robustness ---" | tee -a "${REPORT_FILE}"
DEGRADED_VOLS=$(kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{.items[?(@.status.robustness=="degraded")].metadata.name}' 2>/dev/null || echo "")
FAULTED_VOLS=$(kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{.items[?(@.status.robustness=="faulted")].metadata.name}' 2>/dev/null || echo "")

if [ -z "${FAULTED_VOLS}" ] && [ -z "${DEGRADED_VOLS}" ]; then
  log_pass "All Longhorn volumes are healthy."
else
  if [ -n "${DEGRADED_VOLS}" ]; then
    log_warn "Degraded Longhorn volumes found: ${DEGRADED_VOLS}"
  fi
  if [ -n "${FAULTED_VOLS}" ]; then
    log_fail "FAULTED Longhorn volumes found: ${FAULTED_VOLS}"
  fi
fi

echo -e "\n--- Step 8: Checking Failed / CrashLoop Pods ---" | tee -a "${REPORT_FILE}"
CRASH_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | grep -v Terminating || true)
if [ -z "${CRASH_PODS}" ]; then
  log_pass "No pods currently in CrashLoopBackOff or Error state."
else
  log_warn "Found non-running pods:"
  echo "${CRASH_PODS}" | tee -a "${REPORT_FILE}"
fi

echo -e "\n========================================================" | tee -a "${REPORT_FILE}"
echo "   VALIDATION SUMMARY: Errors: ${ERRORS}, Warnings: ${WARNINGS}" | tee -a "${REPORT_FILE}"
echo "   Full Report: ${REPORT_FILE}" | tee -a "${REPORT_FILE}"
echo "========================================================" | tee -a "${REPORT_FILE}"

if [ "${ERRORS}" -gt 0 ]; then
  exit 1
fi
exit 0
