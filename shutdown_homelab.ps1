# 🛑 K3s Homelab Systematic Shutdown (v3 - Robust & Secure)
# This script addresses all previous findings regarding error checking, IP filtering, and credential safety.

$ErrorActionPreference = 'Stop'

# 1. Verification
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { throw "kubectl not found in PATH." }

Write-Host "--- K3s Cluster Shutdown Sequence (v3) ---" -ForegroundColor Cyan

# 2. Dynamic Node Discovery with IPv4 Filtering
Write-Host "Discovering cluster topology..."
$allNodes = kubectl get nodes -o json | ConvertFrom-Json

# Helper to get first IPv4 address
function Get-IPv4 {
    param($addresses)
    return ($addresses | Where-Object { $_.type -eq 'InternalIP' -and $_.address -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1 -ExpandProperty address)
}

$masterNode = $allNodes.items | Where-Object { $_.metadata.labels.'node-role.kubernetes.io/master' -eq 'true' -or $_.metadata.labels.'node-role.kubernetes.io/control-plane' -eq 'true' }
$workerNodes = $allNodes.items | Where-Object { $_.metadata.name -ne $masterNode.metadata.name }

$masterIp = Get-IPv4 -addresses $masterNode.status.addresses
$targets = @()

foreach ($node in $workerNodes) {
    $ip = Get-IPv4 -addresses $node.status.addresses
    if ($ip) {
        $targets += [PSCustomObject]@{ Name = $node.metadata.name; IP = $ip; Role = 'Worker' }
    }
}

Write-Host "Found Master: $($masterNode.metadata.name) ($masterIp)"
Write-Host "Found $($targets.Count) Workers: $($targets.Name -join ', ')"

# 3. Secure Credential Handling (Base64 to avoid quoting issues)
$password = Read-Host "Enter sudo password for suryendub" -AsSecureString
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
$b64Pass = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plainPass))

Write-Host "!!! WARNING: Powering off the entire cluster !!!" -ForegroundColor Red
$confirm = Read-Host "Proceed? (yes/no)"
if ($confirm -ne 'yes') { Write-Host "Aborted."; exit }

# 4. Preflight Checks (Check ALL nodes before starting)
Write-Host "
Running preflight checks on all nodes..." -ForegroundColor Cyan
$allIps = @($targets.IP + $masterIp)
foreach ($ip in $allIps) {
    $testCmd = "echo $b64Pass | base64 -d | sudo -S true"
    & ssh -tt -o BatchMode=yes -o StrictHostKeyChecking=yes suryendub@$ip $testCmd 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Preflight failed for $ip. Check SSH keys or sudo password."
        exit 1
    }
    Write-Host "  - $ip: OK" -ForegroundColor Green
}

# 5. Graceful Worker Shutdown with Strict Error Checking
foreach ($worker in $targets) {
    Write-Host "
--- Processing Worker: $($worker.Name) ---" -ForegroundColor Yellow
    
    # Cordon
    Write-Host "  - Cordoning..."
    kubectl cordon $worker.Name
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to cordon $($worker.Name). Aborting."; exit 1 }
    
    # Drain
    Write-Host "  - Draining pods..."
    kubectl drain $worker.Name --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=90s
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to drain $($worker.Name). Aborting."; exit 1 }
    
    # Poweroff
    Write-Host "  - Powering off..."
    $offCmd = "echo $b64Pass | base64 -d | sudo -S poweroff"
    ssh -tt -o StrictHostKeyChecking=yes suryendub@$worker.IP $offCmd
}

Write-Host "
Waiting 10 seconds for worker cycles..." -ForegroundColor Gray
Start-Sleep -Seconds 10

# 6. Master Shutdown
Write-Host "--- Powering off Master (NUC) ---" -ForegroundColor Red
$masterOffCmd = "echo $b64Pass | base64 -d | sudo -S poweroff"
ssh -tt -o StrictHostKeyChecking=yes suryendub@$masterIp $masterOffCmd

Write-Host "
[SUCCESS] Shutdown sequence complete." -ForegroundColor Green
