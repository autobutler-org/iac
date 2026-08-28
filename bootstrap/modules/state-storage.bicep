// The Terraform state backend itself: one storage account, one container, and the access
// and durability settings that make losing state hard.
//
// Deployed by ../main.bicep, which owns the resource group. Nothing in this file is
// managed by Terraform -- see ../README.md for why.

@description('Azure region for the storage account. Should match the resource group.')
param location string

@description('Globally unique name of the storage account holding Terraform state.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Name of the blob container that holds the .tfstate blobs.')
param containerName string

@description('Object ID granted Storage Blob Data Owner on the account. Empty skips the role assignment.')
param principalId string

@description('Replication SKU for the state account.')
param skuName string

@description('Tags applied to the storage account.')
param tags object

// Storage Blob Data Owner. Terraform needs read+write on the state blob and the ability to
// take and break the blob lease it uses for state locking; Contributor covers the first two
// but not lease-break, which is what `terraform force-unlock` needs.
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true

    // State blobs are never public, and the container below is private regardless. This
    // closes the door at the account level so no container can opt back in by accident.
    allowBlobPublicAccess: false

    // No account keys. Every caller authenticates as an Entra ID principal, which is why
    // every Terraform backend block in this repo sets `use_azuread_auth = true` and omits
    // `resource_group_name` -- that argument only exists to drive the key lookup this
    // setting makes impossible. A leaked key cannot be the way state gets read, because
    // there is no key that works.
    allowSharedKeyAccess: false

    allowCrossTenantReplication: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// The state recovery story. Versioning keeps every prior state blob, so a bad apply or a
// clobbered upload is recoverable by promoting the previous version rather than by hunting
// for someone's local copy. The delete retention windows cover the case where the blob or
// the whole container is removed outright.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

resource stateAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, storageBlobDataOwnerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: principalId
  }
}

// Deleting this account destroys every stack's state at once, and no amount of blob
// versioning survives the account going away. The lock makes that a two-step, deliberate
// act. To actually delete the account:
//   az lock delete --name no-accidental-deletion \
//     --resource-group <rg> --resource-name <account> \
//     --namespace Microsoft.Storage --resource-type storageAccounts
resource deleteLock 'Microsoft.Authorization/locks@2020-05-01' = {
  scope: storageAccount
  name: 'no-accidental-deletion'
  properties: {
    level: 'CanNotDelete'
    notes: 'Holds Terraform state for every stack in this repo. Remove this lock by hand before any intentional deletion.'
  }
}

@description('Name of the storage account holding Terraform state.')
output storageAccountName string = storageAccount.name

@description('Name of the blob container holding the .tfstate blobs.')
output containerName string = container.name

@description('Primary blob service endpoint of the state account.')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
