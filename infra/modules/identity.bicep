// The Logic App's user-assigned identity, pulled out of logicapp.bicep so it can be created before
// (and referenced by) the site, its storage role assignments, and the cross-module function-app role grant.
@description('Name of the user-assigned managed identity.')
param name string

@description('Location for the identity.')
param location string = resourceGroup().location

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: name
  location: location
}

output id string = userAssignedIdentity.id
output principalId string = userAssignedIdentity.properties.principalId
output clientId string = userAssignedIdentity.properties.clientId
