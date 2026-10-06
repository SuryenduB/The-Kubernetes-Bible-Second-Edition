#Requires -Version 7.0

<#
.SYNOPSIS
    Prints the current public *.trycloudflare.com URLs for the Cloudflare
    Quick Tunnel pods running in the cluster.
.DESCRIPTION
    Discovers every cloudflared Quick Tunnel pod in the cloudflare namespace
    (label app.kubernetes.io/name=cloudflared), reads each pod's logs, and
    extracts the ephemeral trycloudflare URL that Cloudflare assigned at
    tunnel creation. Quick Tunnel URLs rotate on every pod restart, so run
    this any time you need the current one.

    Works cross-platform (Windows / Linux / macOS) as long as kubectl is on
    PATH and pointed at the homelab cluster.
.PARAMETER Namespace
    Namespace where the tunnel pods run. Default: cloudflare.
.PARAMETER LabelSelector
    Selector used to discover tunnel pods. Default: app.kubernetes.io/name=cloudflared.
.PARAMETER LogTail
    Number of log lines to read per pod. Default: 1000 (the URL is printed
    once at startup, so even 100 would normally do).
.PARAMETER Verify
    End-to-end probe every discovered URL through Cloudflare's edge, and exit
    non-zero if any of them is unreachable. Required in practice: a Quick
    Tunnel's edge mapping can rot (edge returns 522/523/timeouts) while the
    connector pod stays Running/Ready with restarts=0 and request_errors=0,
    because cloudflared's own /ready only reflects its local view. Without
    -Verify a dead tunnel looks exactly like a healthy one in this table.
.PARAMETER TimeoutSeconds
    Per-probe timeout when -Verify is used. Default: 10.
.EXAMPLE
    PS> .\Get-CloudflareTunnelUrls.ps1
    Prints the current Homepage and Audiobookshelf tunnel URLs once.
.EXAMPLE
    PS> .\Get-CloudflareTunnelUrls.ps1 -Verify
    Probes both URLs through the edge and exits 1 if one is dead.
.EXAMPLE
    PS> .\Get-CloudflareTunnelUrls.ps1 -Watch
    Refreshes the URLs every 30s until Ctrl+C (handy right after a restart).
.EXAMPLE
    PS> .\Get-CloudflareTunnelUrls.ps1 -Watch -IntervalSeconds 10
    Refreshes every 10 seconds.
.EXAMPLE
    PS> .\Get-CloudflareTunnelUrls.ps1 -Watch -Verify -IntervalSeconds 60
    Keeps refreshing and keeps showing which tunnels actually serve traffic.
    Unlike the one-shot run this never exits on its own: a dead tunnel here is
    something to watch recover (or to fix), not a reason to stop looking.

    If a tunnel reports unreachable while its pod is Running/Ready, the edge has
    lost the route to that connector and it will NOT recover on its own - the
    connector never re-registers. Repair it by restarting just that connector:
      kubectl -n cloudflare rollout restart deploy/cloudflared-audiobookshelf-quick
    The Quick Tunnel URL changes when you do that (the old one stays dead).
.NOTES
    Quick Tunnels are ephemeral/demo: no auth, no SLA, URL changes on pod
    restart. For stable URLs use the permanent tunnel (see
    kubernetes-manifests/cloudflare/README.md).
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Namespace = 'cloudflare',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelSelector = 'app.kubernetes.io/name=cloudflared',

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$LogTail = 1000,

    [Parameter()]
    [switch]$Watch,

    [Parameter()]
    [ValidateRange(1, 3600)]
    [int]$IntervalSeconds = 30,

    [Parameter()]
    [switch]$Verify,

    [Parameter()]
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# URL printed once by cloudflared when the quick tunnel is created.
$script:TunnelUrlPattern = 'https://[a-z0-9-]+\.trycloudflare\.com'

function Test-Kubectl {
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        throw 'kubectl not found on PATH. Install kubectl or add it to PATH.'
    }
}

# Runs a native command, captures stdout+stderr, and throws on non-zero exit.
function Invoke-Native {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter()]
        [string[]]$Arguments = @()
    )

    $stdout = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($stdout | Out-String).Trim()
        throw "Command failed ($Command $($Arguments -join ' ')): $detail"
    }
    return ($stdout | Out-String)
}

