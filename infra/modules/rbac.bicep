// =============================================================================
// RBAC — every role assignment in the demo, in one place.
//
// Two sets of principals are granted data-plane access:
//   1. The shared user-assigned managed identity, used by the Function, Logic
//      App, Container App and APIM at runtime.
//   2. The developer running the demo, so that F5/local debugging works through
//      DefaultAzureCredential against the real Azure resources.
//
// Everything is a built-in role, least privilege, with deterministic assignment
// names so redeployment is idempotent.
// =============================================================================

@description('Name of the Service Bus namespace to grant data access on.')
param serviceBusNamespaceName string

@description('Name of the storage account to grant data access on.')
param storageAccountName string

@description('Name of the container registry to grant pull/push on.')
param containerRegistryName string

@description('Name of the Application Insights component to grant metrics publishing on.')
param applicationInsightsName string

@description('Principal id of the shared user-assigned managed identity.')
param managedIdentityPrincipalId string

@description('Principal id of the developer or service principal running the deployment. Leave empty to skip developer grants.')
param developerPrincipalId string = ''

@description('Principal type of the developer principal.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param developerPrincipalType string = 'User'

// --- Built-in role definition ids -------------------------------------------
// Documented by name so a reviewer never has to look a GUID up.
var roles = {
  // Send messages to a Service Bus queue/topic.
  serviceBusDataSender: '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
  // Receive and complete messages from a Service Bus queue/subscription.
  serviceBusDataReceiver: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
  // Full blob data access, including container management. Required by the
  // Functions host for the deployment container and lease blobs.
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  // Queue data access for the Functions host's internal queues.
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  // Table data access for the Functions host's internal state.
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  // Pull container images.
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  // Push container images. Developer only.
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
  // Publish custom metrics/telemetry to Application Insights.
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: serviceBusNamespaceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

// --- Managed identity: Service Bus -------------------------------------------

resource miServiceBusSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: serviceBusNamespace
  name: guid(serviceBusNamespace.id, managedIdentityPrincipalId, roles.serviceBusDataSender)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataSender)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource miServiceBusReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: serviceBusNamespace
  name: guid(serviceBusNamespace.id, managedIdentityPrincipalId, roles.serviceBusDataReceiver)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataReceiver)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Managed identity: Storage (Functions host requirements) ------------------

resource miStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, managedIdentityPrincipalId, roles.storageBlobDataOwner)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource miStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, managedIdentityPrincipalId, roles.storageQueueDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageQueueDataContributor)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource miStorageTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, managedIdentityPrincipalId, roles.storageTableDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageTableDataContributor)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Managed identity: ACR + telemetry ---------------------------------------

resource miAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, managedIdentityPrincipalId, roles.acrPull)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource miMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(applicationInsights.id, managedIdentityPrincipalId, roles.monitoringMetricsPublisher)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringMetricsPublisher)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Developer grants, so local F5 debugging works ---------------------------

var grantDeveloper = !empty(developerPrincipalId)

resource devServiceBusSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeveloper) {
  scope: serviceBusNamespace
  name: guid(serviceBusNamespace.id, developerPrincipalId, roles.serviceBusDataSender)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataSender)
    principalId: developerPrincipalId
    principalType: developerPrincipalType
  }
}

resource devServiceBusReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeveloper) {
  scope: serviceBusNamespace
  name: guid(serviceBusNamespace.id, developerPrincipalId, roles.serviceBusDataReceiver)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataReceiver)
    principalId: developerPrincipalId
    principalType: developerPrincipalType
  }
}

resource devStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeveloper) {
  scope: storageAccount
  name: guid(storageAccount.id, developerPrincipalId, roles.storageBlobDataOwner)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
    principalId: developerPrincipalId
    principalType: developerPrincipalType
  }
}

resource devStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeveloper) {
  scope: storageAccount
  name: guid(storageAccount.id, developerPrincipalId, roles.storageQueueDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageQueueDataContributor)
    principalId: developerPrincipalId
    principalType: developerPrincipalType
  }
}

resource devStorageTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeveloper) {
  scope: storageAccount
  name: guid(storageAccount.id, developerPrincipalId, roles.storageTableDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageTableDataContributor)
    principalId: developerPrincipalId
    principalType: developerPrincipalType
  }
}

resource devAcrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeveloper) {
  scope: containerRegistry
  name: guid(containerRegistry.id, developerPrincipalId, roles.acrPush)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPush)
    principalId: developerPrincipalId
    principalType: developerPrincipalType
  }
}
