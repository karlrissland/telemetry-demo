// =============================================================================
// Identity — one user-assigned managed identity shared by all compute services.
//
// A shared UAMI keeps the demo's RBAC story simple to narrate: one principal,
// one set of role assignments, and every service authenticates as itself with
// no keys or connection strings anywhere.
// =============================================================================

@description('Name of the user-assigned managed identity.')
param identityName string

@description('Azure region for the identity.')
param location string

@description('Tags applied to the identity.')
param tags object = {}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

output identityName string = userAssignedIdentity.name
output identityId string = userAssignedIdentity.id
output identityPrincipalId string = userAssignedIdentity.properties.principalId
output identityClientId string = userAssignedIdentity.properties.clientId
