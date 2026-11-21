#Requires -Version 7.0
<#
PSScriptInfo
.VERSION 1.0
.GUID 550e8400-e29b-41d4-a716-446655440000
.AUTHOR suryendub
.COMPANYNAME Kubernetes Homelab
.COPYRIGHT (c) 2026
.TITLE Repair-ContainerCreating-Pods
.DESCRIPTION
    Detects and repairs Kubernetes pods stuck in ContainerCreating or Init states
    due to Longhorn volume attachment issues (Multi-Attach errors, stale attachments).

    This script addresses the root causes:
    1. Multi-Attach errors: Volume is attached to wrong node
    2. Stale VolumeAttachment objects that prevent reattachment
    3. Longhorn volumes with stale ownerID preventing detachment

.EXAMPLE
    .\Repair-ContainerCreating-Pods.ps1
    Runs in detection mode, reports issues without fixing

.EXAMPLE
    .\Repair-ContainerCreating-Pods.ps1 -Fix
    Automatically fixes detected issues

.EXAMPLE
    .\Repair-ContainerCreating-Pods.ps1 -Fix -Verbose
    Automatically fixes with verbose output

.EXAMPLE
    .\Repair-ContainerCreating-Pods.ps1 -Namespace monitoring
    Checks only the monitoring namespace

.EXAMPLE
    .\Repair-ContainerCreating-Pods.ps1 -Fix -DryRun
    Shows what would be fixed without making changes

.LINK
    https://kubernetes.io/docs/concepts/storage/persistent-volumes/
    https://longhorn.io/docs/
#>

param(
    [switch]$Fix,
    [switch]$Verbose,
    [switch]$DryRun,
    [string]$Namespace,
    [int]$MaxAgeMinutes = 30,
    [string]$OutputFile = "$PSScriptRoot\..\logs\Repair-ContainerCreating-Pods_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

#region Initialization

# Ensure log directory exists
$logDir = Split-Path $OutputFile -Parent
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Start transcription
Start-Transcript -Path $OutputFile -Append

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "K3s ContainerCreating Pod Repair Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check kubectl availability
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl not found. Please ensure kubectl is in your PATH and configured."
    Stop-Transcript
    exit 1
}

# Check if we're connected to a cluster
try {
    $context = kubectl config current-context
    Write-Host "Using context: $context" -ForegroundColor Green
} catch {
    Write-Error "Not connected to a Kubernetes cluster. Run 'kubectl config use-context <context>' first."
    Stop-Transcript
    exit 1
}

#region Helper Functions

function Write-Status {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "[HH:mm:ss]"
    Write-Host "$timestamp $Message" -ForegroundColor $Color
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Status $Message "Red"
}

function Write-Success {
    param([string]$Message)
    Write-Status $Message "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-Status $Message "Yellow"
}

function Invoke-Kubectl {
    param(
        [string[]]$KubeArgs,
        [switch]$IgnoreErrors = $false
    )
    try {
        $result = kubectl @KubeArgs 2>$null
        if ($LASTEXITCODE -ne 0 -and -not $IgnoreErrors) {
            throw "kubectl exited with code $LASTEXITCODE"
        }
        return $result
    } catch {
        if ($IgnoreErrors) {
            return $null
        }
        throw
    }
}

