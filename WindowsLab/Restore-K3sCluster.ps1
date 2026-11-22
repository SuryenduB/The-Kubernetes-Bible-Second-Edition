<#
.SYNOPSIS
    Orchestrates K3s control-plane restoration from the current etcd-snapshot backups on NAS.

.DESCRIPTION
    The nightly state.db backup was retired (APP-01, 2026-10-17). The live job
    k3s-etcd-safe-backup.sh publishes, every 6 hours, one directory containing:

      etcd-snapshot-online-<timestamp>-nuc-<epoch>   online embedded-etcd snapshot
      k3s-config.tar.gz                              /etc/rancher/k3s/
      k3s-identity.tar.gz                            token, node-token, tls/, cred/

    This script discovers only those valid directories (legacy dirs holding a
    0-byte k3s-state.db are ignored), restores config + identity, places the
    snapshot on nuc, then performs the documented embedded-etcd cluster reset.
    Because the cluster has three etcd members, all are stopped first and the
    two non-restoring servers have their db directories archived before they
    rejoin - otherwise the lineage forks and a member stays NotReady forever.

.PARAMETER BackupTimestamp
    Optional timestamp folder on the NAS (e.g., '20261121-180001'). Defaults to
    the newest VALID backup.

.PARAMETER ListOnly
    List valid backups (and flag legacy/invalid ones) without changing anything.

.PARAMETER Force
    Skip the interactive confirmation prompt.

.PARAMETER DryRun
    Discover and validate the backup, then print the planned actions without
    changing the cluster. No credentials are requested.

.PARAMETER NasPassword
    QNAP admin SSH password. Defaults to the documented homelab value.

.EXAMPLE
    PS> .\Restore-K3sCluster.ps1
    (discovers and uses the newest valid etcd-snapshot backup)

.EXAMPLE
    PS> .\Restore-K3sCluster.ps1 -BackupTimestamp "20261121-180001" -ListOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specific timestamp folder name on the NAS")]
    [string]$BackupTimestamp,

    [Parameter()]
    [switch]$ListOnly,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [string]$NasPassword = "558068"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Registry = Join-Path $PSScriptRoot 'homelab-nodes.json'
$NodeRegistry = Get-Content -Path $Registry -Raw | ConvertFrom-Json
$Nuc = $NodeRegistry.nodes | Where-Object { $_.name -eq 'nuc' } | Select-Object -First 1
$ControlPlanes = @($NodeRegistry.nodes | Where-Object { $_.role -eq 'control-plane' })
if (-not $Nuc -or $ControlPlanes.Count -lt 1) {
    throw "Control-plane nodes missing from $Registry"
}

$NasIP = ($NodeRegistry.external | Where-Object { $_.name -eq 'nas' } | Select-Object -First 1).ip
$NasUser = 'admin'
$NasRootPath = '/share/CACHEDEV1_DATA/Public/backups/k3s'
$LocalTmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "k3s-restore-$(Get-Random)"
$script:NodePassword = $null

function Invoke-Remote {
    param(
        [Parameter(Mandatory)] [string]$Target,
        [Parameter(Mandatory)] [string]$Command
    )
    $env:SSHPASS = $script:NodePassword
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        $output = & sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 $Target $Command 2>&1
    }
    else {
        $output = & ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=12 $Target $Command 2>&1
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Remote command failed on ${Target} (exit ${exitCode}): $output"
    }
    return ($output | Out-String).Trim()
}

function Invoke-Nas {
    param([Parameter(Mandatory)] [string]$Command)
    $env:SSHPASS = $NasPassword
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        $output = & sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 "${NasUser}@${NasIP}" $Command 2>&1
    }
    else {
        $output = & ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=12 "${NasUser}@${NasIP}" $Command 2>&1
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "NAS command failed (exit ${exitCode}): $output"
    }
    return ($output | Out-String).Trim()
}

function Copy-ToNasFile {
    param(
        [Parameter(Mandatory)] [string]$NasFile,
        [Parameter(Mandatory)] [string]$LocalFile
    )
    $env:SSHPASS = $NasPassword
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        & sshpass -e scp -o StrictHostKeyChecking=no "${NasUser}@${NasIP}:${NasFile}" $LocalFile 2>&1 | Out-Null
    }
    else {
        & scp -o BatchMode=yes -o StrictHostKeyChecking=no "${NasUser}@${NasIP}:${NasFile}" $LocalFile 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "Failed to download ${NasFile} from NAS." }
}

