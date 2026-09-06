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
    After uncordoning, it cleans up stranded pods on offline nodes and performs an ordered rolling restart:
      1. StatefulSets (databases, caches, queues) — waits for ready status before proceeding
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
.PARAMETER RolloutTimeout
    Timeout in seconds to wait for StatefulSet rollout readiness before starting Deployments. Default: 180.
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

[CmdletBinding(SupportsShouldProcess = $false)]
param(
    [Parameter()]
    [switch]$SkipRestart,

    [Parameter()]
    [switch]$Rebalance,

    [Parameter()]
    [ValidateRange(1.0, 10.0)]
    [double]$RebalanceThreshold = 1.5,

    [Parameter()]
    [ValidateRange(30, 600)]
    [int]$RolloutTimeout = 180
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
Write-Verbose "Parameters: SkipRestart=$SkipRestart, Rebalance=$Rebalance, RebalanceThreshold=$RebalanceThreshold, RolloutTimeout=$RolloutTimeout"

# Namespaces to skip during rolling restart (system / infrastructure)
$SkipNamespaces = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('kube-system', 'longhorn-system', 'argocd', 'cnpg-system', 'tailscale'),
    [System.StringComparer]::OrdinalIgnoreCase
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  K3s Homelab - Resuming Full Capacity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    # ── Step 1: Identify cordoned and offline nodes ──────────────────────
    Write-Host "`n[1/6] Inspecting cluster nodes..." -ForegroundColor Yellow

    Write-Verbose "Fetching node list from cluster..."
    $nodesRaw = kubectl get nodes -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query Kubernetes cluster: $nodesRaw"
    }
    $nodesJson = $nodesRaw | ConvertFrom-Json
    Write-Verbose "Found $($nodesJson.items.Count) nodes in cluster."

    $cordonedNodes = [System.Collections.Generic.List[object]]::new()
    $offlineNodes = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $nodesJson.items) {
        $nodeName = $item.metadata.name
        $isReady = $false
        foreach ($cond in $item.status.conditions) {
            if ($cond.type -eq 'Ready' -and $cond.status -eq 'True') {
                $isReady = $true
                break
            }
        }

        if (-not $isReady) {
            $offlineNodes.Add($nodeName)
        }

        if ($item.spec.PSObject.Properties['unschedulable'] -and $item.spec.unschedulable -eq $true) {
            $cordonedNodes.Add($item)
        }
    }

    if ($offlineNodes.Count -gt 0) {
        Write-Host "  [!] Offline / NotReady node(s): $($offlineNodes -join ', ')" -ForegroundColor Yellow
    }

    # ── Step 2: Uncordon nodes ───────────────────────────────────────────
    Write-Host "`n[2/6] Uncordoning nodes..." -ForegroundColor Yellow
    $wasCordoned = $false
    if ($cordonedNodes.Count -eq 0) {
        Write-Host "  [+] No cordoned nodes found. Cluster is already schedulable." -ForegroundColor Green
    }
    else {
        $wasCordoned = $true
        Write-Host "  Found $($cordonedNodes.Count) cordoned node(s)." -ForegroundColor Gray
        foreach ($node in $cordonedNodes) {
            $name = $node.metadata.name
            Write-Host "  Uncordoning $name..." -ForegroundColor Cyan
            Write-Verbose "Running: kubectl uncordon $name"
            $null = kubectl uncordon $name 2>$null
        }
        Write-Host "  [+] All cordoned nodes uncordoned." -ForegroundColor Green
    }

    # ── Step 3: Clean up stranded, zombie, and terminating pods ──────────
    Write-Host "`n[3/6] Checking for stranded & zombie workloads..." -ForegroundColor Yellow
    $allCurrentPodsRaw = kubectl get pods -A -o json 2>$null
    if ($allCurrentPodsRaw) {
        $allCurrentPods = $allCurrentPodsRaw | ConvertFrom-Json
        foreach ($p in $allCurrentPods.items) {
            $ns = $p.metadata.namespace
            $pname = $p.metadata.name
            if ($SkipNamespaces.Contains($ns)) { continue }

            $targetNode = if ($p.spec.PSObject.Properties['nodeName']) { $p.spec.nodeName } else { '' }
            $isNodeOffline = $targetNode -and $offlineNodes.Contains($targetNode)
            $isTerminating = [bool]$p.metadata.PSObject.Properties['deletionTimestamp']
            $isUnknown = $p.status.phase -eq 'Unknown'

            if ($isNodeOffline -or $isTerminating -or $isUnknown) {
                Write-Host "    Purging stuck/orphaned pod: $pname [$ns] on node: $targetNode..." -ForegroundColor Yellow
                $null = kubectl delete pod $pname -n $ns --grace-period=0 --force 2>$null
            }
        }
    }
    Write-Host "  [+] Pod cleanup complete." -ForegroundColor Green

    # ── Step 4: Ordered rolling restart with strict dependency gating ────
    if ($wasCordoned -and -not $SkipRestart) {
        Write-Host "`n[4/6] Rebalancing workloads (Ordered Rolling Restart)..." -ForegroundColor Yellow

        function Get-RestartableItems {
            param([string]$ResourceType)
            $raw = kubectl get $ResourceType -A -o json 2>$null
            if (-not $raw) { return @() }
            $parsed = $raw | ConvertFrom-Json
            return @($parsed.items | Where-Object {
                (-not $SkipNamespaces.Contains($_.metadata.namespace)) -and
                ($_.spec.replicas -gt 0)
            })
        }

        # Phase A — StatefulSets first (databases, queues, caches)
        Write-Host "  Phase A: Rolling restart of StatefulSets (databases/dependencies)..." -ForegroundColor Gray
        $statefulsets = Get-RestartableItems 'statefulsets'
        Write-Verbose "Found $($statefulsets.Count) restartable StatefulSets."

        foreach ($sts in $statefulsets) {
            $ns = $sts.metadata.namespace
            $name = $sts.metadata.name
            Write-Host "    Restarting statefulset: $name [$ns]..." -ForegroundColor DarkGray
            $null = kubectl rollout restart statefulset/$name -n $ns 2>$null
        }

        $allStsHealthy = $true
        if ($statefulsets.Count -gt 0) {
            Write-Host "  [~] Waiting for StatefulSets to achieve readiness (timeout: ${RolloutTimeout}s)..." -ForegroundColor Gray
            foreach ($sts in $statefulsets) {
                $ns = $sts.metadata.namespace
                $name = $sts.metadata.name
                Write-Host "    Validating rollout: $name [$ns]..." -NoNewline -ForegroundColor DarkGray
                $statusOut = kubectl rollout status statefulset/$name -n $ns --timeout="${RolloutTimeout}s" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host " [READY]" -ForegroundColor Green
                }
                else {
                    $allStsHealthy = $false
                    Write-Host " [RETRYING/VOLUME RESOLVE: $statusOut]" -ForegroundColor Yellow
                    # Delete the pod to release any Longhorn RWO volume lock
                    $null = kubectl delete pod -l app=$name -n $ns --grace-period=0 --force 2>$null
                    Start-Sleep -Seconds 5
                    $statusRetry = kubectl rollout status statefulset/$name -n $ns --timeout=60s 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "      --> $name recovered successfully!" -ForegroundColor Green
                        $allStsHealthy = $true
                    }
                }
            }
            Write-Host "  [+] Phase A complete." -ForegroundColor Green
        }
        else {
            Write-Host "  [+] No restartable StatefulSets found." -ForegroundColor Green
        }

        # Phase B — Deployments (application workloads)
        if (-not $allStsHealthy) {
            Write-Host "  [!] Warning: Some database dependencies took longer to recover. Pausing 10s before Deployments..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }

        Write-Host "`n  Phase B: Rolling restart of Deployments (application services)..." -ForegroundColor Gray
        $deployments = Get-RestartableItems 'deployments'
        Write-Verbose "Found $($deployments.Count) restartable Deployments."

        foreach ($deploy in $deployments) {
            $ns = $deploy.metadata.namespace
            $name = $deploy.metadata.name
            Write-Host "    Restarting deployment: $name [$ns]..." -ForegroundColor DarkGray
            $null = kubectl rollout restart deployment/$name -n $ns 2>$null
        }

        if ($deployments.Count -gt 0) {
            Write-Host "  [+] Deployment rollouts triggered ($($deployments.Count))." -ForegroundColor Green
        }
        else {
            Write-Host "  [+] No restartable Deployments found." -ForegroundColor Green
        }
    }
    elseif ($SkipRestart) {
        Write-Host "`n[4/6] Skipping workload rebalancing (-SkipRestart active)." -ForegroundColor Gray
    }

    # ── Step 5: Workload Rebalancing across underutilized nodes ──────────
    if ($Rebalance) {
        Write-Host "`n[5/6] Analyzing workload distribution..." -ForegroundColor Yellow

        $workerNodes = $nodesJson.items | Where-Object {
            $labels = $_.metadata.labels
            $isControlPlane = $labels.PSObject.Properties['node-role.kubernetes.io/control-plane'] -or
                              $labels.PSObject.Properties['node-role.kubernetes.io/master']
            $readyCond = @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
            (-not $isControlPlane) -and ($readyCond.Count -gt 0)
        }
        $workerNames = $workerNodes | ForEach-Object { $_.metadata.name }
        Write-Verbose "Worker nodes: $($workerNames -join ', ')"

        $allPodsRaw = kubectl get pods -A -o json 2>$null
        $allPods = if ($allPodsRaw) { $allPodsRaw | ConvertFrom-Json } else { [pscustomobject]@{ items = @() } }
        $dsPodOwners = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($pod in $allPods.items) {
            if (-not $pod.metadata -or -not $pod.metadata.ownerReferences) { continue }
            foreach ($ref in $pod.metadata.ownerReferences) {
                if ($ref.kind -eq 'DaemonSet') {
                    $null = $dsPodOwners.Add($pod.metadata.name)
                    break
                }
            }
        }

        $podCountByNode = @{}
        foreach ($w in $workerNames) { $podCountByNode[$w] = 0 }
        foreach ($pod in $allPods.items) {
            if (-not $pod.metadata -or -not $pod.spec) { continue }
            $nodeName = $pod.spec.nodeName
            if ($nodeName -and $podCountByNode.ContainsKey($nodeName) -and
                (-not $dsPodOwners.Contains($pod.metadata.name)) -and
                $pod.status.phase -eq 'Running') {
                $podCountByNode[$nodeName]++
            }
        }

        $totalWorkerPods = ($podCountByNode.Values | Measure-Object -Sum).Sum
        $avgPods = if ($workerNames.Count -gt 0) { [math]::Round($totalWorkerPods / $workerNames.Count, 1) } else { 0 }

        Write-Host "  Worker pod distribution (avg: $avgPods pods/node):" -ForegroundColor Gray
        $overloaded = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($w in ($workerNames | Sort-Object { $podCountByNode[$_] } -Descending)) {
            $count = $podCountByNode[$w]
            $marker = ""
            if ($avgPods -gt 0 -and ($count / $avgPods) -ge $RebalanceThreshold) {
                $marker = " <-- OVERLOADED"
                $overloaded.Add(@{ Name = $w; Count = $count })
            }
            Write-Host "    $w : $count pods$marker" -ForegroundColor $(if ($marker) { 'Red' } else { 'Gray' })
        }

        if ($overloaded.Count -eq 0) {
            Write-Host "  [+] All nodes within balance threshold ($($RebalanceThreshold)x avg)." -ForegroundColor Green
        }
        else {
            Write-Host "`n  Rebalancing $($overloaded.Count) overloaded node(s)..." -ForegroundColor Yellow
            foreach ($node in $overloaded) {
                $name = $node.Name
                Write-Host "`n  >> Processing node: $name ($($node.Count) pods)" -ForegroundColor Cyan

                $null = kubectl cordon $name 2>$null

                $podsToMove = $allPods.items | Where-Object {
                    $_.spec.nodeName -eq $name -and
                    $_.status.phase -eq 'Running' -and
                    (-not $dsPodOwners.Contains($_.metadata.name)) -and
                    (-not $SkipNamespaces.Contains($_.metadata.namespace))
                }

                if ($podsToMove.Count -eq 0) {
                    Write-Host "    [b] No movable pods found." -ForegroundColor Gray
                }
                else {
                    Write-Host "    [b] Evicting $($podsToMove.Count) pods gracefully..." -ForegroundColor DarkGray
                    foreach ($pod in $podsToMove) {
                        $pName = $pod.metadata.name
                        $pNs = $pod.metadata.namespace
                        Write-Host "      Evicting: $pName [$pNs]..." -ForegroundColor DarkGray
                        $null = kubectl delete pod $pName -n $pNs --grace-period=30 --ignore-not-found 2>$null
                    }
                    Start-Sleep -Seconds 10
                }

                $null = kubectl uncordon $name 2>$null
                Write-Host "    [+] $name uncordoned and rebalanced." -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "`n[5/6] Workload rebalancing skipped (-Rebalance not specified)." -ForegroundColor Gray
    }

    # ── Step 6: Cluster Verification & Health Assessment ─────────────────
    Write-Host "`n[6/6] Current Cluster Status & Health Check" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    kubectl get nodes -o wide
    Write-Host ""

    # Check for degraded pods
    $allCurrentPodsRaw = kubectl get pods -A -o json 2>$null
    $degradedPods = [System.Collections.Generic.List[object]]::new()
    if ($allCurrentPodsRaw) {
        $allCurrentPods = $allCurrentPodsRaw | ConvertFrom-Json
        foreach ($pod in $allCurrentPods.items) {
            $phase = $pod.status.phase
            $hasIssue = $false

            if ($phase -notin @('Running', 'Succeeded')) {
                $hasIssue = $true
            }
            elseif ($pod.status.PSObject.Properties['containerStatuses'] -and $pod.status.containerStatuses) {
                foreach ($cs in $pod.status.containerStatuses) {
                    if ($cs.state.PSObject.Properties['waiting'] -and $cs.state.waiting -and 
                        $cs.state.waiting.PSObject.Properties['reason'] -and 
                        $cs.state.waiting.reason -in @('CrashLoopBackOff', 'ImagePullBackOff', 'CreateContainerError', 'ErrImagePull')) {
                        $hasIssue = $true
                        break
                    }
                }
            }

            if ($hasIssue) {
                $degradedPods.Add($pod)
            }
        }
    }

    if ($degradedPods.Count -gt 0) {
        Write-Host "`n[!] The following $($degradedPods.Count) pod(s) need attention:" -ForegroundColor Red
        foreach ($dp in $degradedPods) {
            $waitReason = ""
            if ($dp.status.PSObject.Properties['containerStatuses'] -and $dp.status.containerStatuses) {
                $reasons = [System.Collections.Generic.List[string]]::new()
                foreach ($cs in $dp.status.containerStatuses) {
                    if ($cs.state.PSObject.Properties['waiting'] -and $cs.state.waiting -and $cs.state.waiting.PSObject.Properties['reason']) {
                        $reasons.Add($cs.state.waiting.reason)
                    }
                }
                if ($reasons.Count -gt 0) { $waitReason = " ($($reasons -join ', '))" }
            }
            $targetNode = if ($dp.spec.PSObject.Properties['nodeName']) { $dp.spec.nodeName } else { '<unassigned>' }
            Write-Host "    - [$($dp.metadata.namespace)] $($dp.metadata.name) : $($dp.status.phase)$waitReason on node: $targetNode" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`n[+] All non-system pods are running and healthy!" -ForegroundColor Green
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Cluster capacity restoration complete." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to restore cluster capacity: $($_.Exception.Message)"
    exit 1
}
