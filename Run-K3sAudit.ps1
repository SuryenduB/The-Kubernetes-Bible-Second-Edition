# Run-K3sAudit.ps1 - Orchestrator for K3s audit
$Nodes = @(
    @{ Name = "kubernetes1";  IP = "192.168.0.19" },
    @{ Name = "kubernetes2";  IP = "192.168.0.20" },
    @{ Name = "NUC";         IP = "192.168.0.21" },
    @{ Name = "kubernetes3";  IP = "192.168.0.22" },
    @{ Name = "kubernetes4";  IP = "192.168.0.23" },
    @{ Name = "kubernetes5";  IP = "192.168.0.24" },
    @{ Name = "kubernetes6";  IP = "192.168.0.25" },
    @{ Name = "kubernetes7";  IP = "192.168.0.27" },
    @{ Name = "kubernetes8-debian"; IP = "192.168.0.28" }
)

$AuditDir = "$PSScriptRoot\k3s-audits"
$LocalScript = "$PSScriptRoot\k3s-prod-audit.sh"

if (!(Test-Path $AuditDir)) { New-Item -ItemType Directory -Path $AuditDir | Out-Null }

Write-Host "--- K3s Cluster Production Audit ---" -ForegroundColor Cyan

# 1. Create a clean Unix-formatted script locally
$scriptLines = Get-Content $LocalScript
$unixScript = "$PSScriptRoot\audit_unix.sh"
# Use UTF8 without BOM and explicit LF
[System.IO.File]::WriteAllLines($unixScript, $scriptLines)
# Note: WriteAllLines on Windows usually uses CRLF. Let's force LF.
$content = [System.IO.File]::ReadAllText($unixScript).Replace("`r`n", "`n")
[System.IO.File]::WriteAllText($unixScript, $content)

foreach ($Node in $Nodes) {
    $n = $Node.Name
    $i = $Node.IP
    Write-Host "`n>>> Auditing ${n} (${i})..." -ForegroundColor Yellow
    
    # 2. Upload
    Write-Host "  - Uploading..." -ForegroundColor Gray
    scp -o StrictHostKeyChecking=no "$unixScript" "suryendub@${i}:/tmp/audit.sh" | Out-Null
    
    # Execute
    Write-Host "  - Running script (as root)..." -ForegroundColor Gray
    # We use -p '' to suppress prompt
    ssh -o StrictHostKeyChecking=no suryendub@$i "echo 558068 | sudo -S -p '' bash /tmp/audit.sh"
    
    # 4. Download
    $actualFile = ssh -o StrictHostKeyChecking=no suryendub@$i "ls /tmp/k3s-prod-audit-*.tar.gz 2>/dev/null | head -n 1"
    
    if ($actualFile) {
        $actualFile = $actualFile.Trim()
        Write-Host "  [+] Downloading bundle: $actualFile" -ForegroundColor Green
        scp -o StrictHostKeyChecking=no "suryendub@${i}:${actualFile}" "$AuditDir\${n}.tar.gz"
        # Cleanup
        ssh -o StrictHostKeyChecking=no suryendub@$i "echo 558068 | sudo -S rm -f $actualFile /tmp/audit.sh" | Out-Null
    } else {
        Write-Host "  [!] FAILED to find bundle on ${n}." -ForegroundColor Red
    }
}

Remove-Item "$unixScript" -ErrorAction SilentlyContinue
Write-Host "`nAudit complete. Bundles available in: $AuditDir" -ForegroundColor Green
