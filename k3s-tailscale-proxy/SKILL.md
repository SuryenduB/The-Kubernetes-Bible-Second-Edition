---
name: k3s-tailscale-proxy
description: Correctly expose Kubernetes applications via Tailscale in the Homelab
---

# K3s Tailscale Proxy Skill

In this specific K3s Homelab environment, Tailscale integration is **NOT** achieved by attaching annotations to `Ingress` objects (like Traefik). 

Instead, the Tailscale Kubernetes Operator is configured to watch **`Service`** objects and automatically spin up a dedicated proxy pod to route traffic from the Tailnet into the cluster.

## Instructions for AI Agents

Whenever you need to expose a web application or service securely over Tailscale in this cluster, do **not** create an Ingress. Instead, attach the following annotations directly to the target application's Kubernetes `Service`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-backend
  namespace: my-namespace
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/proxy-class: "tailscale-proxy"
    tailscale.com/hostname: "my-app" # The magic DNS name on the Tailnet
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: my-app-backend
```

### Key Verification Steps:
1. Ensure the `Service` is created.
2. The Tailscale Operator will automatically provision a stateful proxy pod.
3. The application will be immediately reachable at `http://<hostname>` (e.g., `http://my-app`) from any authenticated Tailscale client.
