# ?? K3s Homelab Systematic Shutdown (v8 - Refined & Verified)
[CmdletBinding()]
param(
    [Parameter(HelpMessage="Skip all manual confirmations")]
    [switch]$Force,

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
    [int]$DetachTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop' # Critical for Catch block to trigger on external errors

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

Write-Host "--- K3s Cluster Shutdown Sequence (v8) ---" -ForegroundColor Cyan

# --- Storage-safe helpers: a node must not lose power while Longhorn still has
#     live attachments on it. Unclean detachment is what wedges engine frontends
#     ('Can't open blockdev' on next boot) and forces instance-manager surgery. ---
function Invoke-NodeSsh {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$RemoteCommand
    )
    $sshArgs = @('-n', '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
        "suryendub@$IP", $RemoteCommand)
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        & sshpass -e ssh @sshArgs
    }
    elseif (Test-Path "/usr/local/bin/sshpass") {
        & /usr/local/bin/sshpass -e ssh @sshArgs
    }
    else {
        & ssh @sshArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "ssh to $IP failed with exit code $LASTEXITCODE." }
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
        # 'allNodes' collides with the PowerShell automatic variable; keep it prefixed.
        $registryAllNodes = kubectl get nodes -o json --request-timeout=10s | ConvertFrom-Json

        function Get-IPv4 {
            param($addresses)
            return ($addresses | Where-Object { $_.type -eq 'InternalIP' -and $_.address -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1 -ExpandProperty address)
        }

        $masterNode = $registryAllNodes.items | Where-Object { $_.metadata.labels.'node-role.kubernetes.io/master' -eq 'true' -or $_.metadata.labels.'node-role.kubernetes.io/control-plane' -eq 'true' }
        # Exclude the control plane and every node flagged neverPowerOff (registry:
        # WindowsLab/homelab-nodes.json). kubernetes7 is DELIBERATELY spared - its power
        # switch is broken, so powering it off means it can never be turned back on.
        $workerNodes = $registryAllNodes.items | Where-Object {
            $_.metadata.name -ne $masterNode.metadata.name -and ($neverPowerOff -notcontains $_.metadata.name)
        }

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

# Hard safety net: never power off a node flagged neverPowerOff in the registry.
foreach ($target in $targets) {
    if ($neverPowerOff -contains $target.Name) {
        throw "Refusing to power off '$($target.Name)': marked neverPowerOff in homelab-nodes.json (broken power switch - unrecoverable)."
    }
}
if ($neverPowerOff -contains $masterFallback.Name) {
    throw "Refusing to power off control-plane node '$($masterFallback.Name)': marked neverPowerOff in homelab-nodes.json."
}

Write-Host "Active Mode: $actualMode" -ForegroundColor Cyan
Write-Host "Master: $masterIp"
Write-Host "Workers: $($targets.Name -join ', ')"

# 2. CREDENTIALS
$credPath = Join-Path $PSScriptRoot "cred.xml"
if (Test-Path $credPath) {
    Write-Host "Attempting to read password from credential file..." -ForegroundColor Cyan
    try {
        $password = Import-Clixml -Path $credPath
    } catch {
        if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
            try {
                $password = Get-Secret -Name "k3s-homelab-sudo" -ErrorAction Stop
                Write-Host "Loaded password from SecretStore vault." -ForegroundColor Green
            } catch {
                $password = Read-Host "Enter sudo password" -AsSecureString
            }
        } else {
            $password = Read-Host "Enter sudo password" -AsSecureString
        }
    }
} else {
    if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
        try {
            $password = Get-Secret -Name "k3s-homelab-sudo" -ErrorAction Stop
            Write-Host "Loaded password from SecretStore vault." -ForegroundColor Green
        } catch {
            $password = Read-Host "Enter sudo password" -AsSecureString
        }
    } else {
        $password = Read-Host "Enter sudo password" -AsSecureString
    }
}
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
$b64Pass = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plainPass))

