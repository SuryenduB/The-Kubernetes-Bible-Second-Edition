#Requires -Version 7.0
# Run-K3sAudit.ps1 - Orchestrator for the K3s node audit.
# Uploads scripts/k3s-prod-audit.sh to every homelab node, runs it as root, and downloads
# the resulting bundle into WindowsLab/k3s-audits/.
#
# Fixed in this revision:
#   * the audit script path pointed at WindowsLab\k3s-prod-audit.sh, which does not exist
#     (the real file lives at scripts/k3s-prod-audit.sh), so no bundle was ever produced;
#   * Windows-style '\' path joins did not resolve on macOS/Linux;
#   * the sudo password was hardcoded in plaintext in the command line.

<#
.SYNOPSIS
    Runs the K3s production audit across all homelab nodes and downloads the bundles.

.DESCRIPTION
    Copies scripts/k3s-prod-audit.sh to /tmp/audit.sh on each node (LF-normalised so the
    bash shebang works), executes it as root, then downloads /tmp/k3s-prod-audit-*.tar.gz
    into WindowsLab/k3s-audits/<node>.tar.gz and cleans up the remote artefacts.

    Node inventory comes from WindowsLab/homelab-nodes.json via HomelabNodes.psm1.

    Credentials are resolved in this order (never hardcoded):
      1. -CredentialFile (a clixml-exported SecureString or PSCredential)
      2. SecretStore entry named by -SecretName (default: k3s-homelab-sudo)
      3. Interactive secure prompt

.PARAMETER Nodes
    Restrict the audit to these node names (default: every registered node).

.PARAMETER SshUser
    SSH user for the nodes. Default: suryendub.

.PARAMETER SecretName
    SecretStore secret holding the sudo password. Default: k3s-homelab-sudo.

.PARAMETER CredentialFile
    Optional path to a clixml credential file, as produced by Export-Clixml.

.EXAMPLE
    PS> .\Run-K3sAudit.ps1
    Audit every registered node.

.EXAMPLE
    PS> .\Run-K3sAudit.ps1 -Nodes nuc,kubernetes7
    Audit only the control plane and kubernetes7.

.NOTES
    Requires: ssh, scp, pwsh 7+. Platform: Windows, Linux, macOS.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Nodes,

    [Parameter()]
    [string]$SshUser = 'suryendub',

    [Parameter()]
    [string]$SecretName = 'k3s-homelab-sudo',

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialFile',
        Justification = 'CredentialFile holds a PATH to a clixml credential file, not the credential itself')]
    [string]$CredentialFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Prerequisites ──────────────────────────────────────────────────────
foreach ($tool in @('ssh', 'scp')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool not found in PATH. Install an OpenSSH client and re-run."
    }
}

$registryModule = Join-Path -Path $PSScriptRoot -ChildPath 'HomelabNodes.psm1'
if (-not (Test-Path -Path $registryModule)) {
    throw "Node registry module not found at '$registryModule'. Restore WindowsLab/HomelabNodes.psm1 and WindowsLab/homelab-nodes.json from git."
}
Import-Module $registryModule -Force -DisableNameChecking

# ── Paths (portable: no backslash joins) ───────────────────────────────
$repoRoot = Split-Path -Parent $PSScriptRoot
$LocalScript = Join-Path -Path (Join-Path -Path $repoRoot -ChildPath 'scripts') -ChildPath 'k3s-prod-audit.sh'
if (-not (Test-Path -Path $LocalScript)) {
    throw "Audit script not found at '$LocalScript'. It must stay beside this orchestrator at scripts/k3s-prod-audit.sh."
}

$AuditDir = Join-Path -Path $PSScriptRoot -ChildPath 'k3s-audits'
if (-not (Test-Path -Path $AuditDir)) {
    $null = New-Item -ItemType Directory -Path $AuditDir -Force
}

# Normalise to LF: WriteAllLines emits CRLF on Windows, which breaks the bash shebang.
$unixScript = Join-Path -Path $AuditDir -ChildPath 'audit_unix.sh'
[System.IO.File]::WriteAllLines($unixScript, (Get-Content -Path $LocalScript))
$normalised = ([System.IO.File]::ReadAllText($unixScript)) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($unixScript, $normalised)

