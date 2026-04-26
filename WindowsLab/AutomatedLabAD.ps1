<#
.SYNOPSIS
    AutomatedLab — IAM Engineer AD Lab (Option B: Isolated Subnet)
    Host: Dell Vostro 470 | 16GB RAM | 4 Cores | Windows 11 Pro

.ARCHITECTURE
    ROUTER01 — Dual-NIC router, RRAS routing-only, NAT (Server Core, 1GB)
                NIC 1: 192.168.100.1 on internal lab switch
                NIC 2: DHCP on external switch (internet path)
    DC01     — Forest root DC, AD DS, DNS (Server Core, 2GB)
    SRV01    — Member server, Entra Connect host (Desktop Experience, 4GB)

    The lab runs on an isolated 192.168.100.0/24 subnet. ROUTER01 sits
    between the lab subnet and the physical network, NAT-ing outbound
    traffic. Each VM's gateway (192.168.100.1) is on the same subnet —
    this is what makes the routing valid.

.PREREQUISITES
    - Hyper-V enabled on the host
    - PowerShell 5.1 minimum
    - AutomatedLab installed:
        Install-Module AutomatedLab -AllowClobber -Force -Scope AllUsers
    - Windows Server 2022 evaluation ISO in C:\LabSources\ISOs\
        https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022

.ENTRA CONNECT NOTES
    lab.local cannot be verified in Entra ID. Accounts synced with this
    suffix are automatically reassigned the tenant's onmicrosoft.com UPN.
    Workaround: configure Entra Connect with Alternate Login ID, mapping
    the 'mail' attribute as the sign-in identifier. The AD seeding block
    populates mail on every test user via -EmailAddress.
    Replace 'yourtenant' with your actual M365 dev tenant name.

    TLS 1.2 is enforced on SRV01 post-build via Invoke-LabCommand.

.RAM BUDGET
    ROUTER01  1GB  (~300MB idle)
    DC01      2GB  (~1.2GB idle)
    SRV01     4GB  (~3.2GB under Entra Connect load)
    Host OS         (~3.5GB)
    Headroom        (~5GB)  — safe for simultaneous operation
#>


# ════════════════════════════════════════════════════════════════════════════
# STEP 0 — Run this block alone first to confirm ISO strings
# AL is strict about OS name strings — spacing and case must match exactly.
# Copy the exact OperatingSystemName values into Step 1 variables.
# ════════════════════════════════════════════════════════════════════════════

New-LabSourcesFolder -DriveLetter C

Get-LabAvailableOperatingSystem -Path 'C:\LabSources\ISOs' |
    Select-Object OperatingSystemName |
    Sort-Object OperatingSystemName


# ════════════════════════════════════════════════════════════════════════════
# STEP 1 — Variables
# ════════════════════════════════════════════════════════════════════════════

$labName  = 'IAMLab'
$domain   = 'lab.local'
$labNet   = '192.168.100.0/24'
$routerIP = '192.168.100.1'   # gateway for all lab VMs — on same subnet
$dcIP     = '192.168.100.10'
$srvIP    = '192.168.100.20'

# Paste exact strings from Step 0 output
$osDesktop = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
$osCore    = 'Windows Server 2022 Standard Evaluation'


# ════════════════════════════════════════════════════════════════════════════
# STEP 2 — Lab definition
# Set-LabInstallationCredential must match Add-LabDomainDefinition exactly —
# this is what the AL validator checks when promoting the RootDC.
# ════════════════════════════════════════════════════════════════════════════

New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV

Set-LabInstallationCredential -Username 'LabAdmin' -Password 'P@ssw0rd123!'


# ════════════════════════════════════════════════════════════════════════════
# STEP 3 — Network switches
#
# Two switches required for Option B:
#   'External'  — bound to physical NIC, provides the internet path
#   $labName    — private internal switch, 192.168.100.0/24, lab traffic only
#
# ROUTER01 sits between them. VMs on the internal switch use 192.168.100.1
# as their gateway, which is on their own subnet — this is what makes
# the routing valid, unlike a direct external switch with a foreign gateway.
#
# NIC detection: filters by default gateway presence rather than adapter
# status, which correctly excludes Hyper-V virtual adapters and unused
# physical adapters that appear 'Up' but carry no internet traffic.
# ════════════════════════════════════════════════════════════════════════════

