#Requires -Version 7.0
# Start-K3sHomelab.ps1  (full recovery by default)
# Restores cluster capacity after a power-down. Every recovery phase runs by default:
# uncordon Ready nodes -> recover the cluster core (CoreDNS/Traefik/metrics-server) ->
# recover the Longhorn control plane and instance-managers -> clear multipathd ->
# purge stranded/zombie pods -> repair Longhorn -> recycle CSI plugins ->
# engine-frontend recovery for dead /dev/longhorn devices ->
# serialized workload reconcile -> PDB-aware rebalance -> verify.
# Use the -Skip* switches to opt out of individual phases.
# Symmetrical counterpart to Stop-K3sHomelab-Minimal.ps1 / shutdown_homelab.ps1.
#
# Control plane (since 2026-09-20): THREE embedded-etcd servers - nuc (192.168.0.21),
# server-236 (192.168.0.236) and server-252 (192.168.0.252). All three are protected nodes
# (neverCordon in WindowsLab/homelab-nodes.json), quorum is 2 of 3, and the verification step
# reports quorum headroom so "the API answered" is never mistaken for "the control plane is
# safe". A control-plane member that is NotReady is reported; it is never cordoned, drained
# or removed - starting the host is enough, because its etcd member is retained.

<#
.SYNOPSIS
    Restores a powered-on K3s homelab to full capacity, safely and idempotently.

.DESCRIPTION
    The whole recovery runs by default, so a bare 'Start-K3sHomelab.ps1' performs:

        uncordon Ready nodes -> recover the cluster core (CoreDNS/Traefik/metrics-server/
        local-path-provisioner) -> recover the Longhorn control plane and instance-managers ->
        clear multipathd -> purge stranded/zombie pods -> repair Longhorn -> recycle CSI
        plugins -> serialized workload reconcile -> PDB-aware rebalance -> verify

    A power-cycle leaves the cluster core half-dead in a specific way: the API comes back but
    CoreDNS does not, Longhorn's own managers then cannot resolve their webhook service, no
    instance-manager is created, every volume stays 'unknown' and every consumer pod sits in
    Pending. Steps 3 and 4 exist because uncordoning alone cannot get you out of that.

    Since 2026-09-20 the control plane is three embedded-etcd servers (nuc, server-236,
    server-252), so the run also reports control-plane quorum twice - in the inventory step
    (before any mutation) and in verification. Quorum is 2 of 3: a NotReady member is
    survivable but leaves zero margin, which is stated explicitly rather than inferred from
    'kubectl get nodes' looking green.

    Individual phases are opt-OUT via -SkipPlatformRepair, -SkipMultipathRepair,
    -SkipStorageRepair, -SkipRestartWorkloads and -SkipRebalance. The older opt-in switches
    (-RepairStorage, -RestartWorkloads, -Rebalance, -RepairMultipath) are still accepted but
    are now no-ops with a deprecation notice.

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

.PARAMETER SkipHostMountRepair
    Opt OUT of the last-resort storage recovery: when CSI plugin recycling plus a
    graceful pod cycle still leaves Pending RWO pods (kernel 'Can't open blockdev' -
    the /dev/longhorn device itself is dead), the Longhorn engine frontend on that
    node is respawned by restarting the node's instance-manager. Survivors are then
    moved off nodes with a proven-dead frontend (cordon, cycle, uncordon - protected
    nodes are never cordoned), and anything still stuck is reported as a VOLUME WEDGE
    with snapshot/backup restore guidance (detection only, never auto-restored).
    Runs by default; a node is only touched when every blocked volume on it is
.PARAMETER SkipPlatformRepair
    Opt OUT of the cluster-core recovery: no purge of zombie platform pods and no restart of
    kube-system / longhorn-system controllers that are short of replicas. Runs by default,
    because a power-cycle reliably leaves CoreDNS at 0/1, which silently breaks everything.

.PARAMETER SkipMultipathRepair
    Opt OUT of disabling multipathd on nodes where Longhorn flags it. Runs by default.
    multipathd is Longhorn's documented cause of mounts failing with "Can't open blockdev";
    disabling it is a real node-level change, reversible with 'systemctl enable --now
    multipathd', so only flagged Ready nodes are touched, one at a time, never a protected node.

.PARAMETER MultipathImage
    Image for the temporary privileged repair pod. Default: busybox:1.36 (already pulled on
    these nodes, so no image download is needed).

.PARAMETER RepairMultipath
    Legacy switch. Accepted but no longer required - multipathd remediation already runs by
    default, so this is a no-op that emits a deprecation notice.

.PARAMETER MultipathDebugPod
    Optional name of an existing privileged hostPID pod to exec into instead of creating a
    temporary repair pod. The pod is only used, never deleted.


    Longhorn-healthy (replicas available), Ready nodes only, one node at a time.

.PARAMETER HostMountNodes
    Optional node filter for the engine recovery (e.g. -HostMountNodes
    @('kubernetes4','kubernetes5')). Empty (default) means every Ready node that
    still has storage-blocked pods after the CSI recycle.

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

.PARAMETER NodeSaturationCpuPercent
    Verification-only: CPU usage (metrics.k8s.io vs node capacity) at or above this percentage
    marks a node as saturated. Default: 85. Detection and reporting only - this script never
    remediates saturation, because the node most prone to it (kubernetes7) is protected from
    cordon/drain/power-off.

.PARAMETER NodeSaturationMemoryPercent
    Verification-only: memory usage at or above this percentage marks a node as saturated.
    Default: 90.

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

# Script-level PSScriptAnalyzer suppressions. Each was checked by hand and is either a
# false positive or a deliberate choice for an interactive recovery tool.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive recovery tool: Write-Host is correct for the coloured run-plan banner and inline progress lines. Write-Output would inject those strings into the pipeline and corrupt the report object. The semantic helpers Write-Info/Write-Warn/Write-Ok/Write-Bad wrap it consistently.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
    Justification = 'Start-Job -ScriptBlock { param($ns,$name) } -ArgumentList is the documented way to pass values into a background job. Adding $using: would be wrong - it is for Invoke-Command, and it would bypass the param() binding and always be empty.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script-scope parameters are referenced from inside functions and from default-value expressions, which PSScriptAnalyzer does not track. Verified by hand: MultipathImage, MultipathDebugPod and GracefulDeleteTimeout are all used.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '',
    Justification = '$allNodes is a local holding the kubectl node list; it does not collide with any PowerShell automatic variable in PS7.')]
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # ── Opt-out switches: every recovery phase runs unless it is explicitly skipped ──
    [Parameter()]
    [switch]$SkipStorageRepair,

    [Parameter()]
    [switch]$SkipHostMountRepair,

    [Parameter()]
    [switch]$SkipPlatformRepair,

    [Parameter()]
    [switch]$SkipMultipathRepair,

    [Parameter()]
    [string[]]$HostMountNodes = @(),

    [Parameter()]
    [string]$MultipathImage = 'busybox:1.36',

    # ── Legacy opt-in switch: kept so existing invocations keep working. ──
    #    multipathd repair now runs by default, so this is a no-op with a notice.
    [Parameter()]
    [switch]$RepairMultipath,

    [Parameter()]
    [ValidatePattern('^[a-z0-9][a-z0-9.-]*$')]
    [string]$MultipathDebugPod,

    [Parameter()]
    [switch]$SkipRestartWorkloads,

    # Phase B (Deployments) is skipped while Longhorn is degraded, mirroring the existing
    # Phase A rule for RWO StatefulSets. Many Deployments mount the same RWO volumes, so
    # restarting them against degraded storage is the same deadlock hazard. Use this only
    # when the target Deployments are known to be safe.
    [Parameter()]
    [switch]$ForceRestartWithDegradedStorage,
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
    [ValidateRange(50, 100)]
    [int]$NodeSaturationCpuPercent = 85,

    [Parameter()]
    [ValidateRange(50, 100)]
    [int]$NodeSaturationMemoryPercent = 90,

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
    [switch]$SkipRestart,

    [Parameter()]
    [ValidateRange(10, 300)]
    [int]$GracefulDeleteTimeout = 30,

    [Parameter()]
    [switch]$SkipStaleAttachmentCleanup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Effective phase flags: the full recovery runs by default ───────────
# Everything below reads these flags instead of the raw switches, so the default is
# "do the whole recovery" and each -Skip* switch is a deliberate opt-out.
$DoStorageRepair     = -not $SkipStorageRepair
$DoHostMountRepair   = -not $SkipHostMountRepair
$DoPlatformRepair    = -not $SkipPlatformRepair
$DoMultipathRepair   = -not $SkipMultipathRepair
$DoRebalance         = -not $SkipRebalance
$DoStaleAttachmentCleanup = -not $SkipStaleAttachmentCleanup
# Restart is suppressed by either -SkipRestartWorkloads or the legacy -SkipRestart.
$DoRestartWorkloads  = (-not $SkipRestartWorkloads) -and (-not $SkipRestart)
# Callers that still pass an opt-in switch get a notice instead of a silent no-op.
$LegacyOptInSwitches = @()
if ($RestartWorkloads) { $LegacyOptInSwitches += '-RestartWorkloads' }
if ($RepairStorage) { $LegacyOptInSwitches += '-RepairStorage' }
if ($Rebalance) { $LegacyOptInSwitches += '-Rebalance' }
if ($RepairMultipath) { $LegacyOptInSwitches += '-RepairMultipath' }

# Namespaces owned by platform components: never restarted by the reconcile phase.
$SkipNamespaces = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('kube-system', 'longhorn-system', 'argocd', 'cnpg-system', 'tailscale'),
    [System.StringComparer]::OrdinalIgnoreCase
)

# Longhorn is only touched by the storage-repair phase, never by the restart phase.
$StorageNamespace = 'longhorn-system'
$CsiPluginLabelSelector = 'app=longhorn-csi-plugin'

