#Requires -Version 7.0
# Start-K3sHomelab.ps1  (full recovery by default)
# Restores cluster capacity after a power-down. Every recovery phase now runs by default:
# uncordon Ready nodes -> purge stranded/zombie pods -> repair Longhorn -> recycle CSI
# plugins -> serialized workload reconcile -> PDB-aware rebalance -> verify.
# Use the -Skip* switches to opt out of individual phases.
# Symmetrical counterpart to Stop-K3sHomelab-Minimal.ps1 / shutdown_homelab.ps1.

<#
.SYNOPSIS
    Restores a powered-on K3s homelab to full capacity, safely and idempotently.

.DESCRIPTION
    The whole recovery runs by default, so a bare 'Start-K3sHomelab.ps1' performs:

        uncordon Ready nodes -> purge stranded/zombie pods -> repair Longhorn ->
        recycle CSI plugins -> serialized workload reconcile -> PDB-aware rebalance ->
        verify

    Individual phases are opt-OUT via -SkipStorageRepair, -SkipRestartWorkloads and
    -SkipRebalance. The older opt-in switches (-RepairStorage, -RestartWorkloads,
    -Rebalance) are still accepted but are now no-ops with a deprecation notice.

    The destructive phases used to be opt-in because the original blanket
    'rollout restart + force-delete' pass turned a simple "7 nodes left cordoned"
    problem into a Longhorn RWO deadlock. Every one of the safety rules learned from
    that incident is still enforced - only the need to remember the switches is gone:

      * Uncordon ONLY nodes that are Ready. NotReady nodes stay cordoned and are reported.
      * NEVER force-delete a pod that owns a ReadWriteOnce volume while its node is still
        tearing it down - that caused Multi-Attach / "mount point busy" deadlocks.
        RWO pods stuck Terminating are reported as a storage deadlock and repaired (by
        default now) by recycling the Longhorn CSI plugin on that node.
      * Storage is repaired BEFORE anything that consumes it, and workload restarts are
        gated on Longhorn volume health.
      * Workload restarts run BY DEFAULT now. They are still serialized
        (restart -> wait -> next) and gated on Longhorn volume health, and can be turned
        off with -SkipRestartWorkloads (or the legacy -SkipRestart).
      * Restarts are serialized (restart -> wait -> next) instead of restart-all-then-validate.
      * Drains use the Eviction API so PodDisruptionBudgets are honoured. The iiqstack and
        linguacafe PDBs are maxUnavailable: 0 and must not be bypassed.
      * Protected nodes (control plane, and kubernetes7 whose power switch is broken) are
        never cordoned or drained.
      * Every destructive action goes through one helper, so -DryRun/-WhatIf work and every
        change is recorded in a machine-readable run report.

.PARAMETER SkipRestartWorkloads
    Opt OUT of the deterministic full rolling restart of StatefulSets (serialized,
    storage-gated) followed by Deployments. The restart runs by default.

.PARAMETER SkipStorageRepair
    Opt OUT of touching longhorn-system: no Longhorn CSI plugin recycling and no purge of
    zombie Longhorn pods left behind on offline nodes. Storage repair runs by default
    because it is the gate every RWO consumer depends on.

.PARAMETER SkipRebalance
    Opt OUT of redistributing workloads off overloaded nodes using cordon + Eviction API
    drain (PodDisruptionBudgets respected, protected nodes skipped). Runs by default.

.PARAMETER RestartWorkloads
    Legacy opt-in switch. Accepted but no longer required - it is a no-op that emits a
    deprecation notice, because workload restarts already run by default.

.PARAMETER RepairStorage
    Legacy opt-in switch. Accepted but no longer required - it is a no-op that emits a
    deprecation notice, because storage repair already runs by default.

.PARAMETER Rebalance
    Legacy opt-in switch. Accepted but no longer required - it is a no-op that emits a
    deprecation notice, because the rebalance already runs by default.

.PARAMETER RebalanceThreshold
    Pods-per-node ratio (relative to average) that marks a node as overloaded. Default: 1.5.

.PARAMETER RolloutTimeout
    Seconds to wait for a single StatefulSet/Deployment rollout. Default: 180.

.PARAMETER MaxDurationMinutes
    Global time budget for the whole run. Default: 120 (raised from 45 because the full
    recovery - including the serialized restart of every workload - now runs by default).

.PARAMETER WaitForNodesMinutes
    Wait up to N minutes for the expected nodes to report Ready. Default: 0 (no wait).

.PARAMETER StuckTerminatingMinutes
    A pod Terminating longer than this while owning an RWO volume is treated as a storage
    deadlock. Default: 10.

.PARAMETER ExpectedServer
    Expected API server URL, used as a cluster-identity guard. Defaults to the value in
    WindowsLab/homelab-nodes.json.

.PARAMETER LogPath
    Transcript directory. Default: WindowsLab/logs.

.PARAMETER ReportPath
    Run report (JSON) path. Default: WindowsLab/logs/start-report-<timestamp>.json.

.PARAMETER DryRun
    Show every action that would be taken without performing any mutation.

.PARAMETER FailOnDegraded
    Exit 2 when the post-run verification still finds degraded workloads.

.PARAMETER SkipRestart
    Legacy switch. Still honoured: guarantees no workload restarts happen (equivalent to
    -SkipRestartWorkloads; both can be supplied together harmlessly).

.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -DryRun
    Preview the full recovery without changing anything. Start here.

.EXAMPLE
    PS> .\Start-K3sHomelab.ps1
    The default run: uncordon Ready nodes, purge stranded workloads, repair Longhorn,
    reconcile every workload serially, rebalance overloaded nodes and verify.

.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -SkipRestartWorkloads
    Uncordon + storage repair + rebalance, but leave running workloads alone.

.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -SkipStorageRepair -SkipRestartWorkloads -SkipRebalance
    Minimum-touch recovery: uncordon Ready nodes and purge stranded pods only.

.EXAMPLE
    PS> .\Start-K3sHomelab.ps1 -FailOnDegraded
    Full recovery, and exit 2 when the post-run verification still finds degraded
    workloads (useful from CI/cron).

.NOTES
    Requires: kubectl, pwsh 7+. Optional: ssh/sshpass for node telemetry.
    Platform: Windows, Linux, macOS (PowerShell 7+).
    Defaults: ALL recovery phases run. Only -FailOnDegraded (exit-code semantics) and the
              waiting/budget knobs remain opt-in.
    Exit codes: 0 = healthy, 1 = fatal error, 2 = completed with degraded workloads
                (only when -FailOnDegraded is supplied).
    Safety: this script never powers nodes on or off. Power the hardware on first, then run
            this script to uncordon and reconcile.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # ── Opt-out switches: every recovery phase runs unless it is explicitly skipped ──
    [Parameter()]
    [switch]$SkipStorageRepair,

    [Parameter()]
    [switch]$RepairMultipath,

    [Parameter()]
    [ValidatePattern('^[a-z0-9][a-z0-9.-]*$')]
    [string]$MultipathDebugPod,

    [Parameter()]
    [switch]$SkipRestartWorkloads,

    [Parameter()]
    [switch]$SkipRebalance,

    # ── Legacy opt-in switches: kept so existing invocations keep working. ──
    #    They are no-ops now, because the phases above already run by default.
    [Parameter()]
    [switch]$RestartWorkloads,

    [Parameter()]
    [switch]$RepairStorage,

    [Parameter()]
    [switch]$Rebalance,

    [Parameter()]
    [ValidateRange(1.0, 10.0)]
    [double]$RebalanceThreshold = 1.5,

    [Parameter()]
    [ValidateRange(30, 1800)]
    [int]$RolloutTimeout = 180,

    [Parameter()]
    [ValidateRange(1, 480)]
    [int]$MaxDurationMinutes = 120,

    [Parameter()]
    [ValidateRange(0, 240)]
    [int]$WaitForNodesMinutes = 0,

    [Parameter()]
    [ValidateRange(1, 180)]
    [int]$StuckTerminatingMinutes = 10,

    [Parameter()]
    [string]$ExpectedServer,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [string]$ReportPath,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$FailOnDegraded,

    [Parameter()]
    [switch]$SkipRestart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Effective phase flags: the full recovery runs by default ───────────
# Everything below reads these flags instead of the raw switches, so the default is
# "do the whole recovery" and each -Skip* switch is a deliberate opt-out.
$DoStorageRepair     = -not $SkipStorageRepair
$DoRebalance         = -not $SkipRebalance
# Restart is suppressed by either -SkipRestartWorkloads or the legacy -SkipRestart.
$DoRestartWorkloads  = (-not $SkipRestartWorkloads) -and (-not $SkipRestart)
# Callers that still pass an opt-in switch get a notice instead of a silent no-op.
$LegacyOptInSwitches = @()
if ($RestartWorkloads) { $LegacyOptInSwitches += '-RestartWorkloads' }
if ($RepairStorage) { $LegacyOptInSwitches += '-RepairStorage' }
if ($Rebalance) { $LegacyOptInSwitches += '-Rebalance' }

