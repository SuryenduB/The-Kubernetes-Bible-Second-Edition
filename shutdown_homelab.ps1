# ?? K3s Homelab Systematic Shutdown (v8 - Refined & Verified)
[CmdletBinding()]
param(
    [Parameter(HelpMessage="Skip all manual confirmations")]
    [switch]$Force,

    [Parameter(HelpMessage="Skip the kubectl drain process and power off immediately")]
    [switch]$SkipDrain,

    [Parameter(HelpMessage="Discovery Mode: Auto (detect), Dynamic (Force API), Fallback (Force Hardcoded)")]
    [ValidateSet("Auto", "Dynamic", "Fallback")]
    [string]$Mode = "Auto"
)

$ErrorActionPreference = 'Stop' # Critical for Catch block to trigger on external errors

# --- CONFIGURATION (Hardcoded Fallback) ---
$masterFallback = @{ Name = "nuc"; IP = "192.168.0.21" }
$workerFallback = @(
    @{ Name = "kubernetes1"; IP = "192.168.0.19" },
    @{ Name = "kubernetes2"; IP = "192.168.0.20" },
    @{ Name = "kubernetes3"; IP = "192.168.0.22" },
    @{ Name = "kubernetes4"; IP = "192.168.0.23" },
    @{ Name = "kubernetes5"; IP = "192.168.0.24" },
    @{ Name = "kubernetes6"; IP = "192.168.0.25" },
    @{ Name = "kubernetes7"; IP = "192.168.0.26" },
    @{ Name = "kubernetes8-debian"; IP = "192.168.0.27" }
)

Write-Host "--- K3s Cluster Shutdown Sequence (v8) ---" -ForegroundColor Cyan

# 1. DISCOVERY LOGIC
$targets = @()
$masterIp = $null
$actualMode = ""

if ($Mode -eq "Fallback") {
    $actualMode = "FALLBACK"
} else {
    try {
        Write-Host "Attempting dynamic node discovery..." -ForegroundColor Gray
        # Correct flag is --request-timeout
        $allNodes = kubectl get nodes -o json --request-timeout=10s | ConvertFrom-Json
        
        function Get-IPv4 {
            param($addresses)
            return ($addresses | Where-Object { $_.type -eq 'InternalIP' -and $_.address -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1 -ExpandProperty address)
        }

        $masterNode = $allNodes.items | Where-Object { $_.metadata.labels.'node-role.kubernetes.io/master' -eq 'true' -or $_.metadata.labels.'node-role.kubernetes.io/control-plane' -eq 'true' }
        # Exclude only master from worker list
        $workerNodes = $allNodes.items | Where-Object { $_.metadata.name -ne $masterNode.metadata.name }

        $masterIp = Get-IPv4 -addresses $masterNode.status.addresses
        foreach ($node in $workerNodes) {
            $ip = Get-IPv4 -addresses $node.status.addresses
            if ($ip) { $targets += [PSCustomObject]@{ Name = $node.metadata.name; IP = $ip } }
        }
        $actualMode = "DYNAMIC"
    }
    catch {
        if ($Mode -eq "Dynamic") {
            Write-Error "Force Dynamic mode requested but API is unreachable."
            exit 1
        }
        Write-Host "[!] API Unreachable. Switching to FALLBACK mode." -ForegroundColor Yellow
        $actualMode = "FALLBACK"
    }
}

if ($actualMode -eq "FALLBACK") {
    $masterIp = $masterFallback.IP
    foreach ($w in $workerFallback) { $targets += [PSCustomObject]@{ Name = $w.Name; IP = $w.IP } }
}

Write-Host "Active Mode: $actualMode" -ForegroundColor Cyan
Write-Host "Master: $masterIp"
Write-Host "Workers: $($targets.Name -join ', ')"

# 2. CREDENTIALS
$password = Read-Host "Enter sudo password" -AsSecureString
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
$b64Pass = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plainPass))

if (!$Force) {
    $confirm = Read-Host "!!! WARNING: Powering off entire cluster. Proceed? (yes/no)"
    if ($confirm -ne 'yes') { exit 0 }
}

# 3. SHUTDOWN LOOP
foreach ($worker in $targets) {
    Write-Host "`n--- Node: $($worker.Name) ---" -ForegroundColor Yellow
    
    if ($actualMode -eq "DYNAMIC" -and !$SkipDrain) {
        Write-Host "  - Draining..."
        kubectl cordon $worker.Name | Out-Null
        kubectl drain $worker.Name --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=60s
    }

    Write-Host "  - Powering off..."
    ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$($worker.IP) "echo $b64Pass | base64 -d | sudo -S poweroff"
}

Write-Host "`n--- Powering off Master (NUC) ---" -ForegroundColor Red
ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$masterIp "echo $b64Pass | base64 -d | sudo -S poweroff"
