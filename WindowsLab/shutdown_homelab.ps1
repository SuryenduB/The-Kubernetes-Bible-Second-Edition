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
    [string]$Mode = "Auto"
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

# 3. SHUTDOWN LOOP
foreach ($worker in $targets) {
    Write-Host "`n--- Node: $($worker.Name) ---" -ForegroundColor Yellow

    if ($actualMode -eq "DYNAMIC" -and !$SkipDrain) {
        Write-Host "  - Draining..."
        kubectl cordon $worker.Name | Out-Null
        kubectl drain $worker.Name --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=60s
    }

    Write-Host "  - Powering off..."
    $env:SSHPASS = $plainPass
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        sshpass -e ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$($worker.IP) "echo $b64Pass | base64 -d | sudo -S poweroff"
    } elseif (Test-Path "/usr/local/bin/sshpass") {
        /usr/local/bin/sshpass -e ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$($worker.IP) "echo $b64Pass | base64 -d | sudo -S poweroff"
    } else {
        ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$($worker.IP) "echo $b64Pass | base64 -d | sudo -S poweroff"
    }
}

Write-Host "`n--- Powering off Master (NUC) ---" -ForegroundColor Red
$env:SSHPASS = $plainPass
if (Get-Command sshpass -ErrorAction SilentlyContinue) {
    sshpass -e ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$masterIp "echo $b64Pass | base64 -d | sudo -S poweroff"
} elseif (Test-Path "/usr/local/bin/sshpass") {
    /usr/local/bin/sshpass -e ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$masterIp "echo $b64Pass | base64 -d | sudo -S poweroff"
} else {
    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null suryendub@$masterIp "echo $b64Pass | base64 -d | sudo -S poweroff"
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

