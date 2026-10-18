# K3s Homelab Systematic Shutdown (v10.0 - Evidence-Gated & Farewell-Gated)
#
# Control plane (since 2026-09-20): THREE embedded-etcd servers - nuc (192.168.0.21),
# server-236 (192.168.0.236) and server-252 (192.168.0.252). Powering off members spends
# etcd quorum (2 of 3), so the API answers for only the first one or two poweroffs. The
# script therefore:
#   1. snapshots each control-plane member's Longhorn attachments up front, while the API
#      is still guaranteed to answer,
#   2. powers the workers off first and the control plane last, with the primary endpoint
#      (nuc) last of all, so kubectl keeps working for as long as possible,
#   3. falls back to that snapshot once quorum is spent, and refuses (without -Force) to
#      power off a member that had volumes attached at pre-flight.
# Control-plane members are never drained, and a neverPowerOff member is never touched.
#
# v10.0 - the two smart defaults born of the 2026-10-17 kubernetes5 incident:
#   * EVIDENCE GATE: a failed drain/detach is no longer judged by exit codes alone. Every
#     node at risk of a dirty power-off is first asked whether the safety invariant holds -
#     via the API (eligible pods + volumeattachments) or, once the API is gone, node-local
#     over SSH (0 longhorn devices, 0 data mounts, only system containers running). Proven
#     clean -> poweroff proceeds; unproven -> skipped, with the evidence in the report.
#   * FINISH GATE: the control plane is never powered off while a worker is still up without
#     proof of cleanliness. Stranded workers get one invariant re-check plus one 2x-budget
#     drain retry, and only remain "in the way" if they cannot be resolved - at which point
#     the etcd members stay UP (exit code 2) and a rerun can finish the job, because the
#     API never died. -CompletePendingNodes is the post-mortem: it verifies stranded workers
#     strictly over SSH and powers off only positively-proven-clean ones.
#   * -DrainTimeoutSeconds now defaults to 600 (kubernetes5's drain failed on time, not on
#     safety: its argocd singletons were still terminating at grace 120s when 300s elapsed).
#
# Credentials (v9.2): every poweroff is an SSH login + sudo, so the login identity is resolved
# PER NODE from WindowsLab/homelab-nodes.json ("sshUser") and probed before anything is
# powered off. server-236 accepts only 'SuryenduB' (capital S) while server-252 accepts
# only 'suryendub' (lowercase, verified 2026-10-17) and the Ubuntu workers use 'suryendub' - the resolver tries the registry
# spelling plus its lowercase/capitalised forms and keeps the one that authenticates. The
# sudo password comes from the SecretStore vault ('k3s-homelab-sudo') or cred.xml, and is
# piped to 'sudo -S' base64-encoded so it never appears in the transcript.
#
# -Force skips recoverable control-flow gates, but does not bypass storage safety by itself.
# -AllowDirtyPowerOff is the explicit emergency override for attached/degraded volumes.
# recoverable failure (storage-safety gates still require -AllowDirtyPowerOff):
#   - no confirmation prompt, no abort on degraded storage / volumes still attached,
#   - an unreachable API no longer aborts an explicit -Mode Dynamic run (registry fallback),
#   - a failed kubectl drain no longer withholds that node's poweroff,
#   - every poweroff is retried with a bounded SSH connect timeout and an escalating ladder
#     (poweroff -> shutdown -h now -> systemctl poweroff -i, plus a kernel sysrq stage when
#     -ForceKernelPowerOff is also given, which bypasses systemd's orderly shutdown),
#   - success is judged by reachability, not by the ssh exit code: a *successful* poweroff
#     drops the connection and returns 255, which v8 reported as a failure.
# -Force still refuses the one thing that cannot be undone: a node flagged neverPowerOff in
# homelab-nodes.json (kubernetes7's power switch is broken, so a poweroff is unrecoverable).
# pwsh 7.0+ only: the v10 evidence gate, finish gate and -CompletePendingNodes post-mortem
# all rely on PowerShell 7 stdin piping semantics.
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(HelpMessage="Ignore prompts and continue recoverable errors, but still honor storage-safety gates unless -AllowDirtyPowerOff is also supplied. Never overrides the neverPowerOff rule.")]
    [switch]$Force,

    [Parameter(HelpMessage="Explicitly allow powering off with failed drains or attached/degraded Longhorn volumes. Dangerous: may corrupt stateful databases. Requires -Force.")]
    [switch]$AllowDirtyPowerOff,

    [Parameter(HelpMessage="With -Force: after every SSH poweroff stage has failed on a node, force a kernel-level sysrq poweroff (sync + remount-ro + power off). Bypasses systemd's orderly shutdown - last resort only.")]
    [switch]$ForceKernelPowerOff,

    [Parameter(HelpMessage="Show the full plan without changing anything (read-only kubectl queries, no SSH, no prompts)")]
    [switch]$DryRun,

    [Parameter(HelpMessage="Skip the kubectl drain process and power off immediately")]
    [switch]$SkipDrain,

    [Parameter(HelpMessage="Also power off the local Mac running this script (DANGEROUS: kills your terminal and remote access mid-test). Default: skipped.")]
    [switch]$ShutdownLocalMac,

    [Parameter(HelpMessage="Second-run completion mode (v10.0): instead of a fresh shutdown, verify every registry worker node directly over SSH and power off only those proven clean (no workloads, no Longhorn devices or mounts). Use when a previous shutdown left a worker up after the API died, so drains can no longer run. Control-plane members are never touched here.")]
    [switch]$CompletePendingNodes,

    [Parameter(HelpMessage="Discovery Mode: Auto (detect), Dynamic (Force API), Fallback (Force Hardcoded)")]
    [ValidateSet("Auto", "Dynamic", "Fallback")]
    [string]$Mode = "Auto",

    [Parameter(HelpMessage="Seconds to allow kubectl drain per node (stateful RWO workloads need time to flush; v10.0 default raised from 300 to 600 after kubernetes5 overran the old budget while argocd singletons were still terminating)")]
    [ValidateRange(60, 1800)]
    [int]$DrainTimeoutSeconds = 600,

    [Parameter(HelpMessage="Seconds to wait for Longhorn volumes to detach from a node before powering it off")]
    [ValidateRange(30, 1800)]
    [int]$DetachTimeoutSeconds = 300,

    [Parameter(HelpMessage="Poweroff attempts per node; each attempt escalates one stage (poweroff -> shutdown -h now -> systemctl poweroff -i, then sysrq with -ForceKernelPowerOff)")]
    [ValidateRange(1, 6)]
    [int]$PowerOffAttempts = 3,

    [Parameter(HelpMessage="Seconds to wait for a node to stop answering SSH after each poweroff attempt")]
    [ValidateRange(15, 600)]
    [int]$VerifyPowerOffSeconds = 45,

    [Parameter(HelpMessage="SSH connect timeout in seconds: a hung host must not stall the whole shutdown")]
    [ValidateRange(3, 120)]
    [int]$SshConnectTimeoutSeconds = 15,

    [Parameter(HelpMessage="Write a timestamped transcript + JSON outcome report to WindowsLab/logs/ (default: on). Disable with -NoLog.")]
    [switch]$NoLog,

    [Parameter(HelpMessage="Only prove that every target node has a working SSH login + sudo password (per-node identity from homelab-nodes.json), then exit. Powers nothing off and skips the degraded-storage gate; exit code 1 if any node has no usable credential.")]
    [switch]$VerifyCredentials
)

$ErrorActionPreference = 'Stop' # Critical for Catch block to trigger on external errors

if ($AllowDirtyPowerOff -and -not $Force) {
    throw "-AllowDirtyPowerOff requires -Force; refusing to permit a dirty poweroff without the emergency switch."
}

if ($CompletePendingNodes -and $AllowDirtyPowerOff) {
    throw "-CompletePendingNodes never powers off a node that is not PROVEN clean (that is its point: it runs when drains no longer can), so -AllowDirtyPowerOff has nothing to override here; the two switches are mutually exclusive."
}

if ($CompletePendingNodes -and $VerifyCredentials) {
    throw "-CompletePendingNodes and -VerifyCredentials are separate modes; run them one at a time."
}

# Native command failures (kubectl, ssh) are judged by explicit $LASTEXITCODE checks instead of
# exceptions, so a non-zero exit can never abort the run half-way through a power-down. Set the
# variable only where it exists (7.3+) to stay compatible with the declared 7.0 baseline.
if ($PSVersionTable.PSVersion -ge [version]'7.3') { $PSNativeCommandUseErrorActionPreference = $false }

# Script-scope state shared with the helper functions below (they are plain functions, so they
# cannot see the caller's parameters). DryRun makes every state-changing helper a no-op that
# prints its intent - which is also what makes this script testable without touching the lab.
$script:DryRun = [bool]$DryRun
$script:SudoPasswordSecretName = 'k3s-homelab-sudo'
# Per-node SSH identity, resolved once per run by Resolve-NodeSshUser. Node names are the keys.
# server-236/server-252 are case-sensitive (only 'SuryenduB' authenticates), so the identity can
# no longer be a hardcoded 'suryendub@' - see homelab-nodes.json "sshUser".
$script:SshUserCache = @{}

# v10.0 - EVIDENCE-BASED CLEANLINESS (the drain exit code is only a proxy).
# A drain that overruns its own timeout (argocd singletons churning at grace 120s did exactly
# that on kubernetes5, 2026-10-17) fails as a *command* while the node itself becomes safe
# seconds later, when the last terminating pods are gone. From v10 on, any node whose drain
# or detach gate failed is judged by the actual safety invariant before it may be skipped:
#   * API channel  - zero eligible (non-DaemonSet) pods on the node AND zero Longhorn
#                    volumeattachments on it, live from kubectl,
#   * node-local channel (works once the API is down) - SSH: running containers must all match
#                    the system allowlist below, /dev/longhorn/ must be empty and findmnt must
#                    show no Longhorn data mounts.
# Proven clean -> poweroff proceeds (default behaviour, no extra flag). Proven unclean or
# unverifiable -> the node is skipped, exactly as before, and the new FINISH GATE keeps the
# etcd members up so the situation stays recoverable.
$script:CleanVerdicts = @()
$script:StrandedWorkers = @()
$script:FinishGateBlocked = $false
$script:NodeLocalSystemContainerPattern =
    '^(longhorn|csi|node-driver-registrar|liveness-probe|engine-image|cleanup-loop|premount|pre-pull|remount|fixer|registry-fixer|beszel|svclb|lb-tcp|traefik|kube-|local-path|helm-install|wait)'

# v9.3 - NO SINGLE ERROR ENDS THE RUN.
# A shutdown that stops at the first error is the worst outcome available: part of the fleet is
# down, the control plane is up, and nothing explains what happened. Every *recoverable* failure
# (a node's drain, a credential, an API query, a phase blowing up) is therefore recorded here and
# the run continues with the remaining nodes and phases. Failures surface three times - in the
# transcript, in the JSON report ("errors") and in the exit code - so "kept going" never means
# "pretended it worked". Only the neverPowerOff safety net is still a hard stop, because that
# power-off is physically unrecoverable.
$script:RunErrors = @()

# Shared with the report: initialised up front so a phase that fails early can never make the
# report itself fail on an undefined variable.
$credentialReport = @()
$credentialFailures = @()
$masterPreCheck = @{}
# Set by the -VerifyCredentials path (it writes its own report, so the shutdown finalizer must not
# overwrite it). ExitCode is only ever *raised* to 1, never reset, so a gate that exits non-zero
# keeps its code through the finalizer.
$script:ReportAlreadyWritten = $false
$script:ExitCode = 0

if ($DryRun -and $ForceKernelPowerOff) {
    Write-Host "[DRYRUN] Dry run: the kernel poweroff stage will only be described, not issued." -ForegroundColor DarkGray
}

# --- CONFIGURATION (fallback derived from the shared node registry) ---
# WindowsLab/homelab-nodes.json is the single source of truth for node identity and for
# the 'never power off' constraint (kubernetes7's power switch is broken).
$registryModule = Join-Path -Path $PSScriptRoot -ChildPath 'HomelabNodes.psm1'
if (-not (Test-Path -Path $registryModule)) {
    throw "Node registry module not found at '$registryModule'. Restore WindowsLab/HomelabNodes.psm1 and WindowsLab/homelab-nodes.json from git."
}
Import-Module $registryModule -Force -DisableNameChecking

