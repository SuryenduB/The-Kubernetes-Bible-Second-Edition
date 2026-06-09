---
name: k3s-rebalance
description: Uncordons K3s nodes and performs rolling restarts on all Deployments and StatefulSets to rebalance cluster workloads.
---

# k3s-rebalance

This skill uncordons all schedulable nodes in the K3s cluster and triggers a rolling restart for both Deployments and StatefulSets across all namespaces to evenly distribute workloads.

## When to use
Use this skill when:
- The cluster has been started up after being in a minimal or stopped mode.
- A node has been newly added or brought back online (e.g., via Wake-on-LAN).
- There is a workload imbalance in the cluster (one node carrying a disproportionate number of pods).

## Instructions

1. **Check Node Status**:
   Run `kubectl get nodes -o wide` to verify which nodes are Ready and if any are cordoned (look for `SchedulingDisabled`).

2. **Uncordon Nodes**:
   If there are cordoned nodes, uncordon them using:
   ```bash
   kubectl get nodes -o json | jq -r '.items[] | select(.spec.unschedulable==true) | .metadata.name' | xargs -I {} kubectl uncordon {}
   ```
   Or using PowerShell:
   ```powershell
   pwsh -File ./WindowsLab/Start-K3sHomelab.ps1
   ```

3. **Rebalance Deployments**:
   Perform a rolling restart on all Deployments across all namespaces to redistribute the pods:
   ```bash
   for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
     for deploy in $(kubectl get deployments -n $ns -o jsonpath='{.items[*].metadata.name}'); do
       echo "Restarting deployment/$deploy in namespace $ns..."
       kubectl rollout restart deployment/$deploy -n $ns
     done
   done
   ```

4. **Rebalance StatefulSets**:
   Perform a rolling restart on all StatefulSets across all namespaces:
   ```bash
   for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
     for sts in $(kubectl get statefulsets -n $ns -o jsonpath='{.items[*].metadata.name}'); do
       echo "Restarting statefulset/$sts in namespace $ns..."
       kubectl rollout restart statefulset/$sts -n $ns
     done
   done
   ```

5. **Verify Rebalancing**:
   Run the health scan tool to verify node pod counts:
   ```powershell
   pwsh -Command ". ./Test-K3sClusterHealth.ps1; Test-K3sClusterHealth"
   ```