# Namespaces owned by platform components: never restarted by the reconcile phase.
$SkipNamespaces = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('kube-system', 'longhorn-system', 'argocd', 'cnpg-system', 'tailscale'),
    [System.StringComparer]::OrdinalIgnoreCase
)

# Longhorn is only touched by the storage-repair phase, never by the restart phase.
$StorageNamespace = 'longhorn-system'
$CsiPluginLabelSelector = 'app=longhorn-csi-plugin'

$script:DryRun = [bool]($DryRun -or $WhatIfPreference)
$script:StartedAt = Get-Date
$script:Deadline = $script:StartedAt.AddMinutes($MaxDurationMinutes)
$script:Actions = [System.Collections.Generic.List[object]]::new()
$script:Findings = [System.Collections.Generic.List[string]]::new()
$script:LockFile = Join-Path -Path $PSScriptRoot -ChildPath '.start-k3s-homelab.lock'
$script:TranscriptStarted = $false
$script:LockAcquired = $false

# ── Output helpers ─────────────────────────────────────────────────────
function Write-Step {
    param([string]$Text)
    Write-Host "`n$Text" -ForegroundColor Yellow
}
function Write-Ok {
    param([string]$Text)
    Write-Host "  [+] $Text" -ForegroundColor Green
}
function Write-Warn {
    param([string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}
function Write-Bad {
    param([string]$Text)
    Write-Host "  [-] $Text" -ForegroundColor Red
}
function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Gray
}
function Add-Finding {
    param([string]$Text)
    $script:Findings.Add($Text)
}
function Add-Action {
    param([string]$Type, [string]$Target, [string]$Detail)
    $script:Actions.Add([pscustomobject]@{
        ts     = (Get-Date).ToString('o')
        type   = $Type
        target = $Target
        detail = $Detail
    })
}
function Test-Budget {
    param([string]$Context)
    if ((Get-Date) -gt $script:Deadline) {
        throw "Global time budget ($MaxDurationMinutes minute(s)) exhausted during '$Context'. The cluster may be partially reconciled - inspect the run report and re-run."
    }
}

# ── kubectl wrapper: never silently swallow failures ────────────────────
function Invoke-Kubectl {
    <#
        Runs kubectl, retries transient API failures with backoff, and either throws
        (default) or returns a result object with Ok = $false (-AllowFailure).
        v1 piped everything to 2>$null, which is how "uncordon failed but we printed
        success anyway" was possible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$KubectlArgs,
        [switch]$AllowFailure,
        [int]$Retries = 2
    )

    $attempt = 0
    while ($true) {
        $output = & kubectl @KubectlArgs 2>&1
        $code = $LASTEXITCODE
        $text = ($output | Out-String).Trim()

        if ($code -eq 0) {
            return [pscustomobject]@{ Ok = $true; ExitCode = 0; Output = @($output) }
        }

        $transient = $text -match 'Unable to connect to the server|connection refused|TLS handshake timeout|i/o timeout|EOF|etcdserver: request timed out|context deadline exceeded'
        if ($transient -and $attempt -lt $Retries) {
            $wait = [math]::Pow(2, $attempt) * 2
            Write-Verbose "kubectl $($KubectlArgs -join ' ') failed (transient); retry $($attempt + 1)/$Retries in ${wait}s"
            Start-Sleep -Seconds $wait
            $attempt++
            continue
        }

        if ($AllowFailure) {
            return [pscustomobject]@{ Ok = $false; ExitCode = $code; Output = @($output) }
        }
        throw "kubectl $($KubectlArgs -join ' ') failed (exit $code): $text"
    }
}

function Get-K8sJson {
    <#
        Returns the .items collection for a resource type (or the object itself),
        or an empty array on failure. Never throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$KubectlArgs)

    $result = Invoke-Kubectl -KubectlArgs ($KubectlArgs + @('-o', 'json')) -AllowFailure
    if (-not $result.Ok) { return @() }
    $joined = ($result.Output | Out-String)
    if ([string]::IsNullOrWhiteSpace($joined)) { return @() }
    try { $parsed = $joined | ConvertFrom-Json } catch { return @() }
    if ($parsed.PSObject.Properties['items']) { return @($parsed.items) }
    return @($parsed)
}

function Get-Prop {
    <#
        StrictMode-safe property access (v1 used $_.spec.replicas, which throws when absent).
    #>
    [CmdletBinding()]
    param($Object, [string]$Name, $Default = $null)

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# ── Single choke point for every destructive action ─────────────────────
function Invoke-KubectlMutation {
    <#
        Honours -DryRun and -WhatIf, executes kubectl, and records the action for the
        run report. Returns $true when the mutation succeeded (or was simulated).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string[]]$KubectlArgs,
        [string]$ActionType = 'kubectl',
        [string]$Target = '',
        [switch]$AllowFailure
    )

    $cmdText = 'kubectl ' + ($KubectlArgs -join ' ')

    if ($script:DryRun) {
        Write-Info "[DRY-RUN] $Description"
        Add-Action -Type 'dry-run' -Target $Target -Detail $cmdText
        return $true
    }
    if (-not $PSCmdlet.ShouldProcess($Description, $cmdText)) {
        Add-Action -Type 'skipped' -Target $Target -Detail $Description
        return $false
    }

    $result = Invoke-Kubectl -KubectlArgs $KubectlArgs -AllowFailure:$AllowFailure
    if ($result.Ok) {
        Add-Action -Type $ActionType -Target $Target -Detail $cmdText
    }
    else {
        Add-Action -Type "$ActionType-failed" -Target $Target -Detail (($result.Output | Out-String).Trim())
    }
    return $result.Ok
}

function Get-MinutesSince {
    param([string]$Timestamp)
    if ([string]::IsNullOrWhiteSpace($Timestamp)) { return $null }
    try {
        $parsed = [System.DateTimeOffset]::Parse($Timestamp, [cultureinfo]::InvariantCulture)
    }
    catch { return $null }
    return [math]::Round(([System.DateTimeOffset]::UtcNow - $parsed).TotalMinutes, 1)
}

function Get-PvcMap {
    <#
        namespace/name -> PVC metadata including whether it is ReadWriteOnce.
        Used to decide whether a pod may be force-deleted (see Repair section).
    #>
    [CmdletBinding()]
    param()

    $map = @{}
    foreach ($pvc in (Get-K8sJson -KubectlArgs @('get', 'pvc', '-A'))) {
        $md = Get-Prop $pvc 'metadata'
        $sp = Get-Prop $pvc 'spec'
        $ns = Get-Prop $md 'namespace'
        $nm = Get-Prop $md 'name'
        if (-not $nm) { continue }
        $modes = @(Get-Prop $sp 'accessModes')
        $map["$ns/$nm"] = [pscustomobject]@{
            Namespace   = $ns
            Name        = $nm
            AccessModes = $modes
            IsRwo       = ($modes -contains 'ReadWriteOnce')
        }
    }
    return $map
}

function Get-PodPvcClaims {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns the collection of claims mounted by one pod; kept for caller readability')]
    param($Pod)

    $md = Get-Prop $Pod 'metadata'
    $sp = Get-Prop $Pod 'spec'
    $volumes = Get-Prop $sp 'volumes'
    if (-not $volumes) { return @() }

    $ns = Get-Prop $md 'namespace'
    $claims = [System.Collections.Generic.List[string]]::new()
    foreach ($volume in $volumes) {
        $claimName = Get-Prop (Get-Prop $volume 'persistentVolumeClaim') 'claimName'
        if ($claimName) { $claims.Add("$ns/$claimName") }
    }
    return @($claims)
}

function Get-StorageStatus {
    <#
        Longhorn health snapshot used as the gate before any RWO consumer is touched.
        Returns Ok = $true only when every attached volume is healthy and every Longhorn
        node allows scheduling.
    #>
    [CmdletBinding()]
    param()

    $volumes = Get-K8sJson -KubectlArgs @('get', 'volumes.longhorn.io', '-n', $StorageNamespace)
    $lhNodes = Get-K8sJson -KubectlArgs @('get', 'nodes.longhorn.io', '-n', $StorageNamespace)

    $attachedDegraded = [System.Collections.Generic.List[object]]::new()
    $detached = [System.Collections.Generic.List[string]]::new()
    $healthy = 0

    foreach ($volume in $volumes) {
        $name = Get-Prop (Get-Prop $volume 'metadata') 'name'
        $state = Get-Prop (Get-Prop $volume 'status') 'state'
        $robustness = Get-Prop (Get-Prop $volume 'status') 'robustness'

        if ($state -eq 'attached') {
            if ($robustness -eq 'healthy') { $healthy++ }
            else { $attachedDegraded.Add([pscustomobject]@{ Name = $name; Robustness = $robustness }) }
        }
        else {
            $detached.Add($name)
        }
    }

    $unschedulable = [System.Collections.Generic.List[string]]::new()
    foreach ($lhNode in $lhNodes) {
        $allow = Get-Prop (Get-Prop $lhNode 'spec') 'allowScheduling'
        if ($allow -eq $false) {
            $unschedulable.Add((Get-Prop (Get-Prop $lhNode 'metadata') 'name'))
        }
    }

    return [pscustomobject]@{
        Available           = ($volumes.Count -gt 0)
        VolumeCount         = $volumes.Count
        HealthyCount        = $healthy
        AttachedDegraded    = @($attachedDegraded)
        Detached            = @($detached)
        UnschedulableNodes  = @($unschedulable)
        Ok                  = ($volumes.Count -gt 0 -and $attachedDegraded.Count -eq 0 -and $unschedulable.Count -eq 0)
    }
}