$neverPowerOff = @(Get-NeverPowerOffNodeNames)
$registryNodes = @(Get-HomelabNodes)
$masterRecord = @($registryNodes | Where-Object { $_.role -eq 'control-plane' } | Select-Object -First 1)
if ($masterRecord.Count -eq 0) {
    throw "No control-plane node is defined in homelab-nodes.json."
}
$masterFallback = @{ Name = $masterRecord[0].name; IP = $masterRecord[0].ip }
$workerFallback = @(
    $registryNodes |
        Where-Object { $_.role -ne 'control-plane' -and ($neverPowerOff -notcontains $_.name) } |
        ForEach-Object { @{ Name = $_.name; IP = $_.ip } }
)

Write-Host "--- K3s Cluster Shutdown Sequence (v10.0) ---" -ForegroundColor Cyan

# --- RUN LOGGING (v9.1): every run writes a transcript + JSON report to
#     WindowsLab/logs/ unless -NoLog is given. This is what was missing when
#     the "last knight" run failed silently: the only evidence was a stale
#     WindowsLab/shutdown.log from June. Log name: shutdown-YYYYMMDD-HHMMSS.log
#     plus a matching .json outcome report (down / still-up / skipped per node).
$script:LogPath = $null
$script:ReportPath = $null
$script:RunStartedAt = Get-Date
if (-not $NoLog) {
    $logDir = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
    if (-not (Test-Path -Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogPath = Join-Path -Path $logDir -ChildPath "shutdown-$stamp.log"
    $script:ReportPath = Join-Path -Path $logDir -ChildPath "shutdown-report-$stamp.json"
    try { Start-Transcript -Path $script:LogPath -Append | Out-Null } catch {
        Write-Host "[!] Could not start transcript at $($script:LogPath): $($_.Exception.Message)" -ForegroundColor Yellow
        $script:LogPath = $null
    }
    Write-Host "Logging to: $($script:LogPath)" -ForegroundColor DarkGray
    Write-Host "Report will be: $($script:ReportPath)" -ForegroundColor DarkGray
}

# --- Storage-safe helpers: a node must not lose power while Longhorn still has
#     live attachments on it. Unclean detachment is what wedges engine frontends
#     ('Can't open blockdev' on next boot) and forces instance-manager surgery. ---
function Get-NodeSshArgument {
    <#
    .SYNOPSIS
        Shared ssh argument list: non-interactive, throwaway known_hosts and a *bounded* connect
        timeout (v8 had none, so an unresponsive host could stall the shutdown for the kernel's
        ~75s TCP timeout on every node).
    .DESCRIPTION
        The login identity is a parameter, never a hardcoded literal: server-236 and server-252
        only accept the case-sensitive 'SuryenduB', while every other node uses 'suryendub'.
        NumberOfPasswordPrompts=1 keeps a wrong identity from stalling through three retries.
    #>
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter()][string]$SshUser = 'suryendub',
        [int]$ConnectTimeoutSeconds = 15
    )
    return @('-n', '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
        '-o', "ConnectTimeout=$ConnectTimeoutSeconds", '-o', 'ConnectionAttempts=1',
        '-o', 'NumberOfPasswordPrompts=1', '-o', 'PreferredAuthentications=publickey,password',
        "$SshUser@$IP")
}

function Get-NodeSshUserCandidate {
    <#
    .SYNOPSIS
        Candidate login identities for one node, best guess first: the registry 'sshUser', then its
        all-lowercase and capitalised spellings.
    .DESCRIPTION
        homelab-nodes.json is the source of truth, but a username whose case is wrong is
        indistinguishable from a wrong password at the SSH layer - so instead of trusting one
        spelling we try the three shapes that matter and let authentication decide. Defaults to
        'suryendub' when a node has no sshUser in the registry.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$NodeName
    )

    $registryUser = ''
    try {
        $record = Get-HomelabNode -Name $NodeName
        if ($record -and $record.PSObject.Properties['sshUser'] -and -not [string]::IsNullOrWhiteSpace($record.sshUser)) {
            $registryUser = [string]$record.sshUser
        }
    }
    catch {
        # A node absent from the registry is not fatal here: the default identity still works.
        Write-Verbose "Node '$NodeName' has no registry record or sshUser; falling back to 'suryendub'."
    }
    if ([string]::IsNullOrWhiteSpace($registryUser)) { $registryUser = 'suryendub' }

    $candidates = @()
    $shapes = @(
        $registryUser,
        $registryUser.ToLowerInvariant(),
        ($registryUser.Substring(0, 1).ToUpperInvariant() + $registryUser.Substring(1).ToLowerInvariant())
    )
    foreach ($shape in $shapes) {
        if (-not [string]::IsNullOrWhiteSpace($shape) -and ($candidates -notcontains $shape)) { $candidates += $shape }
    }
    return $candidates
}

function Test-NodeSshCredential {
    <#
    .SYNOPSIS
        $true when $SshUser can log in to $IP with the SSH password already in $env:SSHPASS.
        Read-only: it runs 'echo' remotely and changes nothing on the node.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$SshUser,
        [int]$ConnectTimeoutSeconds = 10
    )

    $marker = 'HOMELAB-CRED-OK'
    $sshArgs = @(Get-NodeSshArgument -IP $IP -SshUser $SshUser -ConnectTimeoutSeconds $ConnectTimeoutSeconds) + @("echo $marker")
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = if (Test-Path -Path '/usr/local/bin/sshpass') {
            & /usr/local/bin/sshpass -e ssh @sshArgs 2>&1
        }
        elseif (Get-Command sshpass -ErrorAction SilentlyContinue) {
            & sshpass -e ssh @sshArgs 2>&1
        }
        else {
            # No sshpass: only key-based authentication can succeed here.
            & ssh @sshArgs 2>&1
        }
        return ((@($output) -join ' ').Contains($marker))
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Test-NodeSudoCredential {
    <#
    .SYNOPSIS
        $true when the sudo password in $env:SSHPASS is accepted by $SshUser@$IP.
    .DESCRIPTION
        Login is only half of a poweroff: the ladder pipes this same password into 'sudo -S'. The
        probe therefore runs 'sudo -k true' - '-k' discards any cached sudo ticket, so a stale
        timestamp can never make a wrong password look valid - with '-p ""' so the prompt prints
        nothing and the password only travels over the base64-encoded stdin pipeline.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$SshUser,
        [int]$ConnectTimeoutSeconds = 10
    )

    if ([string]::IsNullOrEmpty($env:SSHPASS)) { return $false }
    $marker = 'HOMELAB-SUDO-OK'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:SSHPASS))
    $remote = "echo $encoded | base64 -d | sudo -S -p '' -k true 2>/dev/null && echo $marker"
    $sshArgs = @(Get-NodeSshArgument -IP $IP -SshUser $SshUser -ConnectTimeoutSeconds $ConnectTimeoutSeconds) + @($remote)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = if (Test-Path -Path '/usr/local/bin/sshpass') {
            & /usr/local/bin/sshpass -e ssh @sshArgs 2>&1
        }
        elseif (Get-Command sshpass -ErrorAction SilentlyContinue) {
            & sshpass -e ssh @sshArgs 2>&1
        }
        else {
            & ssh @sshArgs 2>&1
        }
        return ((@($output) -join ' ').Contains($marker))
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Resolve-NodeSshUser {


    <#
    .SYNOPSIS
        The login identity that actually authenticates to a node, cached for the run.
    .DESCRIPTION
        Probes the candidates from Get-NodeSshUserCandidate in order and returns the first that logs
        in. Probing is skipped (the registry identity is returned as-is) when there is no password to
        probe with: -DryRun, or an environment where $env:SSHPASS was never set. A node nobody can
        authenticate to keeps its registry identity, so the poweroff ladder reports the real failure
        instead of silently switching accounts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [Parameter(Mandatory)][string]$IP,
        [switch]$NoProbe
    )

    if ($script:SshUserCache.ContainsKey($NodeName)) { return $script:SshUserCache[$NodeName] }

    $candidates = @(Get-NodeSshUserCandidate -NodeName $NodeName)
    $resolved = $candidates[0]

    $canProbe = (-not $NoProbe) -and (-not $script:DryRun) -and (-not [string]::IsNullOrEmpty($env:SSHPASS))
    if ($canProbe) {
        $matched = $null
        foreach ($candidate in $candidates) {
            if (Test-NodeSshCredential -IP $IP -SshUser $candidate) { $matched = $candidate; break }
        }
        if ($matched) {
            $resolved = $matched
            if ($matched -ne $candidates[0]) {
                Write-Host "  [i] $NodeName authenticates as '$matched' (registry lists '$($candidates[0])' - fix sshUser in homelab-nodes.json)." -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "  [!] No registered SSH identity could authenticate to $NodeName ($IP); tried: $($candidates -join ', ')." -ForegroundColor Yellow
        }
    }

    $script:SshUserCache[$NodeName] = $resolved
    return $resolved
}


function Invoke-NodeSshAttempt {

    <#
    .SYNOPSIS
        Runs a remote command and *returns* the ssh exit code instead of throwing.
        The retry ladder in Stop-HomelabNode needs that code, because a poweroff normally
        returns 255 (the host drops the connection as it goes down) - that is success, not
        failure.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$RemoteCommand,
        [Parameter()][string]$SshUser = 'suryendub',
        [int]$ConnectTimeoutSeconds = 15
    )
    $sshArgs = @(Get-NodeSshArgument -IP $IP -SshUser $SshUser -ConnectTimeoutSeconds $ConnectTimeoutSeconds) + @($RemoteCommand)
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        & sshpass -e ssh @sshArgs
    }
    elseif (Test-Path "/usr/local/bin/sshpass") {
        & /usr/local/bin/sshpass -e ssh @sshArgs
    }
    else {
        & ssh @sshArgs
    }
    return $LASTEXITCODE
}

function Invoke-KubectlCommand {
    <#
    .SYNOPSIS
        Runs a mutating kubectl command, throwing when it fails; -DryRun only prints it.
        The exit code is checked explicitly because PowerShell does not turn a native non-zero
        exit into a terminating error by itself.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments
    )
    if ($script:DryRun) {
        Write-Host "  [DRYRUN] kubectl $($Arguments -join ' ')" -ForegroundColor DarkGray
        return
    }
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Test-NodeTcpPort {
    <#
    .SYNOPSIS
        $true when the node accepts a TCP connection on the given port (port 22 = still up).
        Same TcpClient pre-check pattern as Stop-K3sHomelab-Minimal.ps1, without spawning a tool.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$Port = 22,
        [int]$TimeoutMs = 2000
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($IP, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Get-NodeAttachedVolumes {
    <#
    .SYNOPSIS
        PV names with a live Longhorn attachment on the given node (empty = safe to power off).
    .DESCRIPTION
        The exit code is checked explicitly: on an unreachable API kubectl returns non-zero and
        ConvertFrom-Json turns the empty pipeline into $null WITHOUT throwing. Treating that as
        "nothing attached" would let the storage gate wave a node through while it still holds live
        Longhorn attachments - the exact unclean-detach scenario this gate exists to prevent.
    #>
    param([Parameter(Mandatory)][string]$NodeName)
    try {
        $attachments = kubectl get volumeattachment -o json --request-timeout=15s | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $attachments) { return @('UNKNOWN-API-FAILURE') }
    }
    catch { return @('UNKNOWN-API-FAILURE') }
    $attached = @()
    foreach ($item in @($attachments.items)) {
        if ($item.spec.attacher -eq 'driver.longhorn.io' -and
            $item.spec.nodeName -eq $NodeName -and
            $item.status.attached -eq $true) {
            $attached += [string]$item.spec.source.persistentVolumeName
        }
    }
    return $attached
}

function Wait-NodeVolumesDetached {
    <#
    .SYNOPSIS
        Polls until no Longhorn volume stays attached to the node (or the timeout expires).
        Returns $true when the node is storage-clean.
    #>
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [int]$TimeoutSeconds = 300
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $remaining = @(Get-NodeAttachedVolumes -NodeName $NodeName)
        if ($remaining.Count -eq 0) { return $true }
        if ($remaining -contains 'UNKNOWN-API-FAILURE') {
            Write-Host "  [!] Could not query volumeattachments; assuming still attached." -ForegroundColor Yellow
        }
        else {
            Write-Host "  ... waiting for detach on ${NodeName}: $($remaining -join ', ')" -ForegroundColor Gray
        }
        Start-Sleep -Seconds 15
    }
    return $false
}

