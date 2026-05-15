Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RESOURCE_GROUP = "rg-ai-doc-intel-dev"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI was not found. Install Azure CLI or run this script from Azure Cloud Shell."
}

Write-Host "WARNING: This will delete the entire resource group: $RESOURCE_GROUP" -ForegroundColor Yellow
Write-Host "This removes the Azure Container App, Container Apps Environment, ACR, logs, and every resource in that group." -ForegroundColor Yellow
$confirmation = Read-Host "Type DELETE to continue"

if ($confirmation -eq "DELETE") {
  az group delete --name $RESOURCE_GROUP --yes --no-wait
  Write-Host "Deletion started." -ForegroundColor Green
} else {
  Write-Host "Cleanup cancelled."
}
