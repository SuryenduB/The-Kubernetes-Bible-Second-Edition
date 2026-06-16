#Requires -Version 7.0
# Start-K3sHomelab.ps1
# Restores cluster capacity by uncordoning all nodes currently marked as SchedulingDisabled.
# Performs ordered rolling restarts of StatefulSets then Deployments to rebalance workloads.
# Symmetrical counterpart to Stop-K3sHomelab-Minimal.ps1

<#
.SYNOPSIS
    Uncordons all K3s nodes that are currently marked as 'SchedulingDisabled'.
.DESCRIPTION
    This script identifies nodes in the cluster that have been cordoned (e.g., by a shutdown script)
    and executes 'kubectl uncordon' on each to allow workload scheduling again.
    After uncordoning, it performs an ordered rolling restart:
      1. StatefulSets (databases, caches, queues) — must come up first
      2. Deployments (application pods) — depend on the StatefulSets
    System namespaces (kube-system, longhorn-system, argocd, cnpg-system, tailscale) are skipped.
    When -Rebalance is specified, overloaded nodes (>= 1.5x avg pods) are cordoned and drained
    to redistribute workloads across underutilized nodes.
.PARAMETER SkipRestart
    Skip the ordered rolling restart of StatefulSets and Deployments.
.PARAMETER Rebalance
    Enable workload redistribution by cordoning and draining overloaded nodes.
.PARAMETER RebalanceThreshold
    Pods-per-node ratio (relative to average) that triggers rebalancing. Default: 1.5.
.EXAMPLE
    PS> .\Start-K3sHomelab.ps1
.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -SkipRestart
.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -Rebalance
.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -Rebalance -RebalanceThreshold 2.0
.NOTES
    Requires: kubectl, ssh (for node telemetry)
    Platform: Windows, Linux, macOS (PowerShell 7+)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipRestart,

    [Parameter()]
    [switch]$Rebalance,

    [Parameter()]
    [ValidateRange(1.0, 10.0)]
    [double]$RebalanceThreshold = 1.5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Platform & Prerequisites ───────────────────────────────────────────
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl not found in PATH. Install it from https://kubernetes.io/docs/tasks/tools/"
    exit 1
}

$sshAvailable = [bool](Get-Command ssh -ErrorAction SilentlyContinue)
if (-not $sshAvailable) {
    Write-Warning "ssh not found in PATH. Node telemetry (uptime, disk) will be skipped."
}

Write-Verbose "Platform: $(if ($IsWindows) {'Windows'} elseif ($IsMacOS) {'macOS'} elseif ($IsLinux) {'Linux'} else {'Unknown'})"
Write-Verbose "PowerShell: $($PSVersionTable.PSVersion)"
Write-Verbose "Parameters: SkipRestart=$SkipRestart, Rebalance=$Rebalance, RebalanceThreshold=$RebalanceThreshold"

