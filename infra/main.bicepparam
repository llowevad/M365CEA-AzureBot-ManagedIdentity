using './main.bicep'

param appServiceName = 'm365-cea-proxy'
param botServiceName = 'm365-cea-proxy-bot'
param managedIdentityName = 'm365-cea-proxy-id'
param appServiceSku = 'S1'
param a2aBaseUrl = 'https://skcopilot-v2-orchestrator.azurewebsites.net'
param a2aPath = '/a2a/orchestrator'
