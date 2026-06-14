#!/bin/bash
# undeploy.sh - Remove FreeLingo from your K3s cluster
# Usage: ./undeploy.sh

set -e

NAMESPACE="freelingo"

echo "=== Removing FreeLingo from K3s Cluster ==="
echo ""

echo "Deleting all FreeLingo resources..."

# Delete in reverse order (lighter dependencies first)
kubectl delete -f ./tailscale-service.yaml --ignore-not-found=true
kubectl delete -f ./network-policy.yaml --ignore-not-found=true
kubectl delete -f ./ingress.yaml --ignore-not-found=true
kubectl delete -f ./services.yaml --ignore-not-found=true
kubectl delete -f ./frontend-deployment.yaml --ignore-not-found=true
kubectl delete -f ./backend-deployment.yaml --ignore-not-found=true
kubectl delete -f ./mock-gpu-services.yaml --ignore-not-found=true
kubectl delete -f ./db-statefulset.yaml --ignore-not-found=true
kubectl delete -f ./secret-template.yaml --ignore-not-found=true
kubectl delete -f ./serviceaccounts.yaml --ignore-not-found=true

# Delete namespace last (this cascades and deletes everything)
echo "Deleting namespace ${NAMESPACE}..."
kubectl delete -f ./namespace.yaml --ignore-not-found=true

echo ""
echo "=== FreeLingo has been removed ==="