$extNic = (Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -ne $null } |
    Select-Object -First 1 -ExpandProperty InterfaceAlias)

if (-not $extNic) {
    throw 'No internet-facing adapter found. Ensure the host has an active connection with a default gateway.'
}

Write-Host "Binding External switch to: $extNic" -ForegroundColor Cyan

Add-LabVirtualNetworkDefinition -Name 'External' `
    -HyperVProperties @{ SwitchType = 'External'; AdapterName = $extNic }

Add-LabVirtualNetworkDefinition -Name $labName -AddressSpace $labNet


# ════════════════════════════════════════════════════════════════════════════
# STEP 4 — Domain
# ════════════════════════════════════════════════════════════════════════════

Add-LabDomainDefinition -Name $domain `
    -AdminUser     'LabAdmin' `
    -AdminPassword 'P@ssw0rd123!'


# ════════════════════════════════════════════════════════════════════════════
# STEP 5 — ROUTER01
#
# Two NICs — one in each network it connects. This is what makes it a router.
# NIC 1: static IP on the internal lab switch — the gateway all VMs point to
# NIC 2: DHCP on the external switch — receives address from physical router,
#         provides the outbound internet path for NAT
#
# No -DomainName — the router is not domain-joined and does not need
# to resolve AD records. No -DnsServer1 for the same reason.
#
# AL's Routing role installs RRAS. However, AL installs RRAS with VPN
# components that require certificates and cause the service to fail.
# The post-build block below reinstalls as RoutingOnly to fix this.
# ════════════════════════════════════════════════════════════════════════════

$routerNics  = @()
$routerNics += New-LabNetworkAdapterDefinition -VirtualSwitch $labName   -Ipv4Address $routerIP
$routerNics += New-LabNetworkAdapterDefinition -VirtualSwitch 'External' -UseDhcp

Add-LabMachineDefinition -Name 'ROUTER01' `
    -Memory          1GB `
    -Processors      1 `
    -OperatingSystem $osCore `
    -Roles           Routing `
    -NetworkAdapter  $routerNics


# ════════════════════════════════════════════════════════════════════════════
# STEP 6 — DC01
#
# RootDC role: AL promotes this VM and waits for AD DS and DNS to be fully
# operational before configuring any domain-joined machine.
# Server Core: no GUI, ~1.2GB idle RAM.
# ════════════════════════════════════════════════════════════════════════════