# The cluster's own control surface. It is excluded from the workload reconcile phase (it
# must not be restarted as part of a rolling app restart) but it IS recovered explicitly by
# the platform phase, because CoreDNS/Traefik/metrics-server/local-path-provisioner are
# single-replica Deployments that do not come back by themselves after a power-cycle.
$PlatformNamespace = 'kube-system'
$PlatformWaitSeconds = 300
$LonghornWaitSeconds = 420
$MultipathWaitSeconds = 120

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
        # Capture stdout and stderr separately. Merging them (2>&1) corrupts JSON output the
        # moment kubectl writes a warning to stderr - e.g. the v1.33+ "v1 Endpoints is
        # deprecated" notice, which is exactly what made the cluster-DNS probe report zero
        # endpoints forever even though CoreDNS had recovered.
        $errFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "kubectl-err-$PID-$([guid]::NewGuid().ToString('N')).log"
        $output = & kubectl @KubectlArgs 2>$errFile
        $code = $LASTEXITCODE
        $stderr = ''
        if (Test-Path -Path $errFile) {
            $stderr = ((Get-Content -Path $errFile -Raw) -replace '^\s+|\s+$', '')
            Remove-Item -Path $errFile -Force -ErrorAction SilentlyContinue
        }
        $text = (($output | Out-String) + $stderr).Trim()

        if ($code -eq 0) {
            if ($stderr) { Write-Verbose "kubectl $($KubectlArgs -join ' ') (stderr): $stderr" }
            return [pscustomobject]@{ Ok = $true; ExitCode = 0; Output = @($output); Stderr = $stderr }
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
            return [pscustomobject]@{ Ok = $false; ExitCode = $code; Output = @($output) + @($stderr); Stderr = $stderr }
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

function Invoke-SafeGracefulDelete {
    <#
        Graceful pod delete with a timeout, falling back to force-delete.

        Why this exists: 'kubectl delete pod --wait=true' blocks indefinitely when the pod's
        volume cannot unmount, which is how the recovery used to hang on one pod forever.

        NB: the Start-Job payload mixes kubectl's output with the exit code. '$result -eq 0'
        on that array misfires (a leading ErrorRecord makes it a collection-membership test),
        which is how a SUCCESSFUL delete got treated as a failure and an instance-manager was
        force-killed. The exit code is therefore isolated behind an explicit marker line and
        parsed out - never compared against the whole payload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$PodName,
        [Parameter(Mandatory)][string]$Description,
        [Parameter()][string]$ActionType = 'attachment-cycle',
        [Parameter()][string]$Target = '',
        [Parameter()][int]$TimeoutSeconds = $GracefulDeleteTimeout
    )

    if ($script:DryRun) {
        Write-Info "[DRY-RUN] gracefully delete [$Namespace] $PodName (timeout ${TimeoutSeconds}s, force fallback)"
        Add-Action -Type 'dry-run' -Target $Target -Detail "kubectl delete pod $PodName -n $Namespace (timeout ${TimeoutSeconds}s + force fallback)"
        return $true
    }

    $job = Start-Job -ScriptBlock {
        param($ns, $name)
        $out = & kubectl delete pod $name -n $ns --wait=true 2>&1
        $code = $LASTEXITCODE
        Write-Output "===EXITCODE===$code"
        if ($out) { $out | ForEach-Object { Write-Output "===OUT===$_" } }
    } -ArgumentList $Namespace, $PodName

    $completed = $job | Wait-Job -Timeout $TimeoutSeconds
    if ($completed) {
        $lines = @(Receive-Job -Job $job | ForEach-Object { [string]$_ })
        Remove-Job -Job $job -Force
        $exitCodeLine = $lines | Where-Object { $_ -like '===EXITCODE===*' } | Select-Object -Last 1
        $kubectlLines = @($lines | Where-Object { $_ -notlike '===*' -and $_ })
        $exitCode = 1
        if ($exitCodeLine) { $exitCode = [int]($exitCodeLine -replace '^===EXITCODE===', '') }

        if ($exitCode -eq 0) {
            Write-Info "Graceful delete succeeded for [$Namespace] $PodName"
            Add-Action -Type $ActionType -Target $Target -Detail "kubectl delete pod $PodName -n $Namespace --wait=true (graceful)"
            return $true
        }
        Write-Warn ("Graceful delete failed for [{0}] {1} (exit {2}): {3}" -f `
                $Namespace, $PodName, $exitCode, (($kubectlLines | Out-String).Trim()))
    }
    else {
        Remove-Job -Job $job -Force
        Write-Warn "Graceful delete timed out after ${TimeoutSeconds}s for [$Namespace] $PodName, falling back to force-delete"
    }

    Write-Info "Force-deleting [$Namespace] $PodName (graceful delete failed/timed out)"
    return (Invoke-KubectlMutation -Description "$Description (force-delete fallback)" `
            -KubectlArgs @('delete', 'pod', $PodName, '-n', $Namespace, '--grace-period=0', '--force') `
            -ActionType "$ActionType-force" -Target $Target -AllowFailure)
}

function Invoke-SafePodDelete {
    <#
        Pod delete with a timeout for INFRASTRUCTURE pods (CSI plugins, instance-managers).
        Same payload/exit-code handling as Invoke-SafeGracefulDelete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$PodName,
        [Parameter(Mandatory)][string]$Description,
        [Parameter()][string]$ActionType = 'storage-repair',
        [Parameter()][string]$Target = '',
        [Parameter()][int]$TimeoutSeconds = $GracefulDeleteTimeout
    )

    if ($script:DryRun) {
        Write-Info "[DRY-RUN] delete [$Namespace] $PodName (timeout ${TimeoutSeconds}s, force fallback)"
        Add-Action -Type 'dry-run' -Target $Target -Detail "kubectl delete pod $PodName -n $Namespace (timeout ${TimeoutSeconds}s + force fallback)"
        return $true
    }

    $job = Start-Job -ScriptBlock {
        param($ns, $name)
        $out = & kubectl delete pod $name -n $ns --wait=true 2>&1
        $code = $LASTEXITCODE
        Write-Output "===EXITCODE===$code"
        if ($out) { $out | ForEach-Object { Write-Output "===OUT===$_" } }
    } -ArgumentList $Namespace, $PodName

    $completed = $job | Wait-Job -Timeout $TimeoutSeconds
    if ($completed) {
        $lines = @(Receive-Job -Job $job | ForEach-Object { [string]$_ })
        Remove-Job -Job $job -Force
        $exitCodeLine = $lines | Where-Object { $_ -like '===EXITCODE===*' } | Select-Object -Last 1
        $kubectlLines = @($lines | Where-Object { $_ -notlike '===*' -and $_ })
        $exitCode = 1
        if ($exitCodeLine) { $exitCode = [int]($exitCodeLine -replace '^===EXITCODE===', '') }

        if ($exitCode -eq 0) {
            Write-Info "Delete succeeded for [$Namespace] $PodName"
            Add-Action -Type $ActionType -Target $Target -Detail "kubectl delete pod $PodName -n $Namespace --wait=true"
            return $true
        }
        Write-Warn ("Delete failed for [{0}] {1} (exit {2}): {3}" -f `
                $Namespace, $PodName, $exitCode, (($kubectlLines | Out-String).Trim()))
    }
    else {
        Remove-Job -Job $job -Force
        Write-Warn "Delete timed out after ${TimeoutSeconds}s for [$Namespace] $PodName, falling back to force-delete"
    }

    Write-Info "Force-deleting [$Namespace] $PodName (delete failed/timed out)"
    return (Invoke-KubectlMutation -Description "$Description (force-delete fallback)" `
            -KubectlArgs @('delete', 'pod', '-n', $Namespace, $PodName, '--grace-period=0', '--force') `
            -ActionType "$ActionType-force" -Target $Target -AllowFailure)
}

function Get-StaleVolumeAttachment {
    <#
        A VolumeAttachment is stale when the Longhorn volume it references reports a
        currentNodeID that is NOT the attachment's node. That means the cluster's
        attach/detach controller still believes the volume is attached where Longhorn says
        it is not - the consumer pod on the target node then sits in Pending forever with
        "driver.longhorn.io not found in the list of registered CSI drivers" or
        "volume attachment is being deleted".

        Longhorn's currentNodeID is the authority here: it is the node that actually serves
        the block device.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $out = [System.Collections.Generic.List[object]]::new()
    $vas = Get-K8sJson -KubectlArgs @('get', 'volumeattachment')
    if ($vas.Count -eq 0) { return @() }

    foreach ($va in $vas) {
        $name = [string](Get-Prop (Get-Prop $va 'metadata') 'name')
        $node = [string](Get-Prop (Get-Prop $va 'spec') 'nodeName')
        $pv = [string](Get-Prop (Get-Prop (Get-Prop $va 'spec') 'source') 'persistentVolumeName')
        $attached = (Get-Prop (Get-Prop $va 'status') 'attached') -eq $true
        if (-not $attached) { continue }   # already detaching/detached - not our problem

        $volume = @(Get-K8sJson -KubectlArgs @('get', 'volumes.longhorn.io', '-n', $StorageNamespace, $pv))
        if ($volume.Count -eq 0) { continue }
        $lhNode = [string](Get-Prop (Get-Prop $volume[0] 'status') 'currentNodeID')
        if (-not $lhNode) { continue }
        if ($lhNode -eq $node) { continue }   # attachment agrees with Longhorn - healthy

        $out.Add([pscustomobject]@{
                Name        = $name
                Node        = $node
                Volume      = $pv
                LonghornNode = $lhNode
            })
    }
    return @($out)
}

