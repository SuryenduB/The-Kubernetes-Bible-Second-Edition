#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path-to-source> <image-tag>"
    echo "Example: $0 ./my-app 192.168.0.236:5000/my-app:latest"
    exit 1
fi

SOURCE_DIR=$1
IMAGE_TAG=$2
POD_NAME="docker-builder-$(date +%s)"

echo "🚀 [1/5] Spinning up Docker-in-Docker Builder Pod ($POD_NAME)..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: default
spec:
  containers:
  - name: dind
    image: docker:dind
    securityContext:
      privileged: true
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
    command:
    - dockerd
    - --insecure-registry=192.168.0.236:5000
EOF

echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/$POD_NAME --timeout=60s

echo "📦 [2/5] Compressing source directory..."
tar -czf /tmp/build-context.tar.gz -C "$SOURCE_DIR" .

echo "📤 [3/5] Uploading source to builder..."
kubectl cp /tmp/build-context.tar.gz $POD_NAME:/tmp/build-context.tar.gz

echo "🏗️  [4/5] Building and pushing Docker image..."
kubectl exec $POD_NAME -- sh -c "mkdir -p /src && tar -xzf /tmp/build-context.tar.gz -C /src && cd /src && docker build -t $IMAGE_TAG . && docker push $IMAGE_TAG"

echo "🧹 [5/5] Cleaning up..."
kubectl delete pod $POD_NAME
rm /tmp/build-context.tar.gz

echo "✅ Success! Image pushed to $IMAGE_TAG"
