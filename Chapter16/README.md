`az group create --name rg-myfirstakscluster-westeurope --location westeurope -o table`




`az aks create --resource-group rg-myfirstakscluster-westeurope --name aks-myfirstcluster-westeurope --node-count 2 --enable-addons monitoring --generate-ssh-keys -o yaml`




```yaml
aadProfile: null
addonProfiles:
  omsagent:
    config:
      logAnalyticsWorkspaceResourceID: /subscriptions/2ae86d2a-28d5-4737-a84e-4b307ff388ef/resourceGroups/DefaultResourceGroup-WEU/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-2ae86d2a-28d5-4737-a84e-4b307ff388ef-WEU
      useAADAuth: 'true'
    enabled: true
    identity: null
agentPoolProfiles:
- availabilityZones: null
  capacityReservationGroupId: null
  count: 2
  creationData: null
  currentOrchestratorVersion: 1.31.7
  enableAutoScaling: false
  enableEncryptionAtHost: false
  enableFips: false
  enableNodePublicIp: false
  enableUltraSsd: false
  gpuInstanceProfile: null
  hostGroupId: null
  kubeletConfig: null
  kubeletDiskType: OS
  linuxOsConfig: null
  maxCount: null
  maxPods: 110
  minCount: null
  mode: System
  name: nodepool1
  networkProfile: null
  nodeImageVersion: AKSUbuntu-2204gen2containerd-202504.22.0
  nodeLabels: null
  nodePublicIpPrefixId: null
  nodeTaints: null
  orchestratorVersion: '1.31'
  osDiskSizeGb: 128
  osDiskType: Managed
  osSku: Ubuntu
  osType: Linux
  podSubnetId: null
  powerState:
    code: Running
  provisioningState: Succeeded
  proximityPlacementGroupId: null
  scaleDownMode: Delete
  scaleSetEvictionPolicy: null
  scaleSetPriority: null
  spotMaxPrice: null
  tags: null
  type: VirtualMachineScaleSets
  upgradeSettings:
    drainTimeoutInMinutes: null
    maxSurge: 10%
    nodeSoakDurationInMinutes: null
  vmSize: Standard_DS2_v2
  vnetSubnetId: null
  windowsProfile: null
  workloadRuntime: null
apiServerAccessProfile: null
autoScalerProfile: null
autoUpgradeProfile:
  nodeOsUpgradeChannel: NodeImage
  upgradeChannel: null
azureMonitorProfile:
  metrics: null
azurePortalFqdn: aks-myfirs-rg-myfirstaksclu-2ae86d-1mn1vfxo.portal.hcp.westeurope.azmk8s.io
currentKubernetesVersion: 1.31.7
disableLocalAccounts: false
diskEncryptionSetId: null
dnsPrefix: aks-myfirs-rg-myfirstaksclu-2ae86d
enablePodSecurityPolicy: null
enableRbac: true
extendedLocation: null
fqdn: aks-myfirs-rg-myfirstaksclu-2ae86d-1mn1vfxo.hcp.westeurope.azmk8s.io
fqdnSubdomain: null
httpProxyConfig: null
id: /subscriptions/2ae86d2a-28d5-4737-a84e-4b307ff388ef/resourcegroups/rg-myfirstakscluster-westeurope/providers/Microsoft.ContainerService/managedClusters/aks-myfirstcluster-westeurope
identity:
  delegatedResources: null
  principalId: c2ae4546-c50c-4894-a816-dc77e9866534
  tenantId: 6a170404-b749-46ec-8b35-e456a7e9a3ed
  type: SystemAssigned
  userAssignedIdentities: null
identityProfile:
  kubeletidentity:
    clientId: b89a2e2f-fc63-4070-9638-ab84c571da27
    objectId: b2991d13-f2be-4e93-a032-cc39b2a6c808
    resourceId: /subscriptions/2ae86d2a-28d5-4737-a84e-4b307ff388ef/resourcegroups/MC_rg-myfirstakscluster-westeurope_aks-myfirstcluster-westeurope_westeurope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aks-myfirstcluster-westeurope-agentpool
ingressProfile: null
kubernetesVersion: '1.31'
linuxProfile:
  adminUsername: azureuser
  ssh:
    publicKeys:
    - keyData: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCpItUKyPetlU667vf29q6FrRmqyUb1aEG85LK31Y+iyt5zH3AJ9Q8fmMFYu/Om57g2m4hsK11b/fRzQAfIbiJBA0mOjwwV+2Gv5EL4Fxpbd4rJ3LSzCp686licnzXkdUQNysCCetQUnkjuPJPCiLhpJoZmFLrMKX7Qcb/UlhwdO02rudoPUnLI2bQ2OhXq/nQyFo+kCmJetru3jUF5eCUCtZn5paKH/obGKsd+uWUVA6qD+a+5Bjd5mG2x9SMeQnnLnh+UHUfi0cdeXizabIyYXx2wsWs6bRAhU4KD7T63LPK3y50XIcUrU3oONZa1bMdvNVFXet8DL4TYPFxRHLUZ
location: westeurope
maxAgentPools: 100
metricsProfile:
  costAnalysis:
    enabled: false
name: aks-myfirstcluster-westeurope
networkProfile:
  dnsServiceIp: 10.0.0.10
  ipFamilies:
  - IPv4
  loadBalancerProfile:
    allocatedOutboundPorts: null
    backendPoolType: nodeIPConfiguration
    effectiveOutboundIPs:
    - id: /subscriptions/2ae86d2a-28d5-4737-a84e-4b307ff388ef/resourceGroups/MC_rg-myfirstakscluster-westeurope_aks-myfirstcluster-westeurope_westeurope/providers/Microsoft.Network/publicIPAddresses/c3ac0c3c-b963-48af-9a8e-0808e3891c6e
      resourceGroup: MC_rg-myfirstakscluster-westeurope_aks-myfirstcluster-westeurope_westeurope
    enableMultipleStandardLoadBalancers: null
    idleTimeoutInMinutes: null
    managedOutboundIPs:
      count: 1
      countIpv6: null
    outboundIPs: null
    outboundIpPrefixes: null
  loadBalancerSku: standard
  natGatewayProfile: null
  networkDataplane: null
  networkMode: null
  networkPlugin: kubenet
  networkPluginMode: null
  networkPolicy: null
  outboundType: loadBalancer
  podCidr: 10.244.0.0/16
  podCidrs:
  - 10.244.0.0/16
  serviceCidr: 10.0.0.0/16
  serviceCidrs:
  - 10.0.0.0/16
nodeResourceGroup: MC_rg-myfirstakscluster-westeurope_aks-myfirstcluster-westeurope_westeurope
oidcIssuerProfile:
  enabled: false
  issuerUrl: null
podIdentityProfile: null
powerState:
  code: Running
privateFqdn: null
privateLinkResources: null
provisioningState: Succeeded
publicNetworkAccess: null
resourceGroup: rg-myfirstakscluster-westeurope
resourceUid: 6820bae674b93f00015baeea
securityProfile:
  azureKeyVaultKms: null
  defender: null
  imageCleaner: null
  workloadIdentity: null
serviceMeshProfile: null
servicePrincipalProfile:
  clientId: msi
  secret: null
sku:
  name: Base
  tier: Free
storageProfile:
  blobCsiDriver: null
  diskCsiDriver:
    enabled: true
  fileCsiDriver:
    enabled: true
  snapshotController:
    enabled: true
supportPlan: KubernetesOfficial
systemData: null
tags: null
type: Microsoft.ContainerService/ManagedClusters
upgradeSettings: null
windowsProfile: null
workloadAutoScalerProfile:
  keda: null
  verticalPodAutoscaler: null
```




`az aks get-credentials --resource-group rg-myfirstakscluster-westeurope --name aks-myfirstcluster-westeurope`