function ConvertTo-PlainText {
    param([Parameter(Mandatory)]$Secret)
    if ($Secret -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    if ($Secret -is [System.Management.Automation.PSCredential]) {
        return $Secret.GetNetworkCredential().Password
    }
    return [string]$Secret
}

# ── Credential resolution (never hardcoded - v1 leaked '558068' in plaintext) ──
$plainPass = $null

if ($CredentialFile -and (Test-Path -Path $CredentialFile)) {
    Write-Verbose "Loading credentials from '$CredentialFile'"
    $plainPass = ConvertTo-PlainText -Secret (Import-Clixml -Path $CredentialFile)
}
if (-not $plainPass -and (Get-Command Get-Secret -ErrorAction SilentlyContinue)) {
    try {
        $plainPass = ConvertTo-PlainText -Secret (Get-Secret -Name $SecretName -ErrorAction Stop)
        Write-Host "Loaded the sudo password from the SecretStore vault." -ForegroundColor Green
    }
    catch {
        Write-Verbose "SecretStore lookup for '$SecretName' failed: $($_.Exception.Message)"
    }
}
if (-not $plainPass) {
    Write-Host "No stored credential found - prompting (see how-to-manage-homelab-power.md to store one)." -ForegroundColor Yellow
    $plainPass = ConvertTo-PlainText -Secret (Read-Host "Enter the sudo password for '$SshUser'" -AsSecureString)
}
$b64Pass = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($plainPass))

# ── Targets come from the shared node registry ──────────────────────────
$targets = @(Get-HomelabNodes)
if ($Nodes) {
    $targets = @($targets | Where-Object { $Nodes -contains $_.name })
    if ($targets.Count -eq 0) {
        throw "None of the requested node(s) exist in the registry: $($Nodes -join ', ')"
    }
}

Write-Host "--- K3s Cluster Production Audit ---" -ForegroundColor Cyan
Write-Host "Nodes        : $($targets.Count) ($(($targets | ForEach-Object { $_.name }) -join ', '))"
Write-Host "Audit script : $LocalScript"
Write-Host "Output dir   : $AuditDir"

$sshOptions = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ConnectTimeout=10', '-o', 'LogLevel=ERROR')
$results = [System.Collections.Generic.List[object]]::new()

foreach ($node in $targets) {
    $name = $node.name
    $remote = "${SshUser}@$($node.ip)"
    $bundlePath = Join-Path -Path $AuditDir -ChildPath "$name.tar.gz"

    Write-Host "`n>>> Auditing $name ($($node.ip))..." -ForegroundColor Yellow

    $null = & scp @sshOptions $unixScript "${remote}:/tmp/audit.sh" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "scp upload to $name failed - skipping node."
        $results.Add([pscustomobject]@{ Node = $name; Status = 'upload-failed'; Bundle = $null })
        continue
    }

    # Password is base64-wrapped so it is not exposed in plaintext in the remote
    # process list or the local transcript.
    $sudoCommand = "echo $b64Pass | base64 -d | sudo -S -p '' bash /tmp/audit.sh"
    $runOutput = & ssh @sshOptions $remote $sudoCommand 2>&1
    Write-Host (($runOutput | Out-String).Trim())

    $remoteBundle = ((& ssh @sshOptions $remote "ls /tmp/k3s-prod-audit-*.tar.gz 2>/dev/null | head -n 1" 2>&1) | Out-String).Trim()
    if (-not $remoteBundle -or $remoteBundle -match 'No such file|not found') {
        Write-Warning "$name produced no audit bundle - check that the node can run the audit script as root."
        $results.Add([pscustomobject]@{ Node = $name; Status = 'no-bundle'; Bundle = $null })
        continue
    }

    $null = & scp @sshOptions "${remote}:${remoteBundle}" $bundlePath 2>&1
    $fetchOk = ($LASTEXITCODE -eq 0)
    $null = & ssh @sshOptions $remote "echo $b64Pass | base64 -d | sudo -S -p '' rm -f $remoteBundle /tmp/audit.sh" 2>&1

    if ($fetchOk) {
        $sizeKb = [math]::Round((Get-Item -Path $bundlePath).Length / 1KB, 1)
        Write-Host "  [+] Downloaded $bundlePath (${sizeKb} KB)" -ForegroundColor Green
        $results.Add([pscustomobject]@{ Node = $name; Status = 'ok'; Bundle = $bundlePath })
    }
    else {
        Write-Warning "$name bundle download failed."
        $results.Add([pscustomobject]@{ Node = $name; Status = 'download-failed'; Bundle = $null })
    }
}

Remove-Item -Path $unixScript -Force -ErrorAction SilentlyContinue

Write-Host "`n--- Audit summary ---" -ForegroundColor Cyan
foreach ($entry in $results) {
    $colour = if ($entry.Status -eq 'ok') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-20} {1}" -f $entry.Node, $entry.Status) -ForegroundColor $colour
}

$okCount = @($results | Where-Object { $_.Status -eq 'ok' }).Count
Write-Host "`n$okCount/$($results.Count) node(s) audited. Bundles in: $AuditDir" -ForegroundColor Cyan
if ($okCount -lt $results.Count) { exit 2 }