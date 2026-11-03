using '../main.bicep'

param environment = 'dev'
param location = 'eastus'
param workloadName = 'webapp'
param vnetAddressPrefix = '10.10.0.0/16'
param subnetAddressPrefix = '10.10.1.0/24'

// DEV example: deploy two VM instances. Change this value from 1 to 10 as needed.
param vmCount = 10

param adminUsername = 'azureuser'
param vmSize = 'Standard_B2s'

// The deployment helper loads the SSH public key into this process environment variable.
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
