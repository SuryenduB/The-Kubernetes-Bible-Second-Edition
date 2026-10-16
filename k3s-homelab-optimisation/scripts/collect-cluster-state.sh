#!/usr/bin/env bash
# collect-cluster-state.sh: Collect read-only cluster state and diagnostics.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"
OUT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
OUT_FILE="${OUT_DIR}/cluster-state-${TIMESTAMP}.txt"

echo "=== Collecting Kubernetes Cluster State at $(date) ===" | tee "${OUT_FILE}"

run_cmd() {
  local title="$1"
  local cmd="$2"
  echo -e "\n--- [CMD: ${title}] ---" | tee -a "${OUT_FILE}"
  eval "${cmd}" 2>&1 | "${REDACT}" | tee -a "${OUT_FILE}"
}

run_cmd "Kubectl Version" "kubectl version"
run_cmd "Cluster Info" "kubectl cluster-info"
run_cmd "Nodes (Wide)" "kubectl get nodes -o wide"
run_cmd "Nodes (Labels)" "kubectl get nodes --show-labels"
run_cmd "Namespaces" "kubectl get namespaces"
run_cmd "Pods (All Namespaces, Wide)" "kubectl get pods -A -o wide"
run_cmd "Deployments, StatefulSets, DaemonSets" "kubectl get deployments,statefulsets,daemonsets -A"
run_cmd "Jobs & CronJobs" "kubectl get jobs,cronjobs -A"
run_cmd "Persistent Volumes" "kubectl get pv"
run_cmd "Persistent Volume Claims" "kubectl get pvc -A"
run_cmd "Storage Classes" "kubectl get storageclass"
run_cmd "Ingress Classes" "kubectl get ingressclass"
run_cmd "Ingresses" "kubectl get ingress -A"
run_cmd "Services" "kubectl get services -A"
run_cmd "EndpointSlices" "kubectl get endpointslices -A"
run_cmd "Network Policies" "kubectl get networkpolicy -A"
run_cmd "Pod Disruption Budgets" "kubectl get poddisruptionbudget -A"
run_cmd "Priority Classes" "kubectl get priorityclass"
run_cmd "Node Resource Usage (top)" "kubectl top nodes || echo 'Metrics server not available for top nodes'"
run_cmd "Pod Resource Usage (top)" "kubectl top pods -A || echo 'Metrics server not available for top pods'"
run_cmd "Recent Cluster Events" "kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 100"

echo -e "\n=== Cluster state collection completed. Saved to ${OUT_FILE} ==="
