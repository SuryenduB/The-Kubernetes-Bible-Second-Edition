#Requires -Version 7.0
<#
.SYNOPSIS
    Rejoins a former K3s server (server-236/server-252) after an etcd cluster-reset.

.DESCRIPTION
    After Recover-EtcdQuorum.ps1 trims old membership, a powered-on former member
    cannot rejoin on its own: its etcd db still references the dead 3-member
    cluster and k3s-server crash-loops. This script wipes the stale etcd state on
    the target and rejoins it to the live server (nuc) with a FRESH node token.

    Preconditions: the target host is powered on and SSH-reachable, and the API
    on the surviving server is healthy (quorum exists without the target).

    Provenance: mirrors the 2026-09-20 server-252 recovery (hypervisor-level
    outage, rejoined with a new token) and docs/operations/k3s-control-plane-ha-runbook.md.

.EXAMPLE
    # Dry run for server-236
    .\Join-EtcdMember.ps1 -NodeName server-236 -DryRun

.EXAMPLE
    # Rejoin server-236 (token passed via env, never committed)
    $env:K3S_JOIN_TOKEN = '<fresh node token from nuc>'; .\Join-EtcdMember.ps1 -NodeName server-236

.NOTES
    Node identity (IP/SSH user) comes from homelab-nodes.json via
    HomelabNodes.psm1 - never hardcoded. SSH sudo password via $env:SSHPASS;
    the join token via $env:K3S_JOIN_TOKEN or -Token. Neither is written to disk.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('server-236', 'server-252')]
    [string]$NodeName,
    [string]$Token = '',
    [string]$ServerUrl = 'https://192.168.0.21:6443',
    [string]$K3sVersion = 'v1.34.6+k3s1',
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

if (-not $Token) { $Token = $env:K3S_JOIN_TOKEN }
if (-not $Token -and -not $DryRun) { throw 'No join token: pass -Token or $env:K3S_JOIN_TOKEN (fresh node token from the surviving server).' }

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
    return Invoke-NodeSsh -Ip $Ip -User $User -RemoteCommand "echo '$env:SSHPASS' | sudo -S $RemoteCommand"
}

# --- Resolve target identity from the registry (usernames are case-sensitive) ---
$node = Get-HomelabNode -Name $NodeName
if (-not $node) { throw "Node '$NodeName' not found in homelab-nodes.json." }
$ip = $node.ip
$user = $node.sshUser
$shortOctet = $ip.Split('.')[-1]
Write-Host "[*] Target: $NodeName ($ip, ssh user $user)"

# --- Guard: API must be healthy without the target ---
$apiOk = $false
try { $null = kubectl get nodes --request-timeout=15s 2>$null; if ($LASTEXITCODE -eq 0) { $apiOk = $true } } catch { }
if (-not $apiOk -and -not $DryRun) { throw 'API is not responsive - recover quorum first (Recover-EtcdQuorum.ps1).' }
Write-Host '[*] API is healthy. Proceeding with rejoin.'

# --- Guard: target must be SSH-reachable ---
$probe = Invoke-NodeSsh -Ip $ip -User $user -RemoteCommand 'echo SSH_OK'
if ($probe -notcontains 'SSH_OK' -and -not $DryRun) { throw "Target is not SSH-reachable: $ip" }

if ($DryRun) {
    Write-Host "[DRY RUN] Would execute on ${NodeName}:"
    Write-Host '  1. systemctl stop k3s; rm -rf /var/lib/rancher/k3s/server/db/etcd (stale membership)'
    Write-Host "  2. Reinstall/pin k3s $K3sVersion and join $ServerUrl as server-$shortOctet (fresh token)"
    Write-Host '  3. Label node-role.kubernetes.io/master, verify etcd members + node Ready'
    exit 0
}

if ($PSCmdlet.ShouldProcess("$NodeName ($ip)", 'wipe stale etcd state and rejoin control plane')) {
    Write-Host '[1/4] Stopping k3s and wiping stale etcd membership...'
    Invoke-NodeSudo -Ip $ip -User $user -RemoteCommand 'systemctl stop k3s && rm -rf /var/lib/rancher/k3s/server/db/etcd' | Out-Null

    Write-Host '[2/4] Rejoining control plane (pinned version, fresh token)...'
    # Token travels in an env var so it never appears in logs; installer reads it from the environment.
    $joinCmd = "export K3S_TOKEN='$Token'; curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$K3sVersion' sh -s - server " +
        "--server $ServerUrl --node-ip $ip --node-external-ip $ip " +
        "--flannel-iface eth0 --node-name server-$shortOctet"
    Invoke-NodeSudo -Ip $ip -User $user -RemoteCommand $joinCmd | Out-Null

    Write-Host '[3/4] Applying master role label for parity...'
    kubectl label node "server-$shortOctet" node-role.kubernetes.io/master=true --overwrite 2>$null | Out-Null

    Write-Host '[4/4] Verifying membership and node status...'
    $ok = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 10
        $memberLine = kubectl get nodes --request-timeout=10s 2>$null | Select-String "server-$shortOctet\s+Ready"
        if ($memberLine) { $ok = $true; break }
    }
    if (-not $ok) { throw "server-$shortOctet did not become Ready within 5 minutes - inspect k3s on the target." }
    kubectl get nodes
    Write-Host ''
    Write-Host "[+] $NodeName rejoined. Verify quorum: kubectl get --raw='/readyz?verbose'"
}
