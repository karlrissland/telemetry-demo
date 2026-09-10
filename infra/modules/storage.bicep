// =============================================================================
// Storage — backing account for the Flex Consumption Function app.
//
// Shared key access is DISABLED. Flex Consumption is used specifically because
// it supports a fully identity-based storage configuration (AzureWebJobsStorage
// and the deployment container both via managed identity), unlike the classic
// Consumption/Premium plans which still require a content-share connection
// string.
// =============================================================================

@description('Name of the storage account. Lowercase alphanumeric, globally unique.')
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('Tags applied to the storage account.')
param tags object = {}

@description('Storage SKU.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param sku string = 'Standard_LRS'

@description('Name of the blob container that holds the Function deployment package.')
param deploymentContainerName string = 'deployments'

@description('MCAPS policy exemption tags. The MCAPS "Modify" policies StorageAccount_PublicNetwork_Modify and StorageAccount_DisableLocalAuth_Modify silently rewrite publicNetworkAccess to Disabled and allowSharedKeyAccess to false AFTER deployment, which severs the Functions host from its own storage. Both policies honour a SecurityControl=Ignore tag on the resource. Pass {} when deploying outside an MCAPS-governed tenant.')
param policyExemptionTags object = {
  SecurityControl: 'Ignore'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: union(tags, policyExemptionTags)
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  properties: {
    // No account keys. Entra ID only.
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output queueEndpoint string = storageAccount.properties.primaryEndpoints.queue
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table
output deploymentContainerName string = deploymentContainer.name
output deploymentPackageUri string = '${storageAccount.properties.primaryEndpoints.blob}${deploymentContainerName}'