function Get-StuckPods {
    param(
        [string]$NamespaceFilter = "*"
    )
    
    Write-Status "Scanning for pods stuck in ContainerCreating or Init states..."
    
    # Get all pods with ContainerCreating or Init status
    $podsJson = Invoke-Kubectl -KubeArgs @("get", "pods", "--all-namespaces", "-o", "json") -IgnoreErrors
    if (-not $podsJson) {
        Write-Warning "No pods found or error getting pods"
        return @()
    }
    
    $pods = $podsJson | ConvertFrom-Json
    $stuckPods = @()
    
    foreach ($pod in $pods.items) {
        if ($pod.status.phase -in @("Pending", "ContainerCreating") -or 
            ($pod.status.containerStatuses -and 
             $pod.status.containerStatuses[0].state.waiting -and 
             $pod.status.containerStatuses[0].state.waiting.reason -eq "PodInitializing")) {
            
            # Check if pod is older than MaxAgeMinutes
            $podAge = (Get-Date) - $pod.metadata.creationTimestamp
            if ($podAge.TotalMinutes -gt $MaxAgeMinutes) {
                # Check for volume attachment issues
                $hasVolumeIssue = $false
                $volumeError = ""
                
                if ($pod.status.conditions) {
                    foreach ($condition in $pod.status.conditions) {
                        if ($condition.type -eq "PodReadyToStartContainers" -and 
                            $condition.status -eq "False" -and 
                            $condition.message -match "Multi-Attach|attach|mount") {
                            $hasVolumeIssue = $true
                            $volumeError = $condition.message
                            break
                        }
                    }
                }
                
                # Also check events for volume issues
                if (-not $hasVolumeIssue) {
                    $eventsJson = Invoke-Kubectl -KubeArgs @("get", "events", "-n", $pod.metadata.namespace, 
                        "--field-selector", "involvedObject.name=$($pod.metadata.name)", "-o", "json") -IgnoreErrors
                    if ($eventsJson) {
                        $events = $eventsJson | ConvertFrom-Json
                        foreach ($event in $events.items) {
                            if ($event.reason -match "FailedAttachVolume|FailedMount" -and 
                                $event.message -match "Multi-Attach|attach") {
                                $hasVolumeIssue = $true
                                $volumeError = $event.message
                                break
                            }
                        }
                    }
                }
                
                if ($hasVolumeIssue -or $NamespaceFilter -eq "*" -or $pod.metadata.namespace -eq $NamespaceFilter) {
                    $stuckPods += @{
                        Name = $pod.metadata.name
                        Namespace = $pod.metadata.namespace
                        Phase = $pod.status.phase
                        Age = $podAge
                        Node = if ($pod.spec.nodeName) { $pod.spec.nodeName } else { "Not Scheduled" }
                        VolumeError = $volumeError
                        CreationTime = $pod.metadata.creationTimestamp
                        UID = $pod.metadata.uid
                    }
                }
            }
        }
    }
    
    return $stuckPods
}

function Get-VolumeAttachmentForPod {
    param(
        [string]$Namespace,
        [string]$PodName
    )

    $podJson = Invoke-Kubectl -KubeArgs @("get", "pod", "-n", $Namespace, $PodName, "-o", "json") -IgnoreErrors
    if (-not $podJson) { return @() }
    $pod = $podJson | ConvertFrom-Json

    # PVC claim name is NOT the PV name - resolve claim -> PV first.
    $pvNames = @()
    foreach ($volume in $pod.spec.volumes) {
        if ($volume.persistentVolumeClaim) {
            $pvcJson = Invoke-Kubectl -KubeArgs @("get", "pvc", "-n", $Namespace,
                $volume.persistentVolumeClaim.claimName, "-o", "json") -IgnoreErrors
            if ($pvcJson) {
                $pv = [string](($pvcJson | ConvertFrom-Json).spec.volumeName)
                if ($pv) { $pvNames += $pv }
            }
        }
    }
    if ($pvNames.Count -eq 0) { return @() }

    $vaJson = Invoke-Kubectl -KubeArgs @("get", "volumeattachment", "-o", "json") -IgnoreErrors
    if (-not $vaJson) { return @() }
    $attachments = @()
    foreach ($va in ($vaJson | ConvertFrom-Json).items) {
        if ($pvNames -contains [string]$va.spec.source.persistentVolumeName) { $attachments += $va }
    }
    return $attachments
}

function Get-LonghornVolumeForPVC {
    param(
        [string]$Namespace,
        [string]$PVCName
    )
    
    $pvcJson = Invoke-Kubectl -KubeArgs @("get", "pvc", "-n", $Namespace, $PVCName, "-o", "json") -IgnoreErrors
    if (-not $pvcJson) {
        return $null
    }
    
    $pvc = $pvcJson | ConvertFrom-Json
    $volumeName = $pvc.spec.volumeName
    
    if ($volumeName) {
        $volJson = Invoke-Kubectl -KubeArgs @("get", "volume", "-n", "longhorn-system", $volumeName, "-o", "json") -IgnoreErrors
        if ($volJson) {
            return $volJson | ConvertFrom-Json
        }
    }
    
    return $null
}

function Test-LonghornCSIConnection {
    Write-Status "Testing Longhorn CSI driver connectivity..."
    
    $csiPods = Invoke-Kubectl -KubeArgs @("get", "pods", "-n", "longhorn-system", "-l", "app=longhorn-csi-plugin", "-o", "json") -IgnoreErrors
    if ($csiPods) {
        $pods = $csiPods | ConvertFrom-Json
        if ($pods.items.Count -gt 0) {
            Write-Success "Longhorn CSI pods found: $($pods.items.Count)"
            return $true
        }
    }
    
    Write-Warning "Longhorn CSI pods not found or error"
    return $false
}