# Namespaces to skip during rolling restart (system / infrastructure)
$SkipNamespaces = @(
    'kube-system'
    'longhorn-system'
    'argocd'
    'cnpg-system'
    'tailscale'
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  K3s Homelab - Resuming Full Capacity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    # ── Step 1: Identify cordoned nodes ──────────────────────────────────
    Write-Host "`n[1/5] Identifying cordoned nodes..." -ForegroundColor Yellow

    Write-Verbose "Fetching node list from cluster..."
    $nodesJson = kubectl get nodes -o json | ConvertFrom-Json
    Write-Verbose "Found $($nodesJson.items.Count) nodes in cluster."

    $cordonedNodes = $nodesJson.items | Where-Object {
        $_.spec.PSObject.Properties['unschedulable'] -and $_.spec.unschedulable -eq $true
    }

    $wasCordoned = $false
    if (-not $cordonedNodes) {
        Write-Host "  [+] No cordoned nodes found. Cluster is already at full capacity." -ForegroundColor Green
    }
    else {
        $wasCordoned = $true
        Write-Host "  Found $($cordonedNodes.Count) cordoned node(s)." -ForegroundColor Gray

        # ── Step 2: Uncordon nodes ───────────────────────────────────────
        Write-Host "`n[2/5] Uncordoning nodes..." -ForegroundColor Yellow
        foreach ($node in $cordonedNodes) {
            $name = $node.metadata.name
            Write-Host "  Uncordoning $name..." -ForegroundColor Cyan
            Write-Verbose "Running: kubectl uncordon $name"
            kubectl uncordon $name | Out-Null
        }
        Write-Host "  [+] All nodes uncordoned." -ForegroundColor Green
    }

    # ── Step 3: Ordered rolling restart ──────────────────────────────────
    if ($wasCordoned -and -not $SkipRestart) {
        Write-Host "`n[3/5] Rebalancing workloads (Ordered Rolling Restart)..." -ForegroundColor Yellow

        # Helper: filter items outside skipped namespaces
        function Get-RestartableItems {
            param([string]$ResourceType)
            $items = kubectl get $ResourceType -A -o json | ConvertFrom-Json
            $items.items | Where-Object {
                $_.metadata.namespace -notin $SkipNamespaces -and
                $_.spec.replicas -gt 0
            }
        }

        # Phase A — StatefulSets first (databases, caches, queues)
        Write-Host "  Phase A: Restarting StatefulSets (infra dependencies)..." -ForegroundColor Gray
        $statefulsets = Get-RestartableItems 'statefulsets'
        Write-Verbose "Found $($statefulsets.Count) restartable StatefulSets."
        foreach ($sts in $statefulsets) {
            $ns  = $sts.metadata.namespace
            $name = $sts.metadata.name
            Write-Host "    Restarting statefulset: $name [$ns]..." -ForegroundColor DarkGray
            kubectl rollout restart statefulset/$name -n $ns | Out-Null
        }
        if ($statefulsets) {
            Write-Host "  [+] StatefulSet rollouts triggered ($($statefulsets.Count))." -ForegroundColor Green
        }
        else {
            Write-Host "  [+] No restartable StatefulSets found." -ForegroundColor Green
        }

        # Phase B — Deployments (application workloads)
        Write-Host "  Phase B: Restarting Deployments (application pods)..." -ForegroundColor Gray
        $deployments = Get-RestartableItems 'deployments'
        foreach ($deploy in $deployments) {
            $ns  = $deploy.metadata.namespace
            $name = $deploy.metadata.name
            Write-Host "    Restarting deployment: $name [$ns]..." -ForegroundColor DarkGray
            kubectl rollout restart deployment/$name -n $ns | Out-Null
        }
        if ($deployments) {
            Write-Host "  [+] Deployment rollouts triggered ($($deployments.Count))." -ForegroundColor Green
        }
        else {
            Write-Host "  [+] No restartable Deployments found." -ForegroundColor Green
        }
    }
    elseif ($SkipRestart) {
        Write-Host "`n[3/5] Skipping workload rebalancing (-SkipRestart active)." -ForegroundColor Gray
    }

    # ── Step 4: Workload Rebalancing ────────────────────────────────────
    if ($Rebalance) {
        Write-Host "`n[4/5] Analyzing workload distribution..." -ForegroundColor Yellow

        # Get worker nodes (exclude control-plane/master, only Ready nodes)
        $workerNodes = $nodesJson.items | Where-Object {
            $labels = $_.metadata.labels
            $isControlPlane = $labels.PSObject.Properties['node-role.kubernetes.io/control-plane'] -or
                              $labels.PSObject.Properties['node-role.kubernetes.io/master']
            $readyCond = @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
            (-not $isControlPlane) -and ($readyCond.Count -gt 0)
        }
        $workerNames = $workerNodes | ForEach-Object { $_.metadata.name }
        Write-Verbose "Worker nodes: $($workerNames -join ', ')"

        # Count pods per node (exclude DaemonSet pods — they stick to their node)
        Write-Verbose "Fetching all pods..."
        $allPods = kubectl get pods -A -o json | ConvertFrom-Json
        $dsPodOwners = @{}

        # Identify DaemonSet-owned pods via ownerReferences
        Write-Verbose "Identifying DaemonSet-owned pods..."
        foreach ($pod in $allPods.items) {
            if (-not $pod.metadata -or -not $pod.metadata.ownerReferences) { continue }
            foreach ($ref in $pod.metadata.ownerReferences) {
                if ($ref.kind -eq 'DaemonSet') {
                    $dsPodOwners[$pod.metadata.name] = $true
                    break
                }
            }
        }
        Write-Verbose "DaemonSet-owned pods: $($dsPodOwners.Count)"

        $podCountByNode = @{}
        foreach ($w in $workerNames) { $podCountByNode[$w] = 0 }
        foreach ($pod in $allPods.items) {
            if (-not $pod.metadata -or -not $pod.spec) { continue }
            $nodeName = $pod.spec.nodeName
            if ($nodeName -and $podCountByNode.ContainsKey($nodeName) -and
                -not $dsPodOwners.ContainsKey($pod.metadata.name) -and
                $pod.status.phase -eq 'Running') {
                $podCountByNode[$nodeName]++
            }
        }

        Write-Verbose "Pod count by node:"
        foreach ($w in $workerNames) { Write-Verbose "  $w : $($podCountByNode[$w])" }

        $totalWorkerPods = ($podCountByNode.Values | Measure-Object -Sum).Sum
        $avgPods = if ($workerNames.Count -gt 0) { [math]::Round($totalWorkerPods / $workerNames.Count, 1) } else { 0 }
        Write-Verbose "Total movable worker pods: $totalWorkerPods, Average: $avgPods/node"

        Write-Host "  Worker pod distribution (avg: $avgPods pods/node):" -ForegroundColor Gray
        $overloaded = @()
        foreach ($w in ($workerNames | Sort-Object { $podCountByNode[$_] } -Descending)) {
            $count = $podCountByNode[$w]
            $marker = ""
            if ($avgPods -gt 0 -and ($count / $avgPods) -ge $RebalanceThreshold) {
                $marker = " <-- OVERLOADED"
                $overloaded += @{ Name = $w; Count = $count }
            }
            Write-Host "    $w : $count pods$marker" -ForegroundColor $(if ($marker) { 'Red' } else { 'Gray' })
        }

        if ($overloaded.Count -eq 0) {
            Write-Host "  [+] All nodes within balance threshold ($($RebalanceThreshold)x avg)." -ForegroundColor Green
        }
        else {
            Write-Host "`n[5/5] Rebalancing $($overloaded.Count) overloaded node(s)..." -ForegroundColor Yellow

            foreach ($node in $overloaded) {
                $name = $node.Name
                Write-Host "`n  >> Processing node: $name ($($node.Count) pods)" -ForegroundColor Cyan

                # 1. Cordon to prevent new pods from landing
                Write-Host "    [a] Cordoning $name to stop new scheduling..." -ForegroundColor DarkGray
                kubectl cordon $name 2>$null | Out-Null

                # 2. Get non-DaemonSet, non-static pods on this node
                $podsToMove = $allPods.items | Where-Object {
                    $_.spec.nodeName -eq $name -and
                    $_.status.phase -eq 'Running' -and
                    -not $dsPodOwners.ContainsKey($_.metadata.name) -and
                    $_.metadata.namespace -notin $SkipNamespaces
                }

                if ($podsToMove.Count -eq 0) {
                    Write-Host "    [b] No movable pods found." -ForegroundColor Gray
                }
                else {
                    Write-Host "    [b] Draining $($podsToMove.Count) pods (grace period: 60s)..." -ForegroundColor DarkGray
                    # Delete pods one by one to let the scheduler redistribute them
                    foreach ($pod in $podsToMove) {
                        $podName = $pod.metadata.name
                        $podNs = $pod.metadata.namespace
                        Write-Host "      Evicting: $podName [$podNs]..." -ForegroundColor DarkGray
                        kubectl delete pod $podName -n $podNs --grace-period=60 --ignore-not-found 2>$null | Out-Null
                    }
                    Write-Host "    [b] Waiting for pods to reschedule..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 10
                }

                # 3. Uncordon the node so it can accept new pods at a balanced level
                Write-Host "    [c] Uncordoning $name..." -ForegroundColor DarkGray
                kubectl uncordon $name 2>$null | Out-Null

                Write-Host "    [+] $name rebalanced." -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "`n[4/5] Skipping workload rebalancing (-Rebalance not set)." -ForegroundColor Gray
    }

    # ── Step 5: Verification ─────────────────────────────────────────────
    Write-Host "`n[5/5] Current Cluster Status" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    kubectl get nodes -o wide
    Write-Host ""
    kubectl get pods -A --field-selector=status.phase=Running -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase' 2>$null

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Cluster capacity restored." -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to restore cluster capacity: $($_.Exception.Message)"
    exit 1
}
