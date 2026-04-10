# Run-K3sAudit.ps1 - Orchestrator for parallel K3s audit
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
if (!(Test-Path $AuditDir)) { New-Item -ItemType Directory -Path $AuditDir | Out-Null }

Write-Host "--- K3s Cluster Production Audit ---" -ForegroundColor Cyan

# The Audit Command (escaped for bash -c)
$auditCmd = 'TS=$(date +%s); OD=/tmp/audit-$HOSTNAME-$TS; mkdir -p $OD; ' +
            'uname -a > $OD/sys.txt; free -h >> $OD/sys.txt; ' +
            'if command -v k3s &>/dev/null; then k3s --version > $OD/k3s.txt; fi; ' +
            'systemctl status k3s* --no-pager > $OD/svc.txt 2>&1; ' +
            'df -h > $OD/disk.txt; mount | grep longhorn > $OD/lh.txt; ' +
            'ip addr > $OD/net.txt; ' +
            '[ -f /etc/rancher/k3s/registries.yaml ] && cat /etc/rancher/k3s/registries.yaml | sed "s|password: .*|password: [REDACTED]|" > $OD/reg.txt; ' +
            'journalctl -u k3s* -n 50 --no-pager > $OD/log.txt 2>&1; ' +
            'if [ "$HOSTNAME" == "NUC" ] || [ "$HOSTNAME" == "nuc" ]; then ' +
            '  find /var/lib/rancher/k3s/server/tls -name "*.crt" -exec sh -c "echo {} && openssl x509 -enddate -noout -in {}" \; > $OD/certs.txt; ' +
            'fi; ' +
            'tar czf /tmp/audit-$HOSTNAME.tar.gz -C /tmp audit-$HOSTNAME-$TS; rm -rf $OD'

foreach ($Node in $Nodes) {
    $n = $Node.Name
    $i = $Node.IP
    Write-Host "Auditing ${n}..." -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no suryendub@$i "echo 558068 | sudo -S bash -c '$auditCmd'" | Out-Null
    
    # Download
    $actualFile = ssh -o StrictHostKeyChecking=no suryendub@$i "ls /tmp/audit-*.tar.gz 2>/dev/null | head -n 1"
    
    if ($actualFile) {
        $actualFile = $actualFile.Trim()
        Write-Host "  [+] Downloading $actualFile" -ForegroundColor Green
        scp -o StrictHostKeyChecking=no "suryendub@${i}:${actualFile}" "$AuditDir\${n}.tar.gz"
        ssh -o StrictHostKeyChecking=no suryendub@$i "rm -f $actualFile"
    } else {
        Write-Host "  [!] FAILED to find bundle on ${n}" -ForegroundColor Red
    }
}

Write-Host "`nAudit complete. Bundles available in: $AuditDir" -ForegroundColor Green
