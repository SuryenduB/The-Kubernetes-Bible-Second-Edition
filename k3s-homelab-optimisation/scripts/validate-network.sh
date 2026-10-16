#!/usr/bin/env bash
# validate-network.sh: Test pod-to-pod cross-node networking, MTU, and service reachability.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${SCRIPT_DIR}/redact-output.sh"
TEST_NS="k3s-net-val-$$"

cleanup() {
  echo "--- Cleaning up temporary network test resources: ${TEST_NS} ---"
  kubectl delete namespace "${TEST_NS}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Kubernetes Cluster Network Validation ==="

echo "--- 1. Cluster Nodes Status ---"
kubectl get nodes -o wide | "${REDACT}"

echo -e "\n--- 2. Creating test namespace: ${TEST_NS} ---"
kubectl create namespace "${TEST_NS}" >/dev/null

echo -e "\n--- 3. Deploying 2 Test Pods on Distinct Worker Nodes ---"
# Schedule pod 1 on kubernetes1 and pod 2 on kubernetes2
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: net-test-node1
  namespace: ${TEST_NS}
spec:
  nodeSelector:
    kubernetes.io/hostname: kubernetes1
  containers:
  - name: test
    image: busybox:1.36
    command: ["sleep", "300"]
---
apiVersion: v1
kind: Pod
metadata:
  name: net-test-node2
  namespace: ${TEST_NS}
spec:
  nodeSelector:
    kubernetes.io/hostname: kubernetes2
  containers:
  - name: test
    image: busybox:1.36
    command: ["sleep", "300"]
EOF

echo "Waiting for test pods to be Ready..."
kubectl -n "${TEST_NS}" wait --for=condition=Ready pod/net-test-node1 pod/net-test-node2 --timeout=45s >/dev/null

POD1_IP=$(kubectl -n "${TEST_NS}" get pod net-test-node1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl -n "${TEST_NS}" get pod net-test-node2 -o jsonpath='{.status.podIP}')

echo "Pod 1 (kubernetes1) IP: ${POD1_IP}"
echo "Pod 2 (kubernetes2) IP: ${POD2_IP}"

echo -e "\n--- 4. Cross-Node Pod-to-Pod ICMP Reachability ---"
kubectl -n "${TEST_NS}" exec net-test-node1 -- ping -c 3 -W 2 "${POD2_IP}" | "${REDACT}"

echo -e "\n--- 5. Pod-to-Service ClusterIP Reachability ---"
KUBE_API_IP="10.43.0.1"
kubectl -n "${TEST_NS}" exec net-test-node1 -- nc -z -w 3 "${KUBE_API_IP}" 443 && echo "Service ClusterIP (10.43.0.1:443) reached successfully!"

echo -e "\n--- 6. Testing MTU (Checking if Flannel MTU handles packet transmission without DF fragmentation issue) ---"
kubectl -n "${TEST_NS}" exec net-test-node1 -- ping -c 2 -s 1400 "${POD2_IP}" | "${REDACT}"

echo -e "\n=== Network Validation PASSED ==="
