# Upgrade-K3sCluster.ps1 - Orchestrator for K3s Version Upgrade
$TargetVersion = "v1.34.6+k3s1"

# Define nodes based on the environment (Workers first, then Master)
$WorkerNodes = @(
    @{ Name = "kubernetes1";  IP = "192.168.0.19" },
    @{ Name = "kubernetes2";  IP = "192.168.0.20" },
    @{ Name = "kubernetes3";  IP = "192.168.0.22" },
    @{ Name = "kubernetes4";  IP = "192.168.0.23" },
    @{ Name = "kubernetes5";  IP = "192.168.0.24" },
    @{ Name = "kubernetes6";  IP = "192.168.0.25" },
    @{ Name = "kubernetes7";  IP = "192.168.0.26" },
    @{ Name = "kubernetes8-debian"; IP = "192.168.0.27" }
)

$MasterNode = @{ Name = "nuc"; IP = "192.168.0.21" }

$AllNodes = $WorkerNodes + $MasterNode

Write-Host "--- K3s Cluster Rolling Upgrade to $TargetVersion ---" -ForegroundColor Cyan
Write-Host "Will upgrade $( $WorkerNodes.Count ) workers first, then the master node." -ForegroundColor Gray

foreach ($Node in $AllNodes) {
    $n = $Node.Name
    $i = $Node.IP
    
    # 1. Check current version
    $currentVerRaw = kubectl get node $n -o jsonpath="{.status.nodeInfo.kubeletVersion}" 2>$null
    if ($currentVerRaw -eq $TargetVersion) {
        Write-Host "`n>>> [SKIPPING] Node ${n} is already at ${TargetVersion}." -ForegroundColor Green
        continue
    }

    Write-Host "`n>>> Upgrading Node ${n} (${i})..." -ForegroundColor Yellow
    
    # 2. Execute K3s binary replacement via SSH
    Write-Host "  - Initiating K3s binary upgrade via SSH..." -ForegroundColor Gray
    
    # The command downloads the specific K3s version binary, replaces /usr/local/bin/k3s, and restarts the service.
    $serviceName = if ($n -eq "nuc") { "k3s" } else { "k3s-agent" }
    
    # Using a bash script string executed over SSH
    $sshCmd = "echo 558068 | sudo -S -p '' bash -c 'wget -qO /usr/local/bin/k3s https://github.com/k3s-io/k3s/releases/download/$([uri]::EscapeDataString($TargetVersion))/k3s && chmod +x /usr/local/bin/k3s && systemctl restart $serviceName'"
    
    $sshRes = ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no suryendub@$i $sshCmd 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Upgrade command failed on ${n}: $sshRes" -ForegroundColor Red
        continue
    }

    Write-Host "  [+] Upgrade command executed successfully. Waiting for node to become Ready..." -ForegroundColor Green
    
    # 3. Wait for node to be ready and version updated
    $maxRetries = 15
    $retryDelay = 5
    $success = $false

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        Start-Sleep -Seconds $retryDelay
        $statusRaw = kubectl get node $n -o json 2>$null
        
        if ($statusRaw) {
            $nodeObj = $statusRaw | ConvertFrom-Json
            $readyCondition = $nodeObj.status.conditions | Where-Object type -eq 'Ready'
            $kubeletVer = $nodeObj.status.nodeInfo.kubeletVersion
            
            if ($readyCondition.status -eq 'True' -and $kubeletVer -eq $TargetVersion) {
                Write-Host "  [+] Node ${n} is Ready and running ${TargetVersion}!" -ForegroundColor Cyan
                $success = $true
                break
            } else {
                Write-Host "  - Waiting... (Status: $($readyCondition.status), Version: $kubeletVer)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  - Waiting for API to see node $n..." -ForegroundColor DarkGray
        }
    }

    if (-not $success) {
        Write-Host "  [!] Node ${n} did not return to Ready state with new version within timeout." -ForegroundColor Red
    }
}

Write-Host "`n--- Cluster Upgrade Routine Complete ---" -ForegroundColor Cyan
