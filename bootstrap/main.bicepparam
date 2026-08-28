using './main.bicep'

// Defaults in main.bicep cover location, names and SKU. Only the principal is
// environment-specific, because it identifies a person rather than a resource.

// Object ID granted Storage Blob Data Owner on the state account, so Terraform can read,
// write and lease the state blobs. Find your own with:
//   az ad signed-in-user show --query id -o tsv
// For a CI service principal, use its object ID (not its app ID):
//   az ad sp show --id <appId> --query id -o tsv
param principalId = 'c3c8f64c-e515-4eb2-b70e-3cd55748bb08'
