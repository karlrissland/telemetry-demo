// =============================================================================
// Logic App Standard — receives the HTTP request from APIM and publishes the
// message to Service Bus.
//
// Refactored from the original standalone template to take the SHARED
// user-assigned managed identity and the SHARED Application Insights component
// as parameters, instead of creating its own. That keeps every hop reporting to
// one telemetry component under one RBAC principal.
//
// NOTE: this is a demo template. It intentionally does not use an Azure Files
// content share, which limits scale but avoids a storage connection string.
//
// No workflows are deployed here. The host is provisioned empty and workflow
// definitions are pushed later by a PowerShell azd hook.
// =============================================================================

@description('Name of the Logic App Standard site.')
param logicAppName string

@description('Name of the WorkflowStandard hosting plan.')
param hostingPlanName string

@description('Name of the storage account backing the Logic App runtime.')
param storageAccountName string

@description('Azure region for all resources in this module.')
param location string

@description('Tags applied to all resources in this module.')
param tags object = {}

@description('Storage account SKU.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Resource id of the shared user-assigned managed identity.')
param userAssignedIdentityId string

@description('Principal id of the shared user-assigned managed identity.')
param userAssignedIdentityPrincipalId string

@description('Client id of the shared user-assigned managed identity.')
param userAssignedIdentityClientId string

@description('Application Insights connection string.')
param applicationInsightsConnectionString string

@description('Fully qualified Service Bus namespace, e.g. sb-demo.servicebus.windows.net.')
param serviceBusFullyQualifiedNamespace string

@description('Name of the queue the workflow publishes to.')
param ordersQueueName string

@description('Log Analytics workspace resource id for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('WorkflowStandard plan SKU.')
@allowed([
  'WS1'
  'WS2'
  'WS3'
])
param planSku string = 'WS1'

@description('MCAPS policy exemption tags applied to the Logic App storage account. Logic App Standard backs its runtime with Azure Files, which does NOT support managed identity and therefore requires allowSharedKeyAccess=true. The MCAPS Modify policies StorageAccount_DisableLocalAuth_Modify and StorageAccount_PublicNetwork_Modify would rewrite that to false and disable public network access after deployment, breaking the workflow host. Both honour a SecurityControl=Ignore tag on the resource. Pass {} outside an MCAPS-governed tenant.')
param policyExemptionTags object = {
  SecurityControl: 'Ignore'
}

var managementBaseUri = environment().resourceManager
var blobEndpoint = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var queueEndpoint = 'https://${storageAccountName}.queue.${environment().suffixes.storage}'
var tableEndpoint = 'https://${storageAccountName}.table.${environment().suffixes.storage}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: union(tags, policyExemptionTags)
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    // Logic App Standard backs its runtime with Azure Files, and Azure Files does
    // not support managed identity. Shared key access must stay enabled on THIS
    // account or the workflow host will not start. This is the single documented
    // exception to the no-keys rule and it is a platform limitation.
    //
    // In MCAPS the StorageAccount_DisableLocalAuth_Modify policy would flip this
    // back to false after deployment; the SecurityControl=Ignore tag above is what
    // prevents that.
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
  }
}

resource workflowPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: planSku
    tier: 'WorkflowStandard'
    size: planSku
    family: 'WS'
    capacity: 1
  }
  properties: {
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
    reserved: false
  }
}

resource logicApp 'Microsoft.Web/sites@2024-04-01' = {
  name: logicAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'logicapp' })
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: workflowPlan.id
    clientAffinityEnabled: false
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        // --- Host storage, via managed identity ---
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: blobEndpoint
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: queueEndpoint
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: tableEndpoint
        }
        {
          name: 'AzureWebJobsStorage__managedIdentityResourceId'
          value: userAssignedIdentityId
        }
        // --- Workflow runtime ---
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        {
          name: 'FUNCTIONS_INPROC_NET8_ENABLED'
          value: '1'
        }
        {
          name: 'WORKFLOWS_MANAGEMENT_BASE_URI'
          value: managementBaseUri
        }
        // --- Telemetry ---
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        // --- Service Bus built-in ("in-app") connector, via managed identity.
        // The built-in connector is required here; the managed API connector
        // variant persists an access key in an API connection resource.
        {
          name: 'serviceBus_fullyQualifiedNamespace'
          value: serviceBusFullyQualifiedNamespace
        }
        {
          name: 'ORDERS_QUEUE_NAME'
          value: ordersQueueName
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
      ]
    }
  }
}

resource scmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: logicApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: logicApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

// Storage data-plane roles for the Logic App runtime. These are scoped to this
// module's own storage account, so they live here rather than in rbac.bicep.
var roles = {
  // Storage Account Contributor. Grants listKeys, which is how the Logic App
  // Standard runtime obtains the Azure Files key for its content share. Azure
  // Files does not support managed identity, so this role — not a data-plane
  // file role — is what makes the workflow host start.
  storageAccountContributor: '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  // Storage Blob Data Owner
  blobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  // Storage Queue Data Contributor
  queueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  // Storage Table Data Contributor
  tableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
}

resource roleStorageAccountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, userAssignedIdentityPrincipalId, roles.storageAccountContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageAccountContributor)
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource roleBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, userAssignedIdentityPrincipalId, roles.blobDataOwner)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataOwner)
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource roleQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, userAssignedIdentityPrincipalId, roles.queueDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.queueDataContributor)
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource roleTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, userAssignedIdentityPrincipalId, roles.tableDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.tableDataContributor)
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: logicApp
  name: 'logicapp-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
      }
      {
        category: 'WorkflowRuntime'
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

output logicAppName string = logicApp.name
output logicAppId string = logicApp.id
output logicAppHostName string = logicApp.properties.defaultHostName
output logicAppUrl string = 'https://${logicApp.properties.defaultHostName}'
output logicAppPlanName string = workflowPlan.name
output logicAppStorageName string = storageAccount.name
