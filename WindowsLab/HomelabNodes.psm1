#Requires -Version 7.0
<#
    HomelabNodes.psm1
    Loader + accessor for WindowsLab/homelab-nodes.json (the single source of truth for
    homelab node identity and safety constraints).

    Consumed by:
      - Start-K3sHomelab.ps1        (uncordon / repair / reconcile)
      - Stop-K3sHomelab-Minimal.ps1 (power off high-consumption nodes)
      - shutdown_homelab.ps1        (full power-down)

    Why this exists: node lists used to be copy-pasted into every script. The
    'kubernetes7 must never be powered off' constraint was therefore only enforced
    in whichever script someone remembered to update.
#>

Set-StrictMode -Version Latest

$script:RegistryPath = Join-Path -Path $PSScriptRoot -ChildPath 'homelab-nodes.json'
$script:RegistryCache = $null

function Get-HomelabRegistry {
    <#
    .SYNOPSIS
        Returns the full parsed node registry (cached per session).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $script:RegistryPath,

        [Parameter()]
        [switch]$Refresh
    )

    if (-not $Refresh -and $script:RegistryCache -and $Path -eq $script:RegistryPath) {
        return $script:RegistryCache
    }

    if (-not (Test-Path -Path $Path)) {
        throw "Homelab node registry not found at '$Path'. Restore WindowsLab/homelab-nodes.json from git."
    }

    $data = Get-Content -Path $Path -Raw | ConvertFrom-Json

    foreach ($required in @('cluster', 'nodes')) {
        if (-not $data.PSObject.Properties[$required]) {
            throw "Homelab node registry '$Path' is missing the required '$required' section."
        }
    }
    if (@($data.nodes).Count -eq 0) {
        throw "Homelab node registry '$Path' contains no nodes."
    }

    if ($Path -eq $script:RegistryPath) { $script:RegistryCache = $data }
    return $data
}

# powershell-master style pass:
# - singular approved nouns, plural spellings kept behind SuppressMessage-justified aliases
# - [OutputType()] on the multi-return functions
function Get-HomelabNodes {
    <#
    .SYNOPSIS
        Returns the registered Kubernetes nodes (excludes the 'external' section).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Plural noun is the sanctioned Get-* collection exception and the registry v1 contract')]
    param(
        [Parameter()]
        [ValidateSet('worker', 'control-plane', 'any')]
        [string]$Role = 'any',

        [Parameter()]
        [switch]$Refresh
    )

    $nodes = @(Get-HomelabRegistry -Refresh:$Refresh | Select-Object -ExpandProperty nodes)
    if ($Role -ne 'any') {
        $nodes = @($nodes | Where-Object { $_.role -eq $Role })
    }
    return $nodes
}

function Get-HomelabNode {
    <#
    .SYNOPSIS
        Returns a single registered node by name, or $null when not registered.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [switch]$Refresh
    )

    $match = @(Get-HomelabNodes -Refresh:$Refresh | Where-Object { $_.name -ieq $Name })
    if ($match.Count -eq 0) { return $null }
    return $match[0]
}

function Get-HomelabNodeName {
    <#
    .SYNOPSIS
        Returns every registered node name (used for expected-inventory checks).
        (Singular approved noun; the historical plural alias is kept below.)
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Plural is the public contract consumed by all four scripts (registry v1); singular form kept as the approved function name')]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    return @(Get-HomelabNodes -Refresh:$Refresh | ForEach-Object { $_.name })
}

function Get-HomelabNodeNames {
    <#
    .SYNOPSIS
        Registry v1 wrapper for Get-HomelabNodeName (returns every registered node name).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Registry v1 public contract - singular spelling is the preferred form')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [switch]$Refresh
    )
    return Get-HomelabNodeName -Refresh:$Refresh
}

