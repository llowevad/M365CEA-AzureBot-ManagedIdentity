@description('Name of the Azure Bot resource')
param botServiceName string

@description('Location for Bot Service (must be global)')
param location string = 'global'

@description('Client ID of the User-Assigned Managed Identity (= Bot App ID)')
param msaAppId string

@description('Full resource ID of the User-Assigned Managed Identity')
param msaAppMSIResourceId string

@description('Tenant ID for the bot identity')
param msaAppTenantId string

@description('Messaging endpoint (App Service URL + /api/messages)')
param messagingEndpoint string

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botServiceName
  location: location
  kind: 'azurebot'
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: botServiceName
    endpoint: messagingEndpoint
    msaAppId: msaAppId
    msaAppType: 'UserAssignedMSI'
    msaAppMSIResourceId: msaAppMSIResourceId
    msaAppTenantId: msaAppTenantId
  }
}

// Teams channel — required
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
    }
  }
}

// M365 Extensions channel (Copilot integration)
resource m365ExtensionsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'M365Extensions'
  location: location
  properties: {
    channelName: 'M365Extensions'
  }
}

@description('Bot Service resource ID')
output botId string = bot.id
