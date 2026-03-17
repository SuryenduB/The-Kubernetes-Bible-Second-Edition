# 🛑 K3s Homelab Systematic Shutdown Script
# This script shuts down workers first, then the master node.

$workers = @('192.168.0.19', '192.168.0.20', '192.168.0.22', '192.168.0.23', '192.168.0.24', '192.168.0.25')
$master = '192.168.0.21'
$password = '558068'

Write-Host "!!! WARNING: This will power off your entire Kubernetes Cluster !!!" -ForegroundColor Red
$confirm = Read-Host "Are you sure you want to proceed? (yes/no)"
if ($confirm -ne 'yes') { 
    Write-Host "Shutdown aborted." -ForegroundColor Green
    exit 
}

# 1. Shutdown Worker Nodes
foreach ($ip in $workers) {
    Write-Host "--- Powering off Worker: $ip ---" -ForegroundColor Yellow
    # Using -n to prevent ssh from reading from stdin (helps in loops)
    ssh -n -o StrictHostKeyChecking=no suryendub@$ip "echo $password | sudo -S poweroff"
}

# 2. Brief pause to allow workers to initiate shutdown
Write-Host "`nWaiting 5 seconds for workers to start shutting down..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# 3. Shutdown Master Node Last
Write-Host "--- Powering off Master (NUC): $master ---" -ForegroundColor Red
ssh -n -o StrictHostKeyChecking=no suryendub@$master "echo $password | sudo -S poweroff"

Write-Host "`n[SUCCESS] Shutdown commands sent to all nodes." -ForegroundColor Green