function Get-DegradedLonghornVolumes {
    <#
    .SYNOPSIS
        Attached Longhorn volumes whose robustness is not healthy (shutting down now risks data).
    .DESCRIPTION
        Exit code checked explicitly (v9.3): a failed kubectl query must report UNKNOWN, never
        "no degraded volumes" - otherwise an unreachable API reads as "all healthy" and the
        pre-flight gate would approve a power-down it could not actually verify.
    #>
    $degraded = @()
    try {
        $volumes = kubectl get volumes.longhorn.io -n longhorn-system -o json --request-timeout=15s | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $volumes) { return @('UNKNOWN-API-FAILURE') }
    }
    catch { return @('UNKNOWN-API-FAILURE') }
    foreach ($volume in @($volumes.items)) {
        if ($volume.status.state -eq 'attached' -and $volume.status.robustness -ne 'healthy') {
            $degraded += ("{0} ({1}/{2})" -f $volume.metadata.name, $volume.status.state, $volume.status.robustness)
        }
    }
    return $degraded
}

function Test-ApiReachable {
    <#
    .SYNOPSIS
        Fast probe: is the Kubernetes API answering? Used by the control-plane phase, because
        powering off control-plane members spends etcd quorum, after which kubectl cannot answer.
    #>
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & kubectl get --raw='/readyz' --request-timeout=10s 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Get-NodeEligibleWorkloads {
    <#
    .SYNOPSIS
        Names of the pods the API still reports on the node that a full power-off would kill
        outright: Running/Pending, already terminating, NOT owned by a DaemonSet.
        DaemonSet pods (Longhorn manager, CSI, svclb, beszel-agent...) are part of the node's
        infrastructure: kubelet respawns them on boot, so they are not a reason to withhold.
        Returns the sentinel 'UNKNOWN-API-FAILURE' when kubectl cannot answer, so an unreachable
        API can never read as "no workloads" (same convention as Get-NodeAttachedVolumes).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$NodeName)

    try {
        $pods = kubectl get pods -A -o json --request-timeout=15s 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $pods) { return @('UNKNOWN-API-FAILURE') }
    }
    catch { return @('UNKNOWN-API-FAILURE') }

    $eligible = @()
    foreach ($pod in @($pods.items)) {
        if ([string]$pod.spec.nodeName -ne $NodeName) { continue }
        $phase = [string]$pod.status.phase
        if ($phase -notin @('Running', 'Pending')) { continue }
        $owners = @($pod.metadata.ownerReferences | Where-Object { $_.kind -eq 'DaemonSet' })
        if ($owners.Count -gt 0) { continue }
        if ($pod.metadata.deletionTimestamp) {
            $eligible += "terminating: $($pod.metadata.namespace)/$($pod.metadata.name)"
        }
        else {
            $eligible += "$($pod.metadata.namespace)/$($pod.metadata.name) ($phase)"
        }
    }
    return $eligible
}

function Assert-NodeCleanViaApi {
    <#
    .SYNOPSIS
        The API-channel half of the cleanliness invariant: no attached Longhorn volumes and no
        eligible workloads on the node, both asked live from kubectl.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$NodeName)

    $evidence = @()
    $attached = @(Get-NodeAttachedVolumes -NodeName $NodeName)
    if ($attached -contains 'UNKNOWN-API-FAILURE') {
        return [pscustomobject]@{ Node = $NodeName; Channel = 'api'; Clean = $null; Evidence = @('kubectl volumeattachment query failed') }
    }
    if ($attached.Count -gt 0) { $evidence += "attached volumes: $($attached -join ', ')" }

    $workloads = @(Get-NodeEligibleWorkloads -NodeName $NodeName)
    if ($workloads -contains 'UNKNOWN-API-FAILURE') {
        return [pscustomobject]@{ Node = $NodeName; Channel = 'api'; Clean = $null; Evidence = @('kubectl pod query failed') }
    }
    if ($workloads.Count -gt 0) { $evidence += ("eligible workloads still on node: " + ($workloads -join ', ')) }

    return [pscustomobject]@{
        Node     = $NodeName
        Channel  = 'api'
        Clean    = ($evidence.Count -eq 0)
        Evidence = if ($evidence.Count -eq 0) { @('no eligible workloads, no attached volumes') } else { $evidence }
    }
}

function Invoke-NodeLocalCleanlinessProbe {
    <#
    .SYNOPSIS
        The node-local channel: SSH + sudo, three plain facts with the API dead and drains gone -
        (a) Longhorn block devices present, (b) Longhorn data mounts held, (c) the containers
        that are still running. Mirrors the sudo-stdin pipeline of the poweroff ladder
        (base64 password on the first line, script body after it) WITHOUT ssh's -n, which
        would eat the stdin the password travels on.
    .DESCRIPTION
        Password transport reuses the ladder's convention: 'echo <b64> | base64 -d | sudo -S',
        so the plaintext never appears in argv or in the transcript. crictl output is parsed by
        column NAME discovered from the table header - no awk column-index guessing.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'The value is the base64 encoding of the sudo password; the SecureString itself never leaves the orchestrator.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter()][string]$SshUser = 'suryendub',
        [int]$ConnectTimeoutSeconds = 15
    )

    if (-not (Test-NodeTcpPort -IP $IP -Port 22)) {
        return [pscustomobject]@{ Success = $false; Reason = 'TCP 22 not answering (node appears down - nothing to verify)'; Devices = @(); Mounts = @(); ContainerNames = @() }
    }
    if ([string]::IsNullOrEmpty($env:SSHPASS)) {
        return [pscustomobject]@{ Success = $false; Reason = 'no sudo password in SSHPASS'; Devices = @(); Mounts = @(); ContainerNames = @() }
    }

    $body = @'
echo CLN-BEGIN
echo CLN-SECTION devices
ls -1 /dev/longhorn/ 2>/dev/null || true
echo CLN-SECTION mounts
findmnt -l -n -o SOURCE,TARGET 2>/dev/null | grep '/dev/longhorn' || true
echo CLN-SECTION containers
crictl ps --state Running 2>/dev/null || true
echo CLN-END
'@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:SSHPASS))
    $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
        '-o', "ConnectTimeout=$ConnectTimeoutSeconds", '-o', 'ConnectionAttempts=1',
        '-o', 'NumberOfPasswordPrompts=1', '-o', 'PreferredAuthentications=publickey,password',
        "$SshUser@$IP", "sudo -S -p '' bash -s")

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # sshpass -e takes the password from the environment, so the pipeline flows to the
        # remote stdin: sudo -S consumes the first line, bash -s executes the remainder.
        $output = ("$encoded`n$body" | sshpass -e ssh @sshArgs) 2>&1
    }
    catch {
        return [pscustomobject]@{ Success = $false; Reason = "ssh transport problem: $($_.Exception.Message)"; Devices = @(); Mounts = @(); ContainerNames = @() }
    }
    finally {
        $ErrorActionPreference = $previous
    }

    $lines = @($output | ForEach-Object { [string]$_ })
    if (-not (($lines -join ' ').Contains('CLN-END'))) {
        return [pscustomobject]@{ Success = $false; Reason = 'remote probe did not complete (sudo rejected, or crictl unavailable)'; Devices = @(); Mounts = @(); ContainerNames = @() }
    }

    # Sectioned parsing between markers, immune to prompt noise from sudo.
    $devices = @(); $mounts = @(); $containerNames = @()
    $section = ''
    $nameColumn = $null
    foreach ($line in $lines) {
        if ($line -eq 'CLN-SECTION devices') { $section = 'devices'; continue }
        if ($line -eq 'CLN-SECTION mounts') { $section = 'mounts'; continue }
        if ($line -eq 'CLN-SECTION containers') { $section = 'containers'; continue }
        if ($line -eq 'CLN-BEGIN' -or $line -eq 'CLN-END') { continue }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(SUDOPW|Warning:|Welcome|Last login|)') { continue }
        switch ($section) {
            'devices' {
                # ls output is a bare listing; anything real is a device that holds frontend data.
                if ($line -notmatch '^(sudo|bash|ls):') { $devices += $line.Trim() }
            }
            'mounts' {
                if ($line -like '/dev/longhorn*') { $mounts += $line.Trim() }
            }
            'containers' {
                $tokens = @($line -split '\s+' | Where-Object { $_ -ne '' })
                if ($tokens.Contains('NAME')) {
                    # Table header: locate the NAME column once, then read it per row - no
                    # fixed column index that a crictl version bump could invalidate.
                    $nameColumn = $null
                    for ($i = 0; $i -lt $tokens.Count; $i++) { if ($tokens[$i] -eq 'NAME') { $nameColumn = $i } }
                    continue
                }
                if ($null -ne $nameColumn -and $tokens.Count -gt $nameColumn) {
                    $containerNames += $tokens[$nameColumn]
                }
            }
        }
    }
    $containerNames = @($containerNames | Where-Object { $_ -and $_ -ne 'N/A' })
    return [pscustomobject]@{ Success = $true; Reason = ''; Devices = $devices; Mounts = $mounts; ContainerNames = $containerNames }
}

function Assert-NodeCleanLocally {
    <#
    .SYNOPSIS
        Judge the cleanliness invariant from node-local facts only (API-independent).
        Clean = zero Longhorn devices, zero Longhorn data mounts, and every running container
        matches $script:NodeLocalSystemContainerPattern (Longhorn/CSI/svclb/agent plumbing).
        One unknown (non-allowlist) container name -> NOT clean, with the name in the evidence.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [Parameter(Mandatory)][string]$IP
    )

    $sshUser = Resolve-NodeSshUser -NodeName $NodeName -IP $IP
    $probe = Invoke-NodeLocalCleanlinessProbe -IP $IP -SshUser $sshUser
    if (-not $probe.Success) {
        return [pscustomobject]@{ Node = $NodeName; Channel = 'node-local'; Clean = $null; Evidence = @($probe.Reason) }
    }

    $evidence = @()
    if (@($probe.Devices).Count -gt 0) { $evidence += "longhorn devices present: $(@($probe.Devices) -join ', ')" }
    if (@($probe.Mounts).Count -gt 0) { $evidence += "longhorn mounts held: $(@($probe.Mounts) -join ', ')" }
    $offenders = @(@($probe.ContainerNames) | Where-Object { $_ -notmatch $script:NodeLocalSystemContainerPattern })
    if ($offenders.Count -gt 0) { $evidence += "containers outside the system allowlist: $($offenders -join ', ')" }

    return [pscustomobject]@{
        Node     = $NodeName
        Channel  = 'node-local'
        Clean    = ($evidence.Count -eq 0)
        Evidence = if ($evidence.Count -eq 0) { @("clean: 0 devices, 0 mounts, $(@($probe.ContainerNames).Count) system containers only") } else { $evidence }
    }
}

function Assert-NodeCleanliness {
    <#
    .SYNOPSIS
        The decision helper callers use: API channel first (fast, authoritative), node-local
        channel as the fallback when the API cannot answer. DryRun prints intent and returns
        an unknown verdict so nothing downstream acts on it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [Parameter(Mandatory)][string]$IP
    )

    if ($script:DryRun) {
        Write-Host "  [DRYRUN] would verify cleanliness on ${NodeName}: eligible pods + volumeattachments via the API, or SSH probe (devices/mounts/container allowlist) when the API is down." -ForegroundColor DarkGray
        return [pscustomobject]@{ Node = $NodeName; Channel = 'dryrun'; Clean = $null; Evidence = @('dry run - not verified') }
    }

    if (Test-ApiReachable) {
        $api = Assert-NodeCleanViaApi -NodeName $NodeName
        if ($null -ne $api.Clean) { return $api }
    }
    return (Assert-NodeCleanLocally -NodeName $NodeName -IP $IP)
}

function Add-CleanVerdict {
    <#
    .SYNOPSIS
        One line in the transcript + one record in the report for every cleanliness decision,
        so "why did this node get skipped / powered off with a failed drain" is answerable
        without reading the whole transcript.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [Parameter(Mandatory)][string]$Verdict,
        [Parameter(Mandatory)][string]$Channel,
        [string[]]$Evidence = @()
    )
    $script:CleanVerdicts += [pscustomobject]@{
        node     = $NodeName
        verdict  = $Verdict
        channel  = $Channel
        evidence = @($Evidence)
        at       = (Get-Date).ToString('o')
    }
    Write-Host "  [i] cleanliness verdict [$NodeName]: $Verdict ($Channel) $(@($Evidence) -join '; ')" -ForegroundColor DarkGray
}


