<#
.SYNOPSIS
    Deploys the M365 Custom Engine Agent infrastructure and application to Azure.
.DESCRIPTION
    Creates the resource group, deploys Bicep templates, and zip-deploys the Node.js app.
.PARAMETER ResourceGroup
    Name of the Azure resource group.
.PARAMETER Location
    Azure region (default: eastus).
.PARAMETER ParamFile
    Path to the .bicepparam file (default: main.bicepparam).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$Location = 'eastus',

    [string]$ParamFile = './main.bicepparam'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== M365 Custom Engine Agent — Infrastructure Deployment ===" -ForegroundColor Cyan

# 1. Create resource group
Write-Host "`n[1/3] Creating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }

# 2. Deploy Bicep templates
Write-Host "[2/3] Deploying Bicep templates..." -ForegroundColor Yellow
$result = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file './main.bicep' `
    --parameters $ParamFile `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw "Bicep deployment failed" }

$hostname = $result.properties.outputs.appServiceHostname.value
Write-Host "  App Service hostname: $hostname" -ForegroundColor Green
Write-Host "  Messaging endpoint:   https://$hostname/api/messages" -ForegroundColor Green

# 3. Zip-deploy the application
Write-Host "[3/3] Deploying application code..." -ForegroundColor Yellow

$appName = $result.properties.parameters.appServiceName.value

Push-Location (Join-Path $PSScriptRoot '..')
if (-not (Test-Path 'dist')) {
    Write-Host "  Building project..." -ForegroundColor Gray
    npm run build
}

# Create zip package
$zipPath = Join-Path $PSScriptRoot 'deploy.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path 'dist/*', 'node_modules/*', 'package.json' -DestinationPath $zipPath

az webapp deploy `
    --resource-group $ResourceGroup `
    --name $appName `
    --src-path $zipPath `
    --type zip `
    --output none

if ($LASTEXITCODE -ne 0) { throw "Application deployment failed" }
Pop-Location

# Cleanup
Remove-Item $zipPath -ErrorAction SilentlyContinue

Write-Host "`n=== Deployment complete ===" -ForegroundColor Cyan
Write-Host "Bot messaging endpoint: https://$hostname/api/messages"
Write-Host "Next steps:"
Write-Host "  1. Verify bot in Azure Portal > Bot Service > Test in Web Chat"
Write-Host "  2. Install Teams app package to sideload the agent"
