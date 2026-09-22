# K3s Homelab Systematic Shutdown (v9 - Definitive & Verified)
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
# -Force is the "make it stop" switch. It skips every *refusable* gate and rides out every
# recoverable failure:
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
[CmdletBinding()]
param(
    [Parameter(HelpMessage="Ignore every refusable warning (confirmation, degraded storage, volumes still attached, unreachable API), retry each poweroff through its full escalation ladder and keep going until every target node is confirmed down. Never overrides the neverPowerOff rule.")]
    [switch]$Force,

    [Parameter(HelpMessage="With -Force: after every SSH poweroff stage has failed on a node, force a kernel-level sysrq poweroff (sync + remount-ro + power off). Bypasses systemd's orderly shutdown - last resort only.")]
    [switch]$ForceKernelPowerOff,

    [Parameter(HelpMessage="Show the full plan without changing anything (read-only kubectl queries, no SSH, no prompts)")]
    [switch]$DryRun,

    [Parameter(HelpMessage="Skip the kubectl drain process and power off immediately")]
    [switch]$SkipDrain,

    [Parameter(HelpMessage="Also power off the local Mac running this script (DANGEROUS: kills your terminal and remote access mid-test). Default: skipped.")]
    [switch]$ShutdownLocalMac,

    [Parameter(HelpMessage="Discovery Mode: Auto (detect), Dynamic (Force API), Fallback (Force Hardcoded)")]
    [ValidateSet("Auto", "Dynamic", "Fallback")]
    [string]$Mode = "Auto",

    [Parameter(HelpMessage="Seconds to allow kubectl drain per node (stateful RWO workloads need time to flush)")]
    [ValidateRange(60, 1800)]
    [int]$DrainTimeoutSeconds = 300,

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
    [int]$SshConnectTimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop' # Critical for Catch block to trigger on external errors

# Native command failures (kubectl, ssh) are judged by explicit $LASTEXITCODE checks instead of
# exceptions, so a non-zero exit can never abort the run half-way through a power-down. Set the
# variable only where it exists (7.3+) to stay compatible with the declared 7.0 baseline.
if ($PSVersionTable.PSVersion -ge [version]'7.3') { $PSNativeCommandUseErrorActionPreference = $false }

# Script-scope state shared with the helper functions below (they are plain functions, so they
# cannot see the caller's parameters). DryRun makes every state-changing helper a no-op that
# prints its intent - which is also what makes this script testable without touching the lab.
$script:DryRun = [bool]$DryRun
$script:SudoPasswordSecretName = 'k3s-homelab-sudo'

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

Write-Host "--- K3s Cluster Shutdown Sequence (v9) ---" -ForegroundColor Cyan

# --- Storage-safe helpers: a node must not lose power while Longhorn still has
#     live attachments on it. Unclean detachment is what wedges engine frontends
#     ('Can't open blockdev' on next boot) and forces instance-manager surgery. ---
function Get-NodeSshArgument {
    <#
    .SYNOPSIS
        Shared ssh argument list: non-interactive, throwaway known_hosts and a *bounded* connect
        timeout (v8 had none, so an unresponsive host could stall the shutdown for the kernel's
        ~75s TCP timeout on every node).
    #>
    param(
        [Parameter(Mandatory)][string]$IP,
        [int]$ConnectTimeoutSeconds = 15
    )
    return @('-n', '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
        '-o', "ConnectTimeout=$ConnectTimeoutSeconds", '-o', 'ConnectionAttempts=1',
        "suryendub@$IP")
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
        [int]$ConnectTimeoutSeconds = 15
    )
    $sshArgs = @(Get-NodeSshArgument -IP $IP -ConnectTimeoutSeconds $ConnectTimeoutSeconds) + @($RemoteCommand)
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
    #>
    param([Parameter(Mandatory)][string]$NodeName)
    try {
        $attachments = kubectl get volumeattachment -o json --request-timeout=15s | ConvertFrom-Json
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
    #>
    $degraded = @()
    try {
        $volumes = kubectl get volumes.longhorn.io -n longhorn-system -o json --request-timeout=15s | ConvertFrom-Json
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
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [Parameter(Mandatory)][string]$IP,
        # Not mandatory: -DryRun sends nothing, so it passes an empty string.
        [Parameter()][string]$EncodedPassword = '',
        [int]$MaxAttempts = 3,
        [int]$ConnectTimeoutSeconds = 15,
        [int]$VerifyTimeoutSeconds = 45,
        [switch]$AllowKernelPowerOff
    )

    if (-not $script:DryRun -and [string]::IsNullOrEmpty($EncodedPassword)) {
        throw "No sudo password was resolved for $NodeName; refusing to send an unauthenticated poweroff."
    }

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
        Write-Host "  [DRYRUN] would power off $NodeName ($IP) through: $((@($ladder.Label)) -join ' -> ')" -ForegroundColor DarkGray
        return [pscustomobject]@{ Node = $NodeName; IP = $IP; Down = $null; Stage = 'dryrun'; Attempts = 0 }
    }

    for ($attempt = 1; $attempt -le $ladder.Count; $attempt++) {
        $stage = $ladder[$attempt - 1]
        Write-Host "  - Poweroff attempt $attempt/$($ladder.Count) on $NodeName ($($stage.Label))..."
        try {
            $exitCode = Invoke-NodeSshAttempt -IP $IP -RemoteCommand $stage.Command -ConnectTimeoutSeconds $ConnectTimeoutSeconds
            Write-Host "    ssh exit code $exitCode (255 normally means the host dropped the connection as it powered off)." -ForegroundColor DarkGray
        }
        catch {
            # ssh/sshpass itself could not be launched: report it and still verify, because the
            # host may already have gone down before the client gave up.
            Write-Host "  [!] ssh transport problem for ${NodeName}: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if (Wait-NodeDown -IP $IP -NodeName $NodeName -TimeoutSeconds $VerifyTimeoutSeconds) {
            return [pscustomobject]@{ Node = $NodeName; IP = $IP; Down = $true; Stage = $stage.Label; Attempts = $attempt }
        }
        Write-Host "  [!] $NodeName still answering after '$($stage.Label)'." -ForegroundColor Yellow
    }

    return [pscustomobject]@{ Node = $NodeName; IP = $IP; Down = $false; Stage = 'exhausted'; Attempts = $ladder.Count }
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
        $registryAllNodes = kubectl get nodes -o json --request-timeout=10s | ConvertFrom-Json

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
            $masterTargets = @($registryNodes | Where-Object { $_.role -eq 'control-plane' } | ForEach-Object {
                [PSCustomObject]@{ Name = $_.name; IP = $_.ip }
            })
        }
        $masterIp = $masterTargets[-1].IP

        foreach ($node in $workerNodes) {
            $ip = Get-IPv4 -addresses $node.status.addresses
            if ($ip) { $targets += [PSCustomObject]@{ Name = $node.metadata.name; IP = $ip } }
        }
        $actualMode = "DYNAMIC"
    }
    catch {
        if ($Mode -eq "Dynamic" -and !$Force) {
            Write-Error "Force Dynamic mode requested but API is unreachable."
            exit 1
        }
        if ($Mode -eq "Dynamic") {
            # -Force is exactly the case where the API may already be gone (an earlier, interrupted
            # power-down, spent etcd quorum, k3s down): aborting here would leave the cluster
            # half-powered, so fall back to the registry list and keep going.
            Write-Host "[!] -Force: API unreachable, falling back to the registry node list." -ForegroundColor Yellow
        }
        else {
            Write-Host "[!] API Unreachable. Switching to FALLBACK mode." -ForegroundColor Yellow
        }
        $actualMode = "FALLBACK"
    }
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
if ($actualMode -ne "FALLBACK") {
    Write-Host "`n--- Pre-flight: Longhorn health ---" -ForegroundColor Cyan
    $degradedVolumes = @(Get-DegradedLonghornVolumes)
    if ($degradedVolumes -contains 'UNKNOWN-API-FAILURE') {
        Write-Host "[!] Could not query Longhorn health; proceeding blind." -ForegroundColor Yellow
    }
    elseif ($degradedVolumes.Count -gt 0) {
        Write-Host "[!] Degraded attached volumes detected:" -ForegroundColor Red
        foreach ($vol in $degradedVolumes) { Write-Host "    - $vol" -ForegroundColor Red }
        if (!$Force) {
            Write-Error "Aborting: resolve degraded volumes first, or re-run with -Force to accept the risk."
            exit 1
        }
        Write-Host "[!] -Force supplied: proceeding despite degraded storage." -ForegroundColor Red
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
if ($actualMode -ne "FALLBACK") {
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
                # The drain was only buying the workloads time to migrate; failing it must not
                # withhold the poweroff that follows. Without -Force the old behaviour is kept
                # (skip the node, report it) so an accidental run stays conservative.
                Write-Host "  [!] Drain failed for $($worker.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                if (!$Force) {
                    Write-Host "  [!] Skipping poweroff for this node (re-run with -Force to power it off anyway)." -ForegroundColor Red
                    $skippedNodes += $worker.Name
                    continue
                }
                Write-Host "  [!] -Force: powering off despite the failed drain." -ForegroundColor Red
            }
        }
        elseif ($SkipDrain) {
            Write-Host "  [!] -SkipDrain: pods and volumes are NOT being evacuated first." -ForegroundColor Yellow
        }

        if (!$SkipDrain -and -not $script:DryRun) {
            Write-Host "  - Waiting for Longhorn detach (timeout ${DetachTimeoutSeconds}s)..."
            $clean = Wait-NodeVolumesDetached -NodeName $worker.Name -TimeoutSeconds $DetachTimeoutSeconds
            if (!$clean) {
                $left = @(Get-NodeAttachedVolumes -NodeName $worker.Name)
                if (!$Force) {
                    Write-Host "  [!] Volumes still attached to $($worker.Name): $($left -join ', ')" -ForegroundColor Red
                    Write-Host "  [!] Skipping poweroff for this node (re-run with -Force to override)." -ForegroundColor Red
                    $skippedNodes += $worker.Name
                    continue
                }
                Write-Host "  [!] -Force supplied: powering off with volumes still attached: $($left -join ', ')" -ForegroundColor Red
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
            elseif (!$Force) {
                Write-Host "  [!] Volumes still attached to ${masterName}; skipping poweroff (re-run with -Force to override)." -ForegroundColor Red
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
            if ($preAttached.Count -gt 0 -and ($preAttached -notcontains 'UNKNOWN-API-FAILURE') -and !$Force) {
                Write-Host "  [!] ${masterName} had attached volume(s) at pre-flight ($($preAttached -join ', ')) and the API is no longer answering - skipping poweroff (re-run with -Force to override)." -ForegroundColor Red
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

Write-Host "`n--- Shutdown Summary ---" -ForegroundColor Cyan
if ($script:DryRun) {
    Write-Host "[DRYRUN] Nothing was changed: no node was cordoned, drained or powered off." -ForegroundColor DarkGray
}
if ($skippedNodes.Count -gt 0) {
    Write-Host "Skipped (storage/drain not clean, no -Force): $($skippedNodes -join ', ')" -ForegroundColor Yellow
}
if ($failedNodes.Count -gt 0) {
    Write-Host "Still answering after every poweroff stage: $($failedNodes -join ', ')" -ForegroundColor Red
    Write-Host "  These hosts ignored sudo poweroff, shutdown -h now and systemctl poweroff -i. Retry with -Force -ForceKernelPowerOff, or use the physical power button." -ForegroundColor Yellow
}
if ($skippedNodes.Count -eq 0 -and $failedNodes.Count -eq 0) {
    if ($script:DryRun) { Write-Host "[+] Dry run complete: review the plan above, then re-run without -DryRun." -ForegroundColor Green }
    else { Write-Host "[+] All target nodes processed cleanly (each one verified unreachable on TCP 22)." -ForegroundColor Green }
}

# Guarded: powering off the machine running this script kills the terminal, kubectl
# access and any chance to observe or recover the cluster mid-test. Opt-in only.
if ($ShutdownLocalMac -and $script:DryRun) {
    Write-Host "`n--- [DRYRUN] would power off the local Mac (-ShutdownLocalMac supplied) ---" -ForegroundColor DarkGray
}
elseif ($ShutdownLocalMac) {
    Write-Host "`n--- Powering off Local Mac (-ShutdownLocalMac supplied) ---" -ForegroundColor Red
    "test" | sudo -S shutdown -h now
}
else {
    Write-Host "`n--- Local Mac left powered on (use -ShutdownLocalMac to include it) ---" -ForegroundColor Yellow
}

if ($script:DryRun) { exit 0 }
if ($skippedNodes.Count -gt 0 -or $failedNodes.Count -gt 0) { exit 1 }
exit 0