#endregion Helper Functions

#region Main Logic

Write-Status "Starting ContainerCreating pod repair scan..."
Write-Status "Max age for stuck pods: $MaxAgeMinutes minutes"

# Get stuck pods
$stuckPods = Get-StuckPods -NamespaceFilter $Namespace

if ($stuckPods.Count -eq 0) {
    Write-Success "No pods found stuck in ContainerCreating or Init states older than $MaxAgeMinutes minutes."
    Stop-Transcript
    exit 0
}

Write-Status "Found $($stuckPods.Count) pods with potential volume attachment issues:"
Write-Host ""

$issuesFound = 0
$issuesFixed = 0

foreach ($pod in $stuckPods) {
    Write-Host "  [$($pod.Namespace)] $($pod.Name) - $($pod.Phase) - Age: $($pod.Age.ToString("hhmm"))" -ForegroundColor Yellow
    
    if ($pod.VolumeError) {
        Write-Host "    Error: $($pod.VolumeError)" -ForegroundColor Red
    }
    
    $issuesFound++
}

Write-Host ""

if (-not $Fix) {
    Write-Status "Run with -Fix parameter to automatically repair these issues."
    Write-Status "Example: .\$($MyInvocation.MyCommand.Name) -Fix"
    Stop-Transcript
    exit 0
}

# Test Longhorn CSI connectivity before attempting fixes
if (-not (Test-LonghornCSIConnection)) {
    Write-ErrorMsg "Longhorn CSI driver may not be functional. Manual intervention required."
    if ($DryRun) {
        Write-Status "Dry-run: Would attempt fixes but Longhorn CSI is not responding"
    }
    Stop-Transcript
    exit 1
}

Write-Status "Attempting to repair $($stuckPods.Count) stuck pods..."
Write-Host ""

