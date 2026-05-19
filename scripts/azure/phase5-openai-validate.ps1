Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE5_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase5-openai.json"

foreach ($file in @($PHASE2_OUTPUT_FILE, $PHASE5_OUTPUT_FILE)) {
  if (-not (Test-Path $file)) {
    throw "Missing output file: $file"
  }
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase5 = Get-Content -Path $PHASE5_OUTPUT_FILE -Raw | ConvertFrom-Json

$RESOURCE_GROUP = $phase5.resourceGroup
$CONTAINER_APP_NAME = $phase5.containerAppName
$APP_URL = $phase5.appUrl
$AOAI_ACCOUNT_NAME = $phase5.azureOpenAIAccountName
$AOAI_DEPLOYMENT_NAME = $phase5.deploymentName
$ACR_LOGIN_SERVER = $phase2.acrLoginServer

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

Write-Host "==> Azure OpenAI resource" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "cognitiveservices", "account", "show",
  "--name", $AOAI_ACCOUNT_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--output", "table"
)

Write-Host "==> Azure OpenAI deployment" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "cognitiveservices", "account", "deployment", "show",
  "--name", $AOAI_ACCOUNT_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--deployment-name", $AOAI_DEPLOYMENT_NAME,
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

Write-Host "==> RBAC role assignment" -ForegroundColor Cyan
$principalId = Invoke-NativeOutput "az" @(
  "containerapp", "show",
  "--name", $CONTAINER_APP_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "identity.userAssignedIdentities.*.principalId | [0]",
  "--output", "tsv"
)
$aoaiId = Invoke-NativeOutput "az" @(
  "cognitiveservices", "account", "show",
  "--name", $AOAI_ACCOUNT_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "id",
  "--output", "tsv"
)
Invoke-NativeCommand "az" @(
  "role", "assignment", "list",
  "--assignee-object-id", $principalId,
  "--role", "Cognitive Services OpenAI User",
  "--scope", $aoaiId,
  "--only-show-errors",
  "--output", "table"
)

Write-Host "==> Health" -ForegroundColor Cyan
Invoke-RestMethod "$APP_URL/health" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Ready" -ForegroundColor Cyan
Invoke-RestMethod "$APP_URL/ready" | ConvertTo-Json -Depth 8 | Write-Host

Write-Host "==> Functional upload/analyze/analytics validation" -ForegroundColor Cyan
$testPdf = Join-Path $env:TEMP "ai-doc-intel-phase5-test.pdf"
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
<< /Length 186 >>
stream
BT
/F1 18 Tf
72 720 Td
(Factura de servicios profesionales con vencimiento proximo.) Tj
0 -28 Td
(Proveedor: Contoso Consulting. Importe total: 2500 EUR.) Tj
0 -28 Td
(Riesgo: revisar condiciones de pago y penalizaciones.) Tj
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
0000000308 00000 n
0000000544 00000 n
trailer
<< /Root 1 0 R /Size 6 >>
startxref
614
%%EOF
'@
Set-Content -Path $testPdf -Value $pdfContent -Encoding ASCII

$uploadJson = & curl.exe -s -f -X POST -F "file=@$testPdf;type=application/pdf" "$APP_URL/documents/upload"
if ($LASTEXITCODE -ne 0) {
  throw "Upload PDF validation failed."
}
$uploaded = $uploadJson | ConvertFrom-Json
$uploaded | ConvertTo-Json -Depth 8 | Write-Host

$analyze = Invoke-RestMethod -Method POST "$APP_URL/documents/$($uploaded.id)/analyze"
$analyze | ConvertTo-Json -Depth 12 | Write-Host

if ($analyze.analysis.summary -match "Resumen simulado") {
  throw "Analyze validation failed: summary still looks mocked."
}
if ([int]$analyze.usage.total_tokens -le 0) {
  throw "Analyze validation failed: usage.total_tokens must be greater than 0."
}

$analytics = Invoke-RestMethod "$APP_URL/analytics/usage"
$analytics | ConvertTo-Json -Depth 8 | Write-Host
if ([int]$analytics.total_tokens -le 0) {
  throw "Analytics validation failed: total_tokens must be greater than 0."
}

Write-Host "Image registry: $ACR_LOGIN_SERVER" -ForegroundColor Green
Write-Host "Swagger URL: $APP_URL/docs" -ForegroundColor Green
