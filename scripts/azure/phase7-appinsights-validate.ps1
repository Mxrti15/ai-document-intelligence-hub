Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE7_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase7-appinsights.json"

if (-not (Test-Path $PHASE7_OUTPUT_FILE)) {
  throw "Missing output file: $PHASE7_OUTPUT_FILE"
}

$phase7 = Get-Content -Path $PHASE7_OUTPUT_FILE -Raw | ConvertFrom-Json

$RESOURCE_GROUP = $phase7.resourceGroup
$APP_INSIGHTS_NAME = $phase7.applicationInsightsName
$CONTAINER_APP_NAME = $phase7.containerAppName
$APP_URL = $phase7.appUrl

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

function Ensure-AppInsightsExtension {
  Invoke-NativeCommand "az" @(
    "extension", "add",
    "--name", "application-insights",
    "--yes",
    "--upgrade",
    "--only-show-errors"
  )
}

function Wait-AppInsightsTrace {
  param(
    [Parameter(Mandatory = $true)][string]$AppId,
    [int]$Attempts = 12,
    [int]$DelaySeconds = 20
  )

  $query = "traces | where timestamp > ago(20m) | where message contains 'document_' or message contains 'azure_openai_call_completed' or message contains 'analytics_requested' | order by timestamp desc | take 10"

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    Write-Host "Checking Application Insights traces ($attempt/$Attempts)..."
    try {
      $result = Invoke-NativeOutput "az" @(
        "monitor", "app-insights", "query",
        "--app", $AppId,
        "--analytics-query", $query,
        "--only-show-errors",
        "--output", "json"
      )
      if ($result -match "document_" -or $result -match "azure_openai_call_completed" -or $result -match "analytics_requested") {
        $result | Write-Host
        return
      }
    } catch {
      Write-Warning "Application Insights query failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $DelaySeconds
  }

  throw "Telemetry traces were not visible in Application Insights after waiting."
}

Ensure-AppInsightsExtension

Write-Host "==> Application Insights" -ForegroundColor Cyan
Invoke-NativeCommand "az" @(
  "monitor", "app-insights", "component", "show",
  "--app", $APP_INSIGHTS_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "{name:name, location:location, appId:appId, provisioningState:provisioningState}",
  "--output", "table"
)

$appId = Invoke-NativeOutput "az" @(
  "monitor", "app-insights", "component", "show",
  "--app", $APP_INSIGHTS_NAME,
  "--resource-group", $RESOURCE_GROUP,
  "--only-show-errors",
  "--query", "appId",
  "--output", "tsv"
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
$testPdf = Join-Path $env:TEMP "ai-doc-intel-phase7-test.pdf"
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
<< /Length 139 >>
stream
BT
/F1 18 Tf
72 720 Td
(Factura de observabilidad para validar Application Insights.) Tj
0 -28 Td
(Importe: 780 EUR. Riesgo: revisar SLA y penalizaciones.) Tj
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
0000000275 00000 n
0000000464 00000 n
trailer
<< /Root 1 0 R /Size 6 >>
startxref
534
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

Write-Host "==> Application Insights traces" -ForegroundColor Cyan
Wait-AppInsightsTrace -AppId $appId

Write-Host "Swagger URL: $APP_URL/docs" -ForegroundColor Green
