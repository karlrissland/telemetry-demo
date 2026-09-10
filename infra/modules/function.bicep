// =============================================================================
// Function — .NET 8 isolated worker on the Flex Consumption plan.
//
// Flex Consumption is chosen deliberately: it is the only Functions hosting
// plan where BOTH the AzureWebJobsStorage account and the deployment package
// container can be accessed with a managed identity. Classic Consumption and
// Elastic Premium still require a WEBSITE_CONTENTAZUREFILECONNECTIONSTRING,
// which would break the "no connection strings" rule this demo is built on.
//
// No application code is deployed here. The host is provisioned empty and the
// code is pushed later by a PowerShell azd hook.
// =============================================================================

@description('Name of the function app.')
param functionAppName string

@description('Name of the Flex Consumption hosting plan.')
param hostingPlanName string

@description('Azure region for the function app.')
param location string

@description('Tags applied to all resources in this module.')
param tags object = {}

@description('Resource id of the user-assigned managed identity the app runs as.')
param userAssignedIdentityId string

@description('Client id of the user-assigned managed identity, used by the identity-based app settings.')
param userAssignedIdentityClientId string

@description('Blob service URI of the Function storage account.')
param storageBlobEndpoint string

@description('Blob container URI that holds the deployment package.')
param deploymentPackageContainerUri string

@description('Application Insights connection string.')
param applicationInsightsConnectionString string

@description('Fully qualified Service Bus namespace, e.g. sb-demo.servicebus.windows.net.')
param serviceBusFullyQualifiedNamespace string

@description('Name of the inbound queue the Function triggers on.')
param ordersQueueName string

@description('Name of the outbound queue the Function publishes to.')
param ordersProcessedQueueName string

@description('Memory per instance in MB.')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

@description('Maximum number of instances the app can scale to.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 40

@description('Log Analytics workspace resource id for diagnostic settings.')
param logAnalyticsWorkspaceId string

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'function' })
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: deploymentPackageContainerUri
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: userAssignedIdentityId
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        // --- Host storage, via managed identity (no keys) ---
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageBlobEndpoint
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: userAssignedIdentityClientId
        }
        // --- Telemetry ---
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        // --- Service Bus trigger/output binding, via managed identity ---
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: serviceBusFullyQualifiedNamespace
        }
        {
          name: 'ServiceBusConnection__credential'
          value: 'managedidentity'
        }
        {
          name: 'ServiceBusConnection__clientId'
          value: userAssignedIdentityClientId
        }
        // --- Application configuration consumed by the Function code ---
        {
          name: 'ORDERS_QUEUE_NAME'
          value: ordersQueueName
        }
        {
          name: 'ORDERS_PROCESSED_QUEUE_NAME'
          value: ordersProcessedQueueName
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
      ]
    }
  }
}

// Key-based publishing is turned off; deployments go through the identity-based
// blob container configured above.
resource scmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: functionApp
  name: 'func-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FunctionAppLogs'
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

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output functionAppHostName string = functionApp.properties.defaultHostName
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output hostingPlanName string = hostingPlan.name
