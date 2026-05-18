Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE3_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase3-storage.json"

if (-not (Test-Path $PHASE2_OUTPUT_FILE)) {
  throw "Falta outputs/azure-phase2-deployment.json. Ejecuta primero Fase 2."
}

if (-not (Test-Path $PHASE3_OUTPUT_FILE)) {
  throw "Falta outputs/azure-phase3-storage.json. Ejecuta primero scripts/azure/phase3-storage-deploy.ps1."
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase3 = Get-Content -Path $PHASE3_OUTPUT_FILE -Raw | ConvertFrom-Json

$RESOURCE_GROUP = $phase2.resourceGroup
$CONTAINER_APP_NAME = $phase2.containerAppName
$APP_URL = $phase3.appUrl
$STORAGE_ACCOUNT_NAME = $phase3.storageAccountName
$STORAGE_CONTAINER_NAME = $phase3.storageContainerName

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
  }
}

Write-Host "==> Storage Account" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "storage", "account", "show",
  "--name", $STORAGE_ACCOUNT_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--output", "table"
)

Write-Host "==> Blob container" -ForegroundColor Cyan
$storageKey = az storage account keys list `
  --account-name $STORAGE_ACCOUNT_NAME `
  --resource-group $RESOURCE_GROUP `
  --query "[0].value" `
  --output tsv

Invoke-NativeCommand "az" @(
  "storage", "container", "show",
  "--name", $STORAGE_CONTAINER_NAME,
  "--account-name", $STORAGE_ACCOUNT_NAME,
  "--account-key", $storageKey,
  "--output", "table"
)

Write-Host "==> Container App env vars" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "containerapp", "show",
  "--name", $CONTAINER_APP_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--query", "properties.template.containers[0].env",
  "--output", "table"
)

Write-Host "==> Health" -ForegroundColor Cyan
Invoke-RestMethod "$APP_URL/health" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Ready" -ForegroundColor Cyan
Invoke-RestMethod "$APP_URL/ready" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Functional upload/analyze/blob validation" -ForegroundColor Cyan
$testPdf = Join-Path $env:TEMP "ai-doc-intel-phase3-test.pdf"
$pdfContent = @'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 119 >>
stream
BT
/F1 18 Tf
72 720 Td
(Factura de prueba con posible riesgo operativo.) Tj
0 -28 Td
(Importe total: 100 euros.) Tj
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000241 00000 n
0000000411 00000 n
trailer
<< /Root 1 0 R /Size 6 >>
startxref
481
%%EOF
'@
Set-Content -Path $testPdf -Value $pdfContent -Encoding ASCII

$uploadJson = & curl.exe -s -f -X POST -F "file=@$testPdf;type=application/pdf" "$APP_URL/documents/upload"
if ($LASTEXITCODE -ne 0) {
  throw "Upload PDF validation failed."
}
$uploaded = $uploadJson | ConvertFrom-Json
$uploaded | ConvertTo-Json -Depth 8 | Write-Host

$analysis = Invoke-RestMethod -Method POST "$APP_URL/documents/$($uploaded.id)/analyze"
$analysis | ConvertTo-Json -Depth 8 | Write-Host

Invoke-RestMethod "$APP_URL/documents/$($uploaded.id)/analysis" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Blob list" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "storage", "blob", "list",
  "--account-name", $STORAGE_ACCOUNT_NAME,
  "--container-name", $STORAGE_CONTAINER_NAME,
  "--account-key", $storageKey,
  "--output", "table"
)

Write-Host "Swagger URL: $APP_URL/docs" -ForegroundColor Green
Write-Host "List blobs command:" -ForegroundColor Green
Write-Host "az storage blob list --account-name $STORAGE_ACCOUNT_NAME --container-name $STORAGE_CONTAINER_NAME --account-key <storage-key> --output table"
