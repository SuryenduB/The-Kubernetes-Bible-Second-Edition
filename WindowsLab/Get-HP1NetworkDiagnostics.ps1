#Requires -Version 5.1
# Get-HP1NetworkDiagnostics.ps1
# Read-only collector for the "Mac cannot reach HP-1 (192.168.0.103) while the guest
# server-236 (192.168.0.236) on the same physical NIC is reachable" investigation.
#
# Context: HP-1 (DESKTOP-32DRFM7) is a Hyper-V host. Its wired I219-LM is bound to the
# "WiFI External" external vSwitch (the name is historical - it is wired). server-236 is a
# Hyper-V guest on that switch and also runs the local Docker registry on :5000. Chrome
# Remote Desktop works outbound; inbound LAN traffic to the host vNIC does not answer.
#
# This script CHANGES NOTHING. It writes one text report to the Desktop and prints it, so
# the whole snapshot can be shared in one paste. Run it from an elevated PowerShell on HP-1:
#   powershell -ExecutionPolicy Bypass -File .\Get-HP1NetworkDiagnostics.ps1
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'hp1-netdiag.txt')
)

function Section([string]$Title) { "`n=============================================================="; "===== $Title"; "==============================================================" }
function Try-Run([scriptblock]$Block) {
    try { & $Block } catch { "  (unavailable: $($_.Exception.Message))" }
}

$report = & {
    Section 'Identity'
    Try-Run { Get-CimInstance Win32_ComputerSystem | Format-List Name, Manufacturer, Model, TotalPhysicalMemory }
    Try-Run { Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, BuildNumber, LastBootUpTime }

    Section 'IPv4 addresses - WHICH adapter owns 192.168.0.103?'
    Try-Run { Get-NetIPAddress -AddressFamily IPv4 | Sort-Object InterfaceAlias |
        Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin, SuffixOrigin -AutoSize }

    Section 'IP configuration (gateway / DNS per adapter)'
    Try-Run { Get-NetIPConfiguration -Detailed | Out-String -Width 200 }

    Section 'Adapters (ifIndex / status / link / MAC)'
    Try-Run { Get-NetAdapter | Sort-Object ifIndex |
        Format-Table ifIndex, Name, Status, LinkSpeed, MacAddress, MediaType -AutoSize }

    Section 'Routing table - look for a SECOND default route (Default Switch NAT hijack)'
    Try-Run { Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix |
        Format-Table ifIndex, InterfaceAlias, DestinationPrefix, NextHop, RouteMetric -AutoSize }

    Section 'Connection profiles'
    Try-Run { Get-NetConnectionProfile | Format-Table InterfaceAlias, Name, NetworkCategory, IPv4Connectivity -AutoSize }

    Section 'Firewall profiles'
    Try-Run { Get-NetFirewallProfile | Format-Table Name, Enabled -AutoSize }

    Section 'Hyper-V switches'
    Try-Run { Get-VMSwitch | Format-Table Name, SwitchType, AllowManagementOS, NetAdapterInterfaceDescription -AutoSize }

    Section 'Management-OS vNICs'
    Try-Run { Get-VMNetworkAdapter -ManagementOS | Format-Table Name, SwitchName, MacAddress, Status, IPAddresses -AutoSize }

    Section 'Management-OS VLAN'
    Try-Run { Get-VMNetworkAdapter -ManagementOS | Get-VMNetworkAdapterVlan | Format-List }

    Section 'Guests (server-236 / k3s-master) and their adapters'
    Try-Run { Get-VM | Format-Table Name, State, Status, Generation, SwitchName -AutoSize }
    Try-Run { Get-VM | Get-VMNetworkAdapter | Format-Table VMName, Name, SwitchName, MacAddress, Status, IPAddresses -AutoSize }
    Try-Run { Get-VM | Get-VMNetworkAdapterVlan | Format-List }

    Section 'VLAN advanced property (physical NIC + host vNIC)'
    Try-Run { Get-NetAdapterAdvancedProperty -Name 'Ethernet', 'vEthernet (WiFI External)' -ErrorAction SilentlyContinue |
        Where-Object DisplayName -match 'VLAN' | Format-Table Name, DisplayName, DisplayValue -AutoSize }

    Section 'Checksum / LSO offload state (as changed during troubleshooting)'
    Try-Run { Get-NetAdapterChecksumOffload -Name '*' | Format-Table Name, IpIPv4, TcpIPv4, UdpIPv4 -AutoSize }
    Try-Run { Get-NetAdapterLso -Name '*' | Format-Table Name, V1IPv4Enabled, IPv4Enabled -AutoSize }

    Section 'Hyper-V binding on the physical NIC'
    Try-Run { Get-NetAdapterBinding -Name 'Ethernet' |
        Where-Object { $_.ComponentID -match 'vms|ms_' } |
        Format-Table Name, ComponentID, DisplayName, Enabled -AutoSize }

    Section 'sshd service + listeners'
    Try-Run { Get-Service sshd | Format-Table Name, Status, StartType -AutoSize }
    Try-Run { Get-NetTCPConnection -State Listen -LocalPort 22 | Format-Table LocalAddress, LocalPort, OwningProcess -AutoSize }

    Section 'ARP / neighbour table (host)'
    Try-Run { Get-NetNeighbor -AddressFamily IPv4 |
        Where-Object State -ne 'Unreachable' |
        Format-Table ifIndex, IPAddress, LinkLayerAddress, State -AutoSize }

    Section 'Self-connectivity tests'
    Try-Run { Test-NetConnection 192.168.0.1   | Format-List ComputerName, RemoteAddress, PingSucceeded }
    Try-Run { Test-NetConnection 192.168.0.103 -Port 22 | Format-List ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded }
    Try-Run { Test-NetConnection 192.168.0.236 -Port 22 | Format-List ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded }

    Section 'route print -4'
    Try-Run { route print -4 }
}

$report | Tee-Object -FilePath $OutFile
"`nReport saved to: $OutFile"
