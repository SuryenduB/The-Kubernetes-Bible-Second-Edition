#Requires -Version 7.0
# Stop-K3sHomelab-Minimal.ps1
# Powers off high-consumption nodes, keeping only nuc + kubernetes5 + kubernetes7 running
# Hardware saved: kubernetes1, kubernetes2, kubernetes3, kubernetes4, kubernetes6, kubernetes8-debian

<#
.SYNOPSIS
    Gracefully stops high-consumption nodes in the K3s cluster to reduce power.
.DESCRIPTION
    Cordon and drains workloads from power-hungry nodes (kubernetes1-4, 6, 8-debian),
    preserving the minimal surviving set: nuc (control plane) + kubernetes5 + kubernetes7.
    Then cleanly executes remote poweroff via SSH with connectivity pre-checks and credential caching.
.PARAMETER Force
    Skip confirmation prompts.
.PARAMETER SkipDrain
    Skip the kubectl drain phase and power off immediately.
.PARAMETER Timeout
    Timeout in seconds for draining each node. Default: 90.
.EXAMPLE
    PS> .\Stop-K3sHomelab-Minimal.ps1
.EXAMPLE
    PS> .\Stop-K3sHomelab-Minimal.ps1 -Force
.EXAMPLE
    PS> .\Stop-K3sHomelab-Minimal.ps1 -Force -SkipDrain
.NOTES
    Requires: kubectl, ssh
    Platform: Windows, Linux, macOS (PowerShell 7+)
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipDrain,

    [Parameter()]
    [ValidateRange(30, 300)]
    [int]$Timeout = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Nodes to power off (high power consumers)
$nodesToShutdown = @(
    @{ Name = 'kubernetes1'; IP = '192.168.0.19' },
    @{ Name = 'kubernetes2'; IP = '192.168.0.20' },
    @{ Name = 'kubernetes3'; IP = '192.168.0.22' },
    @{ Name = 'kubernetes4'; IP = '192.168.0.23' },
    @{ Name = 'kubernetes6'; IP = '192.168.0.25' },
    @{ Name = 'kubernetes8-debian'; IP = '192.168.0.27' }
)

# Nodes to keep running
$nodesToKeep = @(
    @{ Name = 'nuc';         IP = '192.168.0.21' },
    @{ Name = 'kubernetes5'; IP = '192.168.0.24' },
    @{ Name = 'kubernetes7'; IP = '192.168.0.26' }
)

$sshUser = 'suryendub'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  K3s Homelab - Minimal Mode Shutdown" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nKeeping alive (Minimal Quorum):" -ForegroundColor Green
foreach ($n in $nodesToKeep) {
    Write-Host "  [+] $($n.Name) ($($n.IP))" -ForegroundColor Green
}

Write-Host "`nTargeted for Power Off:" -ForegroundColor Yellow
foreach ($n in $nodesToShutdown) {
    Write-Host "  [-] $($n.Name) ($($n.IP))" -ForegroundColor Yellow
}

if (-not $Force) {
    $confirm = Read-Host "`nProceed with minimal mode shutdown? (yes/no)"
    if ($confirm -ne 'yes') {
        Write-Host "Operation aborted by user." -ForegroundColor Yellow
        return
    }
}

# ── Credential Resolution ──────────────────────────────────────────────
$credPath = Join-Path -Path $PSScriptRoot -ChildPath "cred.xml"
$plainPass = $null

if (Test-Path -Path $credPath) {
    try {
        $sec = Import-Clixml -Path $credPath
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
    }
    catch {
        Write-Verbose "Could not import cred.xml: $_"
    }
}

if (-not $plainPass) {
    if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
        try {
            $sec = Get-Secret -Name "k3s-homelab-sudo" -ErrorAction Stop
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
        }
        catch {
            Write-Verbose "SecretStore vault item not found: $_"
        }
    }
}

# Default known fallback password if not in vault
if (-not $plainPass) {
    $plainPass = '558068'
}

$b64Pass = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($plainPass))

# ── Step 1: Cordon target nodes ────────────────────────────────────────
Write-Host "`n[1/4] Cordoning target nodes..." -ForegroundColor Yellow
foreach ($node in $nodesToShutdown) {
    $name = $node.Name
    Write-Host "  Cordoning $name..." -ForegroundColor DarkGray
    $null = kubectl cordon $name 2>$null
}
Write-Host "  [+] Cordon complete." -ForegroundColor Green

# ── Step 2: Gracefully drain target nodes ──────────────────────────────
if (-not $SkipDrain) {
    Write-Host "`n[2/4] Evicting workloads (kubectl drain, timeout: ${Timeout}s)..." -ForegroundColor Yellow
    foreach ($node in $nodesToShutdown) {
        $name = $node.Name
        Write-Host "  Draining $name..." -ForegroundColor Cyan
        $null = kubectl drain $name --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout="${Timeout}s" 2>$null
    }
    Write-Host "  [+] Drain phase complete." -ForegroundColor Green
}
else {
    Write-Host "`n[2/4] Skipping workload drain (-SkipDrain active)." -ForegroundColor Gray
}

# ── Step 3: Power off reachable nodes via SSH ──────────────────────────
Write-Host "`n[3/4] Sending shutdown signal to target nodes..." -ForegroundColor Yellow
$poweroffCmd = "echo $b64Pass | base64 -d | sudo -S poweroff"

foreach ($node in $nodesToShutdown) {
    $name = $node.Name
    $ip = $node.IP

    Write-Host "  Connecting to $name ($ip)..." -NoNewline
    # Fast pre-check if node is responding
    $tcpTest = $false
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $iar = $client.BeginConnect($ip, 22, $null, $null)
        $wh = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        if ($wh -and $client.Connected) {
            $client.EndConnect($iar)
            $tcpTest = $true
        }
        $client.Dispose()
    }
    catch {
        $tcpTest = $false
    }

    if (-not $tcpTest) {
        Write-Host " [OFFLINE/SKIPPED]" -ForegroundColor DarkGray
        continue
    }

    Write-Host " [SENDING POWEROFF]" -ForegroundColor Red
    $null = ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=4 "$sshUser@$ip" "$poweroffCmd" 2>$null
    Start-Sleep -Milliseconds 500
}

# ── Step 4: Verification ───────────────────────────────────────────────
Write-Host "`n[4/4] Verifying remaining cluster status..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Active Cluster Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
kubectl get nodes -o wide

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Minimal mode complete." -ForegroundColor Green
Write-Host "  Survivors: nuc (control plane) + kubernetes5 + kubernetes7" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

