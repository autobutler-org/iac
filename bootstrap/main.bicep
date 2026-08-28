// Bootstraps the Terraform state backend for this repo, at subscription scope.
//
// This is the one thing Terraform cannot manage, because it is the thing Terraform needs
// before it can manage anything: state has to live somewhere before there is a backend to
// put state in. Deploy it once with `make bootstrap`, then never again in the normal
// course of work. See README.md.
//
//   make bootstrap/whatif   # preview
//   make bootstrap          # deploy

targetScope = 'subscription'

@description('Azure region for the state resource group and storage account.')
param location string = 'eastus'

@description('Resource group that holds the Terraform state storage account.')
param resourceGroupName string = 'autobutler-tfstate'

@description('Globally unique name of the storage account holding Terraform state.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'stautobutlertfstate'

@description('Name of the blob container that holds the .tfstate blobs.')
param containerName string = 'tfstate'

@description('Object ID granted Storage Blob Data Owner on the state account. Empty skips the role assignment.')
param principalId string = ''

@description('Replication SKU. State blobs are tiny, so geo-redundancy is close to free.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_GZRS'
])
param skuName string = 'Standard_GRS'

@description('Tags applied to the state resource group and storage account.')
param tags object = {
  managed_by: 'bicep'
  repo: 'autobutler-org/iac'
  purpose: 'terraform-state'
}

resource stateResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module stateStorage 'modules/state-storage.bicep' = {
  scope: stateResourceGroup
  name: 'terraform-state-storage'
  params: {
    location: location
    storageAccountName: storageAccountName
    containerName: containerName
    principalId: principalId
    skuName: skuName
    tags: tags
  }
}

@description('Resource group holding the Terraform state storage account.')
output resourceGroupName string = stateResourceGroup.name

@description('Name of the storage account holding Terraform state.')
output storageAccountName string = stateStorage.outputs.storageAccountName

@description('Name of the blob container holding the .tfstate blobs.')
output containerName string = stateStorage.outputs.containerName

@description('Primary blob service endpoint of the state account.')
output blobEndpoint string = stateStorage.outputs.blobEndpoint