function Get-K8sNodeReadiness {
    <#
    .SYNOPSIS
        The node's Ready condition ('True'/'False'/'Unknown'), or $null when the API cannot
        answer (expected once etcd quorum is spent). Secondary evidence only - never a gate.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$NodeName)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $state = & kubectl get node $NodeName -o json --request-timeout=10s 2>$null | ConvertFrom-Json
        if (-not $state) { return $null }
        $ready = @($state.status.conditions | Where-Object { $_.type -eq 'Ready' })
        if ($ready.Count -eq 0) { return 'Unknown' }
        return [string]$ready[0].status
    }
    catch {
        return $null
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Wait-NodeDown {
    <#
    .SYNOPSIS
        Polls until the node stops answering on its SSH port (or the timeout expires).
        Powering off is asynchronous, so the ssh exit code alone proves nothing.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$NodeName,
        [int]$TimeoutSeconds = 45
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-NodeTcpPort -IP $IP -Port 22)) { return $true }
        $ready = Get-K8sNodeReadiness -NodeName $NodeName
        $evidence = if ($null -eq $ready) { 'API not answering' } else { "Ready=$ready" }
        Write-Host "  ... $NodeName still answering on TCP 22 ($evidence)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
    return (-not (Test-NodeTcpPort -IP $IP -Port 22))
}

function Stop-HomelabNode {
    <#
    .SYNOPSIS
        Powers one node off through an escalating ladder and verifies that it really went down.
        Returns an outcome object instead of throwing, so one stubborn host can never abort the
        rest of the shutdown. Down=$null means "not attempted" (-DryRun).
    .DESCRIPTION
        The ladder is built one entry per attempt: the graceful stages first (the last graceful
        stage repeats when more attempts are requested than there are stages), then - only with
        -AllowKernelPowerOff - the kernel stage as the FINAL entry:
          1. sudo poweroff
          2. sudo shutdown -h now
          3. sudo systemctl poweroff -i
          4. sysrq sync + remount-ro + poweroff (opt-in via -ForceKernelPowerOff)
        Stage 4 exists because a hung systemd shutdown is exactly the case where a node "still
        reports Ready after poweroff"; it bypasses orderly service shutdown, so it is only ever
        reached after the graceful stages have failed.
        Success is judged by reachability (TCP 22 closes), never by the ssh exit code.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Internal helper: state changes are gated by the script-level -Force/-DryRun/-SkipDrain switches, and -DryRun prints instead of acting.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'The value is already the base64 encoding of the sudo password, which is what the remote "base64 -d | sudo -S" pipeline consumes; the SecureString itself never leaves the orchestrator.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',
        Justification = 'Not an authentication pair: -SshUser is the per-node login account (from homelab-nodes.json, case-sensitive on server-236/252) while -EncodedPassword is the base64 sudo password piped to the remote sudo -S. Both are sent over separate channels, and neither is a PSCredential.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [Parameter(Mandatory)][string]$IP,
        # Not mandatory: -DryRun sends nothing, so it passes an empty string.
        [Parameter()][string]$EncodedPassword = '',
        # Login identity for THIS node. Resolved from the registry (and probed) when left empty.
        [Parameter()][string]$SshUser = '',
        [int]$MaxAttempts = 3,
        [int]$ConnectTimeoutSeconds = 15,
        [int]$VerifyTimeoutSeconds = 45,
        [switch]$AllowKernelPowerOff
    )

    if (-not $script:DryRun -and [string]::IsNullOrEmpty($EncodedPassword)) {
        throw "No sudo password was resolved for $NodeName; refusing to send an unauthenticated poweroff."
    }

    # Per-node identity: 'suryendub' on the Ubuntu workers, case-sensitive 'SuryenduB' on
    # server-236/server-252. Resolve-NodeSshUser probes the registry candidates and caches the
    # winner, so a wrong-case username can no longer masquerade as a wrong password.
    if ([string]::IsNullOrWhiteSpace($SshUser)) {
        $SshUser = Resolve-NodeSshUser -NodeName $NodeName -IP $IP
    }
    Write-Host "  - SSH identity: $SshUser@$IP" -ForegroundColor DarkGray

    $gracefulStages = [ordered]@{
        'sudo poweroff'              = "echo $EncodedPassword | base64 -d | sudo -S poweroff"
        'sudo shutdown -h now'       = "echo $EncodedPassword | base64 -d | sudo -S shutdown -h now"
        'sudo systemctl poweroff -i' = "echo $EncodedPassword | base64 -d | sudo -S systemctl poweroff -i"
    }
    $gracefulNames = @($gracefulStages.Keys)

    # One ladder entry per attempt: the graceful stages first (the last stage repeats when more
    # attempts are requested than there are stages), then - only with -AllowKernelPowerOff - the
    # kernel stage as the FINAL entry. Building the ladder up front matters: mapping attempts 1:1
    # onto a four-entry stage list would mean the default -PowerOffAttempts 3 never reaches the
    # kernel stage at all.
    $ladder = @(
        foreach ($i in 0..($MaxAttempts - 1)) {
            $label = $gracefulNames[[Math]::Min($i, $gracefulNames.Count - 1)]
            [pscustomobject]@{ Label = $label; Command = $gracefulStages[$label] }
        }
    )
    if ($AllowKernelPowerOff) {
        $ladder += [pscustomobject]@{
            Label   = 'sysrq sync + remount-ro + poweroff'
            Command = "echo $EncodedPassword | base64 -d | sudo -S sh -c 'echo 1 > /proc/sys/kernel/sysrq; sync; echo s > /proc/sysrq-trigger; sleep 1; echo u > /proc/sysrq-trigger; sleep 1; echo o > /proc/sysrq-trigger'"
        }
    }

    if ($script:DryRun) {
        Write-Host "  [DRYRUN] would power off $NodeName ($IP) as '$SshUser' through: $((@($ladder.Label)) -join ' -> ')" -ForegroundColor DarkGray
        return [pscustomobject]@{ Node = $NodeName; IP = $IP; SshUser = $SshUser; Down = $null; Stage = 'dryrun'; Attempts = 0 }
    }

    for ($attempt = 1; $attempt -le $ladder.Count; $attempt++) {
        $stage = $ladder[$attempt - 1]
        Write-Host "  - Poweroff attempt $attempt/$($ladder.Count) on $NodeName ($($stage.Label))..."
        try {
            $exitCode = Invoke-NodeSshAttempt -IP $IP -SshUser $SshUser -RemoteCommand $stage.Command -ConnectTimeoutSeconds $ConnectTimeoutSeconds
            Write-Host "    ssh exit code $exitCode (255 normally means the host dropped the connection as it powered off)." -ForegroundColor DarkGray
        }
        catch {
            # ssh/sshpass itself could not be launched: report it and still verify, because the
            # host may already have gone down before the client gave up.
            Write-Host "  [!] ssh transport problem for ${NodeName}: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if (Wait-NodeDown -IP $IP -NodeName $NodeName -TimeoutSeconds $VerifyTimeoutSeconds) {
            return [pscustomobject]@{ Node = $NodeName; IP = $IP; SshUser = $SshUser; Down = $true; Stage = $stage.Label; Attempts = $attempt }
        }
        Write-Host "  [!] $NodeName still answering after '$($stage.Label)'." -ForegroundColor Yellow
    }

    return [pscustomobject]@{ Node = $NodeName; IP = $IP; SshUser = $SshUser; Down = $false; Stage = 'exhausted'; Attempts = $ladder.Count }
}

function Add-RunError {
    <#
    .SYNOPSIS
        Records a recoverable failure (context + message) for the report and keeps the run alive.
    .DESCRIPTION
        Print-and-continue is the whole point (see the v9.3 note at the top): a shutdown is a
        one-way operation across a fleet, so stopping half-way leaves the cluster in a state that
        is harder to recover than any single failed step. Callers pass a short context such as
        'drain:kubernetes3' or 'phase:pre-flight-credentials' so the JSON report can be read
        without the transcript.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$Message
    )

    $script:RunErrors += [pscustomobject]@{
        context = $Context
        message = $Message
        at      = (Get-Date).ToString('o')
    }
    Write-Host "  [!] Error recorded [$Context]: $Message" -ForegroundColor Yellow
    Write-Host "      Continuing: the remaining nodes and phases are still processed." -ForegroundColor DarkGray
}

# 1. DISCOVERY LOGIC
$targets = @()
# K3s HA: every control-plane member is its own target and is powered off LAST, so etcd
# keeps quorum while the workers are drained. The primary (registry's first control-plane
# record, i.e. nuc) is powered off last of all because kubectl talks to 192.168.0.21:6443.
$masterTargets = @()
$masterIp = $null
$actualMode = ""

if ($Mode -eq "Fallback") {
    $actualMode = "FALLBACK"
} else {
    try {
        Write-Host "Attempting dynamic node discovery..." -ForegroundColor Gray
        # Correct flag is --request-timeout
        # 'allNodes' collides with the PowerShell automatic variable; keep it prefixed.
        # Exit code is checked explicitly: kubectl prints its errors on stderr and returns non-zero,
        # and piping that into ConvertFrom-Json yields $null without throwing - which would make an
        # unreachable API look like an EMPTY cluster instead of a failure (v9.3).
        $registryAllNodes = kubectl get nodes -o json --request-timeout=10s | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $registryAllNodes) {
            throw "kubectl get nodes failed (exit code $LASTEXITCODE): the API is not answering."
        }

        function Get-IPv4 {
            param($addresses)
            return ($addresses | Where-Object { $_.type -eq 'InternalIP' -and $_.address -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1 -ExpandProperty address)
        }

        # K3s HA: this cluster has several control-plane members sharing the role labels.
        # Match them ALL - matching only "the" master would leave the other etcd members in
        # the worker list, where they would be drained and powered off first, destroying etcd
        # quorum (and therefore the API) before the shutdown finishes.
        $masterNodes = @($registryAllNodes.items | Where-Object {
            $_.metadata.labels.'node-role.kubernetes.io/master' -eq 'true' -or
            $_.metadata.labels.'node-role.kubernetes.io/control-plane' -eq 'true'
        })
        $masterNames = @($masterNodes | ForEach-Object { $_.metadata.name })

        # Exclude the control plane and every node flagged neverPowerOff (registry:
        # WindowsLab/homelab-nodes.json). kubernetes7 is DELIBERATELY spared - its power
        # switch is broken, so powering it off means it can never be turned back on.
        $workerNodes = @($registryAllNodes.items | Where-Object {
            ($masterNames -notcontains $_.metadata.name) -and ($neverPowerOff -notcontains $_.metadata.name)
        })

        # Control-plane targets, primary endpoint last.
        $primaryMasterName = $masterFallback.Name
        $masterTargets = @(
            $masterNodes | Where-Object { $_.metadata.name -ne $primaryMasterName } | ForEach-Object {
                $ip = Get-IPv4 -addresses $_.status.addresses
                if ($ip) { [PSCustomObject]@{ Name = $_.metadata.name; IP = $ip } }
            }
            $masterNodes | Where-Object { $_.metadata.name -eq $primaryMasterName } | ForEach-Object {
                $ip = Get-IPv4 -addresses $_.status.addresses
                if ($ip) { [PSCustomObject]@{ Name = $_.metadata.name; IP = $ip } }
            }
        )
        if ($masterTargets.Count -eq 0) {
            Write-Host "[!] No control-plane node discovered via the API; using the registry list." -ForegroundColor Yellow
            Add-RunError -Context 'phase:discovery' -Message 'The API listed no control-plane node; falling back to the registry order for the control plane.'
            $registryControlPlaneFallback = @($registryNodes | Where-Object { $_.role -eq 'control-plane' })
            # Primary (nuc, the API endpoint) MUST stay last: powering it off first would take kubectl
            # away from the remaining nodes and leave the run unable to verify them.
            $masterTargets = @(
                $registryControlPlaneFallback | Where-Object { $_.name -ne $masterFallback.Name } | ForEach-Object {
                    [PSCustomObject]@{ Name = $_.name; IP = $_.ip }
                }
                $registryControlPlaneFallback | Where-Object { $_.name -eq $masterFallback.Name } | ForEach-Object {
                    [PSCustomObject]@{ Name = $_.name; IP = $_.ip }
                }
            )
        }
        $masterIp = $masterTargets[-1].IP

        foreach ($node in $workerNodes) {
            $ip = Get-IPv4 -addresses $node.status.addresses
            if ($ip) { $targets += [PSCustomObject]@{ Name = $node.metadata.name; IP = $ip } }
        }
        $actualMode = "DYNAMIC"
    }
    catch {
        # v9.3: never exit here. An unreachable API is a discovery degradation, not a reason to
        # abandon a shutdown the user asked for - the registry is a complete picture of the fleet,
        # so record it and fall through to the registry-based target list below.
        Add-RunError -Context 'phase:discovery' -Message "API discovery failed ($Mode mode): $($_.Exception.Message) Using the registry node list instead."
        $actualMode = "FALLBACK"
    }
}

