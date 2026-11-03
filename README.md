# Azure VM Deployment with Bicep (DEV / QA / PROD)

A modular Azure Bicep project that deploys between 1 and 10 Ubuntu Server 22.04 LTS Gen2 VMs with SSH public-key authentication. The same root template is reused for DEV, QA, and PROD through separate `.bicepparam` files. The VM count is controlled by the `vmCount` parameter and Bicep module loops.

> **Important:** This is a learning / baseline deployment, not a complete production landing zone. Review the production considerations near the end of this file before using it for workloads.

## What the project creates

- One shared virtual network, subnet, and network security group per environment. The NSG has an `Allow-All-Inbound` rule for all inbound protocols and ports from any source (`*`), intentionally permissive for a temporary lab only.
- One Standard SKU, static IPv4 public IP per VM instance.
- One network interface per VM, connected to the shared subnet and that VM instance’s public IP.
- The requested number of Ubuntu Server 22.04 LTS Gen2 VMs, each using SSH public-key authentication (password authentication is disabled).

The root template (`main.bicep`) creates the shared network once, then uses Bicep `for` loops to deploy one public IP, one NIC, and one VM module instance for each requested VM. Each NIC is linked to the public IP with the same instance index, and each VM is linked to its matching NIC. The deployment output returns a `virtualMachines` array containing each VM name, resource ID, NIC name, public IP, and SSH command.

## Project structure

```text
azure_bicep_vm_project/
├── main.bicep
├── README.md
├── parameters/
│   ├── dev.bicepparam
│   ├── qa.bicepparam
│   └── prod.bicepparam
└── modules/
    ├── network.bicep
    ├── publicIp.bicep
    ├── nic.bicep
    └── vm.bicep
```


## VM count and naming

The root template exposes this parameter:

```bicep
@description('Number of Ubuntu virtual machines to deploy. Each VM receives its own NIC and public IP.')
@minValue(1)
@maxValue(10)
param vmCount int = 1
```

The value must be from 1 through 10. Bicep uses `range(0, vmCount)` to create matching public IP, NIC, and VM module instances. All instances in an environment share one VNet, subnet, and NSG. Each instance gets its own Standard static public IP and NIC.

The supplied environment values are deliberately cost-conscious:

| Environment | `vmCount` by default |
|---|---:|
| DEV | 10 |
| QA | 1 |
| PROD | 1 |

To change the number, edit the relevant `.bicepparam` file. For example, to deploy ten DEV VMs:

```bicep
param vmCount = 10
```

To deploy only one DEV VM, change it to `param vmCount = 1`. The first instance keeps the original single-VM names so an existing deployment can be adopted rather than creating a duplicate: `webapp-dev-vm`, `webapp-dev-nic`, and `webapp-dev-pip`. Additional instances use numbered suffixes, such as `webapp-dev-2-vm`, `webapp-dev-2-nic`, and `webapp-dev-2-pip`, continuing up to the configured count.

**Capacity and cost:** Ten `Standard_B2s` VMs require sufficient regional and VM-family vCPU quota and available capacity. This design also creates ten public IP addresses and ten NICs. Check the subscription quota and expected compute/network charges before deploying. The DEV parameter file defaults to ten VMs for demonstration; QA and PROD remain at one VM unless you change their parameter files. When upgrading this project from the original single-VM version, the first VM, NIC, and public IP retain their original resource names; the extra instances are added with numbered names.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+.
- Azure CLI 2.53.0 or later and Bicep CLI 0.22.x or later for deployment with linked `.bicepparam` files. The parameter files also use `readEnvironmentVariable()`.
- An Azure subscription with permission to create resource groups, virtual networks, network security groups, public IPs, NICs, and virtual machines.
- An SSH key pair.

Check the tools:

```powershell
az version
az bicep version
```

Install or update Bicep through Azure CLI:

```powershell
az bicep install
# If Bicep is already installed and you want the latest version:
az bicep upgrade
az bicep version
```

Sign in and select the intended subscription:

```powershell
az login
az account list --output table
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
az account show --output table
```

## 1. Prepare an SSH key pair

Create an Ed25519 key pair if you do not already have one:

```powershell
ssh-keygen -t ed25519 -C "azure-bicep-vm"
```

The default public key path used by the helper script is:

```text
$HOME\.ssh\id_ed25519.pub
```

The private key is `id_ed25519` (without `.pub`). Keep it private. Only the `.pub` public key is passed to the VM deployment.

## 2. Review the NSG inbound rule

The current lab configuration in `modules/network.bicep` deliberately allows all inbound traffic:

```bicep
{
  name: 'Allow-All-Inbound'
  properties: {
    description: 'Allow all inbound traffic from any source. For lab use only.'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 1000
    direction: 'Inbound'
  }
}
```

This means any source can attempt to reach any listening service on the VM. It is unsafe for production and should only be used temporarily in an isolated learning environment. Prefer a narrow source CIDR and only the required ports (for example, TCP/22 from your current public IP) for normal use. The project no longer requires an `adminCidr` parameter because the NSG rule is not restricted to a particular administrator IP.

The `workloadName` must be 2-8 lowercase letters or digits, for example `webapp`. Bicep supports length decorators but does not provide a `@pattern()` decorator. The supplied `deploy.ps1` script checks the lowercase/digit naming rule before it creates Azure resources. If you deploy by another method, follow the same naming rule yourself.

## 3. SSH public-key handling (BCP258 fix)

`main.bicep` declares `sshPublicKey` as a required secure string. Each `.bicepparam` file assigns it by reading an environment variable:

```bicep
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
```

The deployment script reads the `.pub` file, trims the newline, and sets the process environment variable before running Azure CLI. This approach:

- Satisfies the parameter-file requirement (the parameter is assigned in the `.bicepparam` file).
- Avoids placing the key directly in the command-line arguments.
- Keeps the key content out of the repository and parameter file.
- Passes the value to the `@secure()` Bicep parameter.

Do not add the private key to any Bicep file, parameter file, script, or source control.

## 4. Compile and validate the Bicep template

Run from the project root (the folder containing `main.bicep`):

```powershell
az bicep build --file .\main.bicep
az bicep build --file .\modules\network.bicep
az bicep build --file .\modules\publicIp.bicep
az bicep build --file .\modules\nic.bicep
az bicep build --file .\modules\vm.bicep
```

The first command compiles the root template and its referenced local modules. The other commands are optional individual module checks. Fix all compiler errors before deploying.


## 6. Manual DEV deployment (without deploy.ps1)

The `.bicepparam` file contains `using '../main.bicep'`. Therefore, when deploying with this linked parameter file, specify the parameter file with `--parameters` and **do not also specify `--template-file`**.

First, create the resource group (use the same location configured in `dev.bicepparam`):

```powershell
az group create --name rg-webapp-dev --location eastus
```

Load the public key into the environment variable referenced by the parameter file:

```powershell
$env:AZURE_BICEP_SSH_PUBLIC_KEY = (Get-Content "$HOME\.ssh\id_ed25519.pub" -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($env:AZURE_BICEP_SSH_PUBLIC_KEY)) {
    throw 'SSH public key is empty.'
}
```

Validate:

```powershell
az deployment group validate `
  --name validate-webapp-dev `
  --resource-group rg-webapp-dev `
  --parameters .\parameters\dev.bicepparam
```

Preview:

```powershell
az deployment group what-if `
  --name whatif-webapp-dev `
  --resource-group rg-webapp-dev `
  --parameters .\parameters\dev.bicepparam
```

Deploy:

```powershell
az deployment group create `
  --name deploy-webapp-dev `
  --resource-group rg-webapp-dev `
  --parameters .\parameters\dev.bicepparam
```

Note that the parameter file is linked to `main.bicep`, so these commands intentionally omit `--template-file`. Microsoft documents that combining `--template-file` with a linked `.bicepparam` file can produce an error. The same pattern applies to QA and PROD: change the resource group, deployment name, and parameter file.

## 7. Verify the deployment

View the deployment outputs:

```powershell
az deployment group show `
  --resource-group rg-webapp-dev `
  --name deploy-webapp-dev `
  --query properties.outputs `
  --output json