function Copy-ToNodeFile {
    param(
        [Parameter(Mandatory)] [string]$LocalFile,
        [Parameter(Mandatory)] [string]$Target,
        [Parameter(Mandatory)] [string]$RemoteFile
    )
    $env:SSHPASS = $script:NodePassword
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        & sshpass -e scp -o StrictHostKeyChecking=no $LocalFile "${Target}:${RemoteFile}" 2>&1 | Out-Null
    }
    else {
        & scp -o BatchMode=yes -o StrictHostKeyChecking=no $LocalFile "${Target}:${RemoteFile}" 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload ${RemoteFile} to ${Target}." }
}

Write-Host "--- K3s Cluster Restoration (etcd snapshot / APP-01 design) ---" -ForegroundColor Cyan

try {
    # 0. Discovery - only directories with a real etcd snapshot are valid.
    Write-Host "`n[0/6] Discovering valid backups on NAS..." -ForegroundColor Yellow
    $remoteCmd = 'for d in ' + $NasRootPath + '/20*; do [ -d "$d" ] || continue; s=$(ls -1 "$d" 2>/dev/null | grep "^etcd-snapshot-"); if [ -n "$s" ]; then echo "$(basename "$d")|$s"; fi; done | sort'
    $listing = Invoke-Nas -Command $remoteCmd
    $validBackups = @()
    foreach ($line in ($listing -split "`n")) {
        if ($line -match '^(\d{8}-\d{6})\|(etcd-snapshot-\S+)$') {
            $validBackups += [pscustomobject]@{ Timestamp = $Matches[1]; Snapshot = $Matches[2] }
        }
    }
    if ($validBackups.Count -eq 0) { throw "No valid etcd-snapshot backups found in $NasRootPath" }

    $allDirs = @((Invoke-Nas -Command "ls -1 $NasRootPath | grep -E '^[0-9]{8}-[0-9]{6}$'") -split "`n" |
        Where-Object { $_ -match '^\d{8}-\d{6}$' })
    $legacyDirs = @($allDirs | Where-Object {
        $name = $_
        -not ($validBackups | Where-Object { $_.Timestamp -eq $name })
    })

    if ($ListOnly) {
        Write-Host "`nValid etcd-snapshot backups on NAS:" -ForegroundColor Green
        $validBackups | ForEach-Object { Write-Host "  - $($_.Timestamp)  $($_.Snapshot)" }
        if ($legacyDirs.Count -gt 0) {
            Write-Host "`nLegacy/invalid dirs (ignored - 0-byte state.db, no snapshot):" -ForegroundColor DarkYellow
            $legacyDirs | ForEach-Object { Write-Host "  - $_" }
        }
        return
    }

    $selected = $validBackups | Select-Object -Last 1
    if (-not [string]::IsNullOrWhiteSpace($BackupTimestamp)) {
        $selected = $validBackups | Where-Object { $_.Timestamp -eq $BackupTimestamp } | Select-Object -First 1
        if (-not $selected) {
            Write-Host "Available valid backups:" -ForegroundColor Yellow
            $validBackups | ForEach-Object { Write-Host "  - $($_.Timestamp)" }
            throw "Invalid backup timestamp: $BackupTimestamp"
        }
    }
    else {
        Write-Host "  [!] No timestamp given. Defaulting to newest VALID backup: $($selected.Timestamp)" -ForegroundColor Cyan
    }

    $NasPath = "$NasRootPath/$($selected.Timestamp)"
    Write-Host "Target host : $($Nuc.name) ($($Nuc.ip))"
    Write-Host "Source NAS  : ${NasUser}@${NasIP} [$($selected.Timestamp)]" -ForegroundColor Gray
    Write-Host "Snapshot    : $($selected.Snapshot)" -ForegroundColor Gray

    # 1. Validate artifacts before touching the cluster.
    Write-Host "`n[1/6] Validating backup artifacts..." -ForegroundColor Yellow
    $contents = (Invoke-Nas -Command "ls -1 $NasPath") -split "`n"
    foreach ($required in @($selected.Snapshot, 'k3s-config.tar.gz', 'k3s-identity.tar.gz')) {
        if ($contents -notcontains $required) { throw "Missing required artifact: $required" }
    }
    $snapshotSizeKb = [int](Invoke-Nas -Command "du -k $NasPath/$($selected.Snapshot) | cut -f1")
    if ($snapshotSizeKb -lt 10240) { throw "Snapshot is suspiciously small ($snapshotSizeKb KB)." }
    Write-Host "  [+] Snapshot ${snapshotSizeKb} KB, config and identity present." -ForegroundColor Green

    if ($DryRun) {
        Write-Host "`nDRY RUN - backup validated, no cluster changes made." -ForegroundColor Cyan
        Write-Host "Would stop k3s on: $(($ControlPlanes | ForEach-Object { $_.name }) -join ', ')"
        Write-Host "Would restore config + identity and cluster-reset $($Nuc.name) from $($selected.Snapshot)"
        Write-Host "Would archive the db directory on: $((($ControlPlanes | Where-Object { $_.name -ne $Nuc.name }) | ForEach-Object { $_.name }) -join ', ')"
        return
    }

    $script:NodePassword = Read-Host "Enter sudo password for control-plane nodes" -AsSecureString
    $script:NodePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:NodePassword))

    if (-not $Force) {
        Write-Host "`nWARNING: this REWINDS the cluster to $($selected.Timestamp)." -ForegroundColor Magenta
        Write-Host "All three etcd members will be stopped; the two non-restoring members' databases will be archived and reset." -ForegroundColor Magenta
        $confirm = Read-Host "Proceed? (yes/no)"
        if ($confirm -ne 'yes') { Write-Host "Aborted by user." -ForegroundColor Yellow; return }
    }

    # 2. Preflight - every etcd member must be reachable before any change.
    Write-Host "`n[2/6] Preflight: control-plane reachability..." -ForegroundColor Yellow
    foreach ($node in $ControlPlanes) {
        $reachable = Invoke-Remote -Target "$($node.sshUser)@$($node.ip)" -Command 'echo REACHABLE'
        if ($reachable -notmatch 'REACHABLE') { throw "Unexpected preflight output from $($node.name)" }
        Write-Host "  [+] $($node.name) reachable" -ForegroundColor Green
    }

    # 3. Stop every etcd member (a single running member forks the lineage).
    Write-Host "`n[3/6] Stopping k3s on all etcd members..." -ForegroundColor Yellow
    foreach ($node in $ControlPlanes) {
        Invoke-Remote -Target "$($node.sshUser)@$($node.ip)" -Command "echo $script:NodePassword | sudo -S -p '' systemctl stop k3s" | Out-Null
        Write-Host "  [+] stopped $($node.name)" -ForegroundColor Green
    }

    # 4. Download artifacts and restore identity + config on nuc.
    Write-Host "`n[4/6] Restoring config, identity and snapshot on nuc..." -ForegroundColor Yellow
    if (-not (Test-Path $LocalTmpDir)) { New-Item -ItemType Directory -Path $LocalTmpDir | Out-Null }
    $localSnapshot = Join-Path $LocalTmpDir $selected.Snapshot
    $localConfig = Join-Path $LocalTmpDir 'k3s-config.tar.gz'
    $localIdentity = Join-Path $LocalTmpDir 'k3s-identity.tar.gz'

    Copy-ToNasFile -NasFile "$NasPath/$($selected.Snapshot)" -LocalFile $localSnapshot
    Copy-ToNasFile -NasFile "$NasPath/k3s-config.tar.gz" -LocalFile $localConfig
    Copy-ToNasFile -NasFile "$NasPath/k3s-identity.tar.gz" -LocalFile $localIdentity

    $nucTarget = "$($Nuc.sshUser)@$($Nuc.ip)"
    Copy-ToNodeFile -LocalFile $localConfig -Target $nucTarget -RemoteFile /tmp/k3s-config.tar.gz
    Copy-ToNodeFile -LocalFile $localIdentity -Target $nucTarget -RemoteFile /tmp/k3s-identity.tar.gz
    Copy-ToNodeFile -LocalFile $localSnapshot -Target $nucTarget -RemoteFile "/tmp/$($selected.Snapshot)"

    Invoke-Remote -Target $nucTarget -Command "echo $script:NodePassword | sudo -S -p '' tar -xzf /tmp/k3s-config.tar.gz -C /" | Out-Null
    Invoke-Remote -Target $nucTarget -Command "echo $script:NodePassword | sudo -S -p '' tar -xzf /tmp/k3s-identity.tar.gz -C /" | Out-Null
    Write-Host "  [+] config and identity restored (workers will rejoin with the same CA/token)." -ForegroundColor Green

    $snapshotDir = '/var/lib/rancher/k3s/server/db/snapshots'
    Invoke-Remote -Target $nucTarget -Command "echo $script:NodePassword | sudo -S -p '' mkdir -p $snapshotDir && echo $script:NodePassword | sudo -S -p '' cp /tmp/$($selected.Snapshot) $snapshotDir/$($selected.Snapshot) && echo $script:NodePassword | sudo -S -p '' chmod 600 $snapshotDir/$($selected.Snapshot)" | Out-Null
    Write-Host "  [+] snapshot staged at $snapshotDir/$($selected.Snapshot)" -ForegroundColor Green

    # 5. Cluster reset on nuc.
    Write-Host "`n[5/6] Resetting embedded etcd from snapshot on nuc..." -ForegroundColor Yellow
    $resetOutput = Invoke-Remote -Target $nucTarget -Command "echo $script:NodePassword | sudo -S -p '' timeout 300 k3s server --cluster-reset --cluster-reset-restore-path=$snapshotDir/$($selected.Snapshot) 2>&1"
    Write-Host ($resetOutput | Out-String).Trim() -ForegroundColor Gray
    if ($resetOutput -notmatch 'cluster has been reset|cluster-reset') {
        throw "Cluster reset did not report success. Inspect output before proceeding."
    }

    # Other members must not keep the old etcd data directory after a reset.
    foreach ($node in ($ControlPlanes | Where-Object { $_.name -ne $Nuc.name })) {
        $target = "$($node.sshUser)@$($node.ip)"
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $archive = "/var/lib/rancher/k3s/server/db-backup-$stamp"
        Invoke-Remote -Target $target -Command "echo $script:NodePassword | sudo -S -p '' sh -c 'if [ -d /var/lib/rancher/k3s/server/db ]; then mv /var/lib/rancher/k3s/server/db $archive; fi'" | Out-Null
        Write-Host "  [+] $($node.name) old db archived to $archive" -ForegroundColor Green
    }

    # 6. Start nuc, then the other members, and verify.
    Write-Host "`n[6/6] Restarting control plane and verifying..." -ForegroundColor Yellow
    Invoke-Remote -Target $nucTarget -Command "echo $script:NodePassword | sudo -S -p '' systemctl start k3s" | Out-Null
    Start-Sleep -Seconds 30
    $nodes = Invoke-Remote -Target $nucTarget -Command 'kubectl get nodes'
    Write-Host $nodes -ForegroundColor Gray
    foreach ($node in ($ControlPlanes | Where-Object { $_.name -ne $Nuc.name })) {
        $target = "$($node.sshUser)@$($node.ip)"
        Invoke-Remote -Target $target -Command "echo $script:NodePassword | sudo -S -p '' systemctl start k3s" | Out-Null
        Write-Host "  [+] started $($node.name)" -ForegroundColor Green
    }
    Start-Sleep -Seconds 30
    Write-Host "`nFinal node state:" -ForegroundColor Gray
    Write-Host (Invoke-Remote -Target $nucTarget -Command 'kubectl get nodes') -ForegroundColor Gray
    Write-Host "`nRestoration complete using backup: $($selected.Timestamp)" -ForegroundColor Green
}
catch {
    Write-Error "CRITICAL: Restoration failed! Error: $($_.Exception.Message)"
}
finally {
    if (Test-Path $LocalTmpDir) { Remove-Item -Path $LocalTmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($node in $ControlPlanes) {
        $target = "$($node.sshUser)@$($node.ip)"
        $env:SSHPASS = $script:NodePassword
        if ($script:NodePassword -and (Get-Command sshpass -ErrorAction SilentlyContinue)) {
            & sshpass -e ssh -o StrictHostKeyChecking=no $target "rm -f /tmp/k3s-config.tar.gz /tmp/k3s-identity.tar.gz /tmp/etcd-snapshot-*" 2>&1 | Out-Null
        }
    }
    $script:NodePassword = $null
    $env:SSHPASS = ''
}