# A failed discovery must never leave the target lists empty: without them the loops below would
# silently shut nothing down and still report success. Empty lists here mean "fall back to the
# registry", which is the same complete fleet picture minus per-node IP cross-checking.
if ($targets.Count -eq 0 -and $masterTargets.Count -eq 0) {
    Write-Host "[!] Discovery produced no targets; rebuilding both target lists from the registry." -ForegroundColor Yellow
    Add-RunError -Context 'phase:discovery' -Message 'Discovery produced no targets; rebuilding the worker and control-plane lists from the registry.'
    # Clear them so the FALLBACK block below (which appends workers) cannot double-list a node.
    $targets = @()
    $masterTargets = @()
    $actualMode = "FALLBACK"
}
elseif ($targets.Count -eq 0 -and $neverPowerOff.Count -gt 0) {
    # Workers were discovered as zero while a neverPowerOff node is registered: legitimate only
    # when kubernetes7 is the last one standing, but worth recording so the count is explainable.
    Add-RunError -Context 'phase:discovery' -Message 'No worker nodes were discovered (the cluster may already be partly powered down, or only protected nodes are left).'
}

if ($actualMode -eq "FALLBACK") {
    # Registry order decides the primary endpoint (nuc = first control-plane record).
    $registryControlPlane = @($registryNodes | Where-Object { $_.role -eq 'control-plane' })
    $masterTargets = @(
        $registryControlPlane | Where-Object { $_.name -ne $masterFallback.Name } | ForEach-Object {
            [PSCustomObject]@{ Name = $_.name; IP = $_.ip }
        }
        $registryControlPlane | Where-Object { $_.name -eq $masterFallback.Name } | ForEach-Object {
            [PSCustomObject]@{ Name = $_.name; IP = $_.ip }
        }
    )
    $masterIp = $masterFallback.IP
    foreach ($w in $workerFallback) { $targets += [PSCustomObject]@{ Name = $w.Name; IP = $w.IP } }
}

