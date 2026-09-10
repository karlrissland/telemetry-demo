// =============================================================================
// Service Bus — namespace + the two queues that carry the demo message.
//
// Local (SAS key) auth is DISABLED. Every producer and consumer must
// authenticate with Entra ID via managed identity, which is the whole point of
// the demo's security story.
// =============================================================================

@description('Name of the Service Bus namespace. Must be globally unique.')
param serviceBusNamespaceName string

@description('Azure region for the namespace.')
param location string

@description('Tags applied to all resources in this module.')
param tags object = {}

@description('Service Bus SKU. Standard is required for topics; Basic supports queues only.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Standard'

@description('Queue that carries the message from the Logic App to the Function.')
param ordersQueueName string = 'orders'

@description('Queue that carries the message from the Function to the Container App.')
param ordersProcessedQueueName string = 'orders-processed'

@description('Log Analytics workspace resource id for diagnostic settings.')
param logAnalyticsWorkspaceId string

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    // No SAS keys. Entra ID / managed identity only.
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
  }
}

resource ordersQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: ordersQueueName
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 3
    defaultMessageTimeToLive: 'P1D'
    deadLetteringOnMessageExpiration: true
    enablePartitioning: false
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

resource ordersProcessedQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: ordersProcessedQueueName
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 3
    defaultMessageTimeToLive: 'P1D'
    deadLetteringOnMessageExpiration: true
    enablePartitioning: false
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

// Operational + runtime logs flow to the same workspace as the app telemetry so
// a dead-lettered message can be correlated with the application traces.
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: serviceBusNamespace
  name: 'sb-to-log-analytics'
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

output serviceBusNamespaceName string = serviceBusNamespace.name
output serviceBusNamespaceId string = serviceBusNamespace.id
output serviceBusFullyQualifiedNamespace string = replace(replace(serviceBusNamespace.properties.serviceBusEndpoint, 'https://', ''), ':443/', '')
output ordersQueueName string = ordersQueue.name
output ordersProcessedQueueName string = ordersProcessedQueue.name
