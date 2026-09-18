// Orchestrates the demo environment: shared monitoring, the Standard Logic App
// (workflow) and the Function App it calls. The Function App is secured with
// Microsoft Entra ID so the Logic App can invoke it using its managed identity
// instead of a function key.

// Microsoft Graph resources (the app role assignment below) require the microsoftGraph extension.
// bicepconfig.json pins its dynamic-types version. See https://aka.ms/graphbicep/dynamictypes.
extension microsoftGraph

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Base name used to derive resource names.')
param baseName string = uniqueString(resourceGroup().id)

param logicAppName string = 'logic-${baseName}'
param functionAppName string = 'func-${baseName}'
param userAssignedIdentityName string = 'id-${logicAppName}'
param logAnalyticsWorkspaceName string = 'log-${baseName}'
param applicationInsightsName string = 'appi-${baseName}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: userAssignedIdentityName
    location: location
  }
}

module functionApp 'modules/function.bicep' = {
  name: 'functionApp'
  params: {
    appName: functionAppName
    location: location
    applicationInsightsName: applicationInsights.name
    authorizedClientId: identity.outputs.clientId
    authorizedPrincipalId: identity.outputs.principalId
  }
}

module logicApp 'modules/logicapp.bicep' = {
  name: 'logicApp'
  params: {
    appName: logicAppName
    location: location
    applicationInsightsName: applicationInsights.name
    userAssignedIdentityId: identity.outputs.id
    userAssignedIdentityPrincipalId: identity.outputs.principalId
    userAssignedIdentityClientId: identity.outputs.clientId
    functionAppUrl: 'https://${functionApp.outputs.functionAppHostName}/api/HttpTrigger1'
    functionAppAudience: functionApp.outputs.functionAppAudience
  }
}

// Grant the Logic App's user-assigned identity the function app's Function.Invoke app role.
// Declared here (not inside either module) to avoid a circular module dependency:
// the Logic App needs the function's URL/audience, and the function's role grant needs the
// Logic App's identity.
resource callerRoleAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: functionApp.outputs.functionAppRoleId
  principalId: identity.outputs.principalId
  resourceId: functionApp.outputs.functionAppServicePrincipalId
}

output logicAppName string = logicApp.outputs.logicappAppName
output functionAppName string = functionApp.outputs.functionAppName
output functionAppHostName string = functionApp.outputs.functionAppHostName
@description('Set this as the Audience on the Logic App HTTP action Managed Identity authentication.')
output functionAppAudience string = functionApp.outputs.functionAppAudience

