#Requires -Version 5.1
<#
.SYNOPSIS
    Moves the HP-1 external Hyper-V vSwitch off the faulty onboard Intel I219-LM and onto a
    replacement NIC (typically a USB Gigabit Ethernet adapter).

.DESCRIPTION
    HP-1 (DESKTOP-32DRFM7, HP EliteBook 840 G3) cannot be reached from the LAN: its Intel
    I219-LM accepts broadcast (ARP) but discards every inbound unicast addressed to its own
    MAC. Confirmed 2026-10-04 - it is not the IP address (.103 and .105 both fail), not the MAC
    (a brand-new MAC also fails), not Hyper-V (it fails with the vSwitch unbound and a static
    address on the bare NIC), not the firewall/offloads/filters, and not the switch port.
    Guests on the same physical NIC (server-236) are reachable throughout, which is what makes
    this a host-receive fault rather than a LAN one.

    A replacement NIC is therefore the only fix. This script performs the whole migration:
    inventory the VM adapters on the switch, rebuild the switch on the new NIC, reconnect every
    adapter that was on it, and reconfigure the management-OS vNIC (address, gateway, DNS).

    Every VM adapter is inventoried BEFORE the switch is removed, so nothing is lost. The new
    switch carries the same name, so the management-OS vNIC is recreated as
    'vEthernet (WiFI External)' exactly as before.

.PARAMETER NetAdapterName
    Name of the replacement NIC as shown by Get-NetAdapter (e.g. 'Ethernet 2'). Required.

.PARAMETER Restore
    Move the switch back to a named NIC instead of the replacement adapter.

.PARAMETER Address
    Management-OS IPv4 address to assign to the recreated 'vEthernet (WiFI External)'.
    Default 192.168.0.103. Must be an address nothing else on the LAN holds.

.PARAMETER PrefixLength
    IPv4 prefix length. Default 24.

.PARAMETER Gateway
    Default gateway. Default 192.168.0.1.

.PARAMETER DnsServers
    DNS servers. Defaults to the gateway. (A missing DNS entry is what silently breaks
    Chrome Remote Desktop after an address change - the host gets an address and a gateway but
    no resolver, so names never resolve.)

.PARAMETER DryRun
    Report every step and change nothing.

.EXAMPLE
    PS> .\Set-HP1ExternalSwitchNic.ps1 -NetAdapterName 'Ethernet 2' -DryRun
    PS> .\Set-HP1ExternalSwitchNic.ps1 -NetAdapterName 'Ethernet 2' -Address 192.168.0.103
    PS> .\Set-HP1ExternalSwitchNic.ps1 -Restore -NetAdapterName 'Ethernet'

.NOTES
    Run from an ELEVATED Windows PowerShell on HP-1 itself. Chrome Remote Desktop drops for a
    few seconds while the management-OS vNIC is re-addressed and reconnects on its own; losing
    it mid-run is expected, not a failure.

    Requires the Hyper-V module. Guests lose LAN for ~1 minute, including server-236, which
    also hosts the local Docker registry on :5000.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$NetAdapterName,

    [Parameter()]
    [switch]$Restore,

    [Parameter()]
    [string]$Address = '192.168.0.103',

    [Parameter()]
    [ValidateRange(1, 32)]
    [int]$PrefixLength = 24,

    [Parameter()]
    [string]$Gateway = '192.168.0.1',

    [Parameter()]
    [string[]]$DnsServers,

    [Parameter(HelpMessage = 'Report every step and change nothing.')]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SwitchName = 'WiFI External'
$MgmtAlias  = "vEthernet ($SwitchName)"

if (-not $DnsServers -or $DnsServers.Count -eq 0) { $DnsServers = @($Gateway) }

function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Note { param([string]$m) Write-Host "    $m" -ForegroundColor DarkGray }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Warn2{ param([string]$m) Write-Host "    !!  $m" -ForegroundColor Yellow }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Must run elevated (Run as Administrator) on HP-1.'
}
if (-not (Get-Command Get-VMSwitch -ErrorAction SilentlyContinue)) {
    throw 'The Hyper-V module is not available. Run from an elevated Windows PowerShell on HP-1.'
}

# ---------------------------------------------------------------- target NIC
if (-not $NetAdapterName) {
    throw 'Specify -NetAdapterName (e.g. "Ethernet 2"), or use -Restore -NetAdapterName "Ethernet".'
}
$target = Get-NetAdapter -Name $NetAdapterName -ErrorAction SilentlyContinue
if (-not $target) {
    Write-Step 'Available network adapters:'
    Get-NetAdapter | Format-Table Name, Status, LinkSpeed, MacAddress -AutoSize | Out-String | Write-Host
    throw "Adapter '$NetAdapterName' was not found."
}
Write-Step "Target NIC: $($target.Name) [$($target.Status)] $($target.MacAddress)"
if ($target.Status -ne 'Up') {
    Write-Warn2 "Adapter status is '$($target.Status)' - check the cable is linked to the switch."
}
if (-not $Restore) {
    $onboard = Get-NetAdapter | Where-Object { $_.MacAddress -eq 'C8-D3-FF-6A-72-2E' }
    if ($onboard) { Write-Note "Onboard I219-LM present: $($onboard.Name) - the NIC with the receive fault." }
}