function Wait-StorageReady {
    <#
        Polls Longhorn until every attached volume is healthy, or the budget/timeout runs out.
        Replaces v1's blind "restart everything and hope" behaviour.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$PollSeconds = 15
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $status = Get-StorageStatus
    if ($script:DryRun -and -not $status.Ok) {
        # A dry run must stay a fast preview: report the current state instead of waiting
        # for a convergence that a no-op run can never cause.
        Write-Info (("dry-run: not waiting for Longhorn to converge ({0}/{1} volumes healthy, {2} degraded, {3} longhorn node(s) unschedulable)" -f `
                $status.HealthyCount, $status.VolumeCount, $status.AttachedDegraded.Count, $status.UnschedulableNodes.Count))
        return $status
    }
    while (-not $status.Ok -and $sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Test-Budget 'waiting for Longhorn to converge'
        Write-Info ("storage: {0}/{1} volumes healthy, {2} degraded, {3} longhorn node(s) unschedulable - waiting {4}s" -f `
                $status.HealthyCount, $status.VolumeCount, $status.AttachedDegraded.Count, $status.UnschedulableNodes.Count, $PollSeconds)
        Start-Sleep -Seconds $PollSeconds
        $status = Get-StorageStatus
    }
    $sw.Stop()
    return $status
}

function Get-NodeState {
    <#
        Returns node name -> { Name, Ready, Unschedulable, IsProtected, IsExpected, OfflineReason }.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][object[]]$NodeObjects,
        [Parameter()][string[]]$ProtectedNodes = @(),
        [Parameter()][string[]]$ExpectedNodes = @()
    )

    $state = [ordered]@{}
    foreach ($node in $NodeObjects) {
        $name = Get-Prop (Get-Prop $node 'metadata') 'name'
        if (-not $name) { continue }

        $ready = $false
        $reason = ''
        foreach ($condition in @(Get-Prop (Get-Prop $node 'status') 'conditions')) {
            if ((Get-Prop $condition 'type') -eq 'Ready') {
                $ready = ((Get-Prop $condition 'status') -eq 'True')
                if (-not $ready) { $reason = [string](Get-Prop $condition 'reason') }
                break
            }
        }

        $state[$name] = [pscustomobject]@{
            Name          = $name
            Ready         = $ready
            Unschedulable = ((Get-Prop (Get-Prop $node 'spec') 'unschedulable') -eq $true)
            IsProtected   = ($ProtectedNodes -contains $name)
            IsExpected    = ($ExpectedNodes.Count -eq 0 -or $ExpectedNodes -contains $name)
            OfflineReason = $reason
        }
    }
    return $state
}

function Repair-PendingRwoMounts {
    <#
        Clears Longhorn/Kubelet stale mount state that appears after a rollout has
        already started. This is intentionally limited to Pending RWO pods scheduled
        on Ready nodes; stranded pods and terminating RWO pods are handled earlier.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string]$Reason = 'post-rollout')

    if (-not $DoStorageRepair) { return @() }

    $currentNodeState = Get-NodeState -NodeObjects (Get-K8sJson -KubectlArgs @('get', 'nodes')) `
        -ProtectedNodes $protectedNodes -ExpectedNodes $expectedNodes
    $currentPvcMap = Get-PvcMap
    $pendingRwoPods = [System.Collections.Generic.List[object]]::new()

    foreach ($pod in (Get-K8sJson -KubectlArgs @('get', 'pods', '-A'))) {
        $md = Get-Prop $pod 'metadata'
        $sp = Get-Prop $pod 'spec'
        $st = Get-Prop $pod 'status'
        $ns = Get-Prop $md 'namespace'
        if ($SkipNamespaces.Contains($ns)) { continue }
        if ((Get-Prop $st 'phase') -ne 'Pending') { continue }

        $nodeName = [string](Get-Prop $sp 'nodeName')
        if (-not $nodeName -or -not $currentNodeState.Contains($nodeName) -or -not $currentNodeState[$nodeName].Ready) { continue }

        $hasRwo = $false
        foreach ($claim in @(Get-PodPvcClaims -Pod $pod)) {
            if ($currentPvcMap.ContainsKey($claim) -and $currentPvcMap[$claim].IsRwo) { $hasRwo = $true; break }
        }
        if (-not $hasRwo) { continue }

        $pendingRwoPods.Add([pscustomobject]@{
            Namespace = $ns
            Name      = Get-Prop $md 'name'
            Node      = $nodeName
        })
    }

    if ($pendingRwoPods.Count -eq 0) { return @() }

    Write-Warn "$($pendingRwoPods.Count) Pending RWO pod(s) detected during $Reason - recycling CSI and cycling attachments."
    $repairedNodes = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($pod in $pendingRwoPods) {
        if ($repairedNodes.Contains($pod.Node)) { continue }
        Test-Budget "recycling CSI plugin on $($pod.Node) during $Reason"
        Write-Info "Recycling Longhorn CSI plugin on $($pod.Node) for post-rollout stale mount recovery..."
        $pluginPods = Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $StorageNamespace, '-l', $CsiPluginLabelSelector)
        foreach ($pluginPod in ($pluginPods | Where-Object { [string](Get-Prop (Get-Prop $_ 'spec') 'nodeName') -eq $pod.Node })) {
            $pluginName = Get-Prop (Get-Prop $pluginPod 'metadata') 'name'
            $null = Invoke-KubectlMutation -Description "restart longhorn-csi-plugin $pluginName on $($pod.Node)" `
                -KubectlArgs @('delete', 'pod', '-n', $StorageNamespace, $pluginName, '--wait=true') `
                -ActionType 'storage-repair' -Target $pluginName -AllowFailure
        }
        $null = $repairedNodes.Add($pod.Node)
    }

    if ($script:DryRun) {
        Write-Info 'dry-run: not waiting for recycled CSI plugin(s) or cycling Pending RWO pods.'
        return @($pendingRwoPods | ForEach-Object { "$($_.Namespace)/$($_.Name)" })
    }

    Write-Info "Waiting 30s for the recycled CSI plugin(s) before cycling Pending RWO pods..."
    Start-Sleep -Seconds 30

    $repairedPods = [System.Collections.Generic.List[string]]::new()
    foreach ($pod in $pendingRwoPods) {
        Test-Budget "cycling attachment for $($pod.Name) during $Reason"
        Write-Info "Cycling attachment for [$($pod.Namespace)] $($pod.Name): graceful delete so the volume detaches and reattaches..."
        $ok = Invoke-KubectlMutation -Description "gracefully delete stuck volume consumer $($pod.Namespace)/$($pod.Name)" `
            -KubectlArgs @('delete', 'pod', $pod.Name, '-n', $pod.Namespace, '--wait=true') `
            -ActionType 'attachment-cycle' -Target "$($pod.Namespace)/$($pod.Name)" -AllowFailure
        if ($ok) { $repairedPods.Add("$($pod.Namespace)/$($pod.Name)") }
    }

    if ($repairedPods.Count -gt 0) {
        Write-Info "Waiting 45s for repaired RWO pod(s) to reschedule..."
        Start-Sleep -Seconds 45
    }
    return @($repairedPods)
}

# ── Preflight ──────────────────────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  K3s Homelab - Resuming Full Capacity" -ForegroundColor Cyan
Write-Host "  (full recovery by default)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
if ($script:DryRun) {
    Write-Host "  MODE: DRY RUN - no changes will be made" -ForegroundColor Magenta
}
if ($WhatIfPreference) {
    Write-Host "  MODE: -WhatIf (equivalent to -DryRun for this script)" -ForegroundColor Magenta
}

# Make the effective run plan explicit - the point of the default is that a bare run does
# everything, so the only interesting output here is what has been opted out of.
$phasePlan = @(
    "uncordon Ready nodes            : ON (always)"
    "purge stranded/zombie pods      : ON (always)"
    "repair Longhorn + recycle CSI   : $(if ($DoStorageRepair) { 'ON' } else { 'SKIPPED (-SkipStorageRepair)' })"
    "serialized workload reconcile   : $(if ($DoRestartWorkloads) { 'ON' } else { 'SKIPPED' })"
    "PDB-aware rebalance             : $(if ($DoRebalance) { 'ON' } else { 'SKIPPED (-SkipRebalance)' })"
)
Write-Host "  Run plan:" -ForegroundColor DarkGray
foreach ($line in $phasePlan) { Write-Host "    - $line" -ForegroundColor DarkGray }
if ($LegacyOptInSwitches.Count -gt 0) {
    Write-Host (("  NOTE: {0} is deprecated and no longer required - " +
            'those phases run by default now.') -f ($LegacyOptInSwitches -join ', ')) -ForegroundColor Yellow
}

# Transcript + report destinations (both under WindowsLab/logs, which is gitignored).
if (-not $LogPath) { $LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'logs' }
if (-not (Test-Path -Path $LogPath)) {
    $null = New-Item -ItemType Directory -Path $LogPath -Force
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcriptFile = Join-Path -Path $LogPath -ChildPath "start-$stamp.log"
if (-not $ReportPath) {
    $ReportPath = Join-Path -Path $LogPath -ChildPath "start-report-$stamp.json"
}

try {
    Start-Transcript -Path $transcriptFile -Force | Out-Null
    $script:TranscriptStarted = $true
}
catch {
    Write-Warning "Could not start transcript at '$transcriptFile': $($_.Exception.Message)"
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl not found in PATH. Install it (https://kubernetes.io/docs/tasks/tools/) and ensure /usr/local/bin is on PATH."
}
if ($IsMacOS -and (($env:PATH -split ':') -notcontains '/usr/local/bin')) {
    Write-Warn "/usr/local/bin is not on PATH on this macOS host - kubectl/pwsh may not resolve in other shells."
}
Write-Verbose "Platform: $(if ($IsWindows) {'Windows'} elseif ($IsMacOS) {'macOS'} elseif ($IsLinux) {'Linux'} else {'Unknown'})"
Write-Verbose "PowerShell: $($PSVersionTable.PSVersion)"
Write-Verbose ("Parameters: SkipStorageRepair={0} SkipRestartWorkloads={1} SkipRebalance={2} RolloutTimeout={3} " -f `
        $SkipStorageRepair, $SkipRestartWorkloads, $SkipRebalance, $RolloutTimeout)
