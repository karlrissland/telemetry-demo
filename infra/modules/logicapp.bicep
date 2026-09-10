//NOTE: this template is written to support Logic Apps Deployment with Managed Identity.
//  this is not a production ready template.  Not leveraging Azure File Shares will limit this
//  resources ability to scale.

@description('The name of the function app that you wish to create.')
param appName string = 'logic-${uniqueString(resourceGroup().id)}'

@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Location for all resources.')
param location string = resourceGroup().location

param applicationInsightsName string
param userAssignedIdentityName string

var logicAppName = appName
var hostingPlanName = appName
var storageAccountName = '${uniqueString(resourceGroup().id)}logicapp'
var managementbaseuri = environment().resourceManager
// ADDED: Cloud-agnostic storage endpoint variables (Option A)
var blobEndpoint = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var queueEndpoint = 'https://${storageAccountName}.queue.${environment().suffixes.storage}'
var tableEndpoint = 'https://${storageAccountName}.table.${environment().suffixes.storage}'
// ALTERNATIVE (Option B - comment out Option A above and use these directly in appSettings):
// var blobEndpoint = storageAccount.properties.primaryEndpoints.blob
// var queueEndpoint = storageAccount.properties.primaryEndpoints.queue
// var tableEndpoint = storageAccount.properties.primaryEndpoints.table

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: {}
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: []
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userAssignedIdentityName
  location: location
}

resource workflowPlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: hostingPlanName
  location: location
  kind: 'elastic'
  tags: {}
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
    size: 'WS1'
    family: 'WS'
    capacity: 1
  }
  dependsOn: []
}

resource logicApp 'Microsoft.Web/sites@2022-03-01' = {
  name: logicAppName
  kind: 'functionapp,workflowapp'
  location: location
  properties: {
    siteConfig: {
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
          value: userAssignedIdentity.id
        }
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
          name: 'LOGIC_APPS_POWERSHELL_VERSION'
          value: '7.4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'WORKFLOWS_MANAGEMENT_BASE_URI'
          value: managementbaseuri
        }
      ]
    }
    clientAffinityEnabled: false
    virtualNetworkSubnetId: null
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    serverFarmId: resourceId('Microsoft.Web/serverfarms', hostingPlanName)
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  dependsOn: [
    workflowPlan
  ]
}

resource name_scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = {
  parent: logicApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource name_ftp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = {
  parent: logicApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

//Note
// - 17d1049b-9a84-46fb-8f53-869881c3d3ab = Storage File Data SMB Share Elevated Contributor
// - b7e6dc6d-f1e8-4753-8033-0f276bb0955b = Storage Blob Data Owner
// - 974c5e8b-45b9-4653-ba55-5f855dd0fb88 = Storage Queue Data Contributor
// - 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3 = Storage Table Data Contributor 
//Note
// - 17d1049b-9a84-46fb-8f53-869881c3d3ab = Storage File Data SMB Share Elevated Contributor
// - b7e6dc6d-f1e8-4753-8033-0f276bb0955b = Storage Blob Data Owner
// - 974c5e8b-45b9-4653-ba55-5f855dd0fb88 = Storage Queue Data Contributor

resource roleDefinition_Storage_File_Data_SMB_Share_Elevated_Contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, logicAppName, '/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab')
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab'
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleDefinition_Storage_Blob_Data_Owner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, logicAppName, '/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleDefinition_Storage_Queue_Data_Contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, logicAppName, '/providers/Microsoft.Authorization/roleDefinitions/974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/974c5e8b-45b9-4653-ba55-5f855dd0fb88'
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleDefinition_Storage_Table_Data_Contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, logicAppName, '/providers/Microsoft.Authorization/roleDefinitions/0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output logicappAppName string = logicApp.name
output logicappAppId string = logicApp.id
output logicappPlanId string = workflowPlan.id
output logicappPlanName string = workflowPlan.name
output logicappStorageName string = storageAccount.name
output logicappStorageId string = storageAccount.id
