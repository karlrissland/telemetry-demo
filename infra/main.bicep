// =============================================================================
// Azure Integration Telemetry Demo — infrastructure entry point.
//
// Provisions the full hosting surface for the demo:
//   Log Analytics + Application Insights (one shared component)
//   User-assigned managed identity (one shared principal)
//   Service Bus namespace (local auth disabled) + orders / orders-processed
//   Container Registry (admin user disabled)
//   Storage for the Function (shared key disabled)
//   Function app (Flex Consumption, .NET 8 isolated)
//   Logic App Standard (WorkflowStandard plan)
//   Container Apps environment + placeholder container app
//   API Management (Consumption)
//   All RBAC role assignments
//
// Application code and APIM API definitions are NOT deployed here. This template
// provisions empty hosts; PowerShell azd hooks push the apps afterwards.
// =============================================================================

targetScope = 'subscription'

@minLength(1)
@maxLength(24)
@description('Name of the azd environment. Used to name and tag every resource.')
param environmentName string

@minLength(1)
@description('Azure region for all resources.')
param location string

@description('Object id of the developer or service principal running the deployment. Granted data-plane roles so local F5 debugging works through DefaultAzureCredential. azd populates this automatically.')
param principalId string = ''

@description('Type of the deploying principal. Use ServicePrincipal when running in CI.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

@description('Publisher email for API Management notifications.')
param apimPublisherEmail string = 'admin@contoso.com'

@description('Publisher organisation name for API Management.')
param apimPublisherName string = 'Telemetry Demo'

@description('Name of the queue carrying messages from the Logic App to the Function.')
param ordersQueueName string = 'orders'

@description('Name of the queue carrying messages from the Function to the Container App.')
param ordersProcessedQueueName string = 'orders-processed'

@description('Apply the MCAPS SecurityControl=Ignore exemption tag to the two storage accounts. Required in MCAPS-governed tenants, where Modify policies would otherwise disable public network access and shared key auth after deployment and break the Function and Logic App hosts. Set false in a tenant without those policies.')
param applyMcapsPolicyExemption bool = true

@description('Optional override for the resource group name.')
param resourceGroupName string = ''

// --- Naming -----------------------------------------------------------------

var abbrs = loadJsonContent('abbreviations.json')

// Deterministic per-environment suffix: stable across redeploys, unique across
// environments and subscriptions.
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

var tags = {
  'azd-env-name': environmentName
  solution: 'telemetry-demo'
}

// See the module-level comments for why these two storage accounts are exempted.
var policyExemptionTags = applyMcapsPolicyExemption ? { SecurityControl: 'Ignore' } : {}

var rgName = !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
  tags: tags
}

// --- Foundational services ---------------------------------------------------

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    identityName: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  scope: rg
  params: {
    serviceBusNamespaceName: '${abbrs.serviceBusNamespaces}${resourceToken}'
    location: location
    tags: tags
    ordersQueueName: ordersQueueName
    ordersProcessedQueueName: ordersProcessedQueueName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: {
    containerRegistryName: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
  }
}

module functionStorage 'modules/storage.bicep' = {
  name: 'function-storage'
  scope: rg
  params: {
    storageAccountName: '${abbrs.storageStorageAccounts}fn${resourceToken}'
    location: location
    tags: tags
    policyExemptionTags: policyExemptionTags
  }
}

// --- RBAC before compute -----------------------------------------------------
// Role assignments are created before the compute hosts so the Function and
// Container App can reach storage and Service Bus on their first start, rather
// than crash-looping while permissions replicate.

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  scope: rg
  params: {
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    storageAccountName: functionStorage.outputs.storageAccountName
    containerRegistryName: registry.outputs.containerRegistryName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    managedIdentityPrincipalId: identity.outputs.identityPrincipalId
    developerPrincipalId: principalId
    developerPrincipalType: principalType
  }
}

// --- Compute -----------------------------------------------------------------

module functionApp 'modules/function.bicep' = {
  name: 'function'
  scope: rg
  params: {
    functionAppName: '${abbrs.webSitesFunctions}${resourceToken}'
    hostingPlanName: '${abbrs.webServerFarms}fn-${resourceToken}'
    location: location
    tags: tags
    userAssignedIdentityId: identity.outputs.identityId
    userAssignedIdentityClientId: identity.outputs.identityClientId
    storageBlobEndpoint: functionStorage.outputs.blobEndpoint
    deploymentPackageContainerUri: functionStorage.outputs.deploymentPackageUri
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    serviceBusFullyQualifiedNamespace: serviceBus.outputs.serviceBusFullyQualifiedNamespace
    ordersQueueName: serviceBus.outputs.ordersQueueName
    ordersProcessedQueueName: serviceBus.outputs.ordersProcessedQueueName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
  }
  dependsOn: [
    rbac
  ]
}