if (!$Force) {
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

# 3. SHUTDOWN LOOP (per-node resilient: one bad node must not abort the rest)
$failedNodes = @()
$skippedNodes = @()
foreach ($worker in $targets) {
    Write-Host "`n--- Node: $($worker.Name) ---" -ForegroundColor Yellow
    $nodeOk = $true

    try {
        if ($actualMode -eq "DYNAMIC" -and !$SkipDrain) {
            Write-Host "  - Draining (timeout ${DrainTimeoutSeconds}s)..."
            kubectl cordon $worker.Name | Out-Null
            # --disable-eviction: a full power-off is total disruption by definition, so
            # PDBs (e.g. maxUnavailable: 0 singletons, Longhorn instance-managers) cannot
            # be honoured and protect nothing here - they only stall the shutdown until
            # the timeout and force a dirty power-off. Grace periods still apply, and the
            # detach-wait below remains the storage safety gate.
            kubectl drain $worker.Name --ignore-daemonsets --delete-emptydir-data --force --disable-eviction `
                --grace-period=120 --timeout="$($DrainTimeoutSeconds)s"
        }
        elseif ($SkipDrain) {
            Write-Host "  [!] -SkipDrain: pods and volumes are NOT being evacuated first." -ForegroundColor Yellow
        }

        if (!$SkipDrain) {
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

        Write-Host "  - Powering off..."
        $env:SSHPASS = $plainPass
        try {
            Invoke-NodeSsh -IP $worker.IP -RemoteCommand "echo $b64Pass | base64 -d | sudo -S poweroff"
        }
        catch {
            Write-Host "  [!] Poweroff command failed for $($worker.Name): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  [!] Node may already be off; verifying via API..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }

        $down = $false
        for ($i = 0; $i -lt 6; $i++) {
            Start-Sleep -Seconds 10
            try {
                $state = kubectl get node $worker.Name -o json --request-timeout=10s | ConvertFrom-Json
                $ready = @($state.status.conditions | Where-Object { $_.type -eq 'Ready' })
                if ($ready.Count -eq 0 -or $ready[0].status -ne 'True') { $down = $true; break }
            }
            catch { $down = $true; break }
        }
        if ($down) { Write-Host "  [+] $($worker.Name) is down." -ForegroundColor Green }
        else {
            Write-Host "  [!] $($worker.Name) still reports Ready after poweroff." -ForegroundColor Red
            $nodeOk = $false
        }
    }
    catch {
        Write-Host "  [!] Shutdown of $($worker.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
        $nodeOk = $false
    }

    if (!$nodeOk) { $failedNodes += $worker.Name }
}

Write-Host "`n--- Powering off Master (NUC) ---" -ForegroundColor Red
$masterOk = $true
try {
    if (!$SkipDrain) {
        Write-Host "  - Waiting for Longhorn detach on $masterIp (timeout ${DetachTimeoutSeconds}s)..."
        $masterName = $masterFallback.Name
        $clean = Wait-NodeVolumesDetached -NodeName $masterName -TimeoutSeconds $DetachTimeoutSeconds
        if ($clean) { Write-Host "  [+] Storage clean on $masterName." -ForegroundColor Green }
        elseif (!$Force) {
            Write-Host "  [!] Volumes still attached to ${masterName}; skipping master poweroff (re-run with -Force to override)." -ForegroundColor Red
            $skippedNodes += $masterName
            $masterOk = $false
        }
        else { Write-Host "  [!] -Force supplied: powering off master with volumes attached." -ForegroundColor Red }
    }
    if ($masterOk) {
        $env:SSHPASS = $plainPass
        Invoke-NodeSsh -IP $masterIp -RemoteCommand "echo $b64Pass | base64 -d | sudo -S poweroff"
        Write-Host "  [+] Master poweroff command sent." -ForegroundColor Green
    }
}
catch {
    Write-Host "  [!] Master shutdown failed: $($_.Exception.Message)" -ForegroundColor Red
    $failedNodes += $masterFallback.Name
}

Write-Host "`n--- Shutdown Summary ---" -ForegroundColor Cyan
if ($skippedNodes.Count -gt 0) {
    Write-Host "Skipped (storage not clean, no -Force): $($skippedNodes -join ', ')" -ForegroundColor Yellow
}
if ($failedNodes.Count -gt 0) {
    Write-Host "Failed: $($failedNodes -join ', ')" -ForegroundColor Red
}
if ($skippedNodes.Count -eq 0 -and $failedNodes.Count -eq 0) {
    Write-Host "[+] All target nodes processed cleanly." -ForegroundColor Green
}

# Guarded: powering off the machine running this script kills the terminal, kubectl
# access and any chance to observe or recover the cluster mid-test. Opt-in only.
if ($ShutdownLocalMac) {
    Write-Host "`n--- Powering off Local Mac (-ShutdownLocalMac supplied) ---" -ForegroundColor Red
    "test" | sudo -S shutdown -h now
}
else {
    Write-Host "`n--- Local Mac left powered on (use -ShutdownLocalMac to include it) ---" -ForegroundColor Yellow
}

if ($skippedNodes.Count -gt 0 -or $failedNodes.Count -gt 0) { exit 1 }
exit 0

