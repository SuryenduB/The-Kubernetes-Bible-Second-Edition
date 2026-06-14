#!/bin/bash
# deploy.sh - Deploy FreeLingo to your K3s cluster
# Usage: ./deploy.sh
# Before deploying, edit secret-template.yaml with your actual values.

set -e

NAMESPACE="freelingo"
DIR="$(dirname "$0")"

echo "=== Deploying FreeLingo v1.7.2 to K3s Cluster ==="
echo ""

kubectl apply -f "${DIR}/namespace.yaml"
kubectl apply -f "${DIR}/serviceaccounts.yaml"
kubectl apply -f "${DIR}/secret.yaml"
kubectl apply -f "${DIR}/pvc.yaml"
kubectl apply -f "${DIR}/db-statefulset.yaml"
kubectl apply -f "${DIR}/redis-statefulset.yaml"
kubectl apply -f "${DIR}/mock-gpu-services.yaml"
kubectl apply -f "${DIR}/backend-deployment.yaml"
kubectl apply -f "${DIR}/frontend-deployment.yaml"
kubectl apply -f "${DIR}/services.yaml"
kubectl apply -f "${DIR}/ingress.yaml"
kubectl apply -f "${DIR}/network-policy.yaml"
kubectl apply -f "${DIR}/tailscale-service.yaml"

echo ""
echo "=== FreeLingo deployed to namespace '${NAMESPACE}' ==="
echo ""
echo "IMPORTANT: Edit secret-template.yaml with your real values, then re-apply:"
echo "  kubectl apply -f secret-template.yaml"
echo "  kubectl rollout restart -n freelingo deploy/freelingo-backend"
echo ""
echo "Required secrets to set:"
echo "  postgres-password, redis-password (random strings)"
echo "  secret-key                    (generate: openssl rand -hex 32)"
echo "  OPENAI_API_KEY                (NVIDIA NIM key, format: nvapi-...)"
echo ""
echo "LLM: NVIDIA NIM via OpenAI-compatible API (meta/llama-3.1-8b-instruct)"
echo "TTS/STT: local (requires Kokoro/Whisper GPU services - disabled by default)"
echo ""
echo "Monitoring:"
echo "  kubectl get pods -n ${NAMESPACE} -w"
echo "  kubectl logs -n ${NAMESPACE} deployment/freelingo-backend --tail=50 -f"
