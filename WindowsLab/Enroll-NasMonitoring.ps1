<#
.SYNOPSIS
    Enrolls the QNAP NAS (ARMv7) into Beszel monitoring.
    Uses a robust one-liner to bypass Windows/Linux line-ending issues.

.DESCRIPTION
    Automates the deployment and registration of the Beszel agent on QNAP NAS.
    Persistent storage is maintained in the 'Public' share.

.PARAMETER NasIp
    The IP address of the NAS. Default: 192.168.0.128

.PARAMETER HubUrl
    The Hub URL via NodePort. Default: http://192.168.0.24:30090
#>
[CmdletBinding()]
param(
    [string]$NasIp = "192.168.0.128",
    [string]$NasUser = "admin",
    [string]$HubUrl = "http://192.168.0.24:30090",
    [string]$Key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBHMi993ZMbRWvyg7h38/7HRWl6AfOK8jLXidLhBBX+p",
    [string]$Token = "f8c02034-9f5c-42b1-82ad-d5b80dbd5293"
)

$ErrorActionPreference = 'Stop'
$AgentDir = "/share/CACHEDEV1_DATA/Public/beszel-agent"

Write-Host "--- Beszel NAS Enrollment (Fixed) ---" -ForegroundColor Cyan
Write-Host "Target: $NasUser@$NasIp" -ForegroundColor Gray

# Robust remote command string - single line to avoid any CRLF/formatting issues
$RemoteCmd = "export KEY='$Key' ; export TOKEN='$Token' ; export HUB_URL='$HubUrl' ; " +
             "mkdir -p $AgentDir && cd $AgentDir && " +
             "if [ ! -f 'beszel-agent' ]; then curl -L https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_arm.tar.gz -o b.tar.gz && tar -xzf b.tar.gz && chmod +x beszel-agent && rm b.tar.gz ; fi ; " +
             "killall beszel-agent 2>/dev/null || true ; " +
             "./beszel-agent > agent.log 2>&1 & " +
             "sleep 2 && grep 'WebSocket connected' agent.log"

try {
    ssh -o StrictHostKeyChecking=no "$NasUser@$NasIp" $RemoteCmd
    Write-Host "`n✅ NAS successfully connected to Beszel Hub!" -ForegroundColor Green
    Write-Host "View metrics at: http://beszel" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to enroll NAS. Error: $($_.Exception.Message)"
}