Add-LabMachineDefinition -Name 'DC01' `
    -Memory          2GB `
    -Processors      1 `
    -Network         $labName `
    -IpAddress       $dcIP `
    -Gateway         $routerIP `
    -DnsServer1      $dcIP `
    -DomainName      $domain `
    -OperatingSystem $osCore `
    -Roles           RootDC


# ════════════════════════════════════════════════════════════════════════════
# STEP 7 — SRV01
#
# 4GB: Microsoft-documented minimum for Entra Connect.
# Desktop Experience: required for the Entra Connect GUI installer.
# ════════════════════════════════════════════════════════════════════════════

Add-LabMachineDefinition -Name 'SRV01' `
    -Memory          4GB `
    -Processors      2 `
    -Network         $labName `
    -IpAddress       $srvIP `
    -Gateway         $routerIP `
    -DnsServer1      $dcIP `
    -DomainName      $domain `
    -OperatingSystem $osDesktop


# ════════════════════════════════════════════════════════════════════════════
# STEP 8 — Build
#
# Declarative phase ends here. Install-Lab:
#   - Builds VHDX base images from ISOs
#   - Creates and starts VMs in dependency order
#   - Promotes DC01, waits for AD DS and DNS readiness
#   - Domain-joins SRV01
# Expected duration on Vostro 470: 35–50 minutes.
# All VM credentials: LabAdmin / P@ssw0rd123!
# ════════════════════════════════════════════════════════════════════════════

Install-Lab -Verbose


# ════════════════════════════════════════════════════════════════════════════
# STEP 9 — Fix RRAS on ROUTER01
#
# AL's Routing role installs RRAS with VPN components (L2TP/IKEv2) that
# require machine certificates and cause RemoteAccess service to fail.
# Fix: install the RemoteAccess PowerShell module, then reinstall RRAS
# as RoutingOnly which removes the VPN/certificate dependency entirely.
# Run as two separate Invoke-LabCommand calls — Install-WindowsFeature
# requires the session to reinitialise before the module becomes available.
# ════════════════════════════════════════════════════════════════════════════

Invoke-LabCommand -ComputerName ROUTER01 -PassThru -ScriptBlock {
    Install-WindowsFeature RSAT-RemoteAccess-PowerShell
}

Invoke-LabCommand -ComputerName ROUTER01 -PassThru -ScriptBlock {
    Import-Module RemoteAccess

    # Remove the VPN-enabled configuration AL installed
    Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue

    # Reinstall as pure router — no VPN, no L2TP, no certificate requirement
    Install-RemoteAccess -VpnType RoutingOnly

    Get-Service RemoteAccess | Select-Object Name, Status
    Get-RemoteAccess | Select-Object RoutingStatus
}

Invoke-LabCommand -ComputerName ROUTER01 -PassThru -ScriptBlock {
    # Remove any NAT left from a previous attempt
    Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue

    # Bind NAT to the internal lab subnet
    New-NetNat -Name 'LabNAT' -InternalIPInterfaceAddressPrefix '192.168.100.0/24'

    Get-NetNat | Select-Object Name, InternalIPInterfaceAddressPrefix, Active
}


# ════════════════════════════════════════════════════════════════════════════
# STEP 10 — DNS forwarders on DC01
#
# AL promotes the DC and configures AD-integrated DNS but does not set
# external forwarders. Without this, domain-joined VMs can resolve lab.local
# records but fail to resolve anything external — which breaks Windows Update,
# Entra Connect endpoint reach, and internet connectivity tests.
# ════════════════════════════════════════════════════════════════════════════

Invoke-LabCommand -ComputerName DC01 -PassThru -ScriptBlock {
    Add-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1
    Get-DnsServerForwarder
}


# ════════════════════════════════════════════════════════════════════════════
# STEP 11 — RSAT on SRV01
#
# Install-LabWindowsFeature keeps installation inside AL's job tracker so
# failures surface in Show-LabDeploymentSummary.
# Server pattern — Add-WindowsCapability is Windows client only.
# ════════════════════════════════════════════════════════════════════════════

Install-LabWindowsFeature -ComputerName SRV01 -FeatureName @(
    'RSAT-AD-Tools',
    'GPMC',
    'RSAT-AD-AdminCenter'
) -IncludeAllSubFeature


# ════════════════════════════════════════════════════════════════════════════
# STEP 12 — Seed AD on DC01
# ════════════════════════════════════════════════════════════════════════════

Invoke-LabCommand -ComputerName DC01 -PassThru -ScriptBlock {

    $base = 'DC=lab,DC=local'
    $pw   = ConvertTo-SecureString 'P@ssw0rd123!' -AsPlainText -Force

    # Tiered OU structure — mirrors real enterprise design.
    # T0 = privileged identity assets
    # T1 = servers and service accounts
    # T2 = workstations and standard users
    # This makes Entra Connect OU filtering and GPO scoping tests
    # directly transferable to production scenarios.
    'T0-PrivilegedAccess','T1-Servers','T2-Workstations','T2-Users',
    'ServiceAccounts','Groups' | ForEach-Object {
        New-ADOrganizationalUnit -Name $_ `
            -Path $base `
            -ProtectedFromAccidentalDeletion $true
    }

    # Sub-OUs under T2-Users for Entra Connect scoping tests.
    # Example: sync Employees, exclude Contractors — mirrors real filtering.
    'Employees','Contractors','TestAccounts' | ForEach-Object {
        New-ADOrganizationalUnit -Name $_ `
            -Path "OU=T2-Users,$base" `
            -ProtectedFromAccidentalDeletion $true
    }

    # Role-based security groups — access control on groups, not individual ACLs
    @('GRP_HelpDesk','GRP_ITAdmins','GRP_AllEmployees',
      'GRP_Contractors','GRP_ServiceAccounts') | ForEach-Object {
        New-ADGroup -Name $_ `
            -GroupScope    Global `
            -GroupCategory Security `
            -Path          "OU=Groups,$base" `
            -Description   "Lab role group: $_"
    }

    # Test users — -EmailAddress sets the 'mail' AD attribute.
    # Do not also set mail via -OtherAttributes — that causes a conflict error
    # because -EmailAddress and mail map to the same directory attribute.
    # Entra Connect Alternate Login ID reads this attribute for cloud sign-in.
    # Replace 'yourtenant' with your actual M365 developer tenant name.
    1..10 | ForEach-Object {
        New-ADUser `
            -Name                  "TestUser$_" `
            -SamAccountName        "testuser$_" `
            -UserPrincipalName     "testuser$_@lab.local" `
            -EmailAddress          "testuser$_@yourtenant.onmicrosoft.com" `
            -Path                  "OU=Employees,OU=T2-Users,$base" `
            -AccountPassword       $pw `
            -Enabled               $true `
            -PasswordNeverExpires  $false `
            -ChangePasswordAtLogon $false
    }

    # Entra Connect service account.
    # Dedicated and low-privilege — never a Domain Admin.
    # PasswordNeverExpires prevents sync outages from credential expiry.
    New-ADUser `
        -Name                 'svc-EntraConnect' `
        -SamAccountName       'svc-EntraConnect' `
        -Path                 "OU=ServiceAccounts,$base" `
        -AccountPassword      $pw `
        -Enabled              $true `
        -PasswordNeverExpires $true `
        -Description          'Entra Connect sync account — do not use interactively'

    Add-ADGroupMember -Identity 'GRP_ServiceAccounts' -Members 'svc-EntraConnect'

    # Fine-Grained Password Policy for service accounts.
    # FGPP must be linked to a user object or global security group — never an OU.
    # Policy applies to all members of GRP_ServiceAccounts.
    New-ADFineGrainedPasswordPolicy `
        -Name                        'PSO-ServiceAccounts' `
        -Precedence                  10 `
        -MinPasswordLength           20 `
        -LockoutThreshold            0 `
        -ComplexityEnabled           $true `
        -ReversibleEncryptionEnabled $false `
        -MaxPasswordAge              '365.00:00:00' `
        -MinPasswordAge              '0.00:00:00' `
        -PasswordHistoryCount        24 `
        -ProtectedFromAccidentalDeletion $true

    Add-ADFineGrainedPasswordPolicySubject `
        -Identity 'PSO-ServiceAccounts' `
        -Subjects (Get-ADGroup 'GRP_ServiceAccounts')

    # Default Domain Policy — governs standard users, independent of FGPP above
    Set-ADDefaultDomainPasswordPolicy `
        -Identity                 $base `
        -LockoutThreshold         5 `
        -LockoutDuration          '00:30:00' `
        -LockoutObservationWindow '00:30:00'
}


# ════════════════════════════════════════════════════════════════════════════
# STEP 13 — TLS 1.2 on SRV01 (Entra Connect hard prerequisite)
# Runs inside SRV01 — not on the host.
# ════════════════════════════════════════════════════════════════════════════

Invoke-LabCommand -ComputerName SRV01 -PassThru -ScriptBlock {
    $tls12Paths = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server',
        'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
    )
    foreach ($path in $tls12Paths) {
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'Enabled'           -Value 1 -Type DWord
        Set-ItemProperty -Path $path -Name 'DisabledByDefault' -Value 0 -Type DWord
    }
    [Net.ServicePointManager]::SecurityProtocol
}


# ════════════════════════════════════════════════════════════════════════════
# STEP 14 — Post-build verification
# ════════════════════════════════════════════════════════════════════════════

Show-LabDeploymentSummary

Get-LabVM | Select-Object Name, Status, OperatingSystem, Memory, Processors

Get-LabVM | Select-Object Name, IpAddress, Gateway, DnsServer1

# ROUTER01 must be True before SRV01/DC01 can be True
Test-LabMachineInternetConnectivity -ComputerName ROUTER01
Test-LabMachineInternetConnectivity -ComputerName DC01
Test-LabMachineInternetConnectivity -ComputerName SRV01


# ════════════════════════════════════════════════════════════════════════════
# DAY-TO-DAY MANAGEMENT — run individually as needed, never during build
# ════════════════════════════════════════════════════════════════════════════

# Start-LabVM  -All
# Stop-LabVM   -All
# Checkpoint-LabVM      -All -SnapshotName 'Clean baseline'
# Restore-LabVMSnapshot -All -SnapshotName 'Clean baseline'
# Enter-LabPSSession -ComputerName ROUTER01
# Enter-LabPSSession -ComputerName DC01
# Enter-LabPSSession -ComputerName SRV01
# Remove-Lab
