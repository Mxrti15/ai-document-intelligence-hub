Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI was not found. Install Azure CLI or run this script from Azure Cloud Shell."
}

if (-not (Test-Path $OUTPUT_FILE)) {
  throw "Deployment output file was not found: $OUTPUT_FILE. Run scripts/azure/phase2-deploy.ps1 first."
}

$deployment = Get-Content -Path $OUTPUT_FILE -Raw | ConvertFrom-Json
$RESOURCE_GROUP = $deployment.resourceGroup
$CONTAINER_APP_NAME = $deployment.containerAppName

Write-Host "Validating $($deployment.appUrl)" -ForegroundColor Cyan

Write-Host ""
Write-Host "==> /health" -ForegroundColor Cyan
Invoke-RestMethod $deployment.healthUrl | ConvertTo-Json -Depth 8 | Write-Host

Write-Host ""
Write-Host "==> /ready" -ForegroundColor Cyan
Invoke-RestMethod $deployment.readyUrl | ConvertTo-Json -Depth 8 | Write-Host

Write-Host ""
Write-Host "==> Container App status" -ForegroundColor Cyan
az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --query "{name:name, provisioningState:properties.provisioningState, runningStatus:properties.runningStatus}" `
  --output table

Write-Host ""
Write-Host "==> Revisions" -ForegroundColor Cyan
az containerapp revision list `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --output table

Write-Host ""
Write-Host "==> Logs" -ForegroundColor Cyan
az containerapp logs show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --follow false
