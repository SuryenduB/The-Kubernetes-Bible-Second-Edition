# Stop-K3sHomelab-Minimal.ps1
# Powers off high-consumption nodes, keeping only nuc + kubernetes5 + kubernetes7 running
# Hardware saved: kubernetes1 (4C/15GB), kubernetes2 (4C/15GB), kubernetes3 (2C/15GB), kubernetes4 (4C/7.7GB), kubernetes6 (2C/15GB)

[CmdletBinding()]
param()

# Nodes to power off (high power consumers)
$nodesToShutdown = @(
    @{ Name = 'kubernetes1'; IP = '192.168.0.19' },
    @{ Name = 'kubernetes2'; IP = '192.168.0.20' },
    @{ Name = 'kubernetes3'; IP = '192.168.0.22' },
    @{ Name = 'kubernetes4'; IP = '192.168.0.23' },
    @{ Name = 'kubernetes6'; IP = '192.168.0.25' },
    @{ Name = 'kubernetes8-debian'; IP = '192.168.0.28' }
)

# Nodes to keep running
$nodesToKeep = @(
    @{ Name = 'nuc';           IP = '192.168.0.21' },
    @{ Name = 'kubernetes5';   IP = '192.168.0.24' },
    @{ Name = 'kubernetes7';   IP = '192.168.0.27' }
)

$password = '558068'
$sshUser = 'suryendub'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  K3s Homelab - Minimal Mode Shutdown" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nKeeping alive:" -ForegroundColor Green
$nodesToKeep | ForEach-Object { Write-Host "  ✓ $($_.Name) ($($_.IP))" -ForegroundColor Green }
Write-Host "`nPowering off:" -ForegroundColor Red
$nodesToShutdown | ForEach-Object { Write-Host "  ✗ $($_.Name) ($($_.IP))" -ForegroundColor Red }

$confirm = Read-Host "`nAre you sure? (yes/no)"
if ($confirm -ne 'yes') {
    Write-Host "Aborted." -ForegroundColor Yellow
    return
}

# Step 1: Cordon nodes being shut down
Write-Host "`n[1/3] Cordoning nodes to be shut down..." -ForegroundColor Yellow
$nodesToShutdown | ForEach-Object {
    Write-Host "  Cordoning $($_.Name)..."
    kubectl cordon $_.Name 2>$null
}

# Step 2: Drain workloads gracefully
Write-Host "`n[2/3] Draining workloads from nodes..." -ForegroundColor Yellow
$nodesToShutdown | ForEach-Object {
    Write-Host "  Draining $($_.Name)..."
    kubectl drain $_.Name --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>$null
}

# Step 3: Power off nodes
Write-Host "`n[3/3] Powering off nodes..." -ForegroundColor Red
$nodesToShutdown | ForEach-Object {
    Write-Host "  Powering off $($_.Name) ($($_.IP))..."
    ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$sshUser@$($_.IP)" "echo $password | sudo -S poweroff" 2>$null
    Start-Sleep -Seconds 2
}

# Wait for nodes to go offline
Write-Host "`nWaiting for nodes to power off..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Verify remaining cluster
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Remaining Cluster Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
kubectl get nodes -o wide

Write-Host "`n✅ Minimal mode active: nuc + kubernetes5 + kubernetes7 running" -ForegroundColor Green
Write-Host "   Power saved: ~150-250W (5 nodes powered off)" -ForegroundColor Green
