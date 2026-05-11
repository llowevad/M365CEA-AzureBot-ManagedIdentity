targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the App Service (globally unique)')
param appServiceName string

@description('Name of the Azure Bot resource')
param botServiceName string

@description('Name of the User-Assigned Managed Identity')
param managedIdentityName string

@description('App Service Plan SKU (B1 enables always-on)')
@allowed(['F1', 'B1', 'B2', 'S1'])
param appServiceSku string = 'B1'

@description('Base URL of the A2A orchestrator endpoint')
param a2aBaseUrl string

@description('Path on the A2A orchestrator')
param a2aPath string = '/a2a/orchestrator'

// --- User-Assigned Managed Identity (created FIRST) ---
module identity 'modules/managedIdentity.bicep' = {
  name: 'managedIdentity'
  params: {
    identityName: managedIdentityName
    location: location
  }
}

// --- App Service (references the UAI) ---
module appService 'modules/appService.bicep' = {
  name: 'appService'
  params: {
    appServiceName: appServiceName
    location: location
    sku: appServiceSku
    managedIdentityResourceId: identity.outputs.resourceId
    botAppId: identity.outputs.clientId
    tenantId: tenant().tenantId
    a2aBaseUrl: a2aBaseUrl
    a2aPath: a2aPath
  }
}

// --- Azure Bot Service (references the UAI) ---
module bot 'modules/botService.bicep' = {
  name: 'botService'
  params: {
    botServiceName: botServiceName
    msaAppId: identity.outputs.clientId
    msaAppMSIResourceId: identity.outputs.resourceId
    msaAppTenantId: tenant().tenantId
    messagingEndpoint: 'https://${appService.outputs.hostname}/api/messages'
  }
}

// --- Outputs ---
output managedIdentityClientId string = identity.outputs.clientId
output managedIdentityPrincipalId string = identity.outputs.principalId
output appServiceHostname string = appService.outputs.hostname
output messagingEndpoint string = 'https://${appService.outputs.hostname}/api/messages'