function Get-HomelabSurvivorName {
    <#
    .SYNOPSIS
        Names of nodes deliberately kept running during a minimal-mode power-down.
        (Singular approved noun; the historical plural alias is kept below.)
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Plural is the public contract consumed by Stop-K3sHomelab-Minimal.ps1 (registry v1)')]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    $registry = Get-HomelabRegistry -Refresh:$Refresh
    if (-not $registry.PSObject.Properties['survivors']) { return @() }
    return @($registry.survivors)
}

function Get-HomelabSurvivorNames {
    <#
    .SYNOPSIS
        Registry v1 wrapper for Get-HomelabSurvivorName (names of minimal-quorum nodes).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Registry v1 public contract - singular spelling is the preferred form')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [switch]$Refresh
    )
    return Get-HomelabSurvivorName -Refresh:$Refresh
}

function Get-NeverPowerOffNodeName {
    <#
    .SYNOPSIS
        Names of nodes that must never be powered off (e.g. kubernetes7 - broken power switch).
        (Singular approved noun; the historical plural alias is kept below.)
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Plural is the public contract consumed by the shutdown scripts (registry v1)')]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    return @(Get-HomelabNodes -Refresh:$Refresh | Where-Object { $_.neverPowerOff } | ForEach-Object { $_.name })
}

function Get-NeverPowerOffNodeNames {
    <#
    .SYNOPSIS
        Registry v1 wrapper for Get-NeverPowerOffNodeName (names that must never be powered off).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Registry v1 public contract - singular spelling is the preferred form')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [switch]$Refresh
    )
    return Get-NeverPowerOffNodeName -Refresh:$Refresh
}

function Get-ProtectedNodeName {
    <#
    .SYNOPSIS
        Names of nodes that must never be cordoned or drained (control plane, kubernetes7, ...).
        (Singular approved noun; the historical plural alias is kept below.)
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Plural is the public contract consumed by Start-K3sHomelab.ps1 (registry v1)')]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    return @(Get-HomelabNodes -Refresh:$Refresh | Where-Object { $_.neverCordon } | ForEach-Object { $_.name })
}

function Get-ProtectedNodeNames {
    <#
    .SYNOPSIS
        Registry v1 wrapper for Get-ProtectedNodeName (names that must never be cordoned/drained).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Registry v1 public contract - singular spelling is the preferred form')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [switch]$Refresh
    )
    return Get-ProtectedNodeName -Refresh:$Refresh
}

function Test-ProtectedNode {
    <#
    .SYNOPSIS
        $true when the node must never be cordoned/drained.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [switch]$Refresh
    )

    return ((Get-ProtectedNodeName -Refresh:$Refresh) -contains $Name)
}

function Test-NeverPowerOffNode {
    <#
    .SYNOPSIS
        $true when the node must never be powered off.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [switch]$Refresh
    )

    return ((Get-NeverPowerOffNodeName -Refresh:$Refresh) -contains $Name)
}

function Get-HomelabApiServer {
    <#
    .SYNOPSIS
        Expected Kubernetes API server URL, used as a cluster-identity guard.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    $registry = Get-HomelabRegistry -Refresh:$Refresh
    if (-not $registry.cluster.PSObject.Properties['apiServer']) { return $null }
    return $registry.cluster.apiServer
}

function Get-HomelabNodeIpMap {
    <#
    .SYNOPSIS
        Convenience name -> IP map for SSH/power operations.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    $map = @{}
    foreach ($node in (Get-HomelabNodes -Refresh:$Refresh)) {
        $map[$node.name] = $node.ip
    }
    return $map
}

Export-ModuleMember -Function @(
    'Get-HomelabRegistry',
    'Get-HomelabNodes',
    'Get-HomelabNode',
    'Get-HomelabNodeName',
    'Get-HomelabNodeNames',
    'Get-HomelabSurvivorName',
    'Get-HomelabSurvivorNames',
    'Get-NeverPowerOffNodeName',
    'Get-NeverPowerOffNodeNames',
    'Get-ProtectedNodeName',
    'Get-ProtectedNodeNames',
    'Test-ProtectedNode',
    'Test-NeverPowerOffNode',
    'Get-HomelabApiServer',
    'Get-HomelabNodeIpMap'
)