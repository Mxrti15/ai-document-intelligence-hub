Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE6_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase6-keyvault.json"

if (-not (Test-Path $PHASE6_OUTPUT_FILE)) {
  throw "Missing output file: $PHASE6_OUTPUT_FILE"
}

$phase6 = Get-Content -Path $PHASE6_OUTPUT_FILE -Raw | ConvertFrom-Json

$RESOURCE_GROUP = $phase6.resourceGroup
$KEY_VAULT_NAME = $phase6.keyVaultName
$KEY_VAULT_SECRET_NAME = $phase6.keyVaultSecretName
$CONTAINER_APP_NAME = $phase6.containerAppName
$APP_URL = $phase6.appUrl

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
  }
}

function Invoke-NativeOutput {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')`n$output"
  }
  return (($output | Out-String).Trim())
}

Write-Host "==> Key Vault" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "keyvault", "show",
  "--name", $KEY_VAULT_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "{name:name, location:location, rbac:properties.enableRbacAuthorization}",
  "--output", "table"
)

Write-Host "==> Key Vault secret metadata" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "keyvault", "secret", "show",
  "--vault-name", $KEY_VAULT_NAME,
  "--name", $KEY_VAULT_SECRET_NAME,
  "--only-show-errors",
  "--query", "{id:id, enabled:attributes.enabled}",
  "--output", "table"
)

Write-Host "==> Container App managed identity" -ForegroundColor Cyan
$principalId = Invoke-NativeOutput "az" @(
  "containerapp", "show",
  "--name", $CONTAINER_APP_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "identity.userAssignedIdentities.*.principalId | [0]",
  "--output", "tsv"
)
$principalId | Write-Host

Write-Host "==> Key Vault RBAC for Container App" -ForegroundColor Cyan
$keyVaultId = Invoke-NativeOutput "az" @(
  "keyvault", "show",
  "--name", $KEY_VAULT_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "id",
  "--output", "tsv"
)
Invoke-NativeCommand "az" @(
  "role", "assignment", "list",
  "--assignee-object-id", $principalId,
  "--scope", $keyVaultId,
  "--only-show-errors",
  "--output", "table"
)

Write-Host "==> Container App secrets metadata" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "containerapp", "secret", "list",
  "--name", $CONTAINER_APP_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--output", "table"
)

Write-Host "==> Container App env vars" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "containerapp", "show",
  "--name", $CONTAINER_APP_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "properties.template.containers[0].env",
  "--output", "table"
)

Write-Host "==> Health" -ForegroundColor Cyan
Invoke-RestMethod "$APP_URL/health" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Ready" -ForegroundColor Cyan
Invoke-RestMethod "$APP_URL/ready" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Functional upload/analyze/analytics validation" -ForegroundColor Cyan
$testPdf = Join-Path $env:TEMP "ai-doc-intel-phase6-test.pdf"
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
<< /Length 137 >>
stream
BT
/F1 18 Tf
72 720 Td
(Contrato de servicios con clausula de penalizacion.) Tj
0 -28 Td
(Riesgo: revisar vencimiento y condiciones economicas.) Tj
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
0000000273 00000 n
0000000460 00000 n
trailer
<< /Root 1 0 R /Size 6 >>
startxref
530
%%EOF
'@
Set-Content -Path $testPdf -Value $pdfContent -Encoding ASCII

$uploadJson = & curl.exe -s -f -X POST -F "file=@$testPdf;type=application/pdf" "$APP_URL/documents/upload"
if ($LASTEXITCODE -ne 0) {
  throw "Upload PDF validation failed."
}
$uploaded = $uploadJson | ConvertFrom-Json
$uploaded | ConvertTo-Json -Depth 8 | Write-Host

Invoke-RestMethod -Method POST "$APP_URL/documents/$($uploaded.id)/analyze" | ConvertTo-Json -Depth 12 | Write-Host
Invoke-RestMethod "$APP_URL/analytics/usage" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "Swagger URL: $APP_URL/docs" -ForegroundColor Green
