---
name: k3s-dind-build
description: Build Docker images directly inside a K3s cluster using DinD (bypassing local Docker)
---

# K3s DinD Build Skill

When you need to build a Docker image from local source code but the host machine (like a MacBook) does not have `docker` installed locally, you can leverage the K3s cluster to build and push the image.

## Instructions for AI Agents

1. **The Script is Available Globally**: The executable script `k3s-build` is installed on the system path (`/usr/local/bin/k3s-build`).
2. **Usage**: `k3s-build <path-to-source-directory> <registry-url/image-name:tag>`
3. **Example**: `k3s-build ./my-app 192.168.0.236:5000/my-app:latest`

### What it does automatically:
- Deploys a `docker:dind` privileged Pod to the `default` namespace.
- Compresses the target `<path-to-source-directory>`.
- Uses `kubectl cp` to transfer the context into the builder Pod.
- Executes `docker build` and `docker push` internally against the insecure private registry.
- Deletes the Pod and cleans up the temporary files.

### Manual Troubleshooting (If the script fails):
If you need to do this manually without the script, deploy a DinD pod with `--insecure-registry` configured for the target registry, copy the source files to it, and `kubectl exec` into it to run the build.
