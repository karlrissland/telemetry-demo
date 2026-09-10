// =============================================================================
// Container App — Python consumer of the orders-processed queue.
//
// Provisioned with the public quickstart image as a placeholder. The real image
// is built, pushed to ACR, and rolled out by a PowerShell azd hook once the
// application code exists.
//
// Registry authentication uses the user-assigned managed identity (AcrPull).
// There are no registry credentials in the template or in app configuration.
// =============================================================================

@description('Name of the Container Apps managed environment.')
param containerAppsEnvironmentName string

@description('Name of the container app.')
param containerAppName string

@description('Azure region for all resources in this module.')
param location string

@description('Tags applied to all resources in this module.')
param tags object = {}

@description('Resource id of the user-assigned managed identity the app runs as.')
param userAssignedIdentityId string

@description('Client id of the user-assigned managed identity.')
param userAssignedIdentityClientId string

@description('Login server of the container registry, e.g. crdemo.azurecr.io.')
param containerRegistryLoginServer string

@description('Application Insights connection string.')
param applicationInsightsConnectionString string

@description('Fully qualified Service Bus namespace.')
param serviceBusFullyQualifiedNamespace string

@description('Name of the queue this app consumes.')
param ordersProcessedQueueName string

@description('Log Analytics workspace resource id, used by the managed environment.')
param logAnalyticsWorkspaceId string

@description('Log Analytics workspace customer (workspace) id.')
param logAnalyticsCustomerId string

@description('Container image to deploy. Defaults to a placeholder until the real image is pushed.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Set to true once a real image exists in ACR so registry auth is configured.')
param useAcrImage bool = false

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        // The environment's log shipper requires the workspace shared key. This is
        // a platform limitation of Container Apps, not an application credential —
        // it is read at deploy time and never stored in the repo.
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'containerapp' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: useAcrImage ? [
        {
          server: containerRegistryLoginServer
          identity: userAssignedIdentityId
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'app'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'SERVICE_BUS_FQDN'
              value: serviceBusFullyQualifiedNamespace
            }
            {
              name: 'ORDERS_PROCESSED_QUEUE_NAME'
              value: ordersProcessedQueueName
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: userAssignedIdentityClientId
            }
            {
              name: 'OTEL_SERVICE_NAME'
              value: containerAppName
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

output containerAppsEnvironmentName string = containerAppsEnvironment.name
output containerAppsEnvironmentId string = containerAppsEnvironment.id
output containerAppName string = containerApp.name
output containerAppId string = containerApp.id
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