```

List the deployed resources:

```powershell
az vm list -g rg-webapp-dev -d --output table
az network public-ip list -g rg-webapp-dev --output table
az network nic list -g rg-webapp-dev --output table
az network vnet list -g rg-webapp-dev --output table
az network nsg list -g rg-webapp-dev --output table
```

Connect to any deployed VM using SSH. The deployment output contains one SSH command per VM. For example:

```powershell
ssh -i "$HOME\.ssh\id_ed25519" azureuser@<VM_PUBLIC_IP>
```

Replace `<VM_PUBLIC_IP>` with the matching address from the `virtualMachines` output array. Use the username configured in the environment parameter file (`azureuser` for DEV/QA and `azureadmin` for PROD). The current lab NSG allows inbound traffic from any source; the private key is still required for SSH authentication.

## Troubleshooting

### BCP057: `pattern` does not exist in the current context

Bicep does not support an `@pattern()` decorator. The project removes that decorator, keeps the built-in `@minLength(2)` and `@maxLength(8)` checks, and validates the lowercase-alphanumeric convention in `deploy.ps1` instead.

### BCP258: `sshPublicKey` is missing from the params file

Check that each environment `.bicepparam` file contains:

```bicep
param sshPublicKey = readEnvironmentVariable('AZURE_BICEP_SSH_PUBLIC_KEY')
```

For manual deployment, set `$env:AZURE_BICEP_SSH_PUBLIC_KEY` before running the Azure CLI command. For scripted deployment, `deploy.ps1` sets it for you.

### Error: `Only a .bicep file is allowed with a .bicepparam file`

The parameter file already contains a `using '../main.bicep'` declaration. Remove `--template-file` from the deployment command and pass only the `.bicepparam` file after `--parameters`.

### SSH connection times out

- Confirm the NSG is associated with the subnet and that the `Allow-All-Inbound` rule is present and enabled.
- Remember that this open rule exposes listening services; restrict it after lab connectivity testing.
- Confirm the VM is running and the public IP is attached.

### SSH reports `Permission denied (publickey)`

- Use the private key that matches the public key supplied during deployment.
- Use the correct Linux username from the environment parameter file.
- Do not use the `.pub` file with SSH `-i`; pass the private key file.

### VM count, quota, or capacity errors

The template allows `vmCount` from 1 through 10. A deployment of ten VMs can fail if the subscription does not have enough regional or VM-family vCPU quota, or if the selected SKU has insufficient regional capacity. Reduce `vmCount`, request a quota increase, or select an available VM size. Remember that each VM also creates its own NIC and Standard static public IP.

### VM size or image is unavailable

A VM SKU can be unavailable in a region or subscription because of quota or capacity. Check available sizes and quotas, then adjust `vmSize` in the relevant `.bicepparam` file if needed. If the Ubuntu image SKU is unavailable in your region, select a supported Canonical Ubuntu 22.04 Gen2 image reference.

### Deployment fails after partially creating resources

Inspect the deployment error and operation details:

```powershell
az deployment group show `
  --resource-group rg-webapp-dev `
  --name deploy-webapp-dev `
  --query properties.error `
  --output json

az deployment operation group list `
  --resource-group rg-webapp-dev `
  --name deploy-webapp-dev `
  --output table
```

## Cleanup

Deleting the resource group deletes the resources in that environment and stops their associated ongoing charges:

```powershell
az group delete --name rg-webapp-dev --yes --no-wait
```

Repeat only for environments you intentionally want to remove.

## Production considerations

Before production use, consider private access or Azure Bastion, Just-in-Time VM access, Azure Backup, monitoring and alerting, patch management, disk encryption, availability architecture, policy enforcement, private networking, and cost controls. Each running VM and each public IP can incur charges. A ten-VM DEV deployment can therefore cost materially more than the original single-VM deployment. The current `Allow-All-Inbound` NSG rule exposes every VM in the shared subnet and is deliberately insecure; replace it with least-privilege rules before production use.

## Official references

- [Bicep file structure and supported decorators](https://learn.microsoft.com/azure/azure-resource-manager/bicep/file)
- [Create and use Bicep parameter files](https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files)
- [Deploy Bicep files with Azure CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-cli)
