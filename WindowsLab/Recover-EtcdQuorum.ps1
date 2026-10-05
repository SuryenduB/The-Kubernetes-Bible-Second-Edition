#Requires -Version 7.0
<#
.SYNOPSIS
    Recovers a K3s embedded-etcd cluster that has lost quorum (2 of 3 servers down).

.DESCRIPTION
    Resets the surviving server (default: nuc) to a single-member cluster from an
    on-disk etcd snapshot, using `k3s server --cluster-reset
    --cluster-reset-restore-path`. This is the standard k3s disaster-recovery path
    for lost quorum: no surviving peer is required.

    Safe to run only when the API is down due to lost quorum. Refuses to run while
    a healthy quorum exists unless -Force is given.

    After recovery, former members (e.g. server-236/server-252) must rejoin with a
    FRESH node token (see docs/operations/k3s-control-plane-ha-runbook.md) - they
    cannot simply be powered back on.

    Provenance: first used 2026-10-05 when server-236/server-252 were both powered
    off and nuc was stuck `activating` with 1/3 etcd voters. Snapshot
    etcd-snapshot-nuc-1791151204 (00:00, post-repair state) restored cleanly.

.EXAMPLE
    # Dry run: show what would happen
    .\Recover-EtcdQuorum.ps1 -DryRun

.EXAMPLE
    # Recover using the newest on-disk snapshot
    $env:SSHPASS = '<nuc sudo password>'; .\Recover-EtcdQuorum.ps1

.EXAMPLE
    # Recover from a specific snapshot
    $env:SSHPASS = '<nuc sudo password>'; .\Recover-EtcdQuorum.ps1 -SnapshotName etcd-snapshot-nuc-1791151204

.NOTES
    Node identity (nuc IP/SSH user) comes from homelab-nodes.json via
    HomelabNodes.psm1 - never hardcoded. SSH password is taken from $env:SSHPASS
    only; it is never written to disk by this script.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$SnapshotName = '',
    [string]$ServerName = 'nuc',
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$registryModule = Join-Path -Path $PSScriptRoot -ChildPath 'HomelabNodes.psm1'
if (-not (Test-Path $registryModule)) {
    throw "Node registry module not found at '$registryModule'."
}
Import-Module $registryModule -Force -DisableNameChecking

function Invoke-NodeSsh {
    param([string]$Ip, [string]$User, [string]$RemoteCommand)
    $sshArgs = @(
        '-o', 'BatchMode=no',
        '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'PreferredAuthentications=publickey,password',
        '-o', 'NumberOfPasswordPrompts=1',
        "$User@$Ip", $RemoteCommand
    )
    if ($env:SSHPASS -and (Get-Command sshpass -ErrorAction SilentlyContinue)) {
        $out = & sshpass -e ssh @sshArgs 2>&1
    } else {
        $out = & ssh @sshArgs 2>&1
    }
    return $out
}

function Invoke-NodeSudo {
    param([string]$Ip, [string]$User, [string]$RemoteCommand)
    if (-not $env:SSHPASS) { throw 'SSHPASS is not set - password sudo over SSH needs $env:SSHPASS.' }
    $wrapped = "echo '$env:SSHPASS' | sudo -S $RemoteCommand"
    return Invoke-NodeSsh -Ip $Ip -User $User -RemoteCommand $wrapped
}

# --- Resolve server identity from the registry ---
$node = Get-HomelabNode -Name $ServerName
if (-not $node) { throw "Server '$ServerName' not found in homelab-nodes.json." }
$nucIp = $node.ip
$nucUser = $node.sshUser
Write-Host "[*] Surviving server: $ServerName ($nucIp, ssh user $nucUser)"

# --- Guard: refuse while quorum is healthy ---
$apiOk = $false
try {
    $null = kubectl get nodes --request-timeout=15s 2>$null
    if ($LASTEXITCODE -eq 0) { $apiOk = $true }
} catch { $apiOk = $false }
if ($apiOk -and -not $Force -and -not $DryRun) {
    throw 'API is responsive - quorum is not lost. Nothing to do (use -Force to override).'
}
Write-Host "[*] API is unresponsive (quorum lost). Proceeding with reset."

# --- Pick snapshot (newest on-disk unless named) ---
if (-not $SnapshotName) {
    if ($DryRun -and -not $env:SSHPASS) {
        $SnapshotName = '<latest on-disk snapshot>'
    } else {
        $ls = Invoke-NodeSudo -Ip $nucIp -User $nucUser `
            -RemoteCommand 'ls -t /var/lib/rancher/k3s/server/db/snapshots/ | head -n 1'
        $SnapshotName = ($ls | Select-Object -Last 1).Trim()
        if (-not $SnapshotName) { throw 'No on-disk etcd snapshots found on the server.' }
    }
}
$snapPath = "/var/lib/rancher/k3s/server/db/snapshots/$SnapshotName"
Write-Host "[*] Snapshot: $snapPath"
if (-not $DryRun) {
    $exists = Invoke-NodeSudo -Ip $nucIp -User $nucUser -RemoteCommand "test -f $snapPath && echo PRESENT"
    if ($exists -notcontains 'PRESENT') { throw "Snapshot not found on server: $snapPath" }
}

if ($DryRun) {
    Write-Host "[DRY RUN] Would execute on ${ServerName}:"
    Write-Host "  1. systemctl stop k3s"
    Write-Host "  2. k3s server --cluster-reset --cluster-reset-restore-path $snapPath"
    Write-Host '  3. systemctl start k3s, wait for /readyz, kubectl get nodes'
    exit 0
}

if ($PSCmdlet.ShouldProcess("$ServerName ($nucIp)", "etcd cluster-reset restore from $SnapshotName")) {
    Write-Host '[1/4] Stopping k3s...'
    Invoke-NodeSudo -Ip $nucIp -User $nucUser -RemoteCommand 'systemctl stop k3s' | Out-Null
    Start-Sleep -Seconds 5

    Write-Host '[2/4] Restoring snapshot with --cluster-reset (up to ~2 min)...'
    $resetOut = Invoke-NodeSudo -Ip $nucIp -User $nucUser `
        -RemoteCommand "timeout 100 k3s server --cluster-reset --cluster-reset-restore-path $snapPath"
    $resetOut | Select-String -Pattern 'restored snapshot|new cluster|cluster-reset=true|error' | ForEach-Object { Write-Host "  $_" }
    if ($resetOut -notmatch 'restored snapshot') {
        throw 'Reset did not report "restored snapshot" - k3s left STOPPED. Inspect the server before starting it.'
    }

    Write-Host '[3/4] Starting k3s normally...'
    Invoke-NodeSudo -Ip $nucIp -User $nucUser -RemoteCommand 'systemctl start k3s' | Out-Null

    Write-Host '[4/4] Waiting for API...'
    $ready = $false
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Seconds 10
        try {
            $null = kubectl get nodes --request-timeout=10s 2>$null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        } catch { }
    }
    if (-not $ready) { throw 'API did not become ready within 4 minutes - inspect k3s on the server.' }
    kubectl get nodes
    Write-Host ''
    Write-Host '[+] Quorum recovered as single member. Next steps:'
    Write-Host '  - Run Start-K3sHomelab.ps1 -RepairStorage to reconcile workloads/storage.'
    Write-Host '  - Former members must rejoin with a FRESH token (see the HA runbook);'
    Write-Host '    do not just power them on - their old membership was trimmed.'
}