# ------------------------------------------------- inventory adapters first
Write-Step "Inventorying VM adapters currently on '$SwitchName'"
$current = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
$attachments = @()
if ($current) {
    Write-Note "switch type: $($current.SwitchType) -> $($current.NetAdapterInterfaceDescription)"
    $attachments = @(Get-VMNetworkAdapter | Where-Object { $_.SwitchName -eq $SwitchName })
} else {
    Write-Warn2 "No vSwitch named '$SwitchName' exists yet; it will simply be created."
}

if ($attachments.Count -gt 0) {
    $attachments | ForEach-Object { Write-Note ("reconnect: {0} / {1}" -f $_.VMName, $_.Name) }
} else {
    Write-Note 'no VM adapters are attached'
}

$dupes = @($attachments | Group-Object { "$($_.VMName)/$($_.Name)" } | Where-Object Count -gt 1)
foreach ($d in $dupes) {
    Write-Warn2 "$($d.Name) appears $($d.Count) times - reattach those by hand in Hyper-V Manager."
}

if ($DryRun) {
    Write-Step 'Dry run - nothing was changed. Planned steps:'
    Write-Host "    1. Remove-VMSwitch -Name '$SwitchName' -Force"
    Write-Host "    2. New-VMSwitch -Name '$SwitchName' -NetAdapterName '$NetAdapterName' -AllowManagementOS `$true"
    Write-Host "    3. Reconnect $($attachments.Count) VM adapter(s)"
    Write-Host "    4. Address '$MgmtAlias' as $Address/$PrefixLength via $Gateway, DNS $($DnsServers -join ', ')"
    return
}

# ------------------------------------------------------------- rebuild switch
if ($current) {
    Write-Step "Removing '$SwitchName' (guests lose LAN for ~1 minute)"
    if ($PSCmdlet.ShouldProcess($SwitchName, 'Remove-VMSwitch')) {
        Remove-VMSwitch -Name $SwitchName -Force
    }
}

Write-Step "Creating '$SwitchName' on '$NetAdapterName'"
if ($PSCmdlet.ShouldProcess($NetAdapterName, "New-VMSwitch $SwitchName")) {
    New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true | Out-Null
    Write-Ok "switch created on $NetAdapterName"
}

# ------------------------------------------------------------- reattach VMs
if ($attachments.Count -gt 0) {
    Write-Step 'Reconnecting VM adapters'
    foreach ($a in $attachments) {
        try {
            Connect-VMNetworkAdapter -VMName $a.VMName -Name $a.Name -SwitchName $SwitchName -ErrorAction Stop
            Write-Ok "$($a.VMName) / $($a.Name)"
        } catch {
            Write-Warn2 "$($a.VMName) / $($a.Name) : $($_.Exception.Message)"
        }
    }
}

# ------------------------------------------------- management-OS addressing
Write-Step "Addressing '$MgmtAlias'"
if (-not (Get-NetAdapter -Name $MgmtAlias -ErrorAction SilentlyContinue)) {
    Write-Warn2 "'$MgmtAlias' not present yet - the switch may still be initialising. Re-run in a minute."
} else {
    Get-NetIPAddress -InterfaceAlias $MgmtAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceAlias $MgmtAlias -AddressFamily IPv4 `
        -IPAddress $Address -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction Stop
    Set-DnsClientServerAddress -InterfaceAlias $MgmtAlias -ServerAddresses $DnsServers

    if ($PSCmdlet.ShouldProcess($NetAdapterName, 'Enable-NetAdapterBinding vms_pp')) {
        Enable-NetAdapterBinding -Name $NetAdapterName -ComponentID vms_pp -ErrorAction SilentlyContinue
    }
    Write-Ok "$Address/$PrefixLength via $Gateway, DNS $($DnsServers -join ', ')"
}

# ------------------------------------------------------------------ verify
Write-Step 'Verification'
Write-Host ''
Write-Host '    Addresses:' -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
    Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin -AutoSize | Out-String | Write-Host

Write-Host '    Switch:' -ForegroundColor Cyan
Get-VMSwitch | Format-Table Name, SwitchType, AllowManagementOS, NetAdapterInterfaceDescription -AutoSize |
    Out-String | Write-Host

Write-Host '    Guests on the switch:' -ForegroundColor Cyan
$now = @(Get-VMNetworkAdapter | Where-Object { $_.SwitchName -eq $SwitchName })
$now | Format-Table VMName, Name, MacAddress, Status -AutoSize | Out-String | Write-Host

if ($attachments.Count - $now.Count -gt 0) {
    Write-Warn2 "$($attachments.Count - $now.Count) adapter(s) not reconnected - attach them in Hyper-V Manager."
}

Write-Step 'Gateway and name resolution'
if (Test-NetConnection $Gateway -InformationLevel Quiet) {
    Write-Ok "gateway $Gateway reachable"
} else {
    Write-Warn2 "gateway $Gateway NOT reachable"
}

try {
    $null = Resolve-DnsName -Name 'google.com' -ErrorAction Stop
    Write-Ok 'DNS resolution works (Chrome Remote Desktop should reconnect)'
} catch {
    Write-Warn2 "DNS failed - run: Set-DnsClientServerAddress -InterfaceAlias '$MgmtAlias' -ServerAddresses $($DnsServers -join ',')"
}

Write-Host ''
Write-Step "Done. Test LAN reachability from another machine: ping $Address"
Write-Note 'If it is still unreachable the replacement NIC has the same problem - try a different adapter.'
