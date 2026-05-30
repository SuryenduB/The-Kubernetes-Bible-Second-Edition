function Test-K3sClusterHealth {
    <#
    .SYNOPSIS
        Comprehensive K3s cluster health diagnostic with a striking Cyberpunk UI.
    .DESCRIPTION
        Collects robust data from kubectl, evaluates worker load distribution, 
        checks finer aspects like certificates and ingress, and generates a 
        High-Tech HTML dashboard.
    .EXAMPLE
        Test-K3sClusterHealth
    #>
    [CmdletBinding()]
    param()

    $timestamp = Get-Date
    $timestampStr = $timestamp.ToString("yyyyMMdd_HHmmss")
    $displayTime = $timestamp.ToString("MMM dd, yyyy HH:mm")

    # Helper: Execute kubectl safely
    function Invoke-KubeCommand {
        param([string]$ArgsStr)
        try {
            $argArray = -split $ArgsStr
            $res = & kubectl $argArray 2>$null
            if ($res) { return @($res) }
            return @()
        } catch { return @() }
    }

    Write-Host "Initializing K3s Cluster Scan..." -ForegroundColor Cyan

    # 1. NODE DEFINITIONS & ARP RESOLUTION
    $NodeDefs = @(
        @{ Name = "kubernetes1"; IP = "192.168.0.19"; Role = "worker" }
        @{ Name = "kubernetes2"; IP = "192.168.0.20"; Role = "worker" }
        @{ Name = "nuc";         IP = "192.168.0.21"; Role = "control-plane" }
        @{ Name = "kubernetes3"; IP = "192.168.0.22"; Role = "worker" }
        @{ Name = "kubernetes4"; IP = "192.168.0.23"; Role = "worker" }
        @{ Name = "kubernetes5"; IP = "192.168.0.24"; Role = "worker" }
        @{ Name = "kubernetes6"; IP = "192.168.0.25"; Role = "worker" }
        @{ Name = "kubernetes7"; IP = "192.168.0.26"; Role = "worker" }
        @{ Name = "kubernetes8-debian"; IP = "192.168.0.27"; Role = "worker" }
        @{ Name = "NASECDE55";   IP = "192.168.0.128"; Role = "nas" }
        @{ Name = "DESKTOP-32";  IP = "192.168.0.120"; Role = "desktop" }
    )

    Write-Verbose "Resolving MAC addresses..."
    $arpTable = arp -a 2>$null
    $macIndex = @{}
    if ($arpTable) {
        $arpTable | Select-String '\d+\.\d+\.\d+\.\d+\s+[-0-9a-f]{17}' | ForEach-Object {
            $parts = $_ -split '\s+'
            if ($parts.Count -ge 2) { $macIndex[$parts[0].Trim()] = $parts[1].Trim() }
        }
    }

    Write-Host "Pinging nodes and fetching SSH telemetry..." -ForegroundColor Cyan
    $pingResults = $NodeDefs | ForEach-Object {
        $ip = $_.IP
        $up = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
        $uptime = ""; $rootDisk = ""
        if ($up -and $_.Role -ne 'desktop' -and $_.Role -ne 'nas') {
            try {
                $sshCmdArray = @("-o", "ConnectTimeout=1", "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes", "suryendub@$ip", "uptime -p; df -h / | tail -n 1")
                $sshRes = & ssh $sshCmdArray 2>$null
                if ($sshRes -and $sshRes.Count -ge 2) {
                    $uptime = $sshRes[0] -replace '^up\s+',''
                    $rootDisk = ($sshRes[1] -split '\s+')[4]
                }
            } catch {}
        }
        [PSCustomObject]@{
            Node   = $_.Name
            IP     = $ip
            MAC    = if ($macIndex.ContainsKey($ip)) { $macIndex[$ip] } else { "" }
            Status = if ($up) { "UP" } else { "DOWN" }
            Role   = $_.Role
            Uptime = $uptime
            RootDisk = $rootDisk
        }
    }

    # 2. KUBERNETES NODES
    Write-Host "Fetching Kubernetes Nodes..." -ForegroundColor Cyan
    $kubeNodesRaw = Invoke-KubeCommand "get nodes -o wide --no-headers"
    $kubeNodes = @(); $versionMap = @{}; $osMap = @{}; $runtimeMap = @{}
    
    if ($kubeNodesRaw) {
        foreach ($line in $kubeNodesRaw) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+', 8
            if ($parts.Count -ge 7) {
                $runtime = if ($parts.Count -ge 8) { ($parts[-1] -split '://')[-1] } else { "" }
                $ver = $parts[4]; $os = if ($parts.Count -ge 8) { $parts[7] } else { "" }
                
                $versionMap[$ver] = ($versionMap[$ver] ?? 0) + 1
                $osMap[$os] = ($osMap[$os] ?? 0) + 1
                $runtimeMap[$runtime] = ($runtimeMap[$runtime] ?? 0) + 1

                $kubeNodes += [PSCustomObject]@{
                    Name       = $parts[0]
                    Status     = $parts[1]
                    Roles      = $parts[2]
                    Age        = $parts[3]
                    Version    = $ver
                    InternalIP = $parts[5]
                    OS         = $os
                    Runtime    = $runtime
                }
            }
        }
    }

    $totalKubeNodes = $kubeNodes.Count
    $readyNodes = ($kubeNodes | Where-Object Status -eq 'Ready').Count

    # 3. RESOURCE USAGE
    Write-Host "Fetching Node Resource Usage..." -ForegroundColor Cyan
    $topRaw = Invoke-KubeCommand "top nodes --no-headers"
    $nodeResources = @()
    if ($topRaw) {
        foreach ($line in $topRaw) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+'
            if ($parts.Count -ge 5) {
                $memVal = $parts[3]
                $memNum = if ($memVal -match '(\d+)Mi') { [int]$matches[1] } elseif ($memVal -match '(\d+)Gi') { [int]$matches[1]*1024 } else { 0 }
                
                $cpuVal = $parts[1] -replace 'm',''
                $cpuNum = if ($cpuVal -match '^\d+$') { [int]$cpuVal } else { 0 }
                
                $cpuPctVal = $parts[2] -replace '%',''
                $cpuPctNum = if ($cpuPctVal -match '^\d+$') { [int]$cpuPctVal } else { 0 }
                
                $memPctVal = $parts[4] -replace '%',''
                $memPctNum = if ($memPctVal -match '^\d+$') { [int]$memPctVal } else { 0 }

                $nodeResources += [PSCustomObject]@{
                    Node      = $parts[0]
                    CPU       = $cpuNum
                    CPUPct    = $cpuPctNum
                    MemoryMB  = $memNum
                    MemoryPct = $memPctNum
                }
            }
        }
    }

    # 4. PODS AND LOAD BALANCING
    Write-Host "Analyzing Pods and Workload Distribution..." -ForegroundColor Cyan
    $podsRaw = Invoke-KubeCommand "get pods -A -o wide --no-headers"
    $podCountByNs = @{}; $podCountByNode = @{}; $highRestartPods = @(); $evictedPods = @(); $runningPods = @()
    $podStatusCounts = @{ Running = 0; Pending = 0; CrashLoopBackOff = 0; Completed = 0; Evicted = 0; Other = 0 }
    $totalPods = 0
    $restartThreshold = 10

    if ($podsRaw) {
        foreach ($line in $podsRaw) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+', 9
            if ($parts.Count -ge 4) {
                $ns = $parts[0]; $pod = $parts[1]; $status = $parts[3]; $restarts = 0
                if ($parts.Count -ge 5) {
                    $cleanRestarts = $parts[4] -replace '[^0-9]', ''
                    $restarts = if ($cleanRestarts -match '^\d+$') { [int]$cleanRestarts } else { 0 }
                }
                $node = if ($parts.Count -ge 8) { $parts[7] } else { "" }

                $totalPods++
                $podCountByNs[$ns] = ($podCountByNs[$ns] ?? 0) + 1
                if ($node -ne "" -and $node -ne "<none>") {
                    $podCountByNode[$node] = ($podCountByNode[$node] ?? 0) + 1
                }

                if ($status -eq 'Running') { 
                    $podStatusCounts.Running++ 
                    $runningPods += [PSCustomObject]@{ Namespace=$ns; Pod=$pod; Node=$node; Restarts=$restarts }
                }
                elseif ($status -eq 'Pending') { $podStatusCounts.Pending++ }
                elseif ($status -match 'CrashLoop') { $podStatusCounts.CrashLoopBackOff++ }
                elseif ($status -eq 'Completed') { $podStatusCounts.Completed++ }
                elseif ($status -eq 'Evicted') { 
                    $podStatusCounts.Evicted++ 
                    $evictedPods += [PSCustomObject]@{ Namespace=$ns; Pod=$pod; Node=$node }
                }
                else { $podStatusCounts.Other++ }

                if ($restarts -ge $restartThreshold) {
                    $highRestartPods += [PSCustomObject]@{ Namespace=$ns; Pod=$pod; Restarts=$restarts; Status=$status; Node=$node }
                }
            }
        }
    }

    # 5. PVCS
    Write-Host "Evaluating Storage..." -ForegroundColor Cyan
    $pvcRaw = Invoke-KubeCommand "get pvc -A --no-headers"
    $pvcResults = @(); $pvcBound = 0; $pvcPending = 0; $pvcLost = 0
    if ($pvcRaw) {
        foreach ($line in $pvcRaw) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+'
            if ($parts.Count -ge 3) {
                $sts = $parts[2]
                if ($sts -eq 'Bound') { $pvcBound++ } elseif ($sts -eq 'Pending') { $pvcPending++ } elseif ($sts -eq 'Lost') { $pvcLost++ }
                $pvcResults += [PSCustomObject]@{
                    Namespace    = $parts[0]
                    Name         = $parts[1]
                    Status       = $sts
                    Capacity     = if ($parts.Count -ge 5) { $parts[4] } else { "" }
                    StorageClass = if ($parts.Count -ge 7) { $parts[6] } else { "" }
                }
            }
        }
    }
    $totalPVCs = $pvcResults.Count

    # 6. INGRESS / LB
    $ingressRaw = Invoke-KubeCommand "get ingress -A --no-headers"
    $ingressCount = if ($ingressRaw) { $ingressRaw.Count } else { 0 }
    
    $svcRaw = Invoke-KubeCommand "get svc -A --field-selector spec.type=LoadBalancer --no-headers"
    $svcLbs = @()
    if ($svcRaw) {
        foreach ($line in $svcRaw) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 6) {
                $svcLbs += [PSCustomObject]@{ Namespace=$parts[0]; Name=$parts[1]; ExternalIP=$parts[4]; Ports=$parts[5] }
            }
        }
    }

    # 7. CERTIFICATES
    $certRaw = Invoke-KubeCommand "get certificates -A --no-headers"
    $expiredCerts = 0; $certs = @()
    if ($certRaw) {
        foreach ($line in $certRaw) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 3) {
                $ready = $parts[2]
                if ($ready -ne "True") { $expiredCerts++ }
                $certs += [PSCustomObject]@{ Namespace=$parts[0]; Name=$parts[1]; Ready=$ready; Age=$parts[-1] }
            }
        }
    }

    # 7.5 APPLICATION MATRIX
    Write-Host "Fetching Application Matrix..." -ForegroundColor Cyan
    $appMatrix = @()
    $deployRaw = Invoke-KubeCommand "get deployments -A --no-headers"
    if ($deployRaw) {
        foreach ($line in $deployRaw) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 6) { $appMatrix += [PSCustomObject]@{ Namespace=$parts[0]; Type='Deployment'; Name=$parts[1]; Ready=$parts[2]; Age=$parts[5] } }
        }
    }
    $stsRaw = Invoke-KubeCommand "get statefulsets -A --no-headers"
    if ($stsRaw) {
        foreach ($line in $stsRaw) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 4) { $appMatrix += [PSCustomObject]@{ Namespace=$parts[0]; Type='StatefulSet'; Name=$parts[1]; Ready=$parts[2]; Age=$parts[3] } }
        }
    }
    $dsRaw = Invoke-KubeCommand "get daemonsets -A --no-headers"
    if ($dsRaw) {
        foreach ($line in $dsRaw) {
            $parts = $line -split '\s+'
            if ($parts.Count -ge 9) { $appMatrix += [PSCustomObject]@{ Namespace=$parts[0]; Type='DaemonSet'; Name=$parts[1]; Ready=$parts[4]; Age=$parts[-1] } }
        }
    }

    # 8. EVENTS
    $eventsRaw = Invoke-KubeCommand "get events -A --field-selector type=Warning --sort-by=.lastTimestamp --no-headers"
    $warningEvents = @()
    if ($eventsRaw) {
        foreach ($line in $eventsRaw) {
            $parts = $line -split '\s+', 6
            if ($parts.Count -ge 6) {
                $warningEvents += [PSCustomObject]@{ Namespace=$parts[0]; Age=$parts[1]; Reason=$parts[4]; Message=$parts[5] }
            }
        }
    }

    # 9. NAS & KUBECTL VERSION
    $nasResult = $pingResults | Where-Object Node -eq 'NASECDE55'
    $kubectlVerRaw = Invoke-KubeCommand "version"
    $clientVer = ""; $serverVer = ""
    if ($kubectlVerRaw) {
        foreach ($v in $kubectlVerRaw) {
            if ($v -match 'Client Version:\s+(.+)') { $clientVer = $matches[1] }
            if ($v -match 'Server Version:\s+(.+)') { $serverVer = $matches[1] }
        }
    }

    # 10. ANALYSIS & RECOMMENDATIONS
    Write-Host "Formulating Recommendations..." -ForegroundColor Cyan
    $recommendations = @()

    # Worker Load Balancing Analysis
    $workerNodes = $kubeNodes | Where-Object Roles -match 'worker|<none>' | ForEach-Object Name
    $totalWorkerPods = 0
    foreach ($w in $workerNodes) { $totalWorkerPods += ($podCountByNode[$w] ?? 0) }
    $avgPodsPerWorker = if ($workerNodes.Count -gt 0) { [math]::Round($totalWorkerPods / $workerNodes.Count, 1) } else { 0 }
    
    $overloadedNodes = @()
    $underloadedNodes = @()
    foreach ($w in $workerNodes) {
        $count = ($podCountByNode[$w] ?? 0)
        if ($avgPodsPerWorker -gt 0) {
            $ratio = $count / $avgPodsPerWorker
            if ($ratio -ge 1.5) { $overloadedNodes += "$w ($count pods)" }
            elseif ($ratio -le 0.5) { $underloadedNodes += "$w ($count pods)" }
        }
    }

    if ($overloadedNodes.Count -gt 0) {
        $recommendations += "CRITICAL WORKLOAD IMBALANCE: Nodes carrying disproportionate load: $($overloadedNodes -join ', '). Consider cordoning/draining or performing rolling restarts on workloads to redistribute to underutilized nodes."
    }
    if ($underloadedNodes.Count -gt 0) {
        $recommendations += "UNDERUTILIZED NODES: $($underloadedNodes -join ', '). Average load is $avgPodsPerWorker pods/node."
    }

    # General Recommendations
    if ($versionMap.Keys.Count -gt 1) { $recommendations += "Version drift detected. Upgrade all nodes to a consistent K3s version." }
    if ($podStatusCounts.Pending -gt 0) { $recommendations += "$($podStatusCounts.Pending) Pods Pending. Check resource requests or node taints/capacity." }
    if ($podStatusCounts.CrashLoopBackOff -gt 0) { $recommendations += "$($podStatusCounts.CrashLoopBackOff) Pods in CrashLoopBackOff. Review container logs immediately." }
    if ($podStatusCounts.Evicted -gt 0) { $recommendations += "$($podStatusCounts.Evicted) Pods Evicted. Clear dangling pods using 'kubectl get pods | grep Evicted | awk '{print `$1}' | xargs kubectl delete pod'." }
    if ($expiredCerts -gt 0) { $recommendations += "Found $expiredCerts certificate(s) not ready. Check cert-manager logs." }
    if ($pvcPending -gt 0) { $recommendations += "$pvcPending PVCs Pending. Ensure StorageClass is default and provisioner is active." }
    if ($pvcLost -gt 0) { $recommendations += "$pvcLost PVCs Lost. Possible data loss or unbound volumes." }
    if ($nasResult.Status -eq 'DOWN') { $recommendations += "NAS Storage is offline. Check physical connectivity to 192.168.0.128." }

    if ($recommendations.Count -eq 0) { $recommendations += "Cluster operates within optimal parameters. No immediate action required." }

    # 11. GENERATE FRONTEND HTML (Refined Industrial Theme)
    Write-Host "Generating Industrial Dashboard..." -ForegroundColor Magenta

    function esc($t) { if ($t) { ([xml]'').CreateTextNode("$t").OuterXml } else { "" } }

    function statusBadge($s) {
        $c = switch -wildcard ($s) {
            'UP'      { 'success' }
            'DOWN'    { 'danger' }
            'Ready'   { 'success' }
            'Bound'   { 'success' }
            'Running' { 'success' }
            'Failed'  { 'danger' }
            'Lost'    { 'danger' }
            'Evicted' { 'danger' }
            'Pending' { 'warning' }
            'CrashLoop*' { 'danger' }
            'Warning' { 'warning' }
            default   { 'muted' }
        }
        "<span class='badge badge-$c'>$(esc $s)</span>"
    }

    function barPct($pct) {
        $c = if ($pct -gt 80) { 'danger' } elseif ($pct -gt 50) { 'warning' } else { 'success' }
        "<div class='progress-container'><span class='progress-text'>$pct%</span><div class='progress-bar'><div class='progress-fill fill-$c' style='width:$pct%'></div></div></div>"
    }

    # HTML Snippets
    $kubeNodeHtml = ($kubeNodes | Sort-Object Name | ForEach-Object {
        $nodeName = $_.Name
        $isOverloaded = ($overloadedNodes -match $nodeName)
        $podC = ($podCountByNode[$nodeName] ?? 0)
        $podColor = if ($isOverloaded) { "color: var(--danger); font-weight: bold;" } else { "" }
        $pr = $pingResults | Where-Object Node -eq $nodeName | Select-Object -First 1
        $ut = if ($pr -and $pr.Uptime) { $pr.Uptime } else { "-" }
        $rd = if ($pr -and $pr.RootDisk) { $pr.RootDisk } else { "-" }
        "<tr><td><span class='text-highlight'>$(esc $nodeName)</span></td><td>$(esc $_.Roles)</td><td style='text-align:center'>$(statusBadge $_.Status)</td><td>$(esc $_.Version)</td><td style='$podColor'>$podC</td><td>$(esc $_.InternalIP)</td><td>$(esc $ut)</td><td>$(esc $rd)</td></tr>"
    }) -join "`n"

    $resourceHtml = ($nodeResources | Sort-Object MemoryPct -Descending | ForEach-Object {
        "<tr><td><span class='text-highlight'>$(esc $_.Node)</span></td><td>$($_.CPU)m ($(barPct $_.CPUPct))</td><td>$($_.MemoryMB)Mi ($(barPct $_.MemoryPct))</td></tr>"
    }) -join "`n"

    $nsHtml = ($podCountByNs.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        "<tr><td><span class='text-highlight'>$(esc $_.Key)</span></td><td style='text-align:right'>$($_.Value)</td></tr>"
    }) -join "`n"

    $hrHtml = if ($highRestartPods) {
        ($highRestartPods | Sort-Object Restarts -Descending | Select-Object -First 20 | ForEach-Object {
            "<tr><td><span class='text-highlight'>$(esc $_.Pod)</span></td><td>$(esc $_.Namespace)</td><td style='text-align:center'><span class='badge badge-danger'>$($_.Restarts)</span></td><td>$(esc $_.Status)</td><td>$(esc $_.Node)</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='5' style='text-align:center; color: var(--text-muted);'>No high-restart anomalies detected.</td></tr>" }

    $recHtmlAll = ($recommendations | ForEach-Object { "<li>$(esc $_)</li>" }) -join "`n"

    $runningPodsHtml = if ($runningPods.Count -gt 0) {
        ($runningPods | Sort-Object Namespace, Pod | ForEach-Object {
            "<tr><td><span class='text-highlight'>$(esc $_.Pod)</span></td><td>$(esc $_.Namespace)</td><td>$(esc $_.Node)</td><td style='text-align:center'><span class='badge badge-success'>$($_.Restarts)</span></td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='4' style='text-align:center; color: var(--text-muted);'>No running pods detected.</td></tr>" }

    $appMatrixHtml = if ($appMatrix.Count -gt 0) {
        ($appMatrix | Sort-Object Namespace, Type, Name | ForEach-Object {
            $rStyle = if ($_.Ready -match "^0/") { "color: var(--danger); font-weight:bold;" } else { "color: var(--success); font-weight:bold;" }
            "<tr><td><span class='text-highlight'>$(esc $_.Namespace)</span></td><td>$(esc $_.Type)</td><td><span class='text-highlight'>$(esc $_.Name)</span></td><td style='$rStyle text-align:center;'>$(esc $_.Ready)</td><td>$(esc $_.Age)</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='5' style='text-align:center; color: var(--text-muted);'>No applications found</td></tr>" }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>K3s Nexus // Cluster Diagnostics</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
<style>
  :root { 
    --bg-dark: #0f1115; --bg-panel: #16191f; 
    --accent: #ff5722; --accent-hover: #ff784e;
    --text-main: #d1d5db; --text-muted: #6b7280; 
    --text-heading: #f3f4f6;
    --border: #2d3139; --border-light: rgba(255,255,255,0.08);
    --success: #10b981; --warning: #f59e0b; --danger: #ef4444;
  }
  
  body { 
    font-family: 'JetBrains Mono', monospace; background-color: var(--bg-dark); color: var(--text-main); 
    margin: 0; padding: 40px; 
    background-image: 
      radial-gradient(circle at top right, rgba(255, 87, 34, 0.05), transparent 40%),
      linear-gradient(rgba(255,255,255,0.02) 1px, transparent 1px), 
      linear-gradient(90deg, rgba(255,255,255,0.02) 1px, transparent 1px);
    background-size: 100% 100%, 20px 20px, 20px 20px;
    font-size: 12px; line-height: 1.5;
  }

  h1, h2, h3 { font-family: 'Inter', sans-serif; letter-spacing: -0.5px; color: var(--text-heading); font-weight: 600; margin: 0; }
  
  .header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 40px; border-bottom: 1px solid var(--border); padding-bottom: 20px; }
  h1 { font-size: 28px; }
  h1 span { color: var(--text-muted); font-weight: 400; font-family: 'JetBrains Mono'; font-size: 14px; margin-left: 10px; }
  .sys-info { text-align: right; color: var(--text-muted); line-height: 1.6; }

  .dashboard { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 40px; }
  
  .card, .panel {
    background: var(--bg-panel); border: 1px solid var(--border); border-radius: 6px; padding: 24px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.2); position: relative;
    transition: transform 0.2s, box-shadow 0.2s, border-color 0.2s;
  }
  .card:hover, .panel:hover { border-color: var(--text-muted); box-shadow: 0 6px 12px rgba(0,0,0,0.3); transform: translateY(-2px); }
  
  .card::before {
    content: ''; position: absolute; top: 0; left: 0; width: 4px; height: 100%;
    background: var(--border); transition: background 0.2s; border-radius: 6px 0 0 6px;
  }
  .card:hover::before { background: var(--accent); }

  .stat-label { font-size: 11px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; font-weight: 600; margin-bottom: 8px; }
  .stat-value { font-size: 32px; font-family: 'Inter', sans-serif; font-weight: 700; color: var(--text-heading); }
  .stat-success { color: var(--success); }
  .stat-danger { color: var(--danger); }
  .stat-warning { color: var(--warning); }
  
  .layout-grid { display: grid; grid-template-columns: minmax(0, 5fr) minmax(0, 4fr); gap: 24px; align-items: start; }
  @media(max-width: 1200px) { .layout-grid { grid-template-columns: 1fr; } }

  h2 { font-size: 15px; border-bottom: 1px solid var(--border-light); padding-bottom: 12px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }

  table { width: 100%; border-collapse: separate; border-spacing: 0; text-align: left; }
  th { padding: 12px 10px; color: var(--text-muted); font-weight: 600; font-size: 11px; text-transform: uppercase; border-bottom: 1px solid var(--border); letter-spacing: 0.5px; white-space: nowrap; }
  td { padding: 12px 10px; border-bottom: 1px solid var(--border-light); }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: rgba(255,255,255,0.02); }

  .badge { display: inline-flex; align-items: center; padding: 2px 8px; font-size: 10px; font-weight: 600; border-radius: 12px; letter-spacing: 0.5px; text-transform: uppercase; }
  .badge-success { background: rgba(16, 185, 129, 0.1); color: var(--success); border: 1px solid rgba(16, 185, 129, 0.2); }
  .badge-danger { background: rgba(239, 68, 68, 0.1); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.2); }
  .badge-warning { background: rgba(245, 158, 11, 0.1); color: var(--warning); border: 1px solid rgba(245, 158, 11, 0.2); }
  .badge-muted { background: rgba(255,255,255,0.05); color: var(--text-muted); border: 1px solid rgba(255,255,255,0.1); }

  .progress-container { display: flex; align-items: center; gap: 12px; }
  .progress-text { width: 35px; text-align: right; font-size: 11px; color: var(--text-muted); }
  .progress-bar { flex: 1; height: 4px; background: rgba(255,255,255,0.05); border-radius: 2px; overflow: hidden; }
  .progress-fill { height: 100%; background: var(--success); border-radius: 2px; }
  .fill-warning { background: var(--warning); }
  .fill-danger { background: var(--danger); }

  .recommendations { list-style: none; padding: 0; margin: 0; }
  .recommendations li { padding: 12px 16px; margin-bottom: 8px; background: rgba(255, 87, 34, 0.05); border-left: 3px solid var(--accent); border-radius: 0 4px 4px 0; color: var(--text-heading); }
  .text-highlight { color: var(--text-heading); font-weight: 600; font-family: 'Inter', sans-serif; }
  
  ::-webkit-scrollbar { width: 6px; height: 6px; }
  ::-webkit-scrollbar-track { background: transparent; }
  ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
  ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }
</style>
</head>
<body>

<div class="header">
  <h1>K3s_Nexus <span>// INDUSTRIAL_DIAGNOSTICS</span></h1>
  <div class="sys-info">
    SCAN_TIME: $displayTime<br>
    KCT_VER: $(esc $clientVer)<br>
    SRV_VER: $(esc $serverVer)
  </div>
</div>

<div class="dashboard">
  <div class="card">
    <div class="stat-label">Nodes Ready</div>
    <div class="stat-value $(if($readyNodes -eq $totalKubeNodes){'stat-success'}else{'stat-danger'})">$readyNodes / $totalKubeNodes</div>
  </div>
  <div class="card">
    <div class="stat-label">Active Pods</div>
    <div class="stat-value stat-success">$totalPods</div>
  </div>
  <div class="card">
    <div class="stat-label">Avg Pods / Worker</div>
    <div class="stat-value $(if($overloadedNodes.Count -gt 0){'stat-warning'}else{'stat-success'})">$avgPodsPerWorker</div>
  </div>
  <div class="card">
    <div class="stat-label">Anomalies</div>
    <div class="stat-value $(if($podStatusCounts.CrashLoopBackOff -gt 0 -or $podStatusCounts.Pending -gt 0 -or $podStatusCounts.Evicted -gt 0){'stat-danger'}else{'stat-success'})">$($podStatusCounts.CrashLoopBackOff + $podStatusCounts.Pending + $podStatusCounts.Evicted)</div>
  </div>
</div>

<div class="layout-grid">
  <div class="column">
    <div class="panel" style="margin-bottom: 24px;">
      <h2>[01] Infrastructure Matrix</h2>
      <div style="overflow-x: auto;">
        <table>
          <tr><th>Node_ID</th><th>Role</th><th style='text-align:center'>Status</th><th>K3s_Ver</th><th>Pods</th><th>Int_IP</th><th>Uptime</th><th>Disk</th></tr>
          $kubeNodeHtml
        </table>
      </div>
    </div>

    <div class="panel" style="margin-bottom: 24px;">
      <h2>[02] Compute Telemetry</h2>
      <div style="overflow-x: auto;">
        <table>
          <tr><th>Target</th><th>CPU_Load</th><th>Mem_Allocation</th></tr>
          $resourceHtml
        </table>
      </div>
    </div>

    <div class="panel">
      <h2>[03] Critical Process Restarts (Top 20)</h2>
      <div style="overflow-x: auto;">
        <table>
          <tr><th>Entity</th><th>Sector (NS)</th><th style='text-align:center'>Faults</th><th>State</th><th>Host</th></tr>
          $hrHtml
        </table>
      </div>
    </div>
  </div>

  <div class="column">
    <div class="panel" style="margin-bottom: 24px; border-color: var(--accent); box-shadow: 0 4px 12px rgba(255, 87, 34, 0.1);">
      <h2 style="color: var(--text-heading);">[!] Recommendations</h2>
      <ul class="recommendations">
        $recHtmlAll
      </ul>
    </div>

    <div class="panel" style="margin-bottom: 24px;">
      <h2>[04] Load Balancers / Ingress</h2>
      <div style="font-size: 11px; margin-bottom: 12px; color: var(--text-muted);">Total Ingress Routes: $ingressCount</div>
      <div style="overflow-x: auto;">
        <table>
          <tr><th>Service</th><th>Namespace</th><th>Ext_IP</th></tr>
          $(if($svcLbs.Count -gt 0){ ($svcLbs | ForEach-Object { "<tr><td><span class='text-highlight'>$(esc $_.Name)</span></td><td>$(esc $_.Namespace)</td><td>$(esc $_.ExternalIP)</td></tr>" }) -join "`n" }else{ "<tr><td colspan='3' style='text-align:center; color: var(--text-muted);'>No LBs active</td></tr>" })
        </table>
      </div>
    </div>

    <div class="panel">
      <h2>[05] Sector Density (Pods/NS)</h2>
      <div style="max-height: 250px; overflow-y: auto;">
        <table>
          $nsHtml
        </table>
      </div>
    </div>
  </div>
</div>

<div class="panel" style="margin-top: 24px; margin-bottom: 24px;">
  <h2>[06] Application Matrix</h2>
  <div style="font-size: 11px; margin-bottom: 12px; color: var(--text-muted);">Total Apps: $($appMatrix.Count)</div>
  <div style="max-height: 400px; overflow-y: auto;">
    <table>
      <tr><th>Namespace</th><th>Type</th><th>Application Name</th><th style='text-align:center'>Ready</th><th>Age</th></tr>
      $appMatrixHtml
    </table>
  </div>
</div>

<div class="panel" style="margin-top: 24px; margin-bottom: 40px;">
  <h2>[07] Active Pod Diagnostics</h2>
  <div style="font-size: 11px; margin-bottom: 12px; color: var(--text-muted);">Total Running Pods: $($podStatusCounts.Running)</div>
  <div style="max-height: 400px; overflow-y: auto;">
    <table>
      <tr><th>Pod Name</th><th>Namespace</th><th>Node</th><th style='text-align:center'>Restarts</th></tr>
      $runningPodsHtml
    </table>
  </div>
</div>

</body>
</html>
"@

    $reportDir = $PSScriptRoot
    if (-not $reportDir) { $reportDir = $PSCommandPath | Split-Path -Parent }
    if (-not $reportDir) { $reportDir = (Get-Location).Path }
    $reportPath = Join-Path $reportDir "K3s_Cluster_Report_$timestampStr.html"
    $html | Set-Content -Path $reportPath -Encoding UTF8

    Write-Host "Diagnostic compiled successfully. Initiating visual interface..." -ForegroundColor Green
    Invoke-Item -Path $reportPath
}
