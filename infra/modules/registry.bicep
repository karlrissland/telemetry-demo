// =============================================================================
// Container Registry — hosts the Python Container App image.
//
// Admin user is disabled: the Container App pulls with its user-assigned
// managed identity (AcrPull) and the developer pushes with their own identity
// (AcrPush) via `az acr login`. No registry passwords anywhere.
// =============================================================================

@description('Name of the container registry. Alphanumeric only, globally unique.')
param containerRegistryName string

@description('Azure region for the registry.')
param location string

@description('Tags applied to the registry.')
param tags object = {}

@description('Registry SKU. Basic is sufficient for a demo.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Log Analytics workspace resource id for diagnostic settings.')
param logAnalyticsWorkspaceId string

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    // No admin username/password. Entra ID only.
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: containerRegistry
  name: 'acr-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output containerRegistryName string = containerRegistry.name
output containerRegistryId string = containerRegistry.id
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
