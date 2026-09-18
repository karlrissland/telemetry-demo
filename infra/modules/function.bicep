// Deploys the .NET isolated Azure Function App and secures it so that only callers
// presenting a Microsoft Entra ID token issued to an authorized caller identity
// (e.g. the Logic App's managed identity) can invoke it. No function keys required.

extension microsoftGraph
// bicepconfig.json in this folder pins the microsoftGraph extension to a specific
// dynamic-types version. See https://aka.ms/graphbicep/dynamictypes.

@description('The name of the function app that you wish to create.')
param appName string = 'func-${uniqueString(resourceGroup().id)}'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Name of an existing Application Insights component to link telemetry to.')
param applicationInsightsName string

@description('Client ID of the managed identity allowed to call this function app.')
param authorizedClientId string

@description('Principal/object ID of the managed identity allowed to call this function app.')
param authorizedPrincipalId string

@description('The .NET isolated worker runtime version to target on Linux Elastic Premium.')
param dotnetVersion string = '10'

var hostingPlanName = appName
var storageAccountName = '${uniqueString(resourceGroup().id)}func'
var functionAppRoleId = guid(resourceGroup().id, appName, 'FunctionInvoker')

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
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
}

resource hostingPlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: hostingPlanName
  location: location
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
  }
  properties: {
    reserved: true
    maximumElasticWorkerCount: 20
  }
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|${dotnetVersion}'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
  }
}

resource name_scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = {
  parent: functionApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource name_ftp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01' = {
  parent: functionApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

// Storage Blob/Queue/Table Data Contributor so the function app's own identity can use AzureWebJobsStorage.
resource roleAssignment_StorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, appName, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignment_StorageQueueDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, appName, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignment_StorageTableDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, appName, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- Microsoft Entra ID app registration representing this function app as an OAuth resource ---
// No identifierUris: tenant policy requires custom App ID URIs to contain a verified domain,
// tenant ID, or app ID. Using v2 access tokens avoids needing one - the audience is the appId itself.
resource functionAadApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appName
  displayName: appName
  api: {
    requestedAccessTokenVersion: 2
  }
  appRoles: [
    {
      id: functionAppRoleId
      displayName: 'Function Invoker'
      description: 'Allows calling the ${appName} function app.'
      value: 'Function.Invoke'
      allowedMemberTypes: [
        'Application'
      ]
      isEnabled: true
    }
  ]
}

// Enforce that only identities explicitly assigned the Function.Invoke app role can obtain a token,
// even before Easy Auth is evaluated. The actual role grant is done in main.bicep, since the caller
// (the Logic App's identity) is created by a sibling module - assigning it here would create a
// circular module dependency once the Logic App also needs this module's URL/audience outputs.
resource functionAadSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: functionAadApp.appId
  appRoleAssignmentRequired: true
}

// --- Secure the function app inbound with Microsoft Entra ID (Easy Auth), no function keys needed ---
resource authSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: functionApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: functionAadApp.appId
        }
        validation: {
          allowedAudiences: [
            functionAadApp.appId
          ]
          defaultAuthorizationPolicy: {
            allowedApplications: [
              authorizedClientId
            ]
            allowedPrincipals: {
              identities: [
                authorizedPrincipalId
              ]
            }
          }
        }
      }
    }
  }
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output functionAppHostName string = functionApp.properties.defaultHostName
output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppAudience string = functionAadApp.appId
output functionAppClientId string = functionAadApp.appId
output functionAppServicePrincipalId string = functionAadSp.id
output functionAppRoleId string = functionAppRoleId
