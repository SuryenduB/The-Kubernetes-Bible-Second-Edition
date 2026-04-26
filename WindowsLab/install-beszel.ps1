<#
.SYNOPSIS
    Installs and configures the Beszel agent as a Windows Service.

.DESCRIPTION
    Uses Scoop or WinGet to install the beszel-agent binary and NSSM
    to configure it as a background service with the provided credentials.

.PARAMETER Key
    Mandatory. The SSH Public Key from the Beszel Hub.

.PARAMETER Token
    The Universal Token for automated registration.

.PARAMETER Url
    The URL of the Beszel Hub (e.g., http://192.168.0.24:30090).

.PARAMETER ConfigureFirewall
    Switch to automatically create an inbound firewall rule for port 45876.
#>
param (
    [switch]$Elevated,
    [Parameter(Mandatory=$true)]
    [string]$Key,
    [string]$Token = "",
    [string]$Url = "",
    [int]$Port = 45876,
    [string]$AgentPath = "",
    [string]$NSSMPath = "",
    [switch]$ConfigureFirewall,
    [ValidateSet("Auto", "Scoop", "WinGet")]
    [string]$InstallMethod = "Auto"
)

# Check if required parameters are provided
if ([string]::IsNullOrWhiteSpace($Key)) {
    Write-Host "ERROR: SSH Key is required." -ForegroundColor Red
    Write-Host "Usage: .\install-beszel.ps1 -Key 'your-ssh-key-here' [-Token 'your-token-here'] [-Url 'your-hub-url-here'] [-Port port-number] [-InstallMethod Auto|Scoop|WinGet] [-ConfigureFirewall]" -ForegroundColor Yellow
    exit 1
}

# Stop on first error
$ErrorActionPreference = "Stop"

#region Utility Functions

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    param ([string]$Command)
    return (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Find-BeszelAgent {
    $agentCmd = Get-Command "beszel-agent" -ErrorAction SilentlyContinue
    if ($agentCmd) { return $agentCmd.Source }
    
    $commonPaths = @(
        "$env:USERPROFILE\scoop\apps\beszel-agent\current\beszel-agent.exe",
        "$env:ProgramData\scoop\apps\beszel-agent\current\beszel-agent.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\henrygd.beszel-agent*\beszel-agent.exe",
        "$env:ProgramFiles\WinGet\Packages\henrygd.beszel-agent*\beszel-agent.exe",
        "${env:ProgramFiles(x86)}\WinGet\Packages\henrygd.beszel-agent*\beszel-agent.exe"
    )
    foreach ($path in $commonPaths) {
        if ($path.Contains("*")) {
            $foundPaths = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            if ($foundPaths) { return $foundPaths[0].FullName }
        } else {
            if (Test-Path $path) { return $path }
        }
    }
    return $null
}

function Find-NSSM {
    $nssmCmd = Get-Command "nssm" -ErrorAction SilentlyContinue
    if ($nssmCmd) { return $nssmCmd.Source }
    
    $commonPaths = @(
        "$env:USERPROFILE\scoop\apps\nssm\current\nssm.exe",
        "$env:ProgramData\scoop\apps\nssm\current\nssm.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

#endregion

#region Installation Logic

function Install-Scoop {
    if (Test-Admin) { throw "Scoop must be installed as a regular user." }
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}

function Install-NSSM {
    param ([string]$Method = "Scoop")
    if (Test-CommandExists "nssm") { return }
    if ($Method -eq "Scoop") { scoop install nssm }
    elseif ($Method -eq "WinGet") { winget install -e --id NSSM.NSSM --accept-source-agreements --accept-package-agreements }
}

function Install-BeszelWithScoop {
    scoop bucket add beszel https://github.com/henrygd/beszel-scoops 2>$null
    scoop install beszel-agent
    return (Join-Path $(scoop prefix beszel-agent) "beszel-agent.exe")
}

function Install-BeszelWithWinGet {
    winget install --exact --id henrygd.beszel-agent --accept-source-agreements --accept-package-agreements
    return (Get-Command beszel-agent).Source
}

#endregion

#region Service Logic

function Install-NSSMService {
    param ($AgentPath, $Key, $Token, $HubUrl, $Port, $NSSMPath)
    
    $nssm = if ($NSSMPath) { $NSSMPath } else { "nssm" }
    
    if (Get-Service "beszel-agent" -ErrorAction SilentlyContinue) {
        & $nssm stop beszel-agent
        & $nssm remove beszel-agent confirm
    }
    
    & $nssm install beszel-agent $AgentPath
    & $nssm set beszel-agent AppEnvironmentExtra "+KEY=$Key" "+TOKEN=$Token" "+HUB_URL=$HubUrl" "+PORT=$Port"
    
    $logDir = "$env:ProgramData\beszel-agent\logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    & $nssm set beszel-agent AppStdout "$logDir\beszel-agent.log"
    & $nssm set beszel-agent AppStderr "$logDir\beszel-agent.log"
}

#endregion

# --- Main ---
$isAdmin = Test-Admin

if (!$AgentPath) {
    if ($InstallMethod -eq "WinGet" -or (!$isAdmin -and (Test-CommandExists "winget"))) {
        $AgentPath = Install-BeszelWithWinGet
    } else {
        if (!(Test-CommandExists "scoop")) { Install-Scoop }
        $AgentPath = Install-BeszelWithScoop
    }
}

if (!$isAdmin -and !$Elevated) {
    Write-Host "Elevating for service installation..." -ForegroundColor Yellow
    $args = @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Elevated", "-Key", "`"$Key`"", "-Token", "`"$Token`"", "-Url", "`"$Url`"", "-Port", $Port, "-AgentPath", "`"$AgentPath`"")
    if ($ConfigureFirewall) { $args += "-ConfigureFirewall" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    exit
}

if ($isAdmin -or $Elevated) {
    Install-NSSM
    Install-NSSMService -AgentPath $AgentPath -Key $Key -Token $Token -HubUrl $Url -Port $Port
    if ($ConfigureFirewall) {
        Remove-NetFirewallRule -DisplayName "Allow beszel-agent" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "Allow beszel-agent" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port
    }
    nssm start beszel-agent
    Write-Host "✅ Beszel Agent installed and started as a Windows Service." -ForegroundColor Green
}
