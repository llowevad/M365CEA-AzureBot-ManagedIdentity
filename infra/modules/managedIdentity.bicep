@description('Name of the User-Assigned Managed Identity')
param identityName string

@description('Location for the resource')
param location string = resourceGroup().location

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

@description('Client ID of the User-Assigned Managed Identity (used as Bot App ID)')
output clientId string = managedIdentity.properties.clientId

@description('Principal ID for role assignments')
output principalId string = managedIdentity.properties.principalId

@description('Full resource ID of the identity')
output resourceId string = managedIdentity.id
