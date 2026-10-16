#!/usr/bin/env bash
# validate-dns.sh: Test cluster DNS resolution, CoreDNS latency, and external queries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"
TEST_NS="k3s-dns-val-$$"
TEST_POD="dns-test-pod"

cleanup() {
  echo "--- Cleaning up temporary DNS test resources ---"
  kubectl delete namespace "${TEST_NS}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Kubernetes DNS Health and Resolution Validation ==="

echo "--- 1. CoreDNS Pod Status ---"
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide | "${REDACT}"

echo -e "\n--- 2. CoreDNS Endpoints ---"
kubectl -n kube-system get endpoints kube-dns | "${REDACT}"

echo -e "\n--- 3. Creating dedicated test namespace: ${TEST_NS} ---"
kubectl create namespace "${TEST_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo -e "\n--- 4. Running non-destructive DNS resolution test pod ---"
kubectl -n "${TEST_NS}" run "${TEST_POD}" \
  --image=busybox:1.36 \
  --restart=Never \
  --command -- sleep 120 >/dev/null

# Wait for pod to be running
echo "Waiting for test pod to start..."
kubectl -n "${TEST_NS}" wait --for=condition=Ready pod/"${TEST_POD}" --timeout=30s >/dev/null

echo -e "\n--- 5. Testing Internal Cluster Service Resolution ---"
echo "[Query: kubernetes.default.svc.cluster.local]"
kubectl -n "${TEST_NS}" exec "${TEST_POD}" -- nslookup kubernetes.default.svc.cluster.local | "${REDACT}"

echo -e "\n[Query: kube-dns.kube-system.svc.cluster.local]"
kubectl -n "${TEST_NS}" exec "${TEST_POD}" -- nslookup kube-dns.kube-system.svc.cluster.local | "${REDACT}"

echo -e "\n--- 6. Testing External Public Resolution ---"
echo "[Query: google.com]"
kubectl -n "${TEST_NS}" exec "${TEST_POD}" -- nslookup google.com | "${REDACT}"

echo -e "\n--- 7. Testing DNS Latency (time to resolve 5 queries) ---"
kubectl -n "${TEST_NS}" exec "${TEST_POD}" -- time -p sh -c 'for i in 1 2 3 4 5; do nslookup kubernetes.default.svc.cluster.local >/dev/null; done'

echo -e "\n=== DNS Validation PASSED ==="
