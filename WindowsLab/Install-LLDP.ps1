# Install-LLDP.ps1 - Orchestrator for LLDP deployment
$Nodes = @(
    @{ Name = "kubernetes1";  IP = "192.168.0.19" },
    @{ Name = "kubernetes2";  IP = "192.168.0.20" },
    @{ Name = "NUC";         IP = "192.168.0.21" },
    @{ Name = "kubernetes3";  IP = "192.168.0.22" },
    @{ Name = "kubernetes4";  IP = "192.168.0.23" },
    @{ Name = "kubernetes5";  IP = "192.168.0.24" },
    @{ Name = "kubernetes6";  IP = "192.168.0.25" },
    @{ Name = "kubernetes7";  IP = "192.168.0.26" },
    @{ Name = "kubernetes8-debian"; IP = "192.168.0.27" }
)

# Load sudo password from encrypted credential file
$credPath = Join-Path (Split-Path $PSScriptRoot -Parent) "cred.xml"
if (-not (Test-Path $credPath)) {
    $credPath = Join-Path $PSScriptRoot "cred.xml"
}

if (Test-Path $credPath) {
    Write-Host "Attempting to read password from credential file..." -ForegroundColor Cyan
    try {
        $securePassword = Import-Clixml -Path $credPath
    } catch {
        if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
            try {
                $securePassword = Get-Secret -Name "k3s-homelab-sudo" -ErrorAction Stop
                Write-Host "Loaded password from SecretStore vault." -ForegroundColor Green
            } catch {
                $securePassword = Read-Host "Enter sudo password" -AsSecureString
            }
        } else {
            $securePassword = Read-Host "Enter sudo password" -AsSecureString
        }
    }
} else {
    if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
        try {
            $securePassword = Get-Secret -Name "k3s-homelab-sudo" -ErrorAction Stop
            Write-Host "Loaded password from SecretStore vault." -ForegroundColor Green
        } catch {
            $securePassword = Read-Host "Enter sudo password" -AsSecureString
        }
    } else {
        $securePassword = Read-Host "Enter sudo password" -AsSecureString
    }
}
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

Write-Host "--- K3s Cluster LLDP Deployment ---" -ForegroundColor Cyan
Write-Host "This script will enable your switch to identify nodes by name." -ForegroundColor Gray

# Define the installation logic
$installCmd = "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y lldpd && systemctl enable lldpd && systemctl start lldpd"

foreach ($Node in $Nodes) {
    $n = $Node.Name
    $i = $Node.IP
    Write-Host "`n>>> Processing ${n} (${i})..." -ForegroundColor Yellow
    
    # Execute installation via SSH with sudo
    Write-Host "  - Installing lldpd..." -ForegroundColor Gray
    # Using the sudo password pattern from your audit script
    $env:SSHPASS = $plainPass
    if (Get-Command sshpass -ErrorAction SilentlyContinue) {
        sshpass -e ssh -n -o StrictHostKeyChecking=no suryendub@$i "echo $plainPass | sudo -S -p '' bash -c '$installCmd'"
    } elseif (Test-Path "/usr/local/bin/sshpass") {
        /usr/local/bin/sshpass -e ssh -n -o StrictHostKeyChecking=no suryendub@$i "echo $plainPass | sudo -S -p '' bash -c '$installCmd'"
    } else {
        ssh -n -o StrictHostKeyChecking=no suryendub@$i "echo $plainPass | sudo -S -p '' bash -c '$installCmd'"
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [+] SUCCESS: LLDP is now active on ${n}." -ForegroundColor Green
    } else {
        Write-Host "  [!] FAILED to install LLDP on ${n}." -ForegroundColor Red
    }
}

Write-Host "`nDeployment complete. Wait 30-60 seconds for the switch to update its Neighbors table." -ForegroundColor Cyan
