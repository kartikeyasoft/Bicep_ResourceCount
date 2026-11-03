targetScope = 'resourceGroup'

@description('Environment name used for resource naming and tagging.')
@allowed([
  'dev'
  'qa'
  'prod'
])
param environment string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Workload name: use 2-8 lowercase letters or numbers. deploy.ps1 validates this naming convention.')
@minLength(2)
@maxLength(8)
param workloadName string = 'webapp'

@description('Virtual network address space.')
param vnetAddressPrefix string

@description('Subnet address prefix.')
param subnetAddressPrefix string

@description('Number of Ubuntu virtual machines to deploy. Each VM receives its own NIC and public IP.')
@minValue(1)
@maxValue(10)
param vmCount int = 1

@description('Linux VM administrator username.')
param adminUsername string = 'azureuser'

@description('SSH public key for the Linux VMs. Pass this at deployment time; never put a private key in Bicep.')
@secure()
param sshPublicKey string

@description('Linux VM size used for every VM.')
param vmSize string = 'Standard_B2s'

@description('Ubuntu image version.')
param imageVersion string = 'latest'

var namePrefix = '${workloadName}-${environment}'
var commonTags = {
  environment: environment
  workload: workloadName
  managedBy: 'Bicep'
}

// One shared network is used by all VM instances in this environment.
module network './modules/network.bicep' = {
  name: 'network-${environment}'
  params: {
    namePrefix: namePrefix
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    subnetAddressPrefix: subnetAddressPrefix
    tags: commonTags
  }
}

// Each VM gets a separate Standard static public IP address.
@batchSize(5)
module publicIps './modules/publicIp.bicep' = [for i in range(0, vmCount): {
  name: 'public-ip-${environment}-${i + 1}'
  params: {
    namePrefix: (i == 0 ? namePrefix : '${namePrefix}-${i + 1}')
    location: location
    tags: union(commonTags, {
      instance: '${i + 1}'
    })
  }
}]

// Each VM gets a separate NIC attached to the shared subnet and its matching public IP.
@batchSize(5)
module nics './modules/nic.bicep' = [for i in range(0, vmCount): {
  name: 'nic-${environment}-${i + 1}'
  params: {
    namePrefix: (i == 0 ? namePrefix : '${namePrefix}-${i + 1}')
    location: location
    subnetId: network.outputs.subnetId
    publicIpId: publicIps[i].outputs.publicIpId
    tags: union(commonTags, {
      instance: '${i + 1}'
    })
  }
}]

// Deploy the requested number of VMs. Each VM is connected to its matching NIC.
@batchSize(5)
module vmModules './modules/vm.bicep' = [for i in range(0, vmCount): {
  name: 'vm-${environment}-${i + 1}'
  params: {
    namePrefix: (i == 0 ? namePrefix : '${namePrefix}-${i + 1}')
    location: location
    vmSize: vmSize
    nicId: nics[i].outputs.nicId
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    tags: union(commonTags, {
      instance: '${i + 1}'
    })
  }
}]

// Return one object per VM, including the public IP and a ready-to-use SSH command.
output virtualMachines array = [for i in range(0, vmCount): {
  name: vmModules[i].outputs.vmName
  resourceId: vmModules[i].outputs.vmId
  nicName: nics[i].outputs.nicName
  publicIpAddress: publicIps[i].outputs.publicIpAddress
  sshCommand: 'ssh -i <path-to-private-key> ${adminUsername}@${publicIps[i].outputs.publicIpAddress}'
}]

output virtualMachineCount int = vmCount
output virtualNetworkName string = network.outputs.vnetName
output subnetName string = network.outputs.subnetName
output networkSecurityGroupName string = network.outputs.nsgName