Write-Verbose ("Effective: DoStorageRepair={0} DoRestartWorkloads={1} DoRebalance={2} MaxDurationMinutes={3} " -f `
        $DoStorageRepair, $DoRestartWorkloads, $DoRebalance, $MaxDurationMinutes)
Write-Verbose ("Parameters: WaitForNodesMinutes={0} StuckTerminatingMinutes={1} DryRun={2} FailOnDegraded={3} SkipRestart={4} " -f `
        $WaitForNodesMinutes, $StuckTerminatingMinutes, $DryRun, $FailOnDegraded, $SkipRestart)
Write-Verbose "Legacy opt-in switches supplied: $(if ($LegacyOptInSwitches.Count -gt 0) { $LegacyOptInSwitches -join ', ' } else { 'none' })"

# Shared node registry - single source of truth for identity AND safety constraints.
$registryModule = Join-Path -Path $PSScriptRoot -ChildPath 'HomelabNodes.psm1'
if (-not (Test-Path -Path $registryModule)) {
    throw "Node registry module not found at '$registryModule'. Restore WindowsLab/HomelabNodes.psm1 and WindowsLab/homelab-nodes.json from git."
}
Import-Module $registryModule -Force -DisableNameChecking

$expectedNodes = @(Get-HomelabNodeNames)
$protectedNodes = @(Get-ProtectedNodeNames)
$neverPowerOffNodes = @(Get-NeverPowerOffNodeNames)
Write-Verbose "Expected nodes: $($expectedNodes -join ', ')"
Write-Verbose "Protected (never cordon/drain): $($protectedNodes -join ', ')"
Write-Verbose "Never power off: $($neverPowerOffNodes -join ', ')"

# Concurrency lock - v1 allowed two overlapping recovery runs to fight each other.
if (Test-Path -Path $script:LockFile) {
    $lockStale = $true
    try {
        $lock = (Get-Content -Path $script:LockFile -Raw) | ConvertFrom-Json
        $lockStale = $false
        if (Get-Prop $lock 'pid') {
            if (Get-Process -Id $lock.pid -ErrorAction SilentlyContinue) { $lockStale = $false }
            else { $lockStale = $true }
        }
        $lockAge = Get-MinutesSince ([string](Get-Prop $lock 'startedAt'))
        if ($null -ne $lockAge -and $lockAge -gt 720) { $lockStale = $true }
    }
    catch { $lockStale = $true }

    if (-not $lockStale) {
        throw "Another Start-K3sHomelab.ps1 run appears to be in progress. Lock file: $script:LockFile. If that run died, delete the lock file and re-run."
    }
    Write-Warn "Removing stale lock file ($script:LockFile)."
    Remove-Item -Path $script:LockFile -Force -ErrorAction SilentlyContinue
}
if (-not $script:DryRun) {
    [pscustomobject]@{
        pid       = $PID
        host      = [string](& { if ($env:COMPUTERNAME) { $env:COMPUTERNAME } elseif ($env:HOSTNAME) { $env:HOSTNAME } else { [System.Net.Dns]::GetHostName() } })
        user      = [string]$env:USER
        startedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -Path $script:LockFile -Encoding utf8
    $script:LockAcquired = $true
}

# Cluster identity guard: refuse to operate on an unexpected cluster.
$serverResult = Invoke-Kubectl -KubectlArgs @('config', 'view', '--minify', '-o', 'jsonpath={.clusters[0].cluster.server}') -AllowFailure
if (-not $serverResult.Ok) {
    throw "Cannot read the current kubeconfig context. Check KUBECONFIG / cluster reachability."
}
$actualServer = ($serverResult.Output | Out-String).Trim()
if (-not $ExpectedServer) { $ExpectedServer = [string](Get-HomelabApiServer) }
if ($ExpectedServer -and $actualServer -and $actualServer -ne $ExpectedServer) {
    throw "Cluster identity mismatch: kubeconfig points at '$actualServer' but the registry expects '$ExpectedServer'. Refusing to continue. Pass -ExpectedServer only if you are certain."
}
Write-Ok "Cluster identity verified: $actualServer"

$finalExitCode = 0

try {
    # ── Step 1: Inventory ────────────────────────────────────────────────
    Write-Step "[1/7] Inventory - expected vs actual nodes"

    $nodeState = Get-NodeState -NodeObjects (Get-K8sJson -KubectlArgs @('get', 'nodes')) `
        -ProtectedNodes $protectedNodes -ExpectedNodes $expectedNodes

    Write-Info "Registry expects $($expectedNodes.Count) node(s); cluster reports $($nodeState.Count)."

    $missingNodes = @($expectedNodes | Where-Object { -not $nodeState.Contains($_) })
    if ($missingNodes.Count -gt 0) {
        Write-Bad "Expected node(s) absent from the cluster: $($missingNodes -join ', ')"
        Add-Finding "Expected node(s) absent from cluster: $($missingNodes -join ', ')"
    }

    $unexpectedNodes = @($nodeState.Values | Where-Object { -not $_.IsExpected } | ForEach-Object { $_.Name })
    if ($unexpectedNodes.Count -gt 0) {
        Write-Warn "Node(s) present but not in the registry (registry drift): $($unexpectedNodes -join ', ')"
        Add-Finding "Unregistered node(s) present: $($unexpectedNodes -join ', ')"
    }

    $notReadyNodes = @($nodeState.Values | Where-Object { -not $_.Ready })
    if ($notReadyNodes.Count -gt 0) {
        Write-Warn "NotReady node(s): $(($notReadyNodes | ForEach-Object { $_.Name }) -join ', ')"
    }

    if ($WaitForNodesMinutes -gt 0 -and $notReadyNodes.Count -gt 0) {
        Write-Info "Waiting up to $WaitForNodesMinutes minute(s) for NotReady nodes to rejoin..."
        $waitUntil = (Get-Date).AddMinutes($WaitForNodesMinutes)
        while ((Get-Date) -lt $waitUntil) {
            Test-Budget 'waiting for nodes to rejoin'
            Start-Sleep -Seconds 15
            $nodeState = Get-NodeState -NodeObjects (Get-K8sJson -KubectlArgs @('get', 'nodes')) `
                -ProtectedNodes $protectedNodes -ExpectedNodes $expectedNodes
            $notReadyNodes = @($nodeState.Values | Where-Object { -not $_.Ready })
            if ($notReadyNodes.Count -eq 0) { break }
            Write-Info "still NotReady: $(($notReadyNodes | ForEach-Object { $_.Name }) -join ', ')"
        }
    }

    # ── Step 2: Uncordon ONLY Ready nodes ────────────────────────────────
    Write-Step "[2/7] Uncordoning nodes"

    $cordonedBefore = @($nodeState.Values | Where-Object { $_.Unschedulable })
    $uncordonTargets = @($cordonedBefore | Where-Object { $_.Ready })
    $cordonedNotReady = @($cordonedBefore | Where-Object { -not $_.Ready })
    $uncordoned = [System.Collections.Generic.List[string]]::new()

    if ($cordonedBefore.Count -eq 0) {
        Write-Ok "No cordoned nodes - the cluster is already schedulable."
    }
    else {
        Write-Info "Cordoned: $(($cordonedBefore | ForEach-Object { $_.Name }) -join ', ')"
        foreach ($node in $uncordonTargets) {
            Test-Budget "uncordoning $($node.Name)"
            if ($node.IsProtected) {
                # Protected nodes must never be CORDONED; un-cordoning one is always correct.
                Write-Warn "$($node.Name) is a protected node but was cordoned - uncordoning it."
                Add-Finding "Protected node $($node.Name) was found cordoned."
            }
            $ok = Invoke-KubectlMutation -Description "uncordon $($node.Name)" `
                -KubectlArgs @('uncordon', $node.Name) -ActionType 'uncordon' -Target $node.Name -AllowFailure
            if ($ok) {
                Write-Ok "$($node.Name) uncordoned"
                $uncordoned.Add($node.Name)
            }
            else {
                Write-Bad "Failed to uncordon $($node.Name) - see run report"
                Add-Finding "Failed to uncordon $($node.Name)"
            }
        }
        foreach ($node in $cordonedNotReady) {
            Write-Warn "$($node.Name) is NotReady - leaving it cordoned until it rejoins (v1 uncordoned these and then reported success)."
            Add-Finding "Left cordoned because NotReady: $($node.Name)"
        }
    }

    # Refresh node state after uncordoning so later steps see reality.
    $nodeState = Get-NodeState -NodeObjects (Get-K8sJson -KubectlArgs @('get', 'nodes')) `
        -ProtectedNodes $protectedNodes -ExpectedNodes $expectedNodes

    # ── Step 3: Diagnose workloads and storage ───────────────────────────
    Write-Step "[3/7] Diagnosing workloads and storage"

    $pvcMap = Get-PvcMap
    $allPods = Get-K8sJson -KubectlArgs @('get', 'pods', '-A')
    $clusterNodeNames = @($nodeState.Keys)

    $strandedPods = [System.Collections.Generic.List[object]]::new()
    $zombiePods = [System.Collections.Generic.List[object]]::new()
    $rwoDeadlocks = [System.Collections.Generic.List[object]]::new()
    $unschedulablePods = [System.Collections.Generic.List[object]]::new()
    $crashPods = [System.Collections.Generic.List[object]]::new()
    $volumeStuckPods = [System.Collections.Generic.List[object]]::new()

    foreach ($pod in $allPods) {
        $md = Get-Prop $pod 'metadata'
        $sp = Get-Prop $pod 'spec'
        $st = Get-Prop $pod 'status'
        $ns = Get-Prop $md 'namespace'
        $name = Get-Prop $md 'name'

        # Platform namespaces (longhorn-system, kube-system, ...) are handled by the
        # storage-repair step and are never restarted by the reconcile step.
        if ($SkipNamespaces.Contains($ns)) { continue }

        $phase = Get-Prop $st 'phase'
        $nodeName = [string](Get-Prop $sp 'nodeName')
        $deletionTs = Get-Prop $md 'deletionTimestamp'
        $terminatingMinutes = $null
        if ($deletionTs) { $terminatingMinutes = Get-MinutesSince ([string]$deletionTs) }

        $hasRwo = $false
        foreach ($claim in @(Get-PodPvcClaims -Pod $pod)) {
            if ($pvcMap.ContainsKey($claim) -and $pvcMap[$claim].IsRwo) { $hasRwo = $true; break }
        }

        $onDeadNode = $false
        if ($nodeName) {
            if (-not ($clusterNodeNames -contains $nodeName)) { $onDeadNode = $true }
            elseif (-not $nodeState[$nodeName].Ready) { $onDeadNode = $true }
        }

        $reasons = [System.Collections.Generic.List[string]]::new()
        foreach ($cs in @(Get-Prop $st 'containerStatuses')) {
            $reason = Get-Prop (Get-Prop (Get-Prop $cs 'state') 'waiting') 'reason'
            if ($reason) { $reasons.Add([string]$reason) }
        }

        $record = [pscustomobject]@{
            Namespace          = $ns
            Name               = $name
            Node               = $nodeName
            Phase              = $phase
            Reasons            = @($reasons)
            HasRwo             = $hasRwo
            TerminatingMinutes = $terminatingMinutes
        }

        if ($deletionTs -and $hasRwo -and -not $onDeadNode -and
            $null -ne $terminatingMinutes -and $terminatingMinutes -ge $StuckTerminatingMinutes) {
            # The v1 killer: force-deleting these caused Multi-Attach / "mount point busy".
            $rwoDeadlocks.Add($record)
        }
        elseif ($onDeadNode) {
            $strandedPods.Add($record)
        }
        elseif ($phase -eq 'Unknown' -or ($deletionTs -and $null -ne $terminatingMinutes -and $terminatingMinutes -ge $StuckTerminatingMinutes)) {
            $zombiePods.Add($record)
        }
        elseif ($phase -eq 'Pending' -and -not $nodeName) {
            $unschedulablePods.Add($record)
        }
        elseif ($phase -eq 'Pending' -and $nodeName -and $hasRwo) {
            # Scheduled to a Ready node but the volume will not attach/mount. This is the
            # activemq-0 / mail-0 case ("already mounted or mount point busy" / Multi-Attach)
            # and is repairable by recycling the CSI plugin (see step 4b) - never by
            # force-deleting the pod.
            $volumeStuckPods.Add($record)
        }
        elseif (@($reasons | Where-Object { $_ -in @('CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull', 'CreateContainerError', 'RunContainerError') }).Count -gt 0) {
            $crashPods.Add($record)
        }
    }

    Write-Info "Stranded on dead/offline node : $($strandedPods.Count)"
    Write-Info "Zombie (Unknown / stuck Term) : $($zombiePods.Count)"
    Write-Info "Unschedulable (Pending)       : $($unschedulablePods.Count)"
    Write-Info "Crash/ImagePull/CreateError   : $($crashPods.Count)"
    Write-Info "RWO volume deadlocks          : $($rwoDeadlocks.Count)"
    Write-Info "Blocked on volume mount       : $($volumeStuckPods.Count)"

    foreach ($pod in $strandedPods) {
        Write-Warn "stranded: [$($pod.Namespace)] $($pod.Name) on '$($pod.Node)' (node not Ready)"
    }
    foreach ($pod in $rwoDeadlocks) {
        Write-Bad "deadlock: [$($pod.Namespace)] $($pod.Name) Terminating $($pod.TerminatingMinutes)m holding an RWO volume on Ready node '$($pod.Node)'"
        Add-Finding "RWO deadlock: $($pod.Namespace)/$($pod.Name) on $($pod.Node)"
    }
    foreach ($pod in $unschedulablePods) {
        Write-Warn "unschedulable: [$($pod.Namespace)] $($pod.Name) ($($pod.Reasons -join ', '))"
    }

    # Storage snapshot (drives both repair priority and the reconcile gate).
    $storageStatus = Get-StorageStatus
    if ($storageStatus.Available) {
        Write-Info ("Longhorn: {0}/{1} volumes healthy, {2} degraded, {3} detached, {4} node(s) not scheduling" -f `
                $storageStatus.HealthyCount, $storageStatus.VolumeCount,
            $storageStatus.AttachedDegraded.Count, $storageStatus.Detached.Count,
            $storageStatus.UnschedulableNodes.Count)
        if (-not $storageStatus.Ok) { Add-Finding "Longhorn not fully healthy at diagnosis time" }
    }
    else {
        Write-Info "Longhorn not detected - storage-specific repair will be skipped."
    }

    # ── Step 4: Repair (storage first, then stranded workloads) ──────────
    Write-Step "[4/7] Repair - storage first, then stranded workloads"

    $repairedSomething = $false
    $deadNodeNames = @($nodeState.Values | Where-Object { -not $_.Ready } | ForEach-Object { $_.Name })
    $deadNodeNames += $missingNodes

    # 4a - Longhorn pods left Terminating on nodes that are gone.
    #      (v1 could never do this: longhorn-system was in $SkipNamespaces.)
    if ($DoStorageRepair -and $storageStatus.Available) {
        foreach ($lhPod in (Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $StorageNamespace))) {
            $lhName = Get-Prop (Get-Prop $lhPod 'metadata') 'name'
            $lhNode = [string](Get-Prop (Get-Prop $lhPod 'spec') 'nodeName')
            $lhDeletion = Get-Prop (Get-Prop $lhPod 'metadata') 'deletionTimestamp'
            if (-not $lhName -or -not $lhNode -or -not $lhDeletion) { continue }
            if (-not ($deadNodeNames -contains $lhNode)) { continue }

            $age = Get-MinutesSince ([string]$lhDeletion)
            Write-Warn "zombie Longhorn pod on offline node: $lhName ($lhNode, Terminating ${age}m)"
            Test-Budget "removing zombie longhorn pod $lhName"
            $ok = Invoke-KubectlMutation -Description "remove zombie longhorn pod $lhName on $lhNode" `
                -KubectlArgs @('delete', 'pod', '-n', $StorageNamespace, $lhName, '--grace-period=0', '--force') `
                -ActionType 'storage-repair' -Target $lhName -AllowFailure
            if ($ok) { $repairedSomething = $true }
        }
    }

    # 4b - Pods blocked on storage (RWO deadlock, or Pending on a Ready node because the
    #      volume cannot attach/mount). NEVER force-delete these - recycle the CSI plugin
    #      instead, which is exactly what unblocked activemq-0/mail-0 in the real incident.
    $storageBlockedPods = [System.Collections.Generic.List[object]]::new()
    foreach ($pod in $rwoDeadlocks) { $storageBlockedPods.Add($pod) }
    foreach ($pod in $volumeStuckPods) { $storageBlockedPods.Add($pod) }

    if ($storageBlockedPods.Count -gt 0) {
        if (-not $DoStorageRepair) {
            foreach ($pod in $storageBlockedPods) {
                Write-Warn "[$($pod.Namespace)] $($pod.Name) is blocked on storage at node '$($pod.Node)' (phase=$($pod.Phase)), but storage repair was skipped (-SkipStorageRepair). Drop that switch to let the script recycle the Longhorn CSI plugin."
            }
        }
        else {
            $repairedNodes = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($pod in $storageBlockedPods) {
                if (-not $pod.Node -or $repairedNodes.Contains($pod.Node)) { continue }
                Test-Budget "recycling CSI plugin on $($pod.Node)"
                Write-Info "Recycling Longhorn CSI plugin on $($pod.Node) to clear the stale mount for $($pod.Name)..."
                $pluginPods = Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $StorageNamespace, '-l', $CsiPluginLabelSelector)
                foreach ($pluginPod in ($pluginPods | Where-Object { [string](Get-Prop (Get-Prop $_ 'spec') 'nodeName') -eq $pod.Node })) {
                    $pluginName = Get-Prop (Get-Prop $pluginPod 'metadata') 'name'
                    $ok = Invoke-KubectlMutation -Description "restart longhorn-csi-plugin $pluginName on $($pod.Node)" `
                        -KubectlArgs @('delete', 'pod', '-n', $StorageNamespace, $pluginName, '--wait=true') `
                        -ActionType 'storage-repair' -Target $pluginName -AllowFailure
                    if ($ok) { $repairedSomething = $true }
                }
                $null = $repairedNodes.Add($pod.Node)
            }
            if ($script:DryRun) {
                Write-Info 'dry-run: not waiting for the recycled CSI plugin(s).'
            }
            else {
                Write-Info "Waiting 30s for the recycled CSI plugin(s) before continuing..."
                Start-Sleep -Seconds 30
            }

            # Some attachments stay wedged in the CSI flow even after the plugin recycle.
            # What actually unblocked activemq-0/mail-0 in the real incident: a GRACEFUL
            # delete of the volume consumer so the attach/detach controller cycles the
            # attachment (container never started, so no data is at risk). Deliberately
            # NOT --force and NOT --grace-period=0 - that recreates the RWO deadlock.
            $stillBlocked = [System.Collections.Generic.List[object]]::new()
            $livePods = Get-K8sJson -KubectlArgs @('get', 'pods', '-A')
            foreach ($candidate in $storageBlockedPods) {
                foreach ($pod in $livePods) {
                    $md = Get-Prop $pod 'metadata'
                    if ((Get-Prop $md 'namespace') -eq $candidate.Namespace -and (Get-Prop $md 'name') -eq $candidate.Name) {
                        $phase = Get-Prop (Get-Prop $pod 'status') 'phase'
                        if ($phase -notin @('Running', 'Succeeded')) { $stillBlocked.Add($candidate) }
                        break
                    }
                }
            }
            foreach ($pod in $stillBlocked) {
                Test-Budget "cycling attachment for $($pod.Name)"
                Write-Info "Cycling attachment for [$($pod.Namespace)] $($pod.Name): graceful delete so the volume detaches and reattaches..."
                $ok = Invoke-KubectlMutation -Description "gracefully delete stuck volume consumer $($pod.Namespace)/$($pod.Name)" `
                    -KubectlArgs @('delete', 'pod', $pod.Name, '-n', $pod.Namespace, '--wait=true') `
                    -ActionType 'attachment-cycle' -Target "$($pod.Namespace)/$($pod.Name)" -AllowFailure
                if ($ok) { $repairedSomething = $true }
            }
            if ($stillBlocked.Count -gt 0) {
                if ($script:DryRun) {
                    Write-Info 'dry-run: not waiting for the cycled pods to reschedule.'
                }
                else {
                    Write-Info "Waiting 45s for the cycled pods to reschedule..."
                    Start-Sleep -Seconds 45
                }
            }
        }
    }

    # 4c - Stranded / zombie / kubelet-state-leak pods.
    #      Safe to force-delete: either the node hosting them is gone, or the container
    #      never started (CreateContainerError / RunContainerError).
    $podRepairTargets = [System.Collections.Generic.List[object]]::new()
    foreach ($pod in $strandedPods) { $podRepairTargets.Add($pod) }
    foreach ($pod in $zombiePods) { $podRepairTargets.Add($pod) }
    foreach ($pod in $crashPods) {
        if (@($pod.Reasons | Where-Object { $_ -in @('CreateContainerError', 'RunContainerError') }).Count -gt 0) {
            $podRepairTargets.Add($pod)
        }
        else {
            Write-Info "report-only (crashlooping, not auto-deleted): [$($pod.Namespace)] $($pod.Name) ($($pod.Reasons -join ', '))"
        }
    }

    if ($podRepairTargets.Count -eq 0) {
        Write-Ok "No stranded or zombie pods to purge."
    }
    else {
        foreach ($pod in $podRepairTargets) {
            Test-Budget "purging stuck pod $($pod.Name)"
            $rwoNote = if ($pod.HasRwo) { 'holds RWO volume, but node is gone/container never started' } else { 'no RWO volume' }
            Write-Info "Purging stuck pod [$($pod.Namespace)] $($pod.Name) (phase=$($pod.Phase); $rwoNote)"
            $ok = Invoke-KubectlMutation -Description "force-delete stuck pod $($pod.Namespace)/$($pod.Name)" `
                -KubectlArgs @('delete', 'pod', $pod.Name, '-n', $pod.Namespace, '--grace-period=0', '--force') `
                -ActionType 'pod-repair' -Target "$($pod.Namespace)/$($pod.Name)" -AllowFailure
            if ($ok) { $repairedSomething = $true }
        }
    }

    foreach ($pod in $unschedulablePods) {
        Write-Info "unschedulable pod left to the scheduler: [$($pod.Namespace)] $($pod.Name)"
    }

    if ($repairedSomething) {
        if ($script:DryRun) {
            Write-Info 'dry-run: not waiting for repaired workloads to be recreated.'
        }
        else {
            Write-Info "Waiting 20s for repaired workloads to be recreated..."
            Start-Sleep -Seconds 20
        }
    }

    # ── Step 5: Reconcile workloads (OPT-IN) ─────────────────────────────
    Write-Step "[5/7] Reconcile workloads"

function Get-ManagedResource {
    <#
    .SYNOPSIS
        Returns user-managed (non-platform) workloads of a given kind.
        (Singular approved noun; plural meaning documented in the synopsis.)
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns the set of managed workloads for a kind; singular spelling refers to one item')]
    param([Parameter(Mandatory)][string]$ResourceType)

        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($item in (Get-K8sJson -KubectlArgs @('get', $ResourceType, '-A'))) {
            $ns = Get-Prop (Get-Prop $item 'metadata') 'namespace'
            if ($SkipNamespaces.Contains($ns)) { continue }
            $replicas = Get-Prop (Get-Prop $item 'spec') 'replicas'
            if ($null -eq $replicas) { $replicas = 1 }
            if ([int]$replicas -le 0) { continue }
            $result.Add($item)
        }
        return @($result)
    }

    function Test-BudgetSoft {
        if ((Get-Date) -gt $script:Deadline) {
            Write-Warn "Global time budget reached - stopping further waits and moving to verification."
            Add-Finding "Time budget exhausted before reconcile completed"
            return $false
        }
        return $true
    }

    if (-not $DoRestartWorkloads) {
        if ($SkipRestart -and $SkipRestartWorkloads) {
            Write-Info "Restart phase skipped (-SkipRestart and -SkipRestartWorkloads)."
        }
        elseif ($SkipRestartWorkloads) {
            Write-Info "Restart phase skipped (-SkipRestartWorkloads)."
        }
        else {
            Write-Info "Restart phase skipped (-SkipRestart)."
        }
        Add-Finding 'Workload restart phase skipped by request'
    }
    else {
        # Gate on storage health BEFORE touching any RWO consumer.
        if ($storageStatus.Available -and -not $storageStatus.Ok) {
            Write-Warn "Longhorn is not fully healthy - waiting for it to converge before restarting RWO consumers."
            $storageStatus = Wait-StorageReady -TimeoutSeconds 600 -PollSeconds 15
        }
        if ($storageStatus.Available -and -not $storageStatus.Ok) {
            Write-Bad ("Proceeding with degraded storage: {0} attached volume(s) not healthy." -f $storageStatus.AttachedDegraded.Count)
            Add-Finding "Reconcile started with degraded Longhorn volumes"
        }

        # Phase A - StatefulSets, strictly serialized: restart -> wait -> next.
        $statefulsets = @(Get-ManagedResource -ResourceType 'statefulsets')
        Write-Info "Phase A: serialized rolling restart of $($statefulsets.Count) StatefulSet(s)"
        $stalledWorkloads = [System.Collections.Generic.List[string]]::new()

        foreach ($sts in $statefulsets) {
            if (-not (Test-BudgetSoft)) { break }
            $ns = Get-Prop (Get-Prop $sts 'metadata') 'namespace'
            $name = Get-Prop (Get-Prop $sts 'metadata') 'name'
            $target = "$ns/$name"

            # Per-resource re-gate: a mid-run storage degradation must not cascade.
            if ($storageStatus.Available) {
                $gate = Get-StorageStatus
                if (-not $gate.Ok) { $gate = Wait-StorageReady -TimeoutSeconds 300 -PollSeconds 15 }
                if (-not $gate.Ok) {
                    Write-Warn "$target - Longhorn still degraded; skipping restart to avoid an RWO deadlock."
                    Add-Finding "Skipped restart of $target (storage degraded)"
                    $stalledWorkloads.Add($target)
                    continue
                }
            }

            $ok = Invoke-KubectlMutation -Description "rollout restart statefulset/$name -n $ns" `
                -KubectlArgs @('rollout', 'restart', "statefulset/$name", '-n', $ns) `
                -ActionType 'rollout-restart' -Target $target -AllowFailure
            if (-not $ok) {
                $stalledWorkloads.Add($target)
                continue
            }
            if ($script:DryRun) { continue }

            Write-Host "    waiting: $target " -NoNewline -ForegroundColor DarkGray
            $rollout = Invoke-Kubectl -KubectlArgs @('rollout', 'status', "statefulset/$name", '-n', $ns, "--timeout=${RolloutTimeout}s") -AllowFailure
            if ($rollout.Ok) {
                Write-Host "[READY]" -ForegroundColor Green
            }
            else {
                Write-Host "[STALLED]" -ForegroundColor Yellow
                Write-Warn "$target did not become ready within ${RolloutTimeout}s. NOT force-deleting (v1 did, which caused the RWO deadlock) - storage repair already runs by default, so investigate Longhorn if this repeats."
                Add-Finding "StatefulSet stalled: $target"
                $stalledWorkloads.Add($target)
            }
        }

        if ($stalledWorkloads.Count -gt 0) {
            $repairedRwoPods = @(Repair-PendingRwoMounts -Reason 'StatefulSet reconcile')
            if ($repairedRwoPods.Count -gt 0 -and -not $script:DryRun) {
                Write-Info "Rechecking stalled StatefulSet rollout(s) after RWO mount repair..."
                foreach ($target in @($stalledWorkloads)) {
                    if ($target -notmatch '^(?<ns>[^/]+)/(?<name>.+)$') { continue }
                    $ns = $Matches['ns']
                    $name = $Matches['name']
                    Write-Host "    rechecking: $target " -NoNewline -ForegroundColor DarkGray
                    $rollout = Invoke-Kubectl -KubectlArgs @('rollout', 'status', "statefulset/$name", '-n', $ns, "--timeout=${RolloutTimeout}s") -AllowFailure
                    if ($rollout.Ok) {
                        Write-Host "[READY]" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[STALLED]" -ForegroundColor Yellow
                    }
                }
            }
        }

        # Phase B - Deployments (application services), serialized too.
        $deployments = @(Get-ManagedResource -ResourceType 'deployments')
        Write-Info "Phase B: serialized rolling restart of $($deployments.Count) Deployment(s)"

        foreach ($deploy in $deployments) {
            if (-not (Test-BudgetSoft)) { break }
            $ns = Get-Prop (Get-Prop $deploy 'metadata') 'namespace'
            $name = Get-Prop (Get-Prop $deploy 'metadata') 'name'
            $target = "$ns/$name"

            $ok = Invoke-KubectlMutation -Description "rollout restart deployment/$name -n $ns" `
                -KubectlArgs @('rollout', 'restart', "deployment/$name", '-n', $ns) `
                -ActionType 'rollout-restart' -Target $target -AllowFailure
            if (-not $ok) {
                $stalledWorkloads.Add($target)
                continue
            }
            if ($script:DryRun) { continue }

            Write-Host "    waiting: $target " -NoNewline -ForegroundColor DarkGray
            $rollout = Invoke-Kubectl -KubectlArgs @('rollout', 'status', "deployment/$name", '-n', $ns, "--timeout=${RolloutTimeout}s") -AllowFailure
            if ($rollout.Ok) {
                Write-Host "[READY]" -ForegroundColor Green
            }
            else {
                Write-Host "[SLOW]" -ForegroundColor Yellow
                Write-Info "$target is still rolling out - leaving it to its controllers (no force actions)."
            }
        }

        if ($stalledWorkloads.Count -gt 0) {
            Write-Warn "$($stalledWorkloads.Count) workload(s) still need attention: $($stalledWorkloads -join ', ')"
        }
        else {
            Write-Ok "Every restarted workload reported ready."
        }
    }

# ── Step 6: Rebalance (OPT-IN, PDB-aware) ────────────────────────────
    Write-Step "[6/7] Rebalance workload distribution"

    if (-not $DoRebalance) {
        Write-Info "Skipped (-SkipRebalance)."
    }
    else {
        # Protected nodes (control plane, kubernetes7) are never cordoned or drained.
        $candidates = @($nodeState.Values | Where-Object { $_.Ready -and -not $_.IsProtected } | ForEach-Object { $_.Name })
        Write-Info "Rebalance-eligible nodes: $($candidates.Count) (protected excluded: $($protectedNodes -join ', '))"

        $daemonSetPods = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($pod in $allPods) {
            foreach ($ownerRef in @(Get-Prop (Get-Prop $pod 'metadata') 'ownerReferences')) {
                if ((Get-Prop $ownerRef 'kind') -eq 'DaemonSet') {
                    $null = $daemonSetPods.Add([string](Get-Prop (Get-Prop $pod 'metadata') 'name'))
                    break
                }
            }
        }

        $podCountByNode = @{}
        foreach ($nodeName in $candidates) { $podCountByNode[$nodeName] = 0 }

        foreach ($pod in $allPods) {
            $ns = Get-Prop (Get-Prop $pod 'metadata') 'namespace'
            if ($SkipNamespaces.Contains($ns)) { continue }
            $podName = [string](Get-Prop (Get-Prop $pod 'metadata') 'name')
            $nodeName = [string](Get-Prop (Get-Prop $pod 'spec') 'nodeName')
            if (-not $nodeName -or -not $podCountByNode.ContainsKey($nodeName)) { continue }
            if ($daemonSetPods.Contains($podName)) { continue }
            if ((Get-Prop (Get-Prop $pod 'status') 'phase') -ne 'Running') { continue }
            $podCountByNode[$nodeName]++
        }

        $totalMovable = ($podCountByNode.Values | Measure-Object -Sum).Sum
        $average = 0
        if ($candidates.Count -gt 0) { $average = [math]::Round($totalMovable / $candidates.Count, 1) }

        Write-Info "Worker distribution (average $average movable pods/node):"
        $overloaded = [System.Collections.Generic.List[string]]::new()
        foreach ($nodeName in ($candidates | Sort-Object { $podCountByNode[$_] } -Descending)) {
            $count = $podCountByNode[$nodeName]
            $isOverloaded = ($average -gt 0 -and ($count / $average) -ge $RebalanceThreshold)
            $marker = if ($isOverloaded) { ' <-- OVERLOADED' } else { '' }
            Write-Info "  $nodeName : $count pods$marker"
            if ($isOverloaded) { $overloaded.Add($nodeName) }
        }

        if ($overloaded.Count -eq 0) {
            Write-Ok "All eligible nodes are within $($RebalanceThreshold)x the average."
        }
        else {
            foreach ($nodeName in $overloaded) {
                Test-Budget "rebalancing $nodeName"
                if ($protectedNodes -contains $nodeName) {
                    Write-Warn "Refusing to drain protected node '$nodeName'."
                    Add-Finding "Refused to drain protected node $nodeName"
                    continue
                }

                Write-Info "Draining $nodeName via the Eviction API (PodDisruptionBudgets are honoured)..."
                # v1 used 'kubectl delete pod --grace-period=30' here, which bypasses PDBs
                # entirely - unsafe with the maxUnavailable: 0 iiqstack/linguacafe PDBs.
                $ok = Invoke-KubectlMutation -Description "drain $nodeName (eviction API, PDB-aware)" `
                    -KubectlArgs @('drain', $nodeName, '--ignore-daemonsets', '--delete-emptydir-data', '--timeout=180s') `
                    -ActionType 'drain' -Target $nodeName -AllowFailure

                if (-not $ok) {
                    Write-Warn "Drain of $nodeName reported blocked/failed - pods guarded by PodDisruptionBudget were left in place (this is the intended safe behaviour)."
                    Add-Finding "Drain of $nodeName was partially blocked (likely a PDB with maxUnavailable: 0)"
                }
                # Always restore schedulability, even when the drain was blocked.
                $null = Invoke-KubectlMutation -Description "uncordon $nodeName after rebalance" `
                    -KubectlArgs @('uncordon', $nodeName) -ActionType 'uncordon' -Target $nodeName -AllowFailure
                Write-Ok "$nodeName rebalanced and uncordoned."
            }
        }
    }

# ── Step 7: Verify (the checks v1 was missing) ───────────────────────
    Write-Step "[7/7] Verification"

    $nodeStateAfter = Get-NodeState -NodeObjects (Get-K8sJson -KubectlArgs @('get', 'nodes')) `
        -ProtectedNodes $protectedNodes -ExpectedNodes $expectedNodes
    $stillCordonedReady = @($nodeStateAfter.Values | Where-Object { $_.Unschedulable -and $_.Ready } | ForEach-Object { $_.Name })
    $stillNotReady = @($nodeStateAfter.Values | Where-Object { -not $_.Ready } | ForEach-Object { $_.Name })

    if ($stillCordonedReady.Count -gt 0) {
        Write-Bad "Ready-but-cordoned node(s) remain: $($stillCordonedReady -join ', ')"
        Add-Finding "Nodes still cordoned after run: $($stillCordonedReady -join ', ')"
    }
    else {
        Write-Ok "No Ready node is left cordoned."
    }
    if ($stillNotReady.Count -gt 0) {
        Write-Warn "Offline / NotReady node(s): $($stillNotReady -join ', ')"
        Add-Finding "NotReady node(s) at end of run: $($stillNotReady -join ', ')"
    }

    foreach ($node in (Get-K8sJson -KubectlArgs @('get', 'nodes'))) {
        $nodeName = Get-Prop (Get-Prop $node 'metadata') 'name'
        foreach ($condition in @(Get-Prop (Get-Prop $node 'status') 'conditions')) {
            $type = Get-Prop $condition 'type'
            if (($type -in @('MemoryPressure', 'DiskPressure', 'PIDPressure', 'NetworkUnavailable')) -and
                (Get-Prop $condition 'status') -eq 'True') {
                Write-Warn "$nodeName reports $type=True"
                Add-Finding "Node $nodeName has $type=True"
            }
        }
    }

    $storageAfter = Get-StorageStatus
    if ($storageAfter.Available) {
        Write-Info ("Longhorn: {0}/{1} healthy, {2} degraded, {3} detached, {4} node(s) not scheduling" -f `
                $storageAfter.HealthyCount, $storageAfter.VolumeCount,
            $storageAfter.AttachedDegraded.Count, $storageAfter.Detached.Count, $storageAfter.UnschedulableNodes.Count)
        if ($storageAfter.Ok) { Write-Ok "Longhorn volumes are healthy." }
        else { Write-Warn "Longhorn is still degraded."; Add-Finding "Longhorn degraded at end of run" }
    }

    $badAttachments = @(Get-K8sJson -KubectlArgs @('get', 'volumeattachments') |
            Where-Object { (Get-Prop (Get-Prop $_ 'status') 'attached') -ne $true } |
            ForEach-Object { Get-Prop (Get-Prop $_ 'metadata') 'name' })
    if ($badAttachments.Count -gt 0) {
        Write-Warn "$($badAttachments.Count) volume attachment(s) not attached."
        Add-Finding "Unattached VolumeAttachment(s): $($badAttachments.Count)"
    }

    $badPdbs = [System.Collections.Generic.List[string]]::new()
    foreach ($pdb in (Get-K8sJson -KubectlArgs @('get', 'pdb', '-A'))) {
        $status = Get-Prop $pdb 'status'
        $healthy = Get-Prop $status 'currentHealthy'
        $desired = Get-Prop $status 'desiredHealthy'
        if ($null -eq $healthy -or $null -eq $desired) { continue }
        if ([int]$healthy -lt [int]$desired) {
            $md = Get-Prop $pdb 'metadata'
            $label = "$(Get-Prop $md 'namespace')/$(Get-Prop $md 'name')"
            $badPdbs.Add("$label ($healthy/$desired healthy)")
        }
    }
    if ($badPdbs.Count -gt 0) {
        foreach ($entry in $badPdbs) { Write-Warn "PDB below capacity: $entry" }
        Add-Finding "PodDisruptionBudgets below capacity: $($badPdbs.Count)"
    }

    $unhealthyPods = [System.Collections.Generic.List[string]]::new()
    foreach ($pod in (Get-K8sJson -KubectlArgs @('get', 'pods', '-A'))) {
        $md = Get-Prop $pod 'metadata'
        $status = Get-Prop $pod 'status'
        $label = "$(Get-Prop $md 'namespace')/$(Get-Prop $md 'name')"
        $phase = Get-Prop $status 'phase'

        if ($phase -in @('Running', 'Succeeded')) {
            $waiting = Get-Prop (Get-Prop (Get-Prop @(Get-Prop $status 'containerStatuses')[0] 'state') 'waiting') 'reason'
            if ($waiting -in @('CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull', 'CreateContainerError', 'RunContainerError')) {
                $unhealthyPods.Add("$label ($waiting)")
            }
            continue
        }
        if (Get-Prop $md 'deletionTimestamp') { $unhealthyPods.Add("$label (Terminating, phase=$phase)"); continue }
        $unhealthyPods.Add("$label (phase=$phase)")
    }

    if ($unhealthyPods.Count -gt 0) {
        Write-Warn "$($unhealthyPods.Count) pod(s) not healthy:"
        foreach ($entry in $unhealthyPods) { Write-Info "  $entry" }
        Add-Finding "$($unhealthyPods.Count) pod(s) not healthy at end of run"
    }
    else {
        Write-Ok "All pods are Running/Succeeded with no container waiting errors."
    }

    # ── Summary ──────────────────────────────────────────────────────────
    $degradedTotal = $unhealthyPods.Count + $badPdbs.Count + $badAttachments.Count + $stillCordonedReady.Count
    if ($storageAfter.Available) { $degradedTotal += $storageAfter.AttachedDegraded.Count }

    Write-Host "`n========================================" -ForegroundColor Cyan
    if ($degradedTotal -eq 0) {
        Write-Host "  Result: cluster is healthy" -ForegroundColor Green
    }
    else {
        Write-Host "  Result: $degradedTotal item(s) still degraded - see findings" -ForegroundColor Yellow
    }
    Write-Host "========================================" -ForegroundColor Cyan

    if ($FailOnDegraded -and $degradedTotal -gt 0) { $finalExitCode = 2 }
}
catch {
    Write-Bad "FATAL: $($_.Exception.Message)"
    Add-Finding "FATAL: $($_.Exception.Message)"
    $finalExitCode = 1
}
finally {
    function Get-SafeVar {
        param([string]$Name, $Default = $null)
        $variable = Get-Variable -Name $Name -ErrorAction SilentlyContinue
        if ($variable) { return $variable.Value }
        return $Default
    }

    # Machine-readable run report - v1 produced nothing auditable at all.
    try {
        $report = [pscustomobject]@{
            startedAt   = $script:StartedAt.ToString('o')
            finishedAt  = (Get-Date).ToString('o')
            durationSec = [math]::Round(((Get-Date) - $script:StartedAt).TotalSeconds, 1)
            dryRun      = $script:DryRun
            server      = [string](Get-SafeVar 'actualServer' 'unknown')
            options     = [pscustomobject]@{
                # Effective phase plan actually used for this run.
                effectiveRestartWorkloads = [bool]$DoRestartWorkloads
                effectiveStorageRepair    = [bool]$DoStorageRepair
                effectiveRebalance        = [bool]$DoRebalance
                skipRestartWorkloads      = [bool]$SkipRestartWorkloads
                skipStorageRepair         = [bool]$SkipStorageRepair
                skipRebalance             = [bool]$SkipRebalance
                legacyOptInSwitches       = @($LegacyOptInSwitches)
                legacySkipRestart         = [bool]$SkipRestart
                # Kept for backward compatibility with existing report consumers.
                restartWorkloads = [bool]$RestartWorkloads
                repairStorage    = [bool]$RepairStorage
                rebalance        = [bool]$Rebalance
                failOnDegraded   = [bool]$FailOnDegraded
                skipRestart      = [bool]$SkipRestart
            }
            uncordoned  = @(Get-SafeVar 'uncordoned' @())
            findings    = @($script:Findings)
            actions     = @($script:Actions)
            exitCode    = $finalExitCode
        }
        $report | ConvertTo-Json -Depth 8 | Set-Content -Path $ReportPath -Encoding utf8
        Write-Host "`nRun report : $ReportPath" -ForegroundColor Cyan
        Write-Host "Transcript : $transcriptFile" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Could not write the run report to '$ReportPath': $($_.Exception.Message)"
    }

    if ($script:LockAcquired -and (Test-Path -Path $script:LockFile)) {
        Remove-Item -Path $script:LockFile -Force -ErrorAction SilentlyContinue
    }
    if ($script:TranscriptStarted) {
        # Swallowing is intentional here: a failed Stop-Transcript during teardown must
        # never mask the real run result, and Stop-Transcript returns no handle.
        try { Stop-Transcript | Out-Null } catch { Write-Verbose "Stop-Transcript: $($_.Exception.Message)" }
    }

    Write-Host ("Exit code  : {0}  (0=healthy, 1=fatal, 2=degraded)" -f $finalExitCode) -ForegroundColor Cyan
}

exit $finalExitCode
