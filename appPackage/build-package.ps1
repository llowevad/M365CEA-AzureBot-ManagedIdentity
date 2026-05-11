<#
.SYNOPSIS
    Builds a sideload-ready Teams app package (.zip).
.DESCRIPTION
    Replaces placeholder tokens in manifest.json with actual values,
    then zips manifest + icons into a .zip ready for Teams sideloading.
.PARAMETER BotAppId
    The User-Assigned Managed Identity's client ID (used as bot App ID).
.PARAMETER AppServiceName
    The Azure App Service name (without .azurewebsites.net).
.PARAMETER OutputPath
    Path for the output zip file. Default: appPackage/M365CEAProxy.zip
.EXAMPLE
    .\build-package.ps1 -BotAppId "12345678-1234-1234-1234-123456789abc" -AppServiceName "my-cea-app"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$BotAppId,

    [Parameter(Mandatory = $true)]
    [string]$AppServiceName,

    [string]$OutputPath = (Join-Path $PSScriptRoot "M365CEAProxy.zip")
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

Write-Host "=== Teams App Package Builder ===" -ForegroundColor Cyan
Write-Host "Bot App ID:       $BotAppId"
Write-Host "App Service Name: $AppServiceName"
Write-Host ""

# Ensure icons exist
$colorIcon = Join-Path $scriptDir "color.png"
$outlineIcon = Join-Path $scriptDir "outline.png"

if (-not (Test-Path $colorIcon) -or -not (Test-Path $outlineIcon)) {
    Write-Host "Icons not found. Generating placeholders..." -ForegroundColor Yellow
    & (Join-Path $scriptDir "generate-icons.ps1")
}

# Create temp working directory
$tempDir = Join-Path $scriptDir ".build-temp"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Process manifest.json — replace tokens
$manifestContent = Get-Content (Join-Path $scriptDir "manifest.json") -Raw
$manifestContent = $manifestContent -replace '\$\{\{BOT_APP_ID\}\}', $BotAppId
$manifestContent = $manifestContent -replace '\$\{\{APP_SERVICE_NAME\}\}', $AppServiceName
$manifestContent | Set-Content (Join-Path $tempDir "manifest.json") -Encoding UTF8

# Copy icons
Copy-Item $colorIcon (Join-Path $tempDir "color.png")
Copy-Item $outlineIcon (Join-Path $tempDir "outline.png")

# Remove existing zip if present
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

# Create zip
Compress-Archive -Path (Join-Path $tempDir "*") -DestinationPath $OutputPath -Force

# Cleanup temp
Remove-Item $tempDir -Recurse -Force

Write-Host ""
Write-Host "Package built successfully!" -ForegroundColor Green
Write-Host "Output: $OutputPath"
Write-Host ""
Write-Host "To sideload:" -ForegroundColor Yellow
Write-Host "  1. Open Teams → Apps → Manage your apps → Upload a custom app"
Write-Host "  2. Select: $OutputPath"
Write-Host "  3. Add the bot to a chat or channel"
