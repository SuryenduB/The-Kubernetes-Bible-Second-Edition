<#
.SYNOPSIS
    Uninstalls the Beszel agent and removes the Windows Service.

.DESCRIPTION
    Stops and removes the 'beszel-agent' Windows service using NSSM,
    deletes the firewall rule, and cleans up log files.
    Optionally uninstalls the binary via Scoop or WinGet.

.EXAMPLE
    PS> .\uninstall-beszel.ps1
#>
[CmdletBinding()]
param(
    [switch]$UninstallBinary
)

# region Utility Functions
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    param ([string]$Command)
    return (Get-Command $Command -ErrorAction SilentlyContinue)
}
# endregion

if (-not (Test-Admin)) {
    Write-Host "Elevating for uninstallation..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    exit
}

Write-Host "--- Beszel Agent Uninstallation ---" -ForegroundColor Cyan

# 1. Stop and remove the Windows Service
if (Get-Service "beszel-agent" -ErrorAction SilentlyContinue) {
    Write-Host "[1/4] Stopping and removing beszel-agent service..."
    if (Test-CommandExists "nssm") {
        & nssm stop beszel-agent
        & nssm remove beszel-agent confirm
        Write-Host "  [+] Service removed." -ForegroundColor Green
    } else {
        Write-Error "NSSM not found. Service removal failed. Please remove manually."
    }
} else {
    Write-Host "[1/4] Service 'beszel-agent' not found." -ForegroundColor Gray
}

# 2. Remove the Firewall Rule
Write-Host "[2/4] Removing firewall rule..."
if (Get-NetFirewallRule -DisplayName "Allow beszel-agent" -ErrorAction SilentlyContinue) {
    Remove-NetFirewallRule -DisplayName "Allow beszel-agent"
    Write-Host "  [+] Firewall rule removed." -ForegroundColor Green
} else {
    Write-Host "  [+] No firewall rule found." -ForegroundColor Gray
}

# 3. Cleanup Log Files
$logDir = "$env:ProgramData\beszel-agent"
Write-Host "[3/4] Cleaning up data and logs in $logDir..."
if (Test-Path $logDir) {
    Remove-Item -Path $logDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [+] Logs deleted." -ForegroundColor Green
}

# 4. Optional: Uninstall the Binary
if ($UninstallBinary) {
    Write-Host "[4/4] Uninstalling binary..."
    if (Test-CommandExists "scoop") {
        Write-Host "  - Attempting Scoop uninstall..."
        scoop uninstall beszel-agent 2>$null
    }
    if (Test-CommandExists "winget") {
        Write-Host "  - Attempting WinGet uninstall..."
        winget uninstall henrygd.beszel-agent 2>$null
    }
    Write-Host "  [+] Binary uninstallation attempt complete." -ForegroundColor Green
} else {
    Write-Host "[4/4] Skipping binary uninstallation. Binary remains on system." -ForegroundColor Gray
}

Write-Host "`n✅ Beszel Agent has been uninstalled successfully!" -ForegroundColor Green