# End-to-end probe of a public URL through Cloudflare's edge. Returns a short
# status string plus whether the URL actually served a response.
function Test-TunnelUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter()]
        [int]$TimeoutSeconds = 10
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSeconds `
            -SkipHttpErrorCheck -MaximumRedirection 3 -UseBasicParsing
        $code = [int]$response.StatusCode
        return [pscustomobject]@{
            Reachable = ($code -lt 500)
            Status    = "HTTP $code"
        }
    }
    catch {
        # 52x/timeout/DNS all surface here; the edge never reached the connector.
        $message = $_.Exception.Message
        if ($message -match '(\d{3})') { $label = "HTTP $($Matches[1])" } else { $label = 'unreachable' }
        if ($message.Length -gt 60) { $message = $message.Substring(0, 60) }
        return [pscustomobject]@{
            Reachable = $false
            Status    = "$label ($message)"
        }
    }
}

# Returns one row per tunnel pod: App, Url, Pod, Node, Age, Status.
function Get-TunnelUrl {
    $json = Invoke-Native -Command 'kubectl' -Arguments @(
        '-n', $Namespace, 'get', 'pods',
        '-l', $LabelSelector,
        '-o', 'json'
    )

    $podList = $json | ConvertFrom-Json
    if (-not $podList.items -or $podList.items.Count -eq 0) {
        Write-Warning "No pods matched '$LabelSelector' in namespace '$Namespace'."
        return @()
    }

    $rows = foreach ($pod in $podList.items) {
        $status = if ($pod.status.phase) { [string]$pod.status.phase } else { 'Unknown' }
        $node = if ($pod.spec.nodeName) { [string]$pod.spec.nodeName } else { '-' }

        $age = '-'
        if ($pod.metadata.creationTimestamp) {
            $created = [datetime]::Parse($pod.metadata.creationTimestamp, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
            $ts = [datetime]::UtcNow - $created
            if ($ts.TotalDays -ge 1) {
                $age = '{0}d {1}h' -f [int]$ts.Days, $ts.Hours
            }
            else {
                $age = '{0}h {1}m' -f [int]$ts.TotalHours, $ts.Minutes
            }
        }

        # Friendly service name: cloudflared-homepage-quick -> homepage
        # labels is a PSCustomObject after ConvertFrom-Json, so read the
        # property instead of indexing with a string key.
        $app = ''
        $labels = $pod.metadata.labels
        if ($null -ne $labels) {
            $appProp = $labels.PSObject.Properties['app']
            if ($null -ne $appProp) { $app = [string]$appProp.Value }
        }
        $app = $app -replace '^cloudflared-', '' -replace '-quick$', ''
        if (-not $app) { $app = [string]$pod.metadata.name }

        $url = ''
        try {
            $logs = Invoke-Native -Command 'kubectl' -Arguments @(
                '-n', $Namespace, 'logs', ([string]$pod.metadata.name),
                '--tail', $LogTail.ToString()
            )
            $matchesFound = [regex]::Matches($logs, $script:TunnelUrlPattern)
            if ($matchesFound.Count -gt 0) {
                # Last match wins: the most recent tunnel URL for this pod.
                $url = $matchesFound[$matchesFound.Count - 1].Value
            }
        }
        catch {
            Write-Verbose "Could not read logs for $($pod.metadata.name): $_"
        }

        if (-not $url) {
            $url = '(not in logs yet - pod may still be starting)'
        }

        $reachable = '-'
        if ($Verify -and $url -like 'https://*') {
            $probe = Test-TunnelUrl -Url $url -TimeoutSeconds $TimeoutSeconds
            $reachable = if ($probe.Reachable) { 'yes' } else { "NO - $($probe.Status)" }
        }

        [pscustomobject]@{
            Service   = $app
            Url       = $url
            Reachable = $reachable
            Status    = $status
            Node      = $node
            Age       = $age
            Pod       = [string]$pod.metadata.name
        }
    }

    return @($rows)
}

function Show-TunnelUrl {
    $rows = Get-TunnelUrl
    Write-Host ''
    Write-Host ("Cloudflare Quick Tunnel URLs - {0:yyyy-MM-dd HH:mm:ss} UTC" -f [datetime]::UtcNow) -ForegroundColor Cyan
    Write-Host ('Namespace: {0}   (ephemeral: URLs rotate when a pod restarts)' -f $Namespace) -ForegroundColor DarkGray
    if ($Verify) {
        $rows | Format-Table -AutoSize Service, Url, Reachable, Status, Node, Age | Out-String | Write-Host

        $dead = @($rows | Where-Object { $_.Reachable -like 'NO*' })
        if ($dead.Count -gt 0) {
            Write-Warning "$($dead.Count) tunnel URL(s) are NOT serving traffic through the edge, even though the pod may be Running/Ready:"
            foreach ($row in $dead) {
                Write-Warning "  $($row.Service) ($($row.Pod)): $($row.Url) -> $($row.Reachable)"
            }
            Write-Warning 'Restart that connector to get a working (new) URL: kubectl -n cloudflare rollout restart deploy/<pod-deployment>'
        }
    }
    else {
        $rows | Format-Table -AutoSize Service, Url, Status, Node, Age | Out-String | Write-Host
    }
    return $rows
}

try {
    Test-Kubectl

    if ($Watch) {
        Write-Verbose "Watching tunnel URLs every ${IntervalSeconds}s (Ctrl+C to stop)."
        while ($true) {
            # Clear-Host only on a real terminal: when redirected it just prints
            # "TERM environment variable not set." to stderr.
            if (-not [Console]::IsOutputRedirected) { Clear-Host }
            $null = Show-TunnelUrl
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    else {
        $rows = Show-TunnelUrl
        if ($Verify -and @($rows | Where-Object { $_.Reachable -like 'NO*' }).Count -gt 0) { exit 1 }
    }
}
catch {
    Write-Error "Failed to fetch tunnel URLs: $_"
    exit 1
}
