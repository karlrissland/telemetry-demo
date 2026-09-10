// =============================================================================
// API Management — Consumption SKU front door.
//
// Consumption is used so the demo provisions in ~1 minute instead of the 35-45
// minutes the Developer SKU takes. Trade-offs accepted for this demo:
//   * No VNet integration, no self-hosted gateway, no built-in cache.
//   * Request/response size limits are lower than the dedicated tiers.
// Managed identity and the authentication-managed-identity policy ARE supported
// on Consumption, so the backend auth story is unaffected.
//
// APIs and policies are NOT defined here. They are managed as versioned
// artifacts under /apim and applied by the APIM extractor/publisher toolchain
// from a PowerShell azd hook.
// =============================================================================

@description('Name of the API Management service. Globally unique.')
param apiManagementServiceName string

@description('Azure region for the service.')
param location string

@description('Tags applied to all resources in this module.')
param tags object = {}

@description('Publisher email shown on the developer portal and used for notifications.')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string

@description('Resource id of the user-assigned managed identity used for backend authentication.')
param userAssignedIdentityId string

@description('Application Insights resource id, for the gateway diagnostic.')
param applicationInsightsId string

@description('Application Insights instrumentation key, required by the APIM logger.')
@secure()
param applicationInsightsInstrumentationKey string

@description('Log Analytics workspace resource id for diagnostic settings.')
param logAnalyticsWorkspaceId string

resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementServiceName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    // Consumption is serverless; capacity must be 0.
    capacity: 0
  }
  identity: {
    // System-assigned covers gateway-level features; the user-assigned identity is
    // what backend authentication policies reference.
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    // NOTE: no `customProperties` block here. The Consumption SKU rejects the
    // Gateway.Security.Protocols.* properties with CustomPropertiesNotSupportedInSku;
    // it already enforces TLS 1.2+ and disables SSL3/TLS1.0/TLS1.1 by default.
  }
}

// The gateway must appear as a hop in the end-to-end transaction, so it logs to
// the same Application Insights component as every other service.
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Shared Application Insights component for the telemetry demo.'
    resourceId: applicationInsightsId
    credentials: {
      instrumentationKey: applicationInsightsInstrumentationKey
    }
  }
}

resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    // Sample everything — this is a demo and every request must be traceable.
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    frontend: {
      request: {
        headers: [
          'x-correlation-id'
          'traceparent'
        ]
        body: {
          bytes: 1024
        }
      }
      response: {
        headers: [
          'x-correlation-id'
          'traceparent'
        ]
        body: {
          bytes: 1024
        }
      }
    }
    backend: {
      request: {
        headers: [
          'x-correlation-id'
          'traceparent'
        ]
        body: {
          bytes: 1024
        }
      }
      response: {
        headers: [
          'x-correlation-id'
          'traceparent'
        ]
        body: {
          bytes: 1024
        }
      }
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: apiManagementService
  name: 'apim-to-log-analytics'
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

output apiManagementServiceName string = apiManagementService.name
output apiManagementServiceId string = apiManagementService.id
output apiManagementGatewayUrl string = apiManagementService.properties.gatewayUrl
output apiManagementPrincipalId string = apiManagementService.identity.principalId