foreach ($pod in $stuckPods) {
    Write-Status "Processing: [$($pod.Namespace)] $($pod.Name)"
    
    # Get volume attachments for this pod
    $attachments = Get-VolumeAttachmentForPod -Namespace $pod.Namespace -PodName $pod.Name
    
    if ($attachments.Count -gt 0) {
        Write-Status "  Found $($attachments.Count) volume attachment(s)"
        
        foreach ($attachment in $attachments) {
            Write-Status "    Attachment: $($attachment.metadata.name) -> Node: $($attachment.spec.nodeName)"
            
            if ($DryRun) {
                Write-Status "    [DRY-RUN] Would delete volumeattachment: $($attachment.metadata.name)" -ForegroundColor Yellow
                continue
            }
            
            # Delete the volumeattachment
            Write-Status "    Deleting volumeattachment: $($attachment.metadata.name)"
            try {
                Invoke-Kubectl -KubeArgs @("delete", "volumeattachment", $attachment.metadata.name, "--ignore-not-found")
                Write-Success "    Deleted volumeattachment: $($attachment.metadata.name)"
            } catch {
                Write-ErrorMsg "    Failed to delete volumeattachment: $_"
            }
        }
    }
    
    # Longhorn VA CRs hold csi-attacher tickets in spec.attachmentTickets (a map).
    # A ticket with NO matching Kubernetes VolumeAttachment pins the volume to a stale
    # node and blocks reattachment. Patching /status/ownerID is a no-op (status subresource).
    $podJson = Invoke-Kubectl -KubeArgs @("get", "pod", "-n", $pod.Namespace, $pod.Name, "-o", "json") -IgnoreErrors
    if ($podJson) {
        $podObj = $podJson | ConvertFrom-Json
        $allPodsJson = Invoke-Kubectl -KubeArgs @("get", "pods", "-A", "-o", "json") -IgnoreErrors
        $allPods = if ($allPodsJson) { @((($allPodsJson | ConvertFrom-Json).items)) } else { @() }
        $k8sVaJson = Invoke-Kubectl -KubeArgs @("get", "volumeattachment", "-o", "json") -IgnoreErrors
        $liveVaPvs = @()
        if ($k8sVaJson) {
            $liveVaPvs = @((($k8sVaJson | ConvertFrom-Json).items |
                ForEach-Object { [string]$_.spec.source.persistentVolumeName }) | Where-Object { $_ })
        }
        $lhVaJson = Invoke-Kubectl -KubeArgs @("get", "volumeattachments.longhorn.io", "-n", "longhorn-system", "-o", "json") -IgnoreErrors

        foreach ($volume in $podObj.spec.volumes) {
            if (-not $volume.persistentVolumeClaim) { continue }
            $pvcName = $volume.persistentVolumeClaim.claimName
            $pvcJson = Invoke-Kubectl -KubeArgs @("get", "pvc", "-n", $pod.Namespace, $pvcName, "-o", "json") -IgnoreErrors
            if (-not $pvcJson) { continue }
            $pvName = [string](($pvcJson | ConvertFrom-Json).spec.volumeName)
            if (-not $pvName) { continue }

            if ($liveVaPvs -contains $pvName) {
                Write-Status "  PV $pvName still has a Kubernetes VolumeAttachment - leaving Longhorn tickets alone"
                continue
            }

            # The Longhorn VA CR is named after the CSI volumeHandle (normally == PV name).
            $lhVol = $pvName
            $pvJson = Invoke-Kubectl -KubeArgs @("get", "pv", $pvName, "-o", "json") -IgnoreErrors
            if ($pvJson) {
                $handle = [string](($pvJson | ConvertFrom-Json).spec.csi.volumeHandle)
                if ($handle) { $lhVol = $handle }
            }
            $lhVa = @()
            if ($lhVaJson) {
                $lhVa = @((($lhVaJson | ConvertFrom-Json).items) | Where-Object { $_.metadata.name -eq $lhVol })
            }
            if ($lhVa.Count -eq 0) { continue }

            $tickets = $lhVa[0].spec.attachmentTickets
            if (-not $tickets) { continue }

            foreach ($prop in $tickets.PSObject.Properties) {
                $ticket = $prop.Value
                if ([string]$ticket.type -ne 'csi-attacher') { continue }

                # Safety: never yank a ticket whose node still runs a pod consuming this PVC.
                $consumerOnTicketNode = @($allPods | Where-Object {
                    $_.spec.nodeName -eq [string]$ticket.nodeID -and
                    @($_.spec.volumes | Where-Object {
                        $_.persistentVolumeClaim -and $_.persistentVolumeClaim.claimName -eq $pvcName
                    }).Count -gt 0
                }).Count -gt 0
                if ($consumerOnTicketNode) {
                    Write-Warning "  Ticket $($prop.Name) on $($ticket.nodeID): live consumer on that node - skipping"
                    continue
                }

                if ($DryRun) {
                    Write-Status "  [DRY-RUN] Would remove orphan Longhorn ticket $($prop.Name) (node $($ticket.nodeID), PV $pvName)" -ForegroundColor Yellow
                    continue
                }
                $ptr = ([string]$prop.Name) -replace '~', '~0' -replace '/', '~1'
                $patch = '[{"op":"remove","path":"/spec/attachmentTickets/{0}"}]' -f $ptr
                try {
                    Invoke-Kubectl -KubeArgs @("patch", "volumeattachment.longhorn.io", "-n", "longhorn-system", $lhVol, "--type=json", "-p", $patch)
                    Write-Success "  Removed orphan Longhorn ticket $($prop.Name) for $lhVol"
                } catch {
                    Write-ErrorMsg "  Failed to remove Longhorn ticket $($prop.Name): $_"
                }
            }
        }
    }
    
    # Delete the pod to force reschedule
    if ($DryRun) {
        Write-Status "  [DRY-RUN] Would delete pod: [$($pod.Namespace)] $($pod.Name)" -ForegroundColor Yellow
        continue
    }
    
    Write-Status "  Deleting pod to force reschedule: [$($pod.Namespace)] $($pod.Name)"
    try {
        Invoke-Kubectl -KubeArgs @("delete", "pod", "-n", $pod.Namespace, $pod.Name, "--grace-period=0", "--force")
        Write-Success "  Deleted pod: [$($pod.Namespace)] $($pod.Name)"
        $issuesFixed++
    } catch {
        Write-ErrorMsg "  Failed to delete pod: $_"
    }
    
    Write-Host ""
}

Write-Status "Repair complete!"
Write-Status "Issues found: $issuesFound"
Write-Status "Issues fixed: $issuesFixed"

if ($issuesFixed -gt 0) {
    Write-Success "Successfully repaired $issuesFixed pod(s)"
    Write-Status "Pods will reschedule automatically. Check with: kubectl get pods -A | grep -E '(ContainerCreating|Init:)'"
} else {
    Write-Warning "No issues were fixed. Check logs for details."
}

Stop-Transcript

# Return appropriate exit code
exit $issuesFixed

#endregion Main Logic
