# Start-K3sHomelab.ps1
# Restores cluster capacity by uncordoning all nodes currently marked as SchedulingDisabled.
# Symmetrical counterpart to Stop-K3sHomelab-Minimal.ps1

<#
.SYNOPSIS
    Uncordons all K3s nodes that are currently marked as 'SchedulingDisabled'.
.DESCRIPTION
    This script identifies nodes in the cluster that have been cordoned (e.g., by a shutdown script)
    and executes 'kubectl uncordon' on each to allow workload scheduling again.
.EXAMPLE
    PS> .\Start-K3sHomelab.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipRestart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  K3s Homelab - Resuming Full Capacity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    Write-Host "`n[1/3] Identifying cordoned nodes..." -ForegroundColor Yellow
    
    # Get nodes in JSON format for robust parsing
    $nodesJson = kubectl get nodes -o json | ConvertFrom-Json
    
    # Safely find nodes that are unschedulable (avoiding StrictMode errors)
    $cordonedNodes = $nodesJson.items | Where-Object { 
        $_.spec.PSObject.Properties['unschedulable'] -and $_.spec.unschedulable -eq $true 
    }

    $wasCordoned = $false
    if (-not $cordonedNodes) {
        Write-Host "  [+] No cordoned nodes found. Cluster is already at full capacity." -ForegroundColor Green
    }
    else {
        $wasCordoned = $true
        Write-Host "  Found $($cordonedNodes.Count) cordoned nodes." -ForegroundColor Gray
        
        Write-Host "`n[2/3] Uncordoning nodes..." -ForegroundColor Yellow
        foreach ($node in $cordonedNodes) {
            $name = $node.metadata.name
            Write-Host "  Uncordoning $name..." -ForegroundColor Cyan
            kubectl uncordon $name | Out-Null
        }
        Write-Host "  [+] All nodes uncordoned." -ForegroundColor Green
    }

    # Step 3: Rolling restart to rebalance workloads
    if ($wasCordoned -and -not $SkipRestart) {
        Write-Host "`n[3/3] Rebalancing workloads (Rolling Restart)..." -ForegroundColor Yellow
        Write-Host "  Triggering rollout restart for all deployments to redistribute pods..." -ForegroundColor Gray
        
        $deployments = kubectl get deployments -A -o json | ConvertFrom-Json
        foreach ($deploy in $deployments.items) {
            $ns = $deploy.metadata.namespace
            $name = $deploy.metadata.name
            # Only restart if it has replicas
            if ($deploy.spec.replicas -gt 0) {
                Write-Host "  Restarting deployment: $name [$ns]..." -ForegroundColor DarkGray
                kubectl rollout restart deployment/$name -n $ns | Out-Null
            }
        }
        Write-Host "  [+] All deployment rollouts triggered." -ForegroundColor Green
    }
    elseif ($SkipRestart) {
        Write-Host "`n[3/3] Skipping workload rebalancing (-SkipRestart active)." -ForegroundColor Gray
    }

    # Final Verification
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Current Cluster Status" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    kubectl get nodes -o wide

    Write-Host "`n✅ Cluster capacity restored." -ForegroundColor Green
}
catch {
    Write-Error "Failed to restore cluster capacity: $($_.Exception.Message)"
}