module logicApp 'modules/logicapp.bicep' = {
  name: 'logicapp'
  scope: rg
  params: {
    logicAppName: '${abbrs.webSitesLogicApp}${resourceToken}'
    hostingPlanName: '${abbrs.webServerFarms}logic-${resourceToken}'
    storageAccountName: '${abbrs.storageStorageAccounts}la${resourceToken}'
    location: location
    tags: tags
    policyExemptionTags: policyExemptionTags
    userAssignedIdentityId: identity.outputs.identityId
    userAssignedIdentityPrincipalId: identity.outputs.identityPrincipalId
    userAssignedIdentityClientId: identity.outputs.identityClientId
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    serviceBusFullyQualifiedNamespace: serviceBus.outputs.serviceBusFullyQualifiedNamespace
    ordersQueueName: serviceBus.outputs.ordersQueueName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
  }
  dependsOn: [
    rbac
  ]
}

module containerApp 'modules/containerapp.bicep' = {
  name: 'containerapp'
  scope: rg
  params: {
    containerAppsEnvironmentName: '${abbrs.appManagedEnvironments}${resourceToken}'
    containerAppName: '${abbrs.appContainerApps}${resourceToken}'
    location: location
    tags: tags
    userAssignedIdentityId: identity.outputs.identityId
    userAssignedIdentityClientId: identity.outputs.identityClientId
    containerRegistryLoginServer: registry.outputs.containerRegistryLoginServer
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    serviceBusFullyQualifiedNamespace: serviceBus.outputs.serviceBusFullyQualifiedNamespace
    ordersProcessedQueueName: serviceBus.outputs.ordersProcessedQueueName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
  }
  dependsOn: [
    rbac
  ]
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  scope: rg
  params: {
    apiManagementServiceName: '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    userAssignedIdentityId: identity.outputs.identityId
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    applicationInsightsInstrumentationKey: monitoring.outputs.applicationInsightsInstrumentationKey
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
  }
}

// --- Outputs -----------------------------------------------------------------
// These become azd environment values (`azd env get-values`) and are the contract
// consumed by the PowerShell deployment hooks and by tests/*.http.

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_RESOURCE_GROUP string = rg.name

output AZURE_CLIENT_ID string = identity.outputs.identityClientId
output AZURE_MANAGED_IDENTITY_NAME string = identity.outputs.identityName
output AZURE_MANAGED_IDENTITY_ID string = identity.outputs.identityId
output AZURE_MANAGED_IDENTITY_PRINCIPAL_ID string = identity.outputs.identityPrincipalId

output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output LOG_ANALYTICS_WORKSPACE_NAME string = monitoring.outputs.logAnalyticsName
output LOG_ANALYTICS_WORKSPACE_ID string = monitoring.outputs.logAnalyticsId
output LOG_ANALYTICS_CUSTOMER_ID string = monitoring.outputs.logAnalyticsCustomerId

output SERVICE_BUS_NAMESPACE string = serviceBus.outputs.serviceBusNamespaceName
output SERVICE_BUS_FQDN string = serviceBus.outputs.serviceBusFullyQualifiedNamespace
output ORDERS_QUEUE_NAME string = serviceBus.outputs.ordersQueueName
output ORDERS_PROCESSED_QUEUE_NAME string = serviceBus.outputs.ordersProcessedQueueName

output AZURE_CONTAINER_REGISTRY_NAME string = registry.outputs.containerRegistryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.containerRegistryLoginServer

output FUNCTION_APP_NAME string = functionApp.outputs.functionAppName
output FUNCTION_APP_URL string = functionApp.outputs.functionAppUrl
output FUNCTION_STORAGE_ACCOUNT_NAME string = functionStorage.outputs.storageAccountName

output LOGIC_APP_NAME string = logicApp.outputs.logicAppName
output LOGIC_APP_URL string = logicApp.outputs.logicAppUrl

output CONTAINER_APP_NAME string = containerApp.outputs.containerAppName
output CONTAINER_APP_URL string = containerApp.outputs.containerAppUrl
output CONTAINER_APPS_ENVIRONMENT_NAME string = containerApp.outputs.containerAppsEnvironmentName

output APIM_SERVICE_NAME string = apim.outputs.apiManagementServiceName
output APIM_GATEWAY_URL string = apim.outputs.apiManagementGatewayUrl
