<#
.SYNOPSIS
    Orchestrates K3s control-plane restoration from NAS backups with dynamic discovery.

.DESCRIPTION
    This script automates the recovery of a K3s cluster. It dynamically fetches
    available backups from the NAS, defaults to the latest, and restores the
    configuration and SQLite database to the NUC master node.

.PARAMETER BackupTimestamp
    Optional. The timestamp folder name on the NAS (e.g., '20260425-215914').
    If omitted, the script lists available backups and defaults to the latest.

.PARAMETER ListOnly
    Switch to only list available backups on the NAS and exit.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    PS> .\Restore-K3sCluster.ps1
    (Automatically finds and uses the latest backup)

.EXAMPLE
    PS> .\Restore-K3sCluster.ps1 -BackupTimestamp "20260420-222846"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specific timestamp folder name on the NAS")]
    [string]$BackupTimestamp,

    [Parameter()]
    [switch]$ListOnly,

    [Parameter()]
    [switch]$Force
)

# --- Configuration ---
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NucIP = "192.168.0.21"
$NasIP = "192.168.0.128"
$NucUser = "suryendub"
$NasUser = "admin"
$NasRootPath = "/share/CACHEDEV1_DATA/Public/backups/k3s"
$LocalTmpDir = Join-Path -Path $env:TEMP -ChildPath "k3s-restore-$(Get-Random)"

Write-Host "--- K3s Cluster Restoration Orchestrator ---" -ForegroundColor Cyan