# Prefer an orderly worker shutdown before touching nodes that are already affected.
# A node with no live Longhorn attachment and a Ready kubelet is the safest first target;
# NotReady nodes and nodes still holding volumes are deferred so healthy capacity remains
# available to receive evicted workloads and storage detachments.
if ($actualMode -eq "DYNAMIC" -and $targets.Count -gt 1) {
    $orderedTargets = @(
        foreach ($target in $targets) {
            $node = @($registryAllNodes.items | Where-Object { $_.metadata.name -eq $target.Name }) | Select-Object -First 1
            $ready = $false
            if ($node) {
                $ready = @($node.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0
            }
            $attached = @(Get-NodeAttachedVolumes -NodeName $target.Name)
            $attachmentCount = if ($attached -contains 'UNKNOWN-API-FAILURE') { [int]::MaxValue } else { $attached.Count }
            $priority = if ($ready -and $attachmentCount -eq 0) { 0 } elseif ($ready) { 1 } else { 2 }
            [PSCustomObject]@{
                Name = $target.Name
                IP = $target.IP
                ShutdownPriority = $priority
                AttachedVolumeCount = $attachmentCount
            }
        }
    )
    $targets = @($orderedTargets | Sort-Object ShutdownPriority, AttachedVolumeCount, Name |
        Select-Object Name, IP)
    Write-Host "Worker shutdown order: healthy/storage-clean first; affected nodes deferred." -ForegroundColor DarkGray
}

# --- v9.3: ONE ERROR MUST NOT END THE RUN ---
# The rest of the script runs inside try/catch/finally:
#   * try     - the shutdown itself. Its phases (drain, detach gate, credentials) and its loops
#               each handle their own recoverable errors and keep going,
#   * catch   - anything unexpected (or a deliberate fatal, e.g. a neverPowerOff violation) is
#               recorded instead of vanishing; the remainder is skipped, so nothing is powered off
#               after a fatal,
#   * finally - the summary, the run report and the exit code, so a fatal error or an unexpected
#               exception still leaves a transcript and a machine-readable outcome behind.
# This is why the script can no longer die silently half-way through a fleet power-down.
try {

# Hard safety net: never power off a node flagged neverPowerOff in the registry.
foreach ($target in $targets) {
    if ($neverPowerOff -contains $target.Name) {
        throw "Refusing to power off '$($target.Name)': marked neverPowerOff in homelab-nodes.json (broken power switch - unrecoverable)."
    }
}
if ($neverPowerOff -contains $masterFallback.Name) {
    throw "Refusing to power off control-plane node '$($masterFallback.Name)': marked neverPowerOff in homelab-nodes.json."
}
# Same hard safety net for every other control-plane member (K3s HA has more than one).
foreach ($master in $masterTargets) {
    if ($neverPowerOff -contains $master.Name) {
        throw "Refusing to power off control-plane node '$($master.Name)': marked neverPowerOff in homelab-nodes.json."
    }
}

Write-Host "Active Mode: $actualMode" -ForegroundColor Cyan
Write-Host "Primary master (powered off last): $masterIp"
Write-Host "Control plane: $(@($masterTargets | ForEach-Object { $_.Name }) -join ', ')"
Write-Host "Workers: $($targets.Name -join ', ')"

# 2. CREDENTIALS
# -Force is meant to be run unattended (`... < /dev/null`), where a Read-Host prompt returns
# nothing: v8 then powered every node off with an *empty* sudo password and reported success.
# Resolve the password or fail loudly - never continue with an empty one.
function Get-SudoSecureString {
    <#
    .SYNOPSIS
        Loads the sudo password from cred.xml or the SecretStore vault, prompting only when the
        run is allowed to be interactive.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param([switch]$AllowPrompt)

    $credPath = Join-Path $PSScriptRoot 'cred.xml'
    if (Test-Path -Path $credPath) {
        Write-Host "Attempting to read password from credential file..." -ForegroundColor Cyan
        try {
            # Guard the type: clixml can round-trip SecureString or PSCredential (same pattern as
            # Stop-K3sHomelab-Minimal.ps1). A plaintext export is deliberately refused instead of
            # converted - that is the habit the power-management docs steer away from.
            $loaded = Import-Clixml -Path $credPath
            if ($loaded -is [securestring]) { return $loaded }
            if ($loaded -is [pscredential]) { return $loaded.Password }
            Write-Host "  [!] cred.xml holds an unexpected type ($($loaded.GetType().Name)); ignoring it." -ForegroundColor Yellow
        }
        catch {
            Write-Host "  [!] cred.xml unusable: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
        try {
            $secret = Get-Secret -Name $script:SudoPasswordSecretName -ErrorAction Stop
            Write-Host "Loaded password from SecretStore vault." -ForegroundColor Green
            return $secret
        }
        catch {
            Write-Host "  [!] No '$($script:SudoPasswordSecretName)' secret in the vault." -ForegroundColor Yellow
        }
    }

    if (-not $AllowPrompt) {
        throw "No sudo password available (cred.xml missing and '$($script:SudoPasswordSecretName)' not in the vault) and this run must not prompt (unattended -Force/-DryRun). See docs/homelab/how-to-manage-homelab-power.md."
    }
    return (Read-Host "Enter sudo password" -AsSecureString)
}

if ($DryRun) {
    Write-Host "[DRYRUN] Skipping credential resolution and the confirmation prompt." -ForegroundColor DarkGray
    $plainPass = ''
    $b64Pass = ''
}
else {
    if (-not (Get-Command ssh -ErrorAction SilentlyContinue) -and -not (Test-Path -Path '/usr/bin/ssh')) {
        throw "No ssh client available; the nodes cannot be powered off from this host."
    }
    $password = Get-SudoSecureString -AllowPrompt:(-not $Force)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    try {
        $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ([string]::IsNullOrEmpty($plainPass)) {
        throw "The resolved sudo password is empty; refusing to start a shutdown that cannot authenticate."
    }
    $b64Pass = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plainPass))
}

if ($DryRun) {
    Write-Host "[DRYRUN] No confirmation required (nothing will be changed)." -ForegroundColor DarkGray
}
elseif ($VerifyCredentials) {
    Write-Host "[VERIFY] Credential check only: nothing will be cordoned, drained or powered off." -ForegroundColor Cyan
}
elseif ($CompletePendingNodes) {
    Write-Host "[COMPLETE] Second-run completion mode: it powers off ONLY workers proven clean by the evidence gate." -ForegroundColor Cyan
}
elseif ($Force) {
    Write-Host "[!] -Force: skipping the confirmation prompt (definitive shutdown mode)." -ForegroundColor Red
}
else {
    $confirm = Read-Host "!!! WARNING: Powering off entire cluster. Proceed? (yes/no)"
    if ($confirm -ne 'yes') { exit 0 }
}

# 2b. PRE-FLIGHT: refuse to shut down on top of degraded storage unless -Force
# accepts the risk. Powering off with degraded volumes is how replicas fall
# behind and frontends wedge on next boot.
# CompletePendingNodes runs this check itself per node (evidence gate), so it must not be
# aborted by the fleet-level pre-flight.
if ($actualMode -ne "FALLBACK" -and -not $CompletePendingNodes) {
    Write-Host "`n--- Pre-flight: Longhorn health ---" -ForegroundColor Cyan
    $degradedVolumes = @(Get-DegradedLonghornVolumes)
    if ($degradedVolumes -contains 'UNKNOWN-API-FAILURE') {
        Write-Host "[!] Could not query Longhorn health; proceeding blind." -ForegroundColor Yellow
    }
    elseif ($degradedVolumes.Count -gt 0) {
        Write-Host "[!] Degraded attached volumes detected:" -ForegroundColor Red
        foreach ($vol in $degradedVolumes) { Write-Host "    - $vol" -ForegroundColor Red }
        # v9.1: -DryRun is a read-only rehearsal, not a shutdown attempt. The
        # degraded-storage gate must not kill it (the whole point of a dry run
        # is to SEE this output without -Force). Only a real run aborts here.
        if ($script:DryRun) {
            Write-Host "[DRYRUN] Degraded storage noted - a real run would abort here without -Force." -ForegroundColor DarkGray
        }
        elseif ($VerifyCredentials) {
            Write-Host "[VERIFY] Degraded storage noted - not a shutdown run, so the gate is not applied." -ForegroundColor DarkGray
        }
        elseif (!$Force -or !$AllowDirtyPowerOff) {
            # The one deliberate early exit (v9.3). Refusing to power off a fleet that has degraded
            # attached volumes is a PRE-FLIGHT decision: nothing has been touched yet, so there is
            # no half-powered cluster to recover - unlike stopping mid-run, which this version
            # never does. Recorded in the report; -AllowDirtyPowerOff is the explicit emergency override.
            $script:ExitCode = 1
            Add-RunError -Context 'gate:degraded-storage' -Message 'Refused to start: degraded attached Longhorn volumes were detected. Use -Force -AllowDirtyPowerOff only for an emergency.'
            Write-Error "Aborting: resolve degraded volumes first, or re-run with -Force -AllowDirtyPowerOff to accept the risk."
            exit 1
        }
        else {
            Write-Host "[!] -Force supplied: proceeding despite degraded storage." -ForegroundColor Red
        }
    }
    else {
        Write-Host "[+] All attached Longhorn volumes healthy." -ForegroundColor Green
    }
}
else {
    Write-Host "[!] FALLBACK mode: API unreachable, skipping storage pre-flight." -ForegroundColor Yellow
}

# 2c. CONTROL-PLANE PRE-CHECK
# Powering off embedded-etcd members spends quorum, so the API answers only for the first
# poweroff or two: the control-plane phase cannot rely on live kubectl queries. Record each
# member's live Longhorn attachments NOW, while the API is guaranteed to answer, and judge
# the later members from that snapshot (see the control-plane phase at the end).
$masterPreCheck = @{}
if ($actualMode -ne "FALLBACK" -and -not $CompletePendingNodes) {
    Write-Host "`n--- Pre-flight: control-plane storage state ---" -ForegroundColor Cyan
    foreach ($master in $masterTargets) {
        $attached = @(Get-NodeAttachedVolumes -NodeName $master.Name)
        $masterPreCheck[$master.Name] = $attached
        if ($attached -contains 'UNKNOWN-API-FAILURE') {
            Write-Host "  [!] $($master.Name): could not query attached volumes." -ForegroundColor Yellow
        }
        elseif ($attached.Count -gt 0) {
            Write-Host "  [!] $($master.Name): $($attached.Count) attached volume(s) - $($attached -join ', ')" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [+] $($master.Name): storage clean." -ForegroundColor Green
        }
    }
}

# 2d. PRE-FLIGHT: SSH CREDENTIALS
# A poweroff is an SSH login plus sudo; a wrong username or password is the failure mode that
# leaves the cluster half-powered (and, before v9.2, silently: the run only failed at the last
# stage). Prove the identity for every target up front - registry sshUser first, then the
# lowercase/capitalised spellings, because server-236 and server-252 are case-sensitive and only
# accept 'SuryenduB'. -DryRun lists the identities without probing (no password is resolved).
$credentialReport = @()
$credentialFailures = @()
$credentialTargets = @(
    @($targets | ForEach-Object { [pscustomobject]@{ Name = $_.Name; IP = $_.IP } }) +
    @($masterTargets | ForEach-Object { [pscustomobject]@{ Name = $_.Name; IP = $_.IP } })
)
if ($CompletePendingNodes) {
    # Completion mode touches workers only, so probing the etcd members' credentials here
    # is noise: filter them out of the pre-flight list.
    $credentialTargets = @($credentialTargets | Where-Object { @($masterTargets | ForEach-Object { $_.Name }) -notcontains $_.Name })
}

Write-Host "`n--- Pre-flight: SSH credentials ---" -ForegroundColor Cyan
if ($script:DryRun) {
    Write-Host "[DRYRUN] No password resolved, so nothing is probed; identities that would be used:" -ForegroundColor DarkGray
    foreach ($target in $credentialTargets) {
        $user = Resolve-NodeSshUser -NodeName $target.Name -IP $target.IP
        Write-Host "  [DRYRUN] $($target.Name) ($($target.IP)): $user" -ForegroundColor DarkGray
        $credentialReport += [pscustomobject]@{ node = $target.Name; ip = $target.IP; user = $user; status = 'unverified-dryrun' }
    }
}
else {
    # sshpass reads the same variable the poweroff ladder uses.
    $env:SSHPASS = $plainPass
    foreach ($target in $credentialTargets) {
        $credName = $target.Name
        $credIp = $target.IP
        if (-not (Test-NodeTcpPort -IP $credIp -Port 22)) {
            Write-Host "  [-] $credName ($credIp): already unreachable on TCP 22 - no credential needed." -ForegroundColor DarkGray
            $credentialReport += [pscustomobject]@{ node = $credName; ip = $credIp; user = $null; status = 'already-down' }
            continue
        }
        $candidates = @(Get-NodeSshUserCandidate -NodeName $credName)
        $matched = $null
        foreach ($candidate in $candidates) {
            if (Test-NodeSshCredential -IP $credIp -SshUser $candidate) { $matched = $candidate; break }
        }
        if ($matched) {
            $sudoOk = Test-NodeSudoCredential -IP $credIp -SshUser $matched
            if ($sudoOk) {
                $script:SshUserCache[$credName] = $matched
                Write-Host "  [+] $credName ($credIp): authenticated as '$matched' and sudo accepted." -ForegroundColor Green
                $credentialReport += [pscustomobject]@{ node = $credName; ip = $credIp; user = $matched; status = 'ok' }
            }
            else {
                Write-Host "  [!] $credName ($credIp): '$matched' logs in but sudo REJECTED the stored password." -ForegroundColor Red
                $credentialFailures += $credName
                $credentialReport += [pscustomobject]@{ node = $credName; ip = $credIp; user = $matched; status = 'sudo-failed' }
            }
        }
        else {
            Write-Host "  [!] $credName ($credIp): NO usable identity (tried: $($candidates -join ', '))." -ForegroundColor Red
            $credentialFailures += $credName
            $credentialReport += [pscustomobject]@{ node = $credName; ip = $credIp; user = $null; status = 'no-credential' }
        }
    }
    if ($credentialFailures.Count -gt 0) {
        Write-Host "[!] No working credential for: $($credentialFailures -join ', ')" -ForegroundColor Red
        Write-Host "    Fix 'sshUser' in WindowsLab/homelab-nodes.json (usernames are case-sensitive on hostname/OS level)," -ForegroundColor Yellow
        Write-Host "    or store the current sudo password:  Set-Secret -Name $($script:SudoPasswordSecretName) -Secret (Read-Host -AsSecureString)" -ForegroundColor Yellow
        Write-Host "    Continuing: each affected node will report its own failure in the summary below." -ForegroundColor Yellow
    }
    else {
        Write-Host "[+] Every reachable target node authenticated." -ForegroundColor Green
    }
}

# -VerifyCredentials stops here: the point of the switch is to prove the credentials for every
# node (and to fail loudly when one cannot be authenticated) without touching the cluster.
if ($VerifyCredentials) {
    Write-Host "`n--- Credential Verification Summary ---" -ForegroundColor Cyan
    foreach ($entry in $credentialReport) {
        $identity = if ($entry.user) { "$($entry.user)@$($entry.ip)" } else { "(none)" }
        Write-Host ("  {0,-20} {1,-16} {2,-18} {3}" -f $entry.node, $entry.ip, $identity, $entry.status)
    }
    if ($script:RunErrors.Count -gt 0) {
        Write-Host "Recoverable errors during the check (the run continued): $($script:RunErrors.Count)" -ForegroundColor Yellow
        foreach ($runError in $script:RunErrors) {
            Write-Host "    - [$($runError.context)] $($runError.message)" -ForegroundColor Yellow
        }
    }
    if ($credentialFailures.Count -gt 0) {
        Write-Host "[!] Nodes without a usable credential: $($credentialFailures -join ', ')" -ForegroundColor Red
        $script:ExitCode = 1
    }
    elseif ($script:RunErrors.Count -gt 0) {
        Write-Host "[!] Every listed node authenticated, but the run reported recoverable errors above." -ForegroundColor Yellow
        $script:ExitCode = 1
    }
    else {
        Write-Host "[+] Credentials verified for every target node listed above." -ForegroundColor Green
        $script:ExitCode = 0
    }
    if ($script:ReportPath) {
        $verifyReport = [ordered]@{
            startedAt          = $script:RunStartedAt.ToString('o')
            finishedAt         = (Get-Date).ToString('o')
            mode               = 'VERIFY-CREDENTIALS'
            dryRun             = $false
            forced             = [bool]$Force
            credentials        = @($credentialReport)
            credentialFailures = @($credentialFailures)
            errors             = @($script:RunErrors)
            log                = $script:LogPath
        }
        try { $verifyReport | ConvertTo-Json -Depth 4 | Set-Content -Path $script:ReportPath -Encoding UTF8 } catch {
            Write-Host "[!] Could not write report: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Write-Host "Report: $($script:ReportPath)" -ForegroundColor DarkGray
        Write-Host "Log: $($script:LogPath)" -ForegroundColor DarkGray
    }
    # This path wrote its own report, so the shutdown finalizer must not overwrite it.
    $script:ReportAlreadyWritten = $true
    exit $script:ExitCode
}

# v10.0 - COMPLETE PENDING NODES: the "intelligent second run".
# Scenario: a previous shutdown skipped a worker (drain overran its budget, gate refused a
# dirty power-off) and then died with the API, so a plain rerun can never finish the job -
# the registry-fallback path cannot drain and its detach gate reads UNKNOWN while the API
# is down. This mode asks the node itself instead of asking the API:
#   * TCP 22 closed   -> already down, record and move on,
#   * node-local probe clean (0 Longhorn devices, 0 mounts, only system containers running)
#     -> power it off through the same escalating ladder as the main run,
#   * anything unverified (unclean container names, devices, mounts, probe failure)
#     -> REFUSE and report the evidence. It never acts without positive proof of cleanliness,
#        so -AllowDirtyPowerOff has no role here (that is enforced at parameter parsing).
# Workers only: control-plane members are cordoned and host no workloads by design; finishing
# etcd members is the main script's job (it snapshots their attachments while the API lives).
if ($CompletePendingNodes) {
    Write-Host "`n--- Complete Pending Nodes (v10.0) ---" -ForegroundColor Cyan
    Write-Host "Target: every registry worker flagged neither skipped-safe nor neverPowerOff." -ForegroundColor DarkGray
    Write-Host "Control-plane members are deliberately NOT touched by this mode." -ForegroundColor DarkGray
    Write-Host "Context note: discovery ran before this mode but did not participate in it - in the" -ForegroundColor DarkGray
    Write-Host "API-already-down scenario its failures are EXPECTED, so they do not raise the exit code." -ForegroundColor DarkGray
    $script:RunErrors = @($script:RunErrors | Where-Object { $_.context -notlike 'phase:discovery*' })

    $completeResults = @()
    $completeRefusals = @()
    if ($script:DryRun) {
        Write-Host "[DRYRUN] No SSH connections, no password use - listing what would be verified:" -ForegroundColor DarkGray
        Remove-Item Env:SSHPASS -ErrorAction SilentlyContinue
    }
    else {
        $env:SSHPASS = $plainPass
    }

    foreach ($worker in $workerFallback) {
        Write-Host "`n--- Complete: $($worker.Name) ($($worker.IP)) ---" -ForegroundColor Yellow
        if (-not (Test-NodeTcpPort -IP $worker.IP -Port 22)) {
            Write-Host "  [-] already down (TCP 22 closed) - nothing to do." -ForegroundColor DarkGray
            $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'already-down' }
            continue
        }
        if ($script:DryRun) {
            Write-Host "  [DRYRUN] TCP 22 answers: node is UP. Would run Assert-NodeCleanliness (API channel if alive, node-local probe otherwise); poweroff only on positive proof of cleanliness." -ForegroundColor DarkGray
            $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'would-verify' }
            continue
        }

        $verdict = Assert-NodeCleanliness -NodeName $worker.Name -IP $worker.IP
        $verdictText = if ($verdict.Clean -eq $true) { 'clean' } elseif ($verdict.Clean -eq $false) { 'unclean' } else { 'unverified' }
        Add-CleanVerdict -NodeName $worker.Name -Verdict $verdictText -Channel $verdict.Channel -Evidence $verdict.Evidence
        if ($verdict.Clean -eq $true) {
            Write-Host "  [+] Node-local cleanliness proven - powering off." -ForegroundColor Green
            $outcome = Stop-HomelabNode -NodeName $worker.Name -IP $worker.IP -EncodedPassword $b64Pass `
                -MaxAttempts $PowerOffAttempts -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -VerifyTimeoutSeconds $VerifyPowerOffSeconds -AllowKernelPowerOff:$ForceKernelPowerOff
            if ($outcome.Down -eq $true) {
                Write-Host "  [+] $($worker.Name) is down (stage: $($outcome.Stage), attempt: $($outcome.Attempts))." -ForegroundColor Green
                $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'powered-off' }
            }
            elseif ($null -eq $outcome.Down) {
                Write-Host "  [DRYRUN] left untouched." -ForegroundColor DarkGray
                $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'dryrun' }
            }
            else {
                Write-Host "  [!] still answering after every poweroff stage." -ForegroundColor Red
                $completeRefusals += $worker.Name
                $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'poweroff-failed' }
            }
        }
        elseif ($verdict.Clean -eq $false) {
            Write-Host "  [!] REFUSED - node does not satisfy the cleanliness invariant:" -ForegroundColor Red
            foreach ($ev in $verdict.Evidence) { Write-Host "      - $ev" -ForegroundColor Red }
            Write-Host "  [!] Nothing was powered off. Resolve on the node (ssh $($worker.IP)) or bring the API back and use the normal shutdown." -ForegroundColor Yellow
            $completeRefusals += $worker.Name
            $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'refused-unclean' }
        }
        else {
            Write-Host "  [!] Could not verify cleanliness ($($verdict.Evidence -join '; ')) - refusing." -ForegroundColor Yellow
            $completeRefusals += $worker.Name
            $completeResults += [pscustomobject]@{ node = $worker.Name; ip = $worker.IP; status = 'refused-unverified' }
        }
    }

    Write-Host "`n--- Completion Summary ---" -ForegroundColor Cyan
    foreach ($entry in $completeResults) {
        Write-Host ("  {0,-20} {1,-16} {2}" -f $entry.node, $entry.ip, $entry.status)
    }
    if ($completeRefusals.Count -gt 0) {
        Write-Host "[!] Completion left these nodes up without proof of cleanliness: $($completeRefusals -join ', ')" -ForegroundColor Red
        $script:ExitCode = 1
    }
    else {
        Write-Host "[+] Every pending node is down or was powered off on positive proof of cleanliness." -ForegroundColor Green
        $script:ExitCode = 0
    }

    if ($script:RunErrors.Count -gt 0) {
        Write-Host "Recoverable errors recorded: $($script:RunErrors.Count)" -ForegroundColor Yellow
        foreach ($runError in $script:RunErrors) { Write-Host "    - [$($runError.context)] $($runError.message)" -ForegroundColor Yellow }
        if ($completeRefusals.Count -eq 0) { $script:ExitCode = 1 }
    }

    if ($script:ReportPath) {
        $completeReport = [ordered]@{
            startedAt  = $script:RunStartedAt.ToString('o')
            finishedAt = (Get-Date).ToString('o')
            mode       = 'COMPLETE-PENDING-NODES'
            dryRun     = [bool]$script:DryRun
            forced     = [bool]$Force
            results    = @($completeResults)
            refusals   = @($completeRefusals)
            cleanliness = @($script:CleanVerdicts)
            errors     = @($script:RunErrors)
            log        = $script:LogPath
        }
        try { $completeReport | ConvertTo-Json -Depth 4 | Set-Content -Path $script:ReportPath -Encoding UTF8 } catch {
            Write-Host "[!] Could not write report: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Write-Host "Report: $($script:ReportPath)" -ForegroundColor DarkGray
        Write-Host "Log: $($script:LogPath)" -ForegroundColor DarkGray
    }
    $script:ReportAlreadyWritten = $true
    exit $script:ExitCode
}

# 3. SHUTDOWN LOOP (per-node resilient: one bad node must not abort the rest)
$failedNodes = @()
$skippedNodes = @()
foreach ($worker in $targets) {
    Write-Host "`n--- Node: $($worker.Name) ---" -ForegroundColor Yellow
    $nodeOk = $true

    try {
        if ($actualMode -eq "DYNAMIC" -and !$SkipDrain) {
            Write-Host "  - Draining (timeout ${DrainTimeoutSeconds}s)..."
            try {
                # --disable-eviction: a full power-off is total disruption by definition, so
                # PDBs (e.g. maxUnavailable: 0 singletons, Longhorn instance-managers) cannot
                # be honoured and protect nothing here - they only stall the shutdown until
                # the timeout and force a dirty power-off. Grace periods still apply, and the
                # detach-wait below remains the storage safety gate.
                Invoke-KubectlCommand -Arguments @('cordon', $worker.Name)
                Invoke-KubectlCommand -Arguments @('drain', $worker.Name, '--ignore-daemonsets',
                    '--delete-emptydir-data', '--force', '--disable-eviction',
                    '--grace-period=120', "--timeout=$($DrainTimeoutSeconds)s")
            }
            catch {
                # v10.0: the drain is only buying the workloads time to migrate, so its exit
                # code is a proxy - a drain that overruns its own budget (argocd singletons
                # churning at grace 120 on kubernetes5, 2026-10-17) fails as a *command* while
                # the node seconds later becomes safe. The real invariant is judged directly:
                #   -AllowDirtyPowerOff            -> override, power off regardless (unchanged),
                #   no -Force                      -> skip the node (accidental-run behaviour),
                #   -Force alone (new default)     -> power off ONLY on positive proof of
                #                                     cleanliness (API or node-local channel).
                Write-Host "  [!] Drain failed for $($worker.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                if (!$Force) {
                    Write-Host "  [!] Skipping poweroff for this node (a deliberate shutdown re-runs with -Force; the evidence gate then decides)." -ForegroundColor Red
                    $skippedNodes += $worker.Name
                    Add-CleanVerdict -NodeName $worker.Name -Verdict 'unclean-skipped' -Channel 'none' -Evidence "drain failed and -Force not supplied"
                    continue
                }
                if ($AllowDirtyPowerOff) {
                    Write-Host "  [!] -Force -AllowDirtyPowerOff: powering off despite the failed drain." -ForegroundColor Red
                }
                else {
                    Write-Host "  - Judging the cleanliness invariant directly (drain exit code ignored)..." -ForegroundColor DarkGray
                    $verdict = Assert-NodeCleanliness -NodeName $worker.Name -IP $worker.IP
                    $verdictText = if ($verdict.Clean -eq $true) { 'clean' } elseif ($verdict.Clean -eq $false) { 'unclean' } else { 'unverified' }
                    Add-CleanVerdict -NodeName $worker.Name -Verdict $verdictText -Channel $verdict.Channel -Evidence $verdict.Evidence
                    if ($verdict.Clean -eq $true) {
                        Write-Host "  [+] Node is PROVEN safe (no eligible workloads, no attached volumes) - proceeding despite the failed drain." -ForegroundColor Green
                    }
                    else {
                        Write-Host "  [!] Refusing to power off $($worker.Name): the cleanliness invariant did not hold ($($verdict.Evidence -join '; '))." -ForegroundColor Red
                        Write-Host "  [!] It stays up; the finish gate below keeps the etcd members running so this stays recoverable." -ForegroundColor Yellow
                        $skippedNodes += $worker.Name
                        continue
                    }
                }
            }
        }
        elseif ($SkipDrain) {
            Write-Host "  [!] -SkipDrain: pods and volumes are NOT being evacuated first." -ForegroundColor Yellow
        }

        if (!$SkipDrain -and -not $script:DryRun) {
            Write-Host "  - Waiting for Longhorn detach (timeout ${DetachTimeoutSeconds}s)..."
            if (Test-ApiReachable) {
                $clean = Wait-NodeVolumesDetached -NodeName $worker.Name -TimeoutSeconds $DetachTimeoutSeconds
            }
            else {
                # v10.0: previously this polled a dead API for the whole timeout and then
                # skipped the node. The node-local channel now answers the same question in
                # seconds, whether the API is healthy or already spent.
                Write-Host "  [i] API not answering - switching to the node-local cleanliness probe." -ForegroundColor DarkGray
                $clean = $false
            }
            if (!$clean) {
                if ($AllowDirtyPowerOff) {
                    $left = @(Get-NodeAttachedVolumes -NodeName $worker.Name)
                    Write-Host "  [!] -Force supplied: powering off with volumes still attached: $($left -join ', ')" -ForegroundColor Red
                }
                else {
                    Write-Host "  - Judging the cleanliness invariant directly (detach gate inconclusive)..." -ForegroundColor DarkGray
                    $verdict = Assert-NodeCleanliness -NodeName $worker.Name -IP $worker.IP
                    $verdictText = if ($verdict.Clean -eq $true) { 'clean' } elseif ($verdict.Clean -eq $false) { 'unclean' } else { 'unverified' }
                    Add-CleanVerdict -NodeName $worker.Name -Verdict $verdictText -Channel $verdict.Channel -Evidence $verdict.Evidence
                    if ($verdict.Clean -eq $true) {
                        Write-Host "  [+] Node is PROVEN safe (0 longhorn devices, 0 mounts, system containers only) - proceeding." -ForegroundColor Green
                    }
                    else {
                        Write-Host "  [!] Refusing to power off $($worker.Name): the cleanliness invariant did not hold ($($verdict.Evidence -join '; '))." -ForegroundColor Red
                        Write-Host "  [!] It stays up; the finish gate below keeps the etcd members running so this stays recoverable." -ForegroundColor Yellow
                        $skippedNodes += $worker.Name
                        continue
                    }
                }
            }
            else {
                Write-Host "  [+] Storage clean on $($worker.Name)." -ForegroundColor Green
            }
        }
        elseif (!$SkipDrain) {
            Write-Host "  [DRYRUN] would wait for the Longhorn volumes to detach before powering off." -ForegroundColor DarkGray
        }

        Write-Host "  - Powering off..."
        $env:SSHPASS = $plainPass
        $outcome = Stop-HomelabNode -NodeName $worker.Name -IP $worker.IP -EncodedPassword $b64Pass `
            -MaxAttempts $PowerOffAttempts -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
            -VerifyTimeoutSeconds $VerifyPowerOffSeconds -AllowKernelPowerOff:$ForceKernelPowerOff

        if ($outcome.Down -eq $true) {
            Write-Host "  [+] $($worker.Name) is down (stage: $($outcome.Stage), attempt: $($outcome.Attempts))." -ForegroundColor Green
        }
        elseif ($null -eq $outcome.Down) {
            Write-Host "  [DRYRUN] $($worker.Name) left untouched." -ForegroundColor DarkGray
        }
        else {
            Write-Host "  [!] $($worker.Name) is still answering after every poweroff stage ($($outcome.Attempts) attempt(s))." -ForegroundColor Red
            if ($ForceKernelPowerOff) { Write-Host "  [!] The kernel sysrq stage was already tried; it may need a physical power button." -ForegroundColor Red }
            else { Write-Host "  [!] Re-run with -Force -ForceKernelPowerOff to add the kernel-level stage." -ForegroundColor Red }
            $nodeOk = $false
        }
    }
    catch {
        Write-Host "  [!] Shutdown of $($worker.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
        $nodeOk = $false
    }

    if (!$nodeOk) { $failedNodes += $worker.Name }
}

# v10.0 - FINISH GATE (marks the structural fix for the stranded-worker trap).
# A skipped worker must now be RESOLVED before a single etcd member can lose quorum; powering
# off the control plane with a worker still up is what made kubernetes5 permanently
# un-replayable on 2026-10-17 (the API died, and a rerun could then neither drain it nor
# verify its storage). Recovery, in escalating order of preference:
#   1. still-up workers are re-judged by the cleanliness invariant (API channel - O(1s)),
#   2. an unclean worker with a live API gets ONE extended drain retry (2x the budget),
#   3. a clean worker is powered off immediately through the standard ladder,
#   4. only if a worker remains up WITHOUT positive proof of cleanliness does the gate BLOCK
#      the control-plane phase and leave the API running, with exit code 2. A plain rerun
#      then finishes the job (drains still work), or -CompletePendingNodes does when the
#      API has since died.
# -AllowDirtyPowerOff keeps its meaning: the explicit choice to race a worker alongside the
# control plane and proceeds past this gate.
Write-Host "`n--- Finish gate: workers before quorum ---" -ForegroundColor Cyan
$stillUpWorkers = @(@($targets) | Where-Object {
    -not $script:DryRun -and (Test-NodeTcpPort -IP $_.IP -Port 22 -TimeoutMs 3000) -and $AllowDirtyPowerOff -eq $false
})
if ($script:DryRun) {
    $stillUpWorkers = @()
    Write-Host "[DRYRUN] Finish gate noted: the control plane would only power off after every worker is down or proven clean." -ForegroundColor DarkGray
}
elseif ($AllowDirtyPowerOff) {
    Write-Host "  [!] -AllowDirtyPowerOff supplied: the finish gate is overridden; stranded workers, if any, race the control plane." -ForegroundColor Red
}
else {
    foreach ($strander in $stillUpWorkers) {
        Write-Host "  [!] Worker $($strander.Name) is still up after its pass - re-judging cleanliness..." -ForegroundColor Red
        $verdict = Assert-NodeCleanliness -NodeName $strander.Name -IP $strander.IP
        if ($verdict.Clean -eq $false -and (Test-ApiReachable)) {
            Write-Host "  - UNCLEAN via API. One extended drain retry (2x budget) before the gate can allow the etcd phase..." -ForegroundColor Yellow
            $retryBudget = [Math]::Min(1800, 2 * $DrainTimeoutSeconds)
            try {
                Invoke-KubectlCommand -Arguments @('cordon', $strander.Name)
                Invoke-KubectlCommand -Arguments @('drain', $strander.Name, '--ignore-daemonsets',
                    '--delete-emptydir-data', '--force', '--disable-eviction',
                    '--grace-period=120', "--timeout=$($retryBudget)s")
            }
            catch {
                Add-RunError -Context "finish-gate:drain-retry:$($strander.Name)" -Message "extended drain retry failed: $($_.Exception.Message)"
            }
            $verdict = Assert-NodeCleanliness -NodeName $strander.Name -IP $strander.IP
        }
        $verdictText = if ($verdict.Clean -eq $true) { 'clean' } elseif ($verdict.Clean -eq $false) { 'unclean' } else { 'unverified' }
        Add-CleanVerdict -NodeName $strander.Name -Verdict "$verdictText (finish gate)" -Channel $verdict.Channel -Evidence $verdict.Evidence

        if ($verdict.Clean -eq $true) {
            Write-Host "  - Proven safe: powering off $($strander.Name) during the finish gate." -ForegroundColor Green
            $env:SSHPASS = $plainPass
            $outcome = Stop-HomelabNode -NodeName $strander.Name -IP $strander.IP -EncodedPassword $b64Pass `
                -MaxAttempts $PowerOffAttempts -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -VerifyTimeoutSeconds $VerifyPowerOffSeconds -AllowKernelPowerOff:$ForceKernelPowerOff
            if ($outcome.Down -eq $true) {
                Write-Host "  [+] $($strander.Name) resolved by the finish gate (stage: $($outcome.Stage), attempt: $($outcome.Attempts))." -ForegroundColor Green
                $skippedNodes = @($skippedNodes | Where-Object { $_ -ne $strander.Name })
            }
            else {
                Write-Host "  [!] $($strander.Name) still answers despite the recovery poweroff - gate will stay shut." -ForegroundColor Red
                $script:StrandedWorkers += $strander.Name
            }
        }
        else {
            $script:StrandedWorkers += $strander.Name
            Add-RunError -Context "finish-gate:$($strander.Name)" -Message "worker still up without proof of cleanliness: $($verdict.Evidence -join '; ')"
        }
    }

    $script:StrandedWorkers = @(
        foreach ($worker in $targets) {
            if ($script:StrandedWorkers -contains $worker.Name) {
                if (Test-NodeTcpPort -IP $worker.IP -Port 22 -TimeoutMs 3000) { $worker.Name }
            }
        }
    )
    if ($script:StrandedWorkers.Count -gt 0) {
        $script:FinishGateBlocked = $true
        $script:ExitCode = 2
        Write-Host "`n[!!!] FINISH GATE SHUT: $($script:StrandedWorkers -join ', ') remain up without proof of cleanliness." -ForegroundColor Red
        Write-Host "      The CONTROL PLANE WILL BE LEFT RUNNING (etcd quorum + kubectl preserve power to fix this)." -ForegroundColor Red
        Write-Host "      Fix and re-run the same command: the next pass drains normally while the API is still alive," -ForegroundColor Yellow
        Write-Host "      or use -CompletePendingNodes afterwards if the API dies." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] Finish gate open: every worker is down or was resolved on proof of cleanliness." -ForegroundColor Green
    }
}

if ($script:FinishGateBlocked) {
    Write-Host "`n--- Control Plane: SKIPPED (finish gate) ---" -ForegroundColor Red
    Write-Host "Control-plane members deliberately left up: $(@($masterTargets | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Yellow
}
else {
Write-Host "`n--- Powering off Control Plane (last) ---" -ForegroundColor Red
foreach ($master in $masterTargets) {
    $masterName = $master.Name
    $masterOk = $true
    try {
        # The Longhorn detach gate needs the API. Once enough etcd members have been
        # powered off, quorum is spent and kubectl can no longer answer - at that point the
        # gate cannot run for the remaining members, and refusing to continue would leave
        # the worker-only shutdown half-finished. Warn loudly and continue instead.
        $apiUp = Test-ApiReachable
        if ($script:DryRun -and !$SkipDrain) {
            Write-Host "  [DRYRUN] would verify the Longhorn detach state on $masterName before powering it off." -ForegroundColor DarkGray
        }
        elseif (!$SkipDrain -and $apiUp) {
            Write-Host "  - Waiting for Longhorn detach on $masterName (timeout ${DetachTimeoutSeconds}s)..."
            $clean = Wait-NodeVolumesDetached -NodeName $masterName -TimeoutSeconds $DetachTimeoutSeconds
            if ($clean) { Write-Host "  [+] Storage clean on $masterName." -ForegroundColor Green }
            elseif (!$Force -or !$AllowDirtyPowerOff) {
                Write-Host "  [!] Volumes still attached to ${masterName}; skipping poweroff (use -Force -AllowDirtyPowerOff only for an emergency override)." -ForegroundColor Red
                $skippedNodes += $masterName
                $masterOk = $false
            }
            else { Write-Host "  [!] -Force supplied: powering off $masterName with volumes attached." -ForegroundColor Red }
        }
        elseif (!$SkipDrain) {
            # The API is gone (quorum already spent), so the live gate cannot run for this
            # member. Fall back to the pre-flight snapshot taken while the API was alive: if
            # it had attachments, do not silently power it off.
            $preAttached = @()
            if ($masterPreCheck.ContainsKey($masterName)) { $preAttached = @($masterPreCheck[$masterName]) }
            if ($preAttached.Count -gt 0 -and ($preAttached -notcontains 'UNKNOWN-API-FAILURE') -and (!$Force -or !$AllowDirtyPowerOff)) {
                Write-Host "  [!] ${masterName} had attached volume(s) at pre-flight ($($preAttached -join ', ')) and the API is no longer answering - skipping poweroff (use -Force -AllowDirtyPowerOff only for an emergency override)." -ForegroundColor Red
                $skippedNodes += $masterName
                $masterOk = $false
            }
            else {
                Write-Host "  [!] API unreachable (etcd quorum already spent) - storage gate skipped for $masterName." -ForegroundColor Yellow
            }
        }
        if ($masterOk) {
            $env:SSHPASS = $plainPass
            $outcome = Stop-HomelabNode -NodeName $masterName -IP $master.IP -EncodedPassword $b64Pass `
                -MaxAttempts $PowerOffAttempts -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -VerifyTimeoutSeconds $VerifyPowerOffSeconds -AllowKernelPowerOff:$ForceKernelPowerOff
            if ($outcome.Down -eq $true) {
                Write-Host "  [+] $masterName is down (stage: $($outcome.Stage), attempt: $($outcome.Attempts))." -ForegroundColor Green
            }
            elseif ($null -eq $outcome.Down) {
                Write-Host "  [DRYRUN] $masterName left untouched (it is powered off last of all)." -ForegroundColor DarkGray
            }
            else {
                # Judged by reachability, so the 255 exit code of a *successful* poweroff (the host
                # closes the connection as it goes down) can no longer be mistaken for a failure.
                Write-Host "  [!] $masterName is still answering after every poweroff stage ($($outcome.Attempts) attempts)." -ForegroundColor Red
                $failedNodes += $masterName
            }
        }
    }
    catch {
        Write-Host "  [!] Shutdown of $masterName failed: $($_.Exception.Message)" -ForegroundColor Red
        $failedNodes += $masterName
    }
}
} # if finish gate open
# end of the operational try body - what follows is the catch/finally finalizer.
}
# v9.3: an unexpected error is recorded, not fatal - the finally block below still writes the
# summary and the run report, and the exit code still reflects the failure.
catch {
    Add-RunError -Context 'run' -Message "Unexpected error: $($_.Exception.Message)"
}
finally {
if (-not $script:ReportAlreadyWritten) {
Write-Host "`n--- Shutdown Summary ---" -ForegroundColor Cyan
if ($script:DryRun) { Write-Host "[DRYRUN] Nothing was changed: no node was cordoned, drained or powered off." -ForegroundColor DarkGray }
if ($script:FinishGateBlocked) {
    Write-Host "FINISH GATE SHUT - control plane DELIBERATELY left running ($(@($masterTargets | ForEach-Object { $_.Name }) -join ', ')):" -ForegroundColor Red
    Write-Host "  Stranded workers (still answering on TCP 22, no proof of cleanliness): $($script:StrandedWorkers -join ', ')" -ForegroundColor Red
    Write-Host "  Next step: re-run the same command (the API is still alive, so drains work and stranded workers get resolved)," -ForegroundColor Yellow
    Write-Host "  or - if the API has since died - review the evidence above and use -Force -CompletePendingNodes." -ForegroundColor Yellow
}
if ($skippedNodes.Count -gt 0) {
    Write-Host "Skipped (cleanliness invariant not proven, nodes left up): $($skippedNodes -join ', ')" -ForegroundColor Yellow
}
if ($script:CleanVerdicts.Count -gt 0) {
    Write-Host "Cleanliness evidence per node:" -ForegroundColor DarkGray
    foreach ($cv in $script:CleanVerdicts) {
        Write-Host ("    {0,-16} {1} [{2}] {3}" -f $cv.node, $cv.verdict, $cv.channel, (@($cv.evidence) -join '; ')) -ForegroundColor DarkGray
    }
}
if ($failedNodes.Count -gt 0) {
    Write-Host "Still answering after every poweroff stage: $($failedNodes -join ', ')" -ForegroundColor Red
    Write-Host "  These hosts ignored sudo poweroff, shutdown -h now and systemctl poweroff -i. Retry with -Force -ForceKernelPowerOff, or use the physical power button." -ForegroundColor Yellow
}
if ($script:RunErrors.Count -gt 0) {
    Write-Host "Recoverable errors (the run continued past each one): $($script:RunErrors.Count)" -ForegroundColor Yellow
    foreach ($runError in $script:RunErrors) {
        Write-Host "    - [$($runError.context)] $($runError.message)" -ForegroundColor Yellow
    }
}
if ($skippedNodes.Count -eq 0 -and $failedNodes.Count -eq 0) {
    if ($script:DryRun) { Write-Host "[+] Dry run complete: review the plan above, then re-run without -DryRun." -ForegroundColor Green }
    elseif ($script:RunErrors.Count -gt 0) { Write-Host "[!] Every target node is down, but $($script:RunErrors.Count) recoverable error(s) were recorded above." -ForegroundColor Yellow }
    else { Write-Host "[+] All target nodes processed cleanly (each one verified unreachable on TCP 22)." -ForegroundColor Green }
}

# Guarded: powering off the machine running this script kills the terminal, kubectl
# access and any chance to observe or recover the cluster mid-test. Opt-in only.
if ($ShutdownLocalMac -and $script:DryRun) {
    Write-Host "`n--- [DRYRUN] would power off the local Mac (-ShutdownLocalMac supplied) ---" -ForegroundColor DarkGray
}
elseif ($ShutdownLocalMac) {
    Write-Host "`n--- Powering off Local Mac (-ShutdownLocalMac supplied) ---" -ForegroundColor Red
    try { "test" | sudo -S shutdown -h now } catch {
        Add-RunError -Context 'local-mac' -Message "Could not power off the local Mac: $($_.Exception.Message)"
    }
}
else {
    Write-Host "`n--- Local Mac left powered on (use -ShutdownLocalMac to include it) ---" -ForegroundColor Yellow
}

# Exit code: only ever RAISED (never reset), so a deliberate gate that set a code keeps it
# through this finalizer. 1 = a node was skipped / is still up, a credential failed, or any
# recoverable error was recorded. 2 (v10.0) = the finish gate shut: worker(s) are stranded
# WITHOUT proof of cleanliness, and the control plane was deliberately left running.
if ($script:ExitCode -eq 0 -and ($skippedNodes.Count -gt 0 -or $failedNodes.Count -gt 0 -or $script:RunErrors.Count -gt 0)) { $script:ExitCode = 1 }

# --- RUN REPORT (v9.1): machine-readable outcome next to the transcript ---
if ($script:ReportPath) {
    $excludedFromDown = @()
    if ($script:FinishGateBlocked) {
        # The gate kept the etcd members up, so they must not appear in "down".
        $excludedFromDown = @($masterTargets | ForEach-Object { $_.Name })
    }
    $downNodes = @(
        @($targets | ForEach-Object { $_.Name }) + @($masterTargets | ForEach-Object { $_.Name }) |
            Where-Object { ($skippedNodes -notcontains $_) -and ($failedNodes -notcontains $_) -and
                           ($excludedFromDown -notcontains $_) -and (-not $script:DryRun) }
    )
    $downNodes = @($downNodes | Where-Object { $_ })
    $report = [ordered]@{
        startedAt  = $script:RunStartedAt.ToString('o')
        finishedAt = (Get-Date).ToString('o')
        mode       = $actualMode
        dryRun     = [bool]$script:DryRun
        forced     = [bool]$Force
        finishGateBlocked = [bool]$script:FinishGateBlocked
        strandedWorkers   = @($script:StrandedWorkers)
        credentials = @($credentialReport)
        credentialFailures = @($credentialFailures)
        cleanliness = @($script:CleanVerdicts)
        errors     = @($script:RunErrors)
        down       = @($downNodes)
        skipped    = @($skippedNodes)
        failed     = @($failedNodes)
        log        = $script:LogPath
    }
    try { $report | ConvertTo-Json -Depth 4 | Set-Content -Path $script:ReportPath -Encoding UTF8 } catch {
        Write-Host "[!] Could not write report: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "Report: $($script:ReportPath)" -ForegroundColor DarkGray
    Write-Host "Log: $($script:LogPath)" -ForegroundColor DarkGray
}
}
try { Stop-Transcript | Out-Null } catch { Write-Verbose "Transcript was not active: $($_.Exception.Message)" }

if ($script:DryRun) { exit 0 }
exit $script:ExitCode
}

