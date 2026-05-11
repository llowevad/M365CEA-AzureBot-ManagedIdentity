@description('Name of the App Service (globally unique)')
param appServiceName string

@description('Location for the resource')
param location string = resourceGroup().location

@description('App Service Plan SKU')
@allowed(['F1', 'B1', 'B2', 'S1'])
param sku string = 'B1'

@description('Resource ID of the User-Assigned Managed Identity')
param managedIdentityResourceId string

@description('Client ID of the User-Assigned Managed Identity (= Bot App ID)')
param botAppId string

@description('Azure AD tenant ID')
param tenantId string

@description('Base URL of the A2A orchestrator endpoint')
param a2aBaseUrl string

@description('Path on the A2A orchestrator')
param a2aPath string = '/a2a/orchestrator'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appServiceName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: sku
  }
  properties: {
    reserved: true // required for Linux
  }
}

resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: sku != 'F1' // F1 does not support always-on
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'MicrosoftAppId', value: botAppId }
        { name: 'MicrosoftAppTenantId', value: tenantId }
        { name: 'A2A_BASE_URL', value: a2aBaseUrl }
        { name: 'A2A_PATH', value: a2aPath }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
      ]
    }
  }
}

@description('Default hostname of the App Service')
output hostname string = appService.properties.defaultHostName

@description('Resource ID of the App Service')
output resourceId string = appService.id