try {
    # 0. Backup Discovery
    Write-Host "`n[0/5] Discovering available backups on NAS..." -ForegroundColor Yellow
    # Get sorted list of directories that match the timestamp pattern
    $remoteCmd = "ls -1 $NasRootPath | grep -E '^[0-9]{8}-[0-9]{6}$' | sort"
    $availableBackups = ssh -o StrictHostKeyChecking=no "${NasUser}@${NasIP}" $remoteCmd | Where-Object { $_ -match '^\d{8}-\d{6}$' }

    if (-not $availableBackups) {
        throw "No valid backups found in $NasRootPath"
    }

    if ($ListOnly) {
        Write-Host "`nAvailable Backups on NAS:" -ForegroundColor Green
        $availableBackups | ForEach-Object { Write-Host "  - $_" }
        return
    }

    $selectedBackup = $BackupTimestamp
    if ([string]::IsNullOrWhiteSpace($selectedBackup)) {
        # Pick the latest (last in the sorted list)
        $selectedBackup = $availableBackups | Select-Object -Last 1
        Write-Host "  [!] No timestamp provided. Defaulting to LATEST: $selectedBackup" -ForegroundColor Cyan
    }
    else {
        if ($availableBackups -notcontains $selectedBackup) {
            Write-Warning "Provided timestamp '$selectedBackup' not found on NAS."
            Write-Host "Available options:"
            $availableBackups | ForEach-Object { Write-Host "  - $_" }
            throw "Invalid backup timestamp."
        }
    }

    $NasPath = "$NasRootPath/$selectedBackup"
    Write-Host "Target Host : $NucUser@$NucIP"
    Write-Host "Source NAS  : $NasUser@$NasIP [$selectedBackup]" -ForegroundColor Gray

    # --- Credentials ---
    $password = Read-Host "Enter sudo/system password" -AsSecureString
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

    if (-not $Force) {
        Write-Host "`nReady to restore from $selectedBackup" -ForegroundColor Magenta
        $confirm = Read-Host "!!! WARNING: This will OVERWRITE the current cluster state. Proceed? (yes/no)"
        if ($confirm -ne 'yes') { 
            Write-Host "Aborted by user." -ForegroundColor Yellow
            return 
        }
    }

    # 1. Validation of internal files
    Write-Host "`n[1/5] Validating internal backup files..." -ForegroundColor Yellow
    $files = ssh -o StrictHostKeyChecking=no "${NasUser}@${NasIP}" "ls $NasPath"
    if ($files -notmatch "k3s-state.db" -or $files -notmatch "k3s-config.tar.gz") {
        throw "Required backup files (db or config) missing in $NasPath"
    }
    Write-Host "  [+] Backup files verified." -ForegroundColor Green

    # 2. Stop K3s Service
    Write-Host "`n[2/5] Stopping K3s service on NUC..." -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no "${NucUser}@${NucIP}" "echo $plainPass | sudo -S systemctl stop k3s"
    Write-Host "  [+] K3s service stopped." -ForegroundColor Green

    # 3. Restore Configuration
    Write-Host "`n[3/5] Restoring cluster configuration..." -ForegroundColor Yellow
    if (-not (Test-Path $LocalTmpDir)) { New-Item -ItemType Directory -Path $LocalTmpDir | Out-Null }

    Write-Host "  - Downloading from NAS..." -ForegroundColor Gray
    scp -o StrictHostKeyChecking=no "${NasUser}@${NasIP}:${NasPath}/k3s-config.tar.gz" (Join-Path $LocalTmpDir "k3s-config.tar.gz")
    scp -o StrictHostKeyChecking=no "${NasUser}@${NasIP}:${NasPath}/k3s-state.db" (Join-Path $LocalTmpDir "k3s-state.db")

    Write-Host "  - Uploading to NUC..." -ForegroundColor Gray
    scp -o StrictHostKeyChecking=no (Join-Path $LocalTmpDir "k3s-config.tar.gz") "${NucUser}@${NucIP}:/tmp/k3s-config.tar.gz"
    scp -o StrictHostKeyChecking=no (Join-Path $LocalTmpDir "k3s-state.db") "${NucUser}@${NucIP}:/tmp/k3s-state.db"

    # Apply config
    ssh -o StrictHostKeyChecking=no "${NucUser}@${NucIP}" "echo $plainPass | sudo -S tar -xzf /tmp/k3s-config.tar.gz -C /"
    Write-Host "  [+] Configuration restored to /etc/rancher/k3s/." -ForegroundColor Green

    # 4. Restore Database State
    Write-Host "`n[4/5] Restoring SQLite database state..." -ForegroundColor Yellow
    $dbPath = "/var/lib/rancher/k3s/server/db"
    ssh -o StrictHostKeyChecking=no "${NucUser}@${NucIP}" "echo $plainPass | sudo -S mkdir -p $dbPath ; echo $plainPass | sudo -S cp /tmp/k3s-state.db $dbPath/state.db ; echo $plainPass | sudo -S chown root:root $dbPath/state.db"
    Write-Host "  [+] Database restored to $dbPath/state.db." -ForegroundColor Green

    # 5. Start K3s Service
    Write-Host "`n[5/5] Restarting K3s service..." -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no "${NucUser}@${NucIP}" "echo $plainPass | sudo -S systemctl start k3s"

    Write-Host "`nVerifying cluster health..." -ForegroundColor Gray
    Start-Sleep -Seconds 15
    ssh -o StrictHostKeyChecking=no "${NucUser}@${NucIP}" "kubectl get nodes"

    Write-Host "`n✅ Restoration Complete using backup: $selectedBackup" -ForegroundColor Green
}
catch {
    Write-Error "CRITICAL: Restoration failed! Error: $($_.Exception.Message)"
}
finally {
    # Cleanup
    if (Test-Path $LocalTmpDir) {
        Remove-Item -Path $LocalTmpDir -Recurse -Force | Out-Null
    }
    ssh -o StrictHostKeyChecking=no "${NucUser}@${NucIP}" "rm -f /tmp/k3s-config.tar.gz /tmp/k3s-state.db" 2>$null
    $plainPass = $null
}

Write-Host "`n⚠️  NOTE: If the Master node was fully re-imaged, you MUST also manually restore /var/lib/rancher/k3s/server/tls from your NAS or a separate backup." -ForegroundColor Yellow