function Clear-StaleVolumeAttachment {
    <#
        Deletes stale VolumeAttachments so the attach/detach controller re-attaches the
        volume where Longhorn actually serves it. Never touches an attachment whose node
        matches Longhorn's currentNodeID, and never a volume that is not faulted/attached
        elsewhere. Returns the list of cleared attachment names.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $stale = @(Get-StaleVolumeAttachment)
    if ($stale.Count -eq 0) {
        Write-Ok 'No stale VolumeAttachments found.'
        return @()
    }

    if (-not $DoStaleAttachmentCleanup) {
        Write-Warn "stale VolumeAttachment(s) detected but cleanup skipped (-SkipStaleAttachmentCleanup):"
        foreach ($item in $stale) {
            Write-Info "  $($item.Name): volume $($item.Volume) attached on '$($item.Node)' but Longhorn serves it on '$($item.LonghornNode)'"
        }
        Add-Finding "Stale VolumeAttachment(s) not cleared: $($stale.Count)"
        return @()
    }

    $cleared = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $stale) {
        Test-Budget "clearing stale VolumeAttachment $($item.Name)"
        Write-Info ("Stale VolumeAttachment: {0} (volume {1} on '{2}', Longhorn serves it on '{3}') - clearing." -f `
                $item.Name, $item.Volume, $item.Node, $item.LonghornNode)
        $ok = Invoke-KubectlMutation -Description "delete stale volumeattachment $($item.Name)" `
            -KubectlArgs @('delete', 'volumeattachment', $item.Name) `
            -ActionType 'stale-attachment-cleanup' -Target $item.Volume -AllowFailure
        if ($ok) { $cleared.Add($item.Name) }
    }
    return @($cleared)
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
            VolumeName  = [string](Get-Prop $sp 'volumeName')
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
    $faulted = [System.Collections.Generic.List[object]]::new()
    $healthy = 0

    foreach ($volume in $volumes) {
        $name = Get-Prop (Get-Prop $volume 'metadata') 'name'
        $state = Get-Prop (Get-Prop $volume 'status') 'state'
        $robustness = Get-Prop (Get-Prop $volume 'status') 'robustness'
        $created = Get-Prop (Get-Prop $volume 'status') 'created'

        # 'faulted' is qualitatively different from 'degraded': replays are exhausted and the
        # volume needs a restore, not a retry. It is tracked separately so it can be reported
        # as a data-plane fault and never counted as merely slow.
        if ($robustness -eq 'faulted') {
            $faulted.Add([pscustomobject]@{ Name = $name; State = $state; Created = $created })
            continue
        }

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
        Faulted             = @($faulted)
        UnschedulableNodes  = @($unschedulable)
        Ok                  = ($volumes.Count -gt 0 -and $attachedDegraded.Count -eq 0 -and
            $faulted.Count -eq 0 -and $unschedulable.Count -eq 0)
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
        [Parameter()][int]$PollSeconds = 15,
        [Parameter()][int]$StallIterations = 8
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
    # Convergence is not linear. In the 2026-09-25 run this loop spun for 36 iterations
    # (~9 min) while healthy volume count oscillated 2 -> 3 -> 4 -> 2 -> 3, never trending up,
    # and the recovery that actually mattered (a stuck longhorn-manager pod on kubernetes7
    # being reaped) only completed AFTER the wait was abandoned. Track the best count seen and
    # bail as soon as several consecutive polls fail to beat it, so the run can move on to the
    # phases that might actually help instead of burning its whole budget here.
    $bestHealthy = if ($status.HealthyCount) { $status.HealthyCount } else { 0 }
    $stalled = 0

    while (-not $status.Ok -and $sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Test-Budget 'waiting for Longhorn to converge'
        Write-Info ("storage: {0}/{1} volumes healthy, {2} degraded, {3} longhorn node(s) unschedulable - waiting {4}s" -f `
                $status.HealthyCount, $status.VolumeCount, $status.AttachedDegraded.Count, $status.UnschedulableNodes.Count, $PollSeconds)
        Start-Sleep -Seconds $PollSeconds
        $status = Get-StorageStatus

        if ($status.HealthyCount -gt $bestHealthy) {
            if ($stalled -gt 0) {
                Write-Info ("storage: improving again ({0} healthy, was stalled at {1}) - continuing to wait." -f $status.HealthyCount, $bestHealthy)
            }
            $bestHealthy = $status.HealthyCount
            $stalled = 0
        }
        else {
            $stalled++
            if ($stalled -ge $StallIterations) {
                Write-Warn ("storage: no improvement over {0} consecutive polls (best {1}/{2} healthy) - stopping the wait early and continuing." -f `
                        $stalled, $bestHealthy, $status.VolumeCount)
                Add-Finding ("Longhorn storage stalled at {0}/{1} healthy after {2} polls without improvement" -f $bestHealthy, $status.VolumeCount, $stalled)
                break
            }
        }
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

function ConvertFrom-K8sQuantity {
    <#
        Parses a Kubernetes resource quantity into base units: CPU -> cores, memory -> bytes.
        Handles the suffixes seen on node capacity and metrics.k8s.io (n/u/m for CPU;
        Ki/Mi/Gi/Ti/Pi/Ei and k/M/G/T/P/E for memory). Returns $null for anything
        unparseable, so a weird value degrades one report line instead of crashing the
        verification phase.
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()][AllowEmptyString()][string]$Quantity)

    if ([string]::IsNullOrWhiteSpace($Quantity)) { return $null }
    if ($Quantity.Trim() -match '^([0-9]+(?:\.[0-9]+)?)(n|u|m|Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?$') {
        $value = [double]$Matches[1]
        # Case-sensitive: 'm' (millicores) and 'M' (megabytes) are different suffixes.
        switch -CaseSensitive ($Matches[2]) {
            'n' { return $value / 1e9 }
            'u' { return $value / 1e6 }
            'm' { return $value / 1e3 }
            'Ki' { return $value * 1KB }
            'Mi' { return $value * 1MB }
            'Gi' { return $value * 1GB }
            'Ti' { return $value * 1TB }
            'Pi' { return $value * 1PB }
            'Ei' { return $value * 1PB * 1KB }
            'k' { return $value * 1e3 }
            'M' { return $value * 1e6 }
            'G' { return $value * 1e9 }
            'T' { return $value * 1e12 }
            'P' { return $value * 1e15 }
            'E' { return $value * 1e18 }
            default { return $value }
        }
    }
    return $null
}

function Get-NodeSaturation {
    <#
    .SYNOPSIS
        Per-node CPU/memory saturation snapshot: metrics.k8s.io usage vs node capacity,
        plus the Longhorn replica count per node.

    .DESCRIPTION
        Added after the kubernetes7 incident (2026-09-20, see WindowsLab/k8s7-cpu-report.md):
        a PERMANENT SURVIVOR node that cannot be cordoned, drained or powered off was pinned
        at ~99% CPU (load average 34 on 4 cores) because Longhorn re-replicated volumes onto
        it while other storage nodes were down. This check exists to DETECT AND REPORT that
        state. It never remediates: the only relief valves (cordon/drain/power-off) are all
        forbidden on protected nodes, and on unprotected nodes the rebalance phase already
        owns redistribution. Metrics come from metrics-server (part of the cluster core this
        script recovers); when metrics.k8s.io is unavailable the check reports "unknown"
        instead of failing.

    .OUTPUTS
        MetricsAvailable, Nodes (per-node usage/saturation entries), ReplicaCountByNode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object[]]$NodeObjects,
        [Parameter()][string[]]$ProtectedNodes = @(),
        [Parameter()][int]$CpuThresholdPercent = 85,
        [Parameter()][int]$MemoryThresholdPercent = 90
    )

    # Longhorn replica placement: counted independently of metrics, because "how many
    # replicas did this node absorb" is the first question the incident report asks.
    $replicaCountByNode = @{}
    foreach ($replica in @(Get-K8sJson -KubectlArgs @('get', 'replicas', '-n', $StorageNamespace))) {
        $replicaNode = [string](Get-Prop (Get-Prop $replica 'spec') 'nodeID')
        if ($replicaNode) {
            if (-not $replicaCountByNode.ContainsKey($replicaNode)) { $replicaCountByNode[$replicaNode] = 0 }
            $replicaCountByNode[$replicaNode]++
        }
    }

    # Live usage from metrics-server. One raw API call; failure degrades to "unknown".
    $usageByNode = @{}
    $metricsAvailable = $false
    $metricsResult = Invoke-Kubectl -KubectlArgs @('get', '--raw', '/apis/metrics.k8s.io/v1beta1/nodes') -AllowFailure
    if ($metricsResult.Ok) {
        try {
            $metrics = (($metricsResult.Output | Out-String) | ConvertFrom-Json)
            foreach ($item in @($metrics.items)) {
                $usageByNode[[string](Get-Prop (Get-Prop $item 'metadata') 'name')] = [pscustomobject]@{
                    CpuCores    = ConvertFrom-K8sQuantity -Quantity ([string](Get-Prop (Get-Prop $item 'usage') 'cpu'))
                    MemoryBytes = ConvertFrom-K8sQuantity -Quantity ([string](Get-Prop (Get-Prop $item 'usage') 'memory'))
                }
            }
            $metricsAvailable = ($usageByNode.Count -gt 0)
        }
        catch {
            Write-Verbose "metrics.k8s.io parse failed: $($_.Exception.Message)"
            $metricsAvailable = $false
        }
    }
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($node in @($NodeObjects)) {
        $name = [string](Get-Prop (Get-Prop $node 'metadata') 'name')
        if (-not $name) { continue }

        $capacity = Get-Prop (Get-Prop $node 'status') 'capacity'
        $cpuCapacity = ConvertFrom-K8sQuantity -Quantity ([string](Get-Prop $capacity 'cpu'))
        $memCapacity = ConvertFrom-K8sQuantity -Quantity ([string](Get-Prop $capacity 'memory'))

        $usage = $usageByNode[$name]
        $cpuPercent = $null
        $memPercent = $null
        if ($usage -and $null -ne $usage.CpuCores -and $cpuCapacity -and $cpuCapacity -gt 0) {
            $cpuPercent = [math]::Round(($usage.CpuCores / $cpuCapacity) * 100, 1)
        }
        if ($usage -and $null -ne $usage.MemoryBytes -and $memCapacity -and $memCapacity -gt 0) {
            $memPercent = [math]::Round(($usage.MemoryBytes / $memCapacity) * 100, 1)
        }

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $cpuPercent -and $cpuPercent -ge $CpuThresholdPercent) { $reasons.Add("CPU $cpuPercent% >= $CpuThresholdPercent%") }
        if ($null -ne $memPercent -and $memPercent -ge $MemoryThresholdPercent) { $reasons.Add("memory $memPercent% >= $MemoryThresholdPercent%") }

        $entries.Add([pscustomobject]@{
                Name          = $name
                IsProtected   = ($ProtectedNodes -contains $name)
                CpuPercent    = $cpuPercent
                MemoryPercent = $memPercent
                ReplicaCount  = $(if ($replicaCountByNode.ContainsKey($name)) { $replicaCountByNode[$name] } else { 0 })
                Saturated     = ($reasons.Count -gt 0)
                Reasons       = @($reasons)
            })
    }

    return [pscustomobject]@{
        MetricsAvailable   = $metricsAvailable
        Nodes              = @($entries)
        ReplicaCountByNode = $replicaCountByNode
    }
}

function Get-ControlPlaneStatus {
    <#
    .SYNOPSIS
        Embedded-etcd view of the cluster: which nodes carry the control-plane role, how many
        are Ready, and whether that still satisfies etcd's quorum majority.

    .DESCRIPTION
        Added for the three-server embedded-etcd topology (2026-09-20: nuc, server-236,
        server-252). With a single server this check was meaningless; with several it is the
        difference between "the API is up" and "the API is up but one more failure takes it
        down". Quorum is floor(members / 2) + 1, so three members tolerate one loss and two
        members tolerate none.

        Also reports whether clients still address a single member: every kubeconfig in this
        lab points at https://192.168.0.21:6443, which survives an etcd member loss but not
        the loss of nuc itself.

    .PARAMETER NodeObjects
        Node objects as returned by 'kubectl get nodes -o json' (the .items array).

    .PARAMETER ApiServerUrl
        The current kubeconfig API server URL, used to detect the single-member endpoint.

    .OUTPUTS
        A status object: MemberCount, ReadyCount, Quorum, HasQuorum, ToleratesLoss, Members,
        NotReady, Endpoint, SingleEndpoint.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object[]]$NodeObjects,

        [Parameter()][string]$ApiServerUrl = ''
    )

    $members = [System.Collections.Generic.List[object]]::new()
    foreach ($node in @($NodeObjects)) {
        $metadata = Get-Prop $node 'metadata'
        $labels = Get-Prop $metadata 'labels'
        $isControlPlane = ((Get-Prop $labels 'node-role.kubernetes.io/control-plane') -eq 'true') -or
        ((Get-Prop $labels 'node-role.kubernetes.io/master') -eq 'true')
        if (-not $isControlPlane) { continue }

        $ready = $false
        foreach ($condition in @(Get-Prop (Get-Prop $node 'status') 'conditions')) {
            if ((Get-Prop $condition 'type') -eq 'Ready') {
                $ready = ((Get-Prop $condition 'status') -eq 'True')
                break
            }
        }

        $ip = ''
        foreach ($address in @(Get-Prop (Get-Prop $node 'status') 'addresses')) {
            if ((Get-Prop $address 'type') -eq 'InternalIP') {
                $ip = [string](Get-Prop $address 'address')
                break
            }
        }

        $members.Add([pscustomobject]@{
                Name   = [string](Get-Prop $metadata 'name')
                IsEtcd = ((Get-Prop $labels 'node-role.kubernetes.io/etcd') -eq 'true')
                Ready  = $ready
                IP     = $ip
            })
    }

    # Members labelled 'etcd' are the embedded-etcd voters. Fall back to every control-plane
    # node when the label is absent (older/agent-only nodes carry neither).
    $etcdMembers = @($members | Where-Object { $_.IsEtcd })
    $voters = if ($etcdMembers.Count -gt 0) { $etcdMembers } else { @($members) }
    $quorum = [int][math]::Floor($voters.Count / 2) + 1
    $readyCount = @($voters | Where-Object { $_.Ready }).Count

    $endpointHost = ''
    if ($ApiServerUrl) {
        try { $endpointHost = ([System.Uri]$ApiServerUrl).Host } catch { $endpointHost = '' }
    }
    # A single-member endpoint is one that resolves to exactly one control-plane member;
    # a VIP or DNS name across the members matches none of them.
    $endpointMatches = 0
    if ($endpointHost) {
        $endpointMatches = @($voters | Where-Object { $_.Name -ieq $endpointHost -or $_.IP -eq $endpointHost }).Count
    }

    return [pscustomobject]@{
        MemberCount    = $voters.Count
        ReadyCount     = $readyCount
        Quorum         = $quorum
        HasQuorum      = ($readyCount -ge $quorum)
        ToleratesLoss  = [int][math]::Max(0, $readyCount - $quorum)
        Members        = @($voters)
        NotReady       = @($voters | Where-Object { -not $_.Ready } | ForEach-Object { $_.Name })
        Endpoint       = $endpointHost
        SingleEndpoint = ($voters.Count -gt 1 -and $endpointMatches -eq 1)
    }
}

function Repair-PendingRwoMounts {
    <#
        Clears Longhorn/Kubelet stale mount state that appears after a rollout has
        already started. This is intentionally limited to Pending RWO pods scheduled
        on Ready nodes; stranded pods and terminating RWO pods are handled earlier.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns the set of Pending RWO pods it repaired; plural noun is correct for a collection return')]
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

function Get-PendingPodStatus {
    <#
        Re-checks candidate pods against live state. Returns one record per pod that
        is still not Running/Succeeded, with its current node and whether it is only
        waiting in init (volumes mounted, e.g. waiting for its database).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([object[]]$Candidates = @())

    $livePods = Get-K8sJson -KubectlArgs @('get', 'pods', '-A')
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $Candidates) {
        foreach ($pod in $livePods) {
            $md = Get-Prop $pod 'metadata'
            if ((Get-Prop $md 'namespace') -eq $candidate.Namespace -and (Get-Prop $md 'name') -eq $candidate.Name) {
                $st = Get-Prop $pod 'status'
                if ((Get-Prop $st 'phase') -notin @('Running', 'Succeeded')) {
                    $conds = @(Get-Prop $st 'conditions')
                    $initialized = @($conds | Where-Object { (Get-Prop $_ 'type') -eq 'Initialized' })
                    $readyToStart = @($conds | Where-Object { (Get-Prop $_ 'type') -eq 'PodReadyToStartContainers' })
                    $inInit = ($initialized.Count -gt 0 -and (Get-Prop $initialized[0] 'status') -ne 'True' -and
                        $readyToStart.Count -gt 0 -and (Get-Prop $readyToStart[0] 'status') -eq 'True')
                    $out.Add([pscustomobject]@{
                            Namespace = $candidate.Namespace
                            Name      = $candidate.Name
                            Node      = [string](Get-Prop (Get-Prop $pod 'spec') 'nodeName')
                            Phase     = [string](Get-Prop $st 'phase')
                            InInit    = [bool]$inInit
                            LivePod   = $pod
                        })
                }
                break
            }
        }
    }
    return @($out)
}

function Repair-StaleVolumeFrontend {
    <#
        Last-resort Longhorn recovery for storage-blocked pods that survive the CSI
        plugin recycle plus graceful pod cycle. Symptom: kubelet keeps reporting
        'already mounted or mount point busy' while the kernel logs
        '/dev/longhorn/<volume>: Can't open blockdev' and the device is absent from
        /proc/mounts. The engine frontend on that node is wedged - the block device
        itself is dead, so no amount of CSI recycling or pod cycling can mount it.
        Respawning the node's instance-manager restarts every engine process on that
        node (brief IO stall on that node's volumes) and re-exposes healthy frontends.

        Guards: Ready nodes only, one node at a time, and a node is only touched when
        every blocked volume on it is Longhorn-healthy (attached + healthy robustness,
        i.e. replicas are available). Anything else is report-only.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [object[]]$BlockedPods = @(),
        [hashtable]$PvcMap = @{},
        $NodeState = $null,
        [string[]]$NodeFilter = @()
    )

    if (-not $DoHostMountRepair) {
        Write-Warn 'Engine recovery skipped (-SkipHostMountRepair); still-blocked RWO pods are report-only.'
        return @()
    }
    if ($BlockedPods.Count -eq 0) { return @() }

    $byNode = @{}
    foreach ($pod in $BlockedPods) {
        if (-not $pod.Node) { continue }
        if ($NodeFilter.Count -gt 0 -and -not ($NodeFilter -contains $pod.Node)) { continue }
        if (-not $byNode.ContainsKey($pod.Node)) { $byNode[$pod.Node] = [System.Collections.Generic.List[object]]::new() }
        $byNode[$pod.Node].Add($pod)
    }
    if ($byNode.Count -eq 0) { return @() }

    $volumes = Get-K8sJson -KubectlArgs @('get', 'volumes.longhorn.io', '-n', $StorageNamespace)
    $livePods = Get-K8sJson -KubectlArgs @('get', 'pods', '-A')
    $repairedNodes = [System.Collections.Generic.List[string]]::new()

    foreach ($nodeName in @($byNode.Keys)) {
        if ($null -ne $NodeState -and $NodeState.Contains($nodeName) -and -not $NodeState[$nodeName].Ready) {
            Write-Warn "engine recovery skipped on '$nodeName': node is not Ready."
            continue
        }

        $pvNames = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($pod in $byNode[$nodeName]) {
            $live = @($livePods | Where-Object {
                    (Get-Prop (Get-Prop $_ 'metadata') 'namespace') -eq $pod.Namespace -and
                    (Get-Prop (Get-Prop $_ 'metadata') 'name') -eq $pod.Name
                })
            if ($live.Count -eq 0) { continue }
            foreach ($claim in @(Get-PodPvcClaims -Pod $live[0])) {
                if ($PvcMap.ContainsKey($claim) -and $PvcMap[$claim].VolumeName) {
                    $null = $pvNames.Add($PvcMap[$claim].VolumeName)
                }
            }
        }
        if ($pvNames.Count -eq 0) {
            Write-Warn "engine recovery skipped on '$nodeName': could not resolve Longhorn volumes for the blocked pods."
            continue
        }

        $healthy = $true
        foreach ($pv in $pvNames) {
            $match = @($volumes | Where-Object { (Get-Prop (Get-Prop $_ 'metadata') 'name') -eq $pv })
            if ($match.Count -eq 0) { Write-Bad "volume $pv not found in Longhorn; skipping engine recovery on '$nodeName'."; $healthy = $false; break }
            $state = Get-Prop (Get-Prop $match[0] 'status') 'state'
            $robustness = Get-Prop (Get-Prop $match[0] 'status') 'robustness'
            if ($state -ne 'attached' -or $robustness -ne 'healthy') {
                Write-Bad "volume $pv is $state/$robustness (not attached/healthy); skipping engine recovery on '$nodeName'."
                Add-Finding "Engine recovery refused on ${nodeName}: volume ${pv} is ${state}/${robustness}"
                $healthy = $false
                break
            }
        }
        if (-not $healthy) { continue }

        Test-Budget "respawning instance-manager on $nodeName"
        Write-Warn "Stale Longhorn frontend on '$nodeName' ($($pvNames.Count) healthy volume(s) affected) - respawning instance-manager."
        $imPods = Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $StorageNamespace, '-l', 'longhorn.io/component=instance-manager')
        $touched = $false
        foreach ($imPod in ($imPods | Where-Object { [string](Get-Prop (Get-Prop $_ 'spec') 'nodeName') -eq $nodeName })) {
            $imName = Get-Prop (Get-Prop $imPod 'metadata') 'name'
            $ok = Invoke-KubectlMutation -Description "restart instance-manager $imName on $nodeName" `
                -KubectlArgs @('delete', 'pod', '-n', $StorageNamespace, $imName, '--wait=true') `
                -ActionType 'engine-recovery' -Target $imName -AllowFailure
            if ($ok) { $touched = $true }
        }
        if (-not $touched) {
            Write-Warn "no instance-manager pod found on '$nodeName'; nothing respawned."
            continue
        }
        $repairedNodes.Add($nodeName)

        if (-not $script:DryRun) {
            Write-Info "Waiting 60s for the respawned engine(s) on '$nodeName' to re-expose frontends..."
            Start-Sleep -Seconds 60
        }
    }

    if ($repairedNodes.Count -gt 0 -and $script:DryRun) {
        Write-Info 'dry-run: not waiting for respawned engine(s).'
    }
    return @($repairedNodes)
}

# ── Platform (cluster core) recovery ───────────────────────────────────
# Why this exists: after a power-cycle the cluster's own control surface is the last thing
# to come back, and it does not come back by itself. CoreDNS, Traefik, metrics-server and
# local-path-provisioner are single-replica Deployments; when their node disappears the pod
# goes to ContainerStatusUnknown, the ReplicaSet refuses to replace a pod that still exists,
# and the Deployment sits at 0/1 forever.
#
# A dead CoreDNS is a hard blocker for everything downstream, and that is the part that is
# easy to miss: Longhorn's managers cannot resolve their own conversion-webhook service
# without cluster DNS, so their readiness fails, Longhorn never marks the node Ready, no
# instance-manager is created, every volume stays 'unknown' and each consumer pod sits in
# Pending. That is the chain that makes a plain 'kubectl uncordon' look like it did nothing.
function Get-ControllerWorkloadStatus {
    <#
    .SYNOPSIS
        Readiness of every Deployment/DaemonSet in a namespace, so recovery can restart
        exactly the controllers that are short of replicas.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns one row per controller workload in the namespace; the plural meaning is the contract')]
    param(
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter()][string[]]$NameFilter = @(),
        [Parameter()][string[]]$NameExclude = @()
    )

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($kind in @('deployment', 'daemonset')) {
        foreach ($item in (Get-K8sJson -KubectlArgs @('get', $kind, '-n', $Namespace))) {
            $name = [string](Get-Prop (Get-Prop $item 'metadata') 'name')
            if (-not $name) { continue }
            if ($NameFilter.Count -gt 0 -and -not ($NameFilter -contains $name)) { continue }

            $excluded = $false
            foreach ($pattern in $NameExclude) { if ($name -like $pattern) { $excluded = $true; break } }
            if ($excluded) { continue }

            if ($kind -eq 'deployment') {
                $desired = Get-Prop (Get-Prop $item 'spec') 'replicas'
                if ($null -eq $desired) { $desired = 1 }
                $ready = Get-Prop (Get-Prop $item 'status') 'readyReplicas'
            }
            else {
                $desired = Get-Prop (Get-Prop $item 'status') 'desiredNumberScheduled'
                $ready = Get-Prop (Get-Prop $item 'status') 'numberReady'
            }
            if ($null -eq $desired) { $desired = 0 }
            if ($null -eq $ready) { $ready = 0 }

            $out.Add([pscustomobject]@{
                    Kind      = $kind
                    Name      = $name
                    Namespace = $Namespace
                    Desired   = [int]$desired
                    Ready     = [int]$ready
                    Healthy   = ([int]$desired -gt 0 -and [int]$ready -ge [int]$desired)
                })
        }
    }
    return @($out)
}
function Repair-PlatformNamespace {
    <#
    .SYNOPSIS
        Brings one platform namespace back: purge zombie controller pods, then restart only
        the controllers that are short of replicas.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter()][string]$Reason = 'platform recovery',
        [Parameter()][string[]]$NameFilter = @(),
        [Parameter()][string[]]$NameExclude = @(),
        [Parameter()][string[]]$RestartExclude = @(),
        [Parameter()]$NodeState = $null
    )

    if (-not $DoPlatformRepair) {
        Write-Warn "platform recovery skipped for '$Namespace' (-SkipPlatformRepair)."
        return [pscustomobject]@{ Restarted = @(); Purged = @() }
    }

    $purged = [System.Collections.Generic.List[string]]::new()
    foreach ($zombie in (Get-PlatformZombiePod -Namespace $Namespace -NameFilter $NameFilter `
                -NameExclude $NameExclude -NodeState $NodeState)) {
        Test-Budget "purging zombie platform pod $($zombie.Name)"
        Write-Info "purging zombie platform pod [$Namespace] $($zombie.Name) ($($zombie.Why))"
        $ok = Invoke-KubectlMutation -Description "force-delete zombie platform pod $Namespace/$($zombie.Name)" `
            -KubectlArgs @('delete', 'pod', $zombie.Name, '-n', $Namespace, '--grace-period=0', '--force') `
            -ActionType 'platform-repair' -Target "$Namespace/$($zombie.Name)" -AllowFailure
        if ($ok) { $purged.Add($zombie.Name) }
    }

    $restarted = [System.Collections.Generic.List[string]]::new()
    foreach ($workload in (Get-ControllerWorkloadStatus -Namespace $Namespace -NameFilter $NameFilter `
                -NameExclude $NameExclude)) {
        if ($workload.Healthy) { continue }
        $excluded = $false
        foreach ($pattern in $RestartExclude) { if ($workload.Name -like $pattern) { $excluded = $true; break } }
        if ($excluded) { continue }

        Test-Budget "restarting $($workload.Kind)/$($workload.Name) during $Reason"
        Write-Warn "$Namespace/$($workload.Kind)/$($workload.Name) is $($workload.Ready)/$($workload.Desired) ready - restarting."
        $ok = Invoke-KubectlMutation -Description "rollout restart $($workload.Kind)/$($workload.Name) -n $Namespace ($Reason)" `
            -KubectlArgs @('rollout', 'restart', "$($workload.Kind)/$($workload.Name)", '-n', $Namespace) `
            -ActionType 'platform-repair' -Target "$Namespace/$($workload.Name)" -AllowFailure
        if ($ok) { $restarted.Add("$Namespace/$($workload.Name)") }
    }

    return [pscustomobject]@{ Restarted = @($restarted); Purged = @($purged) }
}
function Get-PlatformZombiePod {
    <#
    .SYNOPSIS
        Platform-owned pods that can never recover on their own and block their controller
        from creating a replacement (kubelet lost them, or their node is gone).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter()][string[]]$NameFilter = @(),
        [Parameter()][string[]]$NameExclude = @(),
        [Parameter()]$NodeState = $null
    )

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($pod in (Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $Namespace))) {
        $md = Get-Prop $pod 'metadata'
        $st = Get-Prop $pod 'status'
        $name = [string](Get-Prop $md 'name')
        if (-not $name) { continue }
        if (Get-Prop $md 'deletionTimestamp') { continue }

        if ($NameFilter.Count -gt 0) {
            $matched = $false
            foreach ($pattern in $NameFilter) { if ($name -like $pattern) { $matched = $true; break } }
            if (-not $matched) { continue }
        }
        $excluded = $false
        foreach ($pattern in $NameExclude) { if ($name -like $pattern) { $excluded = $true; break } }
        if ($excluded) { continue }

        $phase = [string](Get-Prop $st 'phase')
        $reason = [string](Get-Prop $st 'reason')
        $node = [string](Get-Prop (Get-Prop $pod 'spec') 'nodeName')

        $zombie = $false
        $why = ''
        if ($phase -in @('Unknown', 'Failed')) { $zombie = $true; $why = "phase=$phase" }
        elseif ($reason -eq 'NodeLost') { $zombie = $true; $why = 'NodeLost' }
        elseif ($null -ne $NodeState -and $node -and $NodeState.Contains($node) -and -not $NodeState[$node].Ready) {
            $zombie = $true
            $why = "stranded on NotReady node '$node'"
        }
        else {
            foreach ($cs in @(Get-Prop $st 'containerStatuses')) {
                $terminatedReason = Get-Prop (Get-Prop (Get-Prop $cs 'state') 'terminated') 'reason'
                if ($terminatedReason -eq 'ContainerStatusUnknown') {
                    $zombie = $true
                    $why = 'ContainerStatusUnknown'
                    break
                }
            }
        }
        if (-not $zombie) { continue }

        $out.Add([pscustomobject]@{ Namespace = $Namespace; Name = $name; Node = $node; Why = $why })
    }
    return @($out)
}
function Get-DnsEndpointCount {
    <#
    .SYNOPSIS
        Ready kube-dns endpoint addresses. Zero means cluster DNS cannot answer anything.

    .DESCRIPTION
        Prefers EndpointSlice (current API); falls back to the deprecated v1 Endpoints. Only
        addresses the API reports as ready are counted - an EndpointSlice endpoint with
        'ready=false' is not a working DNS server, and v1 Endpoints lists the same address
        once per port, so a single ready backend is reported once.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $ready = 0
    foreach ($slice in (Get-K8sJson -KubectlArgs @('get', 'endpointslice', '-n', $PlatformNamespace,
                '-l', 'kubernetes.io/service-name=kube-dns'))) {
        foreach ($ep in @(Get-Prop $slice 'endpoints')) {
            if ((Get-Prop (Get-Prop $ep 'conditions') 'ready') -eq $true) { $ready++ }
        }
    }
    if ($ready -gt 0) { return $ready }

    # v1 Endpoints fallback: count a backend once, regardless of how many ports it exposes.
    $ips = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ep in (Get-K8sJson -KubectlArgs @('get', 'endpoints', 'kube-dns', '-n', $PlatformNamespace))) {
        foreach ($subset in @(Get-Prop $ep 'subsets')) {
            foreach ($address in @(Get-Prop $subset 'addresses')) {
                $ip = [string](Get-Prop $address 'ip')
                if ($ip) { $null = $ips.Add($ip) }
            }
        }
    }
    return $ips.Count
}

function Wait-DnsReady {
    <#
    .SYNOPSIS
        Waits for cluster DNS to have a ready endpoint. This is the gate for the whole
        recovery: without it Longhorn's own managers cannot reach their webhook service.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][int]$TimeoutSeconds = 300,
        [Parameter()][int]$PollSeconds = 10
    )

    $count = Get-DnsEndpointCount
    if ($count -gt 0) { return $true }
    if ($script:DryRun) {
        Write-Info 'dry-run: not waiting for cluster DNS to come back.'
        return $false
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($count -eq 0 -and $sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Test-Budget 'waiting for cluster DNS'
        Write-Info "kube-dns still has no ready endpoint - waiting ${PollSeconds}s..."
        Start-Sleep -Seconds $PollSeconds
        $count = Get-DnsEndpointCount
    }
    $sw.Stop()
    return ($count -gt 0)
}
# ── Longhorn control-plane recovery ────────────────────────────────────
# Why this exists: 'volume unknown' with crashlooping csi-plugin pods is not a volume problem,
# it is a control-plane problem. When a whole cluster is power-cycled, Longhorn's own
# controllers come back before CoreDNS does, fail their readiness checks, never update the
# longhorn Node status, and therefore never recreate the instance-managers that every mount
# depends on. Recycling CSI plugin pods (the newer storage-repair phase) cannot help with
# that, because there is no instance-manager left to serve the block device.
function Get-LonghornControlPlaneStatus {
    <#
    .SYNOPSIS
        Longhorn's own control-plane health: controller readiness, instance-managers versus
        what the ready nodes should host, and Longhorn's view of node readiness.
        Longhorn v1.8+ runs one consolidated instance-manager per Ready node.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $managers = @(Get-ControllerWorkloadStatus -Namespace $StorageNamespace -NameFilter @('longhorn-manager'))
    $plugins = @(Get-ControllerWorkloadStatus -Namespace $StorageNamespace -NameFilter @('longhorn-csi-plugin'))

    $lhNodes = Get-K8sJson -KubectlArgs @('get', 'nodes.longhorn.io', '-n', $StorageNamespace)
    $readyNodes = 0
    $multipathNodes = [System.Collections.Generic.List[string]]::new()
    foreach ($lhNode in $lhNodes) {
        $names = [string](Get-Prop (Get-Prop $lhNode 'metadata') 'name')
        foreach ($condition in @(Get-Prop (Get-Prop $lhNode 'status') 'conditions')) {
            $type = Get-Prop $condition 'type'
            if ($type -eq 'Ready' -and (Get-Prop $condition 'status') -eq 'True') { $readyNodes++ }
            if ($type -eq 'Multipathd' -and (Get-Prop $condition 'status') -ne 'True' -and $names) {
                $multipathNodes.Add($names)
            }
        }
    }

    $imCount = @(Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $StorageNamespace,
            '-l', 'longhorn.io/component=instance-manager')).Count
    # Longhorn v1.8+ runs one consolidated 'aio' instance-manager per node (engine + replica
    # duties combined), NOT the older split pair. One per Ready node is the healthy target;
    # waiting for two per node stalls forever because Longhorn never creates the second one.
    $expectedIm = $readyNodes

    $managerReady = 0
    $managerDesired = 0
    if ($managers.Count -gt 0) { $managerReady = $managers[0].Ready; $managerDesired = $managers[0].Desired }
    $pluginReady = 0
    $pluginDesired = 0
    if ($plugins.Count -gt 0) { $pluginReady = $plugins[0].Ready; $pluginDesired = $plugins[0].Desired }

    return [pscustomobject]@{
        ManagerReady            = $managerReady
        ManagerDesired          = $managerDesired
        PluginReady             = $pluginReady
        PluginDesired           = $pluginDesired
        NodeReady               = $readyNodes
        NodeCount               = @($lhNodes).Count
        InstanceManagerCount    = $imCount
        ExpectedInstanceManager = $expectedIm
        MultipathNodes          = @($multipathNodes)
        Ok                      = ($managerDesired -gt 0 -and $managerReady -ge $managerDesired -and
            $pluginDesired -gt 0 -and $pluginReady -ge $pluginDesired -and
            $readyNodes -gt 0 -and $imCount -ge $expectedIm)
    }
}


function Repair-LonghornControlPlane {
    <#
    .SYNOPSIS
        Restores Longhorn's own controllers and instance-managers before any volume is touched.

    .DESCRIPTION
        Only fault-tolerant controller workloads are restarted - never engine-image, never a
        share-manager, never an instance-manager pod. Instance-managers cannot be created
        directly: they appear once Longhorn's node status flips to Ready, which needs working
        cluster DNS first (see the platform phase). One is expected per Ready node (v1.8+ uses a
        single consolidated 'aio' manager) - zero means no volume on that node can attach at all.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $status = Get-LonghornControlPlaneStatus
    Write-Info ("longhorn control plane: manager {0}/{1}, csi-plugin {2}/{3}, instance-managers {4}/{5}, nodes Ready {6}/{7}" -f `
            $status.ManagerReady, $status.ManagerDesired, $status.PluginReady, $status.PluginDesired,
        $status.InstanceManagerCount, $status.ExpectedInstanceManager, $status.NodeReady, $status.NodeCount)

    if ($status.Ok) {
        Write-Ok 'Longhorn control plane is ready.'
        return $status
    }

    # Collapse guard, evaluated BEFORE any controller restart. On 2026-09-25 the Longhorn node
    # count fell 7/9 -> 5/9 -> 2/9 -> 1/9 while the run kept cycling csi-provisioner /
    # csi-snapshotter / longhorn-driver-deployer / longhorn-ui and both DaemonSets. Restarting
    # the components that ARE the control plane while it is collapsing accelerates the
    # collapse. Below the floor, do not mutate - observe and report instead.
    $collapseFloor = [math]::Max(1, [math]::Ceiling($status.NodeCount * 0.5))
    $alreadyCollapsed = ($status.NodeCount -gt 0 -and $status.NodeReady -lt $collapseFloor)

    if ($alreadyCollapsed) {
        Write-Bad ("Longhorn control plane is COLLAPSING ({0}/{1} nodes Ready, floor {2}) - skipping controller restarts." -f `
                $status.NodeReady, $status.NodeCount, $collapseFloor)
        Write-Warn 'A collapsing control plane needs a human to find the blocking pod (check for pods stuck Terminating) - blind restarts make this worse.'
        Add-Finding ("Longhorn control plane collapsed at start of repair ({0}/{1} nodes Ready)" -f $status.NodeReady, $status.NodeCount)
    }
    else {
        $null = Repair-PlatformNamespace -Namespace $StorageNamespace -Reason 'Longhorn control-plane recovery' `
            -NameExclude @('engine-image-*', 'instance-manager-*', 'share-manager-*') `
            -RestartExclude @('engine-image-*', 'instance-manager-*')
    }

    if ($script:DryRun) {
        Write-Info 'dry-run: not waiting for Longhorn controllers / instance-managers.'
        return Get-LonghornControlPlaneStatus
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $collapsed = $alreadyCollapsed

    while ($sw.Elapsed.TotalSeconds -lt $LonghornWaitSeconds) {
        Test-Budget 'waiting for the Longhorn control plane'
        $status = Get-LonghornControlPlaneStatus
        if ($status.Ok) { break }

        if (-not $collapsed -and $status.NodeCount -gt 0 -and $status.NodeReady -lt $collapseFloor) {
            $collapsed = $true
            Write-Bad ("Longhorn control plane is COLLAPSING ({0}/{1} nodes Ready, floor {2}) - no further controller restarts will be attempted." -f `
                    $status.NodeReady, $status.NodeCount, $collapseFloor)
            Write-Warn 'A collapsing control plane needs a human to find the blocking pod (check for pods stuck Terminating) - blind restarts make this worse.'
            Add-Finding ("Longhorn control plane collapsed to {0}/{1} ready nodes during the wait" -f $status.NodeReady, $status.NodeCount)
            break
        }

        # Say which node(s) are lagging, not just a bare ratio - "7/14 instance-managers" hides
        # the fact that the missing ones are all on one node.
        $lagging = @()
        foreach ($lhNode in (Get-K8sJson -KubectlArgs @('get', 'nodes.longhorn.io', '-n', $StorageNamespace))) {
            $name = [string](Get-Prop (Get-Prop $lhNode 'metadata') 'name')
            if (-not $name) { continue }
            $ready = $false
            foreach ($condition in @(Get-Prop (Get-Prop $lhNode 'status') 'conditions')) {
                if ((Get-Prop $condition 'type') -eq 'Ready' -and (Get-Prop $condition 'status') -eq 'True') { $ready = $true; break }
            }
            if (-not $ready) { $lagging += "$name(notReady)" }
        }
        $imNodes = @{}
        foreach ($pod in (Get-K8sJson -KubectlArgs @('get', 'pods', '-n', $StorageNamespace,
                    '-l', 'longhorn.io/component=instance-manager'))) {
            $node = [string](Get-Prop (Get-Prop $pod 'spec') 'nodeName')
            if ($node) { $imNodes[$node] = ($imNodes[$node] + 1) }
        }
        foreach ($lhNode in (Get-K8sJson -KubectlArgs @('get', 'nodes.longhorn.io', '-n', $StorageNamespace))) {
            $name = [string](Get-Prop (Get-Prop $lhNode 'metadata') 'name')
            if (-not $name -or $lagging -contains "$name(notReady)") { continue }
            if (-not $imNodes.ContainsKey($name)) { $lagging += "$name(noIM)" }
        }

        $remaining = [math]::Max(0, [math]::Round($LonghornWaitSeconds - $sw.Elapsed.TotalSeconds))
        Write-Info ("waiting {0}s left: manager {1}/{2}, csi-plugin {3}/{4}, instance-managers {5}/{6}, nodes Ready {7}/{8}" -f `
                $remaining, $status.ManagerReady, $status.ManagerDesired, $status.PluginReady, $status.PluginDesired,
            $status.InstanceManagerCount, $status.ExpectedInstanceManager, $status.NodeReady, $status.NodeCount)
        if ($lagging.Count -gt 0) {
            Write-Info "  still waiting on: $($lagging -join ', ')"
        }
        if ($sw.Elapsed.TotalSeconds -lt $LonghornWaitSeconds) { Start-Sleep -Seconds 20 }
    }
    $sw.Stop()

    if ($status.Ok) {
        Write-Ok ("Longhorn control plane recovered ({0} instance-manager(s) across {1} ready node(s))." -f `
                $status.InstanceManagerCount, $status.NodeReady)
    }
    else {
        Write-Bad ("Longhorn control plane still degraded after {0}s - moving on; the volume-repair phase will retry." -f $LonghornWaitSeconds)
        Write-Info ("  instance-managers {0}/{1}, nodes Ready {2}/{3}" -f `
                $status.InstanceManagerCount, $status.ExpectedInstanceManager, $status.NodeReady, $status.NodeCount)
        Add-Finding ("Longhorn control plane degraded after {0}s wait" -f $LonghornWaitSeconds)
    }
    return $status
}


# ── multipathd remediation ─────────────────────────────────────────────
# Longhorn reports 'Multipathd=True/False' per node: when multipathd is running it can claim
# Longhorn's /dev/longhorn devices and the mount fails with "Can't open blockdev". Longhorn
# computes this condition for us, so detection costs nothing and needs no node access.
function Get-MultipathNodeName {
    <#
    .SYNOPSIS
        Nodes where Longhorn reports multipathd running (its Multipathd condition is not True).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns the collection of affected nodes; the plural meaning is the contract')]
    param()

    return @((Get-LonghornControlPlaneStatus).MultipathNodes)
}


function Repair-Multipathd {
    <#
    .SYNOPSIS
        Disables multipathd on the nodes where Longhorn flags it, because a running
        multipathd claims Longhorn's devices and mounts then fail with "Can't open blockdev".

    .DESCRIPTION
        Deliberately narrow: only nodes Longhorn itself flags, only Ready nodes, one at a time,
        and never a protected node. The command runs inside a privileged pod that joins the
        host PID/mount namespaces, so it is a real node-level change - reversible with
        'systemctl enable --now multipathd'. -MultipathDebugPod points at an existing
        privileged pod to exec into instead of creating one; that pod is never deleted.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns the collection of nodes that were remediated; the plural meaning is the contract')]
    param(
        [Parameter()]$NodeState = $null
    )

    $targets = @(Get-MultipathNodeName)
    if ($targets.Count -eq 0) {
        Write-Ok 'multipathd is not flagged on any Longhorn node.'
        return @()
    }

    if (-not $DoMultipathRepair) {
        Write-Warn "multipathd is running on $(($targets -join ', ')) but repair was skipped (-SkipMultipathRepair)."
        Add-Finding "multipathd running (Longhorn flags it as a known issue): $($targets -join ', ')"
        return @()
    }

    $repaired = [System.Collections.Generic.List[string]]::new()
    foreach ($nodeName in $targets) {
        $state = if ($null -ne $NodeState -and $NodeState.Contains($nodeName)) { $NodeState[$nodeName] } else { $null }
        if ($null -ne $state -and -not $state.Ready) {
            Write-Warn "multipath repair skipped on '$nodeName': node is not Ready."
            continue
        }
        if ($null -ne $state -and $state.IsProtected) {
            # A protected node that Longhorn has ALSO flagged is a suspect, not a non-event.
            # In the 2026-09-25 run kubernetes7 was the only NotReady node and the only
            # multipathd-flagged node at the same time, yet the skip was reported as a shrug.
            # Never auto-repair a protected node, but make the coincidence actionable.
            $alsoUnhealthy = ($null -ne $state) -and (-not $state.Ready)
            if ($alsoUnhealthy) {
                Write-Warn ("multipath repair skipped on protected node '{0}' - this node is ALSO not Ready and may be the cause of the Longhorn degradation. Repair it manually." -f $nodeName)
                Add-Finding ("multipathd flagged on protected AND unhealthy node $nodeName - manual repair likely required")
            }
            else {
                Write-Warn "multipath repair skipped on protected node '$nodeName'."
            }
            continue
        }

        Test-Budget "disabling multipathd on $nodeName"
        Write-Info "Disabling multipathd on '$nodeName' (Longhorn reports it as a known issue)..."

        if ($script:DryRun) {
            Write-Info "[DRY-RUN] disable multipathd on $nodeName via a privileged host-namespace shell"
            Add-Action -Type 'dry-run' -Target $nodeName -Detail "multipathd disable on $nodeName"
            continue
        }

        $phase = ''
        if ($MultipathDebugPod) {
            $ok = Invoke-KubectlMutation -Description "disable multipathd on $nodeName via $MultipathDebugPod" `
                -KubectlArgs @('exec', '-n', $PlatformNamespace, $MultipathDebugPod, '--',
                    'nsenter', '-t', '1', '-m', '-u', '-i', '-n', '-p', '--',
                    'sh', '-c', 'systemctl disable --now multipathd; systemctl mask multipathd') `
                -ActionType 'multipath-repair' -Target $nodeName -AllowFailure
            if ($ok) { $phase = 'Succeeded' }
        }
        else {
$podName = ("multipath-repair-{0}" -f $nodeName) -replace '[^a-z0-9-]', '-'
            if ($podName.Length -gt 63) { $podName = $podName.Substring(0, 63) }
            $manifestPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "multipath-$nodeName.json"
            [pscustomobject]@{
                apiVersion = 'v1'
                kind       = 'Pod'
                metadata   = [pscustomobject]@{
                    name      = $podName
                    namespace = $PlatformNamespace
                    labels    = [pscustomobject]@{ app = 'multipath-repair' }
                }
                spec       = [pscustomobject]@{
                    nodeName      = $nodeName
                    hostPID       = $true
                    restartPolicy = 'Never'
                    tolerations   = @([pscustomobject]@{ operator = 'Exists' })
                    containers    = @([pscustomobject]@{
                            name            = 'repair'
                            image           = $MultipathImage
                            imagePullPolicy = 'IfNotPresent'
                            securityContext = [pscustomobject]@{ privileged = $true }
                            command         = @('nsenter', '-t', '1', '-m', '-u', '-i', '-n', '-p', '--',
                                'sh', '-c', 'systemctl disable --now multipathd; systemctl mask multipathd')
                        })
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding utf8

            $null = Invoke-KubectlMutation -Description "start multipath repair pod $podName on $nodeName" `
                -KubectlArgs @('apply', '-f', $manifestPath) `
                -ActionType 'multipath-repair' -Target $nodeName -AllowFailure

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $MultipathWaitSeconds) {
                Start-Sleep -Seconds 5
                $live = @(Get-K8sJson -KubectlArgs @('get', 'pod', $podName, '-n', $PlatformNamespace))
                if ($live.Count -gt 0) {
                    $phase = [string](Get-Prop (Get-Prop $live[0] 'status') 'phase')
                    if ($phase -in @('Succeeded', 'Failed')) { break }
                }
            }
            $sw.Stop()

            # Always clean up, even when the pod never started (image missing, node pressure).
            $null = Invoke-KubectlMutation -Description "remove multipath repair pod $podName" `
                -KubectlArgs @('delete', 'pod', $podName, '-n', $PlatformNamespace,
                    '--grace-period=0', '--force', '--ignore-not-found') `
                -ActionType 'multipath-repair' -Target $nodeName -AllowFailure
            Remove-Item -Path $manifestPath -Force -ErrorAction SilentlyContinue
        }

        if ($phase -eq 'Succeeded') {
            Write-Ok "multipathd disabled on $nodeName."
            $repaired.Add($nodeName)
        }
        else {
            Write-Warn "multipathd could not be disabled on $nodeName (repair pod phase='$phase') - continuing."
            Add-Finding "multipathd still running on $nodeName"
        }
    }

    return @($repaired)
}
function Get-LatestVolumeBackupName {
    <#
    .SYNOPSIS
        Newest completed Longhorn backup for a volume, or $null when the volume has none.

    .DESCRIPTION
        The actionable half of a faulted-volume report: "restore it" is useless advice without
        a backup name, and a volume with no backup at all can only be rebuilt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$VolumeName
    )

    $newest = $null
    $newestAt = ''
    foreach ($backup in (Get-K8sJson -KubectlArgs @('get', 'backups.longhorn.io', '-n', $StorageNamespace))) {
        $status = Get-Prop $backup 'status'
        if ([string](Get-Prop $status 'volumeName') -ne $VolumeName) { continue }
        if ([string](Get-Prop $status 'state') -ne 'Completed') { continue }

        $at = [string](Get-Prop $status 'backupCreatedAt')
        if ($newestAt -eq '' -or $at -gt $newestAt) {
            $newestAt = $at
            $newest = [string](Get-Prop (Get-Prop $backup 'metadata') 'name')
        }
    }
    return $newest
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
    "platform core + DNS recovery    : $(if ($DoPlatformRepair) { 'ON' } else { 'SKIPPED (-SkipPlatformRepair)' })"
    "Longhorn control-plane recovery : $(if ($DoStorageRepair) { 'ON' } else { 'SKIPPED (-SkipStorageRepair)' })"
    "multipathd remediation          : $(if ($DoMultipathRepair) { 'ON' } else { 'SKIPPED (-SkipMultipathRepair)' })"
    "purge stranded/zombie pods      : ON (always)"
    "repair Longhorn + recycle CSI   : $(if ($DoStorageRepair) { 'ON' } else { 'SKIPPED (-SkipStorageRepair)' })"
    "engine-frontend recovery        : $(if ($DoHostMountRepair) { 'ON' } else { 'SKIPPED (-SkipHostMountRepair)' })"
    "serialized workload reconcile   : $(if ($DoRestartWorkloads) { 'ON' } else { 'SKIPPED' })"
    "restart Deployments on degraded storage : $(if ($ForceRestartWithDegradedStorage) { 'YES (-ForceRestartWithDegradedStorage)' } else { 'no (skipped while Longhorn is degraded)' })"
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
    Write-Step "[1/9] Inventory - expected vs actual nodes"

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

    # Control-plane / embedded-etcd quorum is reported BEFORE any mutation: with more than one
    # server, "the API answers" no longer implies "the control plane can survive a failure".
    $controlPlane = Get-ControlPlaneStatus -NodeObjects (Get-K8sJson -KubectlArgs @('get', 'nodes')) -ApiServerUrl $actualServer
    Write-Info ("Control plane: {0}/{1} embedded-etcd member(s) Ready (quorum {2}; can lose {3})" -f `
            $controlPlane.ReadyCount, $controlPlane.MemberCount, $controlPlane.Quorum, $controlPlane.ToleratesLoss)
    if (-not $controlPlane.HasQuorum) {
        Write-Bad "Control-plane quorum is ALREADY LOST ($($controlPlane.ReadyCount)/$($controlPlane.MemberCount) Ready, quorum $($controlPlane.Quorum)). Recovery steps may fail unpredictably - restore a control-plane member first."
        Add-Finding "Control-plane quorum lost at start of run: $($controlPlane.NotReady -join ', ') NotReady"
    }
    elseif ($controlPlane.NotReady.Count -gt 0) {
        Write-Warn "Control-plane member(s) NotReady: $($controlPlane.NotReady -join ', ') - quorum is held by the remaining $(($controlPlane.Members | Where-Object { $_.Ready }).Count) member(s), with zero further tolerance."
        Add-Finding "Control-plane member(s) NotReady at start of run: $($controlPlane.NotReady -join ', ')"
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
    Write-Step "[2/9] Uncordoning nodes"

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

    # ── Step 3: Platform (cluster core) recovery ─────────────────────────
    Write-Step "[3/9] Platform recovery - cluster core and DNS"

    $platform = Repair-PlatformNamespace -Namespace $PlatformNamespace -Reason 'cluster core recovery' `
        -NodeState $nodeState
    if ($platform.Purged.Count -gt 0) { Write-Ok "purged $($platform.Purged.Count) zombie platform pod(s)." }
    if ($platform.Restarted.Count -gt 0) { Write-Ok "restarted $($platform.Restarted.Count) platform controller(s)." }

    if (Wait-DnsReady -TimeoutSeconds $PlatformWaitSeconds) {
        Write-Ok "cluster DNS is answering ($(Get-DnsEndpointCount) kube-dns endpoint(s))."
    }
    else {
        Add-Finding 'Cluster DNS (kube-dns) has no ready endpoint after platform recovery'
        if ($script:DryRun) {
            Write-Warn 'cluster DNS has no ready endpoint (dry-run: not waited for).'
        }
        else {
            Write-Bad 'cluster DNS still has no ready endpoint - every storage and app phase depends on it.'
        }
    }

    # ── Step 4: Longhorn control plane, then multipathd ──────────────────
    Write-Step "[4/9] Longhorn control plane and host mount blockers"

    if ($DoStorageRepair) {
        $null = Repair-LonghornControlPlane
    }
    else {
        Write-Info 'Longhorn control-plane recovery skipped (-SkipStorageRepair).'
    }
    $null = Repair-Multipathd -NodeState $nodeState


    # ── Step 3: Diagnose workloads and storage ───────────────────────────
    Write-Step "[5/9] Diagnosing workloads and storage"

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
    Write-Step "[6/9] Repair - storage first, then stranded workloads"

    $repairedSomething = $false
    $deadNodeNames = @($nodeState.Values | Where-Object { -not $_.Ready } | ForEach-Object { $_.Name })
    $deadNodeNames += $missingNodes

    # 4a-0 - Clear stale VolumeAttachments before CSI plugin recycling
    # This fixes the case where pods are stuck in Pending because Kubernetes holds
    # onto old attachments for volumes that Longhorn has reattached elsewhere.
    if ($DoStorageRepair -and $DoStaleAttachmentCleanup -and $storageStatus.Available) {
        $cleared = @(Clear-StaleVolumeAttachment)
        if ($cleared.Count -gt 0) {
            Write-Info "Cleared $($cleared.Count) stale VolumeAttachment(s)"
            $repairedSomething = $true
            # Wait a moment for the attach/detach controller to re-attach
            if (-not $script:DryRun) {
                Write-Info "Waiting 10s for the attach/detach controller to re-attach volumes..."
                Start-Sleep -Seconds 10
            }
        }
    }

    # 4a-1 - Longhorn pods left Terminating on nodes that are gone.
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

                # 4b-ii - Last resort: pods still Pending here have a dead engine
                # frontend ('Can't open blockdev'), which CSI recycling and pod
                # cycling cannot fix. Respawn the instance-manager on those nodes
                # (healthy volumes only, Ready nodes only).
                $recheckPods = Get-K8sJson -KubectlArgs @('get', 'pods', '-A')
                $restillBlocked = [System.Collections.Generic.List[object]]::new()
                foreach ($candidate in $stillBlocked) {
                    foreach ($pod in $recheckPods) {
                        $md = Get-Prop $pod 'metadata'
                        if ((Get-Prop $md 'namespace') -eq $candidate.Namespace -and (Get-Prop $md 'name') -eq $candidate.Name) {
                            if ((Get-Prop (Get-Prop $pod 'status') 'phase') -notin @('Running', 'Succeeded')) {
                                # Pods still in init (volumes already mounted, waiting on
                                # something else - e.g. flick-api waiting for its DB) must
                                # not trigger engine recovery: only pods whose containers
                                # cannot even start are mount-blocked.
                                $conds = @(Get-Prop (Get-Prop $pod 'status') 'conditions')
                                $initialized = @($conds | Where-Object { (Get-Prop $_ 'type') -eq 'Initialized' })
                                $readyToStart = @($conds | Where-Object { (Get-Prop $_ 'type') -eq 'PodReadyToStartContainers' })
                                $inInit = ($initialized.Count -gt 0 -and (Get-Prop $initialized[0] 'status') -ne 'True' -and
                                    $readyToStart.Count -gt 0 -and (Get-Prop $readyToStart[0] 'status') -eq 'True')
                                if (-not $inInit) { $restillBlocked.Add($candidate) }
                                else { Write-Info "engine recovery not needed for [$($candidate.Namespace)] $($candidate.Name): still in init, volumes mounted." }
                            }
                            break
                        }
                    }
                }
                if ($restillBlocked.Count -gt 0) {
                    $engineNodes = @(Repair-StaleVolumeFrontend -BlockedPods @($restillBlocked) `
                            -PvcMap $pvcMap -NodeState $nodeState -NodeFilter $HostMountNodes)
                    if ($engineNodes.Count -gt 0) { $repairedSomething = $true }

                    # 4b-iii - Move pods off nodes whose frontend is proven dead (the engine
                    # was just respawned there and the pod still cannot mount). Cordon the
                    # node, gracefully delete the pod so it attaches elsewhere, uncordon.
                    # One move per pod per run; protected nodes are never cordoned.
                    $restillStatus = @(Get-PendingPodStatus -Candidates @($restillBlocked))
                    $cordonedHere = [System.Collections.Generic.List[string]]::new()
                    $movedPods = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $restillStatus) {
                        if ($item.InInit) {
                            Write-Info "reschedule not needed for [$($item.Namespace)] $($item.Name): still in init, volumes mounted."
                            continue
                        }
                        if (-not $item.Node -or -not ($engineNodes -contains $item.Node)) { continue }
                        if ($nodeState.Contains($item.Node) -and $nodeState[$item.Node].IsProtected) {
                            Write-Warn "reschedule skipped for [$($item.Namespace)] $($item.Name): '$($item.Node)' is protected and cannot be cordoned."
                            continue
                        }
                        if (-not ($nodeState.Contains($item.Node) -and $nodeState[$item.Node].Unschedulable)) {
                            Test-Budget "cordoning $($item.Node) for reschedule"
                            $ok = Invoke-KubectlMutation -Description "cordon $($item.Node) to reschedule stuck volume consumer $($item.Namespace)/$($item.Name)" `
                                -KubectlArgs @('cordon', $item.Node) `
                                -ActionType 'reschedule' -Target $item.Node -AllowFailure
                            if ($ok -and -not $cordonedHere.Contains($item.Node)) { $null = $cordonedHere.Add($item.Node) }
                            elseif (-not $ok) { continue }
                        }
                        Test-Budget "rescheduling $($item.Name)"
                        Write-Info "Rescheduling [$($item.Namespace)] $($item.Name) off '$($item.Node)' (frontend proven dead there)..."
                        $ok = Invoke-KubectlMutation -Description "gracefully delete stuck volume consumer $($item.Namespace)/$($item.Name) for reschedule" `
                            -KubectlArgs @('delete', 'pod', $item.Name, '-n', $item.Namespace, '--wait=true') `
                            -ActionType 'reschedule' -Target "$($item.Namespace)/$($item.Name)" -AllowFailure
                        if ($ok) { $movedPods.Add($item); $repairedSomething = $true }
                    }
                    if ($movedPods.Count -gt 0) {
                        if ($script:DryRun) {
                            Write-Info 'dry-run: not waiting for rescheduled pods.'
                        }
                        else {
                            Write-Info "Waiting 60s for rescheduled pod(s) to attach elsewhere..."
                            Start-Sleep -Seconds 60
                        }
                    }

                    # 4b-iv - Volume-level wedge: still Pending after a move (or unmovable).
                    # Detection plus restore guidance only - restoring a volume from a
                    # snapshot/backup is a data-loss decision and is never executed here.
                    $wedgeStatus = @(Get-PendingPodStatus -Candidates @($movedPods))
                    foreach ($nodeName in $cordonedHere) {
                        $null = Invoke-KubectlMutation -Description "uncordon $nodeName after reschedule" `
                            -KubectlArgs @('uncordon', $nodeName) `
                            -ActionType 'reschedule' -Target $nodeName -AllowFailure
                    }
                    $wedgeManual = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $restillStatus) {
                        if ($item.InInit) { continue }
                        if ($item.Node -and ($engineNodes -contains $item.Node) -and
                            $nodeState.Contains($item.Node) -and $nodeState[$item.Node].IsProtected) {
                            $wedgeManual.Add($item)
                        }
                    }
                    foreach ($item in $wedgeStatus) { $wedgeManual.Add($item) }
                    if ($wedgeManual.Count -gt 0) {
                        $snapshots = Get-K8sJson -KubectlArgs @('get', 'snapshots.longhorn.io', '-n', $StorageNamespace)
                        $backups = Get-K8sJson -KubectlArgs @('get', 'backups.longhorn.io', '-n', $StorageNamespace)
                        foreach ($item in $wedgeManual) {
                            $pvNames = [System.Collections.Generic.HashSet[string]]::new()
                            if ($null -ne $item.LivePod) {
                                foreach ($claim in @(Get-PodPvcClaims -Pod $item.LivePod)) {
                                    if ($pvcMap.ContainsKey($claim) -and $pvcMap[$claim].VolumeName) {
                                        $null = $pvNames.Add($pvcMap[$claim].VolumeName)
                                    }
                                }
                            }
                            foreach ($pv in $pvNames) {
                                $readySnaps = @($snapshots | Where-Object {
                                        (Get-Prop (Get-Prop (Get-Prop $_ 'metadata') 'labels') 'longhornvolume') -eq $pv -and
                                        (Get-Prop (Get-Prop $_ 'status') 'readyToUse') -eq $true
                                    } | Sort-Object { Get-Prop (Get-Prop $_ 'metadata') 'creationTimestamp' } -Descending | Select-Object -First 3)
                                $doneBackups = @($backups | Where-Object {
                                        (Get-Prop (Get-Prop $_ 'status') 'volumeName') -eq $pv -and
                                        (Get-Prop (Get-Prop $_ 'status') 'state') -eq 'Completed'
                                    } | Sort-Object { Get-Prop (Get-Prop $_ 'metadata') 'creationTimestamp' } -Descending | Select-Object -First 3)
                                $snapText = if ($readySnaps.Count -gt 0) {
                                    ($readySnaps | ForEach-Object {
                                            "{0} ({1})" -f (Get-Prop (Get-Prop $_ 'metadata') 'name'), (Get-Prop (Get-Prop $_ 'metadata') 'creationTimestamp')
                                        }) -join ', '
                                }
                                else { 'none' }
                                $backupText = if ($doneBackups.Count -gt 0) {
                                    ($doneBackups | ForEach-Object {
                                            "{0} ({1})" -f (Get-Prop (Get-Prop $_ 'metadata') 'name'), (Get-Prop (Get-Prop $_ 'metadata') 'creationTimestamp')
                                        }) -join ', '
                                }
                                else { 'none' }
                                Write-Bad "VOLUME WEDGE: $pv (used by $($item.Namespace)/$($item.Name)) fails on every node; replicas are healthy."
                                Write-Info "  snapshots: $snapText"
                                Write-Info "  backups: $backupText"
                                Write-Info "  manual fix: restore the volume from a snapshot/backup to a NEW volume and swap the PVC."
                                Add-Finding ("VOLUME WEDGE: {0} (used by {1}/{2}); snapshots: {3}; backups: {4} - restore manually" -f `
                                        $pv, $item.Namespace, $item.Name, $snapText, $backupText)
                            }
                        }
                    }
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
    Write-Step "[7/9] Reconcile workloads"

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
            # Report every contributing factor, not just degraded volumes. Control-plane
            # nodes are now permanently allowScheduling=false by design, so a message that
            # only counted unhealthy volumes printed the contradictory
            # "Proceeding with degraded storage: 0 attached volume(s) not healthy."
            $reasons = [System.Collections.Generic.List[string]]::new()
            $degradedCount = if ($storageStatus.AttachedDegraded) { $storageStatus.AttachedDegraded.Count } else { 0 }
            $faultedCount = if ($storageStatus.Faulted) { $storageStatus.Faulted.Count } else { 0 }
            $unschedCount = if ($storageStatus.UnschedulableNodes) { $storageStatus.UnschedulableNodes.Count } else { 0 }
            if ($degradedCount -gt 0) { $reasons.Add("$degradedCount attached volume(s) not healthy") }
            if ($faultedCount -gt 0) { $reasons.Add("$faultedCount faulted volume(s)") }
            if ($unschedCount -gt 0) {
                $reasons.Add("$unschedCount Longhorn node(s) not schedulable ($($storageStatus.UnschedulableNodes -join ', '))")
            }
            Write-Bad ("Proceeding with degraded storage: {0}." -f ($reasons -join '; '))
            if ($unschedCount -gt 0 -and $degradedCount -eq 0 -and $faultedCount -eq 0) {
                Write-Info '  (no unhealthy volumes - the only blocker is Longhorn node scheduling, which may be intentional for protected nodes.)'
            }
            Add-Finding ("Reconcile started with degraded Longhorn volumes: {0}" -f ($reasons -join '; '))
        }

        # Track the storage snapshot used by the workload gate. The initial gate may wait up
        # to 10 minutes for Longhorn to converge; do not repeat that wait for every workload.
        $storageStatusLastChecked = Get-Date
        $storageStatusRefreshSeconds = 5

        # Phase A - StatefulSets, strictly serialized: restart -> wait -> next.
        $statefulsets = @(Get-ManagedResource -ResourceType 'statefulsets')
        $statefulsetCount = if ($statefulsets) { $statefulsets.Count } else { 0 }
        Write-Info "Phase A: serialized rolling restart of $($statefulsetCount) StatefulSet(s)"
        $stalledWorkloads = [System.Collections.Generic.List[string]]::new()

        foreach ($sts in $statefulsets) {
            if (-not (Test-BudgetSoft)) { break }
            $ns = Get-Prop (Get-Prop $sts 'metadata') 'namespace'
            $name = Get-Prop (Get-Prop $sts 'metadata') 'name'
            $target = "$ns/$name"

            # Per-resource re-gate: a mid-run storage degradation must not cascade.
            # Refresh the Longhorn snapshot at most once per interval instead of waiting
            # minutes for every StatefulSet.
            if ($storageStatus.Available -and ((Get-Date) -gt $storageStatusLastChecked.AddSeconds($storageStatusRefreshSeconds))) {
                $storageStatus = Get-StorageStatus
                $storageStatusLastChecked = Get-Date
            }
            if ($storageStatus.Available -and -not $storageStatus.Ok) {
                Write-Warn "$target - Longhorn still degraded; skipping restart to avoid an RWO deadlock."
                Add-Finding "Skipped restart of $target (storage degraded)"
                $stalledWorkloads.Add($target)
                continue
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

        # Same safety rule as Phase A, applied to Phase B. On 2026-09-25 all 12 StatefulSets
        # were correctly skipped because restarting RWO database consumers against degraded
        # Longhorn risks a deadlock - and then 49 Deployments were restarted against exactly
        # the same degraded storage. Many of those Deployments mount the same RWO volumes, so
        # this is the same hazard by another route. Offer an opt-in for operators who know
        # their apps are safe, but do not do it silently.
        $phaseBStorage = $null
        if ($script:DryRun) { $phaseBStorage = $storageStatus }
        else { $phaseBStorage = Get-StorageStatus }

        if ($phaseBStorage.Available -and -not $phaseBStorage.Ok -and -not $ForceRestartWithDegradedStorage) {
            $degradedNow = if ($phaseBStorage.AttachedDegraded) { $phaseBStorage.AttachedDegraded.Count } else { 0 }
            $faultedNow = if ($phaseBStorage.Faulted) { $phaseBStorage.Faulted.Count } else { 0 }
            $unschedNow = if ($phaseBStorage.UnschedulableNodes) { $phaseBStorage.UnschedulableNodes.Count } else { 0 }
            Write-Warn ("storage is not fully healthy ({0}/{1} volumes healthy; {2} degraded, {3} faulted, {4} node(s) unschedulable) - skipping the Deployment restart phase." -f `
                    $phaseBStorage.HealthyCount, $phaseBStorage.VolumeCount, $degradedNow, $faultedNow, $unschedNow)
            Write-Info 'Re-run once Longhorn is healthy, or pass -ForceRestartWithDegradedStorage if these Deployments are known to be safe.'
            Add-Finding ("Deployment restart phase skipped: Longhorn not fully healthy ({0}/{1} healthy)" -f $phaseBStorage.HealthyCount, $phaseBStorage.VolumeCount)
        }
        else {

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
        }  # end of: else { Phase B ran }
    }

# ── Step 6: Rebalance (OPT-IN, PDB-aware) ────────────────────────────
    Write-Step "[8/9] Rebalance workload distribution"

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
    Write-Step "[9/9] Verification"

    # Cache repeated kubectl queries to speed up verification (avoid multiple kubectl get calls)
    $allNodes = Get-K8sJson -KubectlArgs @('get', 'nodes')
    $allPods  = Get-K8sJson -KubectlArgs @('get', 'pods', '-A')
    $volumeAttachments = Get-K8sJson -KubectlArgs @('get', 'volumeattachments')
    $podDisruptionBudgets = Get-K8sJson -KubectlArgs @('get', 'pdb', '-A')
    $storageAfter = Get-StorageStatus

    $nodeStateAfter = Get-NodeState -NodeObjects $allNodes `
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

    # Control-plane / embedded-etcd quorum (three members since 2026-09-20).
    $controlPlaneAfter = Get-ControlPlaneStatus -NodeObjects $allNodes -ApiServerUrl $actualServer
    Write-Info ("Control plane: {0}/{1} embedded-etcd member(s) Ready (quorum {2}; can lose {3})" -f `
            $controlPlaneAfter.ReadyCount, $controlPlaneAfter.MemberCount, $controlPlaneAfter.Quorum, $controlPlaneAfter.ToleratesLoss)
    if (-not $controlPlaneAfter.HasQuorum) {
        Write-Bad "Control-plane quorum LOST: $($controlPlaneAfter.ReadyCount)/$($controlPlaneAfter.MemberCount) member(s) Ready (quorum $($controlPlaneAfter.Quorum)). Do NOT power off or restart anything else - restore a control-plane member first."
        Add-Finding "Control-plane quorum lost at end of run: $($controlPlaneAfter.NotReady -join ', ') NotReady"
    }
    elseif ($controlPlaneAfter.NotReady.Count -gt 0) {
        Write-Warn "Control-plane member(s) NotReady: $($controlPlaneAfter.NotReady -join ', '). Quorum holds, but there is no margin left until it rejoins (its etcd member is retained, so starting the host is enough)."
        Add-Finding "Control-plane member(s) NotReady at end of run: $($controlPlaneAfter.NotReady -join ', ')"
    }
    else {
        Write-Ok "All $($controlPlaneAfter.MemberCount) embedded-etcd member(s) are Ready."
    }
    # Client-side endpoint: reported, never counted as a failure. Every kubeconfig here points
    # at one member address, so the API still dies with nuc even though etcd quorum survives.
    if ($controlPlaneAfter.SingleEndpoint) {
        Write-Warn "API endpoint '$($controlPlaneAfter.Endpoint)' is a single control-plane member, not a VIP/DNS name - clients still lose the API if that member goes down (see the control-plane HA plan, Phase 3.1)."
        Add-Finding "API endpoint is a single control-plane member: $($controlPlaneAfter.Endpoint)"
    }

    foreach ($node in $allNodes) {
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

    # Saturation snapshot: metrics-server usage vs capacity, plus Longhorn replica placement.
    # Detection and reporting ONLY - the relief valves for a saturated node are cordon/drain,
    # and the node most prone to saturation (kubernetes7) is protected from both, so nothing
    # here is counted in $degradedTotal or acted on (same contract as the single-endpoint note).
    $saturation = Get-NodeSaturation -NodeObjects $allNodes -ProtectedNodes $protectedNodes `
        -CpuThresholdPercent $NodeSaturationCpuPercent -MemoryThresholdPercent $NodeSaturationMemoryPercent
    if (-not $saturation.MetricsAvailable) {
        Write-Info 'Node saturation: metrics.k8s.io unavailable (metrics-server not recovered?) - only the pressure conditions above were checked.'
        Add-Finding 'Node saturation check skipped: metrics.k8s.io unavailable'
    }
    else {
        Write-Info 'Node saturation (metrics-server usage vs capacity):'
        foreach ($entry in @($saturation.Nodes | Sort-Object { if ($null -eq $_.CpuPercent) { -1 } else { $_.CpuPercent } } -Descending)) {
            $cpuText = if ($null -ne $entry.CpuPercent) { "$($entry.CpuPercent)%" } else { 'unknown' }
            $memText = if ($null -ne $entry.MemoryPercent) { "$($entry.MemoryPercent)%" } else { 'unknown' }
            $marker = if ($entry.Saturated) { " <-- SATURATED ($($entry.Reasons -join '; '))" } else { '' }
            Write-Info ("  {0} : cpu {1}, mem {2}, longhorn replicas {3}{4}" -f $entry.Name, $cpuText, $memText, $entry.ReplicaCount, $marker)
        }
        $saturatedNodes = @($saturation.Nodes | Where-Object { $_.Saturated })
        foreach ($entry in $saturatedNodes) {
            if ($entry.IsProtected) {
                Write-Bad ("{0} is SATURATED ({1}; {2} Longhorn replica(s)) but is a protected node - it cannot be cordoned, drained or powered off. Relieve it indirectly: bring other storage nodes back so Longhorn rebalances replicas off it, and scale down non-critical workloads pinned to it (see WindowsLab/k8s7-cpu-report.md)." -f `
                        $entry.Name, ($entry.Reasons -join '; '), $entry.ReplicaCount)
                Add-Finding "Protected node $($entry.Name) saturated: $($entry.Reasons -join '; ') ($($entry.ReplicaCount) Longhorn replica(s))"
            }
            else {
                Write-Warn ("{0} is saturated ({1}; {2} Longhorn replica(s))." -f $entry.Name, ($entry.Reasons -join '; '), $entry.ReplicaCount)
                Add-Finding "Node $($entry.Name) saturated: $($entry.Reasons -join '; ')"
            }
        }
        if ($saturatedNodes.Count -eq 0) {
            Write-Ok "No node is above the saturation thresholds (CPU $($NodeSaturationCpuPercent)%, memory $($NodeSaturationMemoryPercent)%)."
        }
    }

    if ($storageAfter.Available) {
        Write-Info ("Longhorn: {0}/{1} healthy, {2} degraded, {3} faulted, {4} detached, {5} node(s) not scheduling" -f `
                $storageAfter.HealthyCount, $storageAfter.VolumeCount,
            $storageAfter.AttachedDegraded.Count, $storageAfter.Faulted.Count,
            $storageAfter.Detached.Count, $storageAfter.UnschedulableNodes.Count)
        if ($storageAfter.Ok) { Write-Ok "Longhorn volumes are healthy." }
        else { Write-Warn "Longhorn is still degraded."; Add-Finding "Longhorn degraded at end of run" }
    }

    # A faulted volume is a data-plane fault: no amount of retrying fixes it, so name the
    # restore point instead of leaving the operator with "volume X is broken".
    if ($storageAfter.Faulted.Count -gt 0) {
        Write-Bad "$($storageAfter.Faulted.Count) faulted Longhorn volume(s) - these need a restore, not a retry:"
        foreach ($faultedVolume in $storageAfter.Faulted) {
            $backupName = Get-LatestVolumeBackupName -VolumeName $faultedVolume.Name
            $claimRef = ''
            $pv = @(Get-K8sJson -KubectlArgs @('get', 'pv', $faultedVolume.Name))
            if ($pv.Count -gt 0) {
                $claim = Get-Prop (Get-Prop $pv[0] 'spec') 'claimRef'
                if ($claim) { $claimRef = "{0}/{1}" -f (Get-Prop $claim 'namespace'), (Get-Prop $claim 'name') }
            }
            if ($backupName) {
                Write-Info "  $($faultedVolume.Name) $claimRef (state=$($faultedVolume.State)) -> restore from $backupName"
            }
            else {
                Write-Info "  $($faultedVolume.Name) $claimRef (state=$($faultedVolume.State)) -> no backup found; rebuild required"
            }
        }
        Add-Finding "Faulted Longhorn volumes: $($storageAfter.Faulted.Count)"
    }

    # Cluster core and DNS: if these are down, every other green line in this report is moot.
    $dnsEndpoints = Get-DnsEndpointCount
    if ($dnsEndpoints -gt 0) {
        Write-Ok "cluster DNS has $dnsEndpoints ready endpoint(s)."
    }
    else {
        Write-Bad 'cluster DNS (kube-dns) has no ready endpoint - apps cannot resolve services.'
        Add-Finding 'Cluster DNS has no ready endpoint at end of run'
    }

    $platformBad = @(Get-ControllerWorkloadStatus -Namespace $PlatformNamespace | Where-Object { -not $_.Healthy })
    if ($platformBad.Count -gt 0) {
        foreach ($workload in $platformBad) {
            Write-Warn "cluster-core controller below capacity: $($workload.Namespace)/$($workload.Name) ($($workload.Ready)/$($workload.Desired))"
        }
        Add-Finding "Cluster-core controllers below capacity: $($platformBad.Count)"
    }
    else {
        Write-Ok 'Every cluster-core controller is at full capacity.'
    }

    $lhAfter = Get-LonghornControlPlaneStatus
    if ($lhAfter.Ok) {
        Write-Ok "Longhorn control plane healthy ($($lhAfter.InstanceManagerCount) instance-manager(s) across $($lhAfter.NodeReady) ready node(s))."
    }
    else {
        Write-Bad ("Longhorn control plane degraded: manager {0}/{1}, csi-plugin {2}/{3}, instance-managers {4}/{5}, nodes Ready {6}/{7}" -f `
                $lhAfter.ManagerReady, $lhAfter.ManagerDesired, $lhAfter.PluginReady, $lhAfter.PluginDesired,
            $lhAfter.InstanceManagerCount, $lhAfter.ExpectedInstanceManager, $lhAfter.NodeReady, $lhAfter.NodeCount)
        Add-Finding 'Longhorn control plane degraded at end of run'
    }

    $badAttachments = @(($volumeAttachments | Where-Object { (Get-Prop (Get-Prop $_ 'status') 'attached') -ne $true }) |
            ForEach-Object { Get-Prop (Get-Prop $_ 'metadata') 'name' })
    if ($badAttachments.Count -gt 0) {
        Write-Warn "$($badAttachments.Count) volume attachment(s) not attached."
        Add-Finding "Unattached VolumeAttachment(s): $($badAttachments.Count)"
    }

    $badPdbs = [System.Collections.Generic.List[string]]::new()
    foreach ($pdb in $podDisruptionBudgets) {
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
    foreach ($pod in $allPods) {
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
    if ($storageAfter.Available) {
        $degradedTotal += $storageAfter.AttachedDegraded.Count
        $degradedTotal += $storageAfter.Faulted.Count
    }
    $degradedTotal += $platformBad.Count
    if ($dnsEndpoints -eq 0) { $degradedTotal++ }
    if (-not $lhAfter.Ok) { $degradedTotal++ }
    # Quorum loss is a real degradation (the API cannot be trusted with further changes).
    # The single-member API endpoint is reported as a finding only - it is an architectural
    # gap documented in the HA plan, not something this run can fix.
    if (-not $controlPlaneAfter.HasQuorum) { $degradedTotal++ }

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
                effectivePlatformRepair   = [bool]$DoPlatformRepair
                effectiveMultipathRepair  = [bool]$DoMultipathRepair
                effectiveRebalance        = [bool]$DoRebalance
                skipRestartWorkloads      = [bool]$SkipRestartWorkloads
                skipStorageRepair         = [bool]$SkipStorageRepair
                skipPlatformRepair        = [bool]$SkipPlatformRepair
                skipMultipathRepair       = [bool]$SkipMultipathRepair
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
