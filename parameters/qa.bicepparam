using '../main.bicep'

param environment = 'qa'
param location = 'eastus'
param workloadName = 'webapp'
param vnetAddressPrefix = '10.20.0.0/16'
param subnetAddressPrefix = '10.20.1.0/24'

// Keep non-DEV environments at one VM by default to control costs.
param vmCount = 1

param adminUsername = 'azureuser'
param vmSize = 'Standard_B2s'

// The deployment helper loads the SSH public key into this process environment variable.
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
