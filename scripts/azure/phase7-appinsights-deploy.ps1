Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE3_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase3-storage.json"
$PHASE4_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase4-sql.json"
$PHASE5_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase5-openai.json"
$PHASE6_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase6-keyvault.json"
$PHASE7_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase7-appinsights.json"

foreach ($file in @($PHASE2_OUTPUT_FILE, $PHASE3_OUTPUT_FILE, $PHASE4_OUTPUT_FILE, $PHASE5_OUTPUT_FILE, $PHASE6_OUTPUT_FILE)) {
  if (-not (Test-Path $file)) {
    throw "Missing output file: $file. Ejecuta primero las fases anteriores."
  }
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase6 = Get-Content -Path $PHASE6_OUTPUT_FILE -Raw | ConvertFrom-Json

$RESOURCE_GROUP = $phase2.resourceGroup
$LOCATION = $phase2.location
$ACR_NAME = $phase2.acrName
$ACR_LOGIN_SERVER = $phase2.acrLoginServer
$CONTAINER_APP_NAME = $phase2.containerAppName
$APP_URL = $phase6.appUrl

$APP_INSIGHTS_NAME = "appi-ai-doc-intel-dev"
$IMAGE_NAME = "ai-doc-intel-backend"
$IMAGE_TAG = "phase7"
$FULL_IMAGE_NAME = "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
  )
  Write-Host ""
  Write-Host "==> $Name" -ForegroundColor Cyan
  & $ScriptBlock
}

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
  $cleanOutput = foreach ($item in $output) {
    if ($item -is [System.Management.Automation.ErrorRecord]) {
      $text = $item.ToString()
      if ($text -match "^WARNING:") { continue }
      $text
    } else {
      [string]$item
    }
  }
  return (($cleanOutput | Out-String).Trim())
}

function Assert-ProviderRegistered {
  param(
    [Parameter(Mandatory = $true)][string]$Namespace,
    [int]$Attempts = 12,
    [int]$DelaySeconds = 10
  )
  Invoke-NativeCommand "az" @("provider", "register", "--namespace", $Namespace, "--wait")
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $state = Invoke-NativeOutput "az" @(
      "provider", "show",
      "--namespace", $Namespace,
      "--only-show-errors",
      "--query", "registrationState",
      "--output", "tsv"
    )
    if ($state -eq "Registered") {
      Write-Host "$Namespace is Registered" -ForegroundColor Green
      return
    }
    Write-Host "$Namespace is $state. Waiting ($attempt/$Attempts)..." -ForegroundColor Yellow
    Start-Sleep -Seconds $DelaySeconds
  }
  throw "Azure provider '$Namespace' is not Registered after $Attempts attempts."
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

function Test-AppInsightsExists {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & az monitor app-insights component show `
      --app $APP_INSIGHTS_NAME `
      --resource-group $RESOURCE_GROUP `
      --only-show-errors `
      --query name `
      --output tsv 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($exitCode -eq 0 -and (($output | Out-String).Trim())) {
    return $true
  }

  $text = ($output | Out-String)
  if ($text -match "ResourceNotFound" -or $text -match "was not found") {
    return $false
  }

  throw "Could not check Application Insights existence. az exit code: ${exitCode}`n$text"
}

function Invoke-HttpWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Name,
    [int]$Attempts = 18,
    [int]$DelaySeconds = 10
  )
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      Write-Host "Checking $Name ($attempt/$Attempts): $Url"
      return Invoke-RestMethod -Uri $Url -TimeoutSec 30
    } catch {
      if ($attempt -eq $Attempts) {
        throw "$Name validation failed after $Attempts attempts. Last error: $($_.Exception.Message)"
      }
      Start-Sleep -Seconds $DelaySeconds
    }
  }
}

Push-Location $PROJECT_ROOT
try {
  Invoke-Step "Checking tooling and providers" {
    Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    Invoke-NativeCommand "docker" @("--version")
    Ensure-AppInsightsExtension
    Assert-ProviderRegistered "Microsoft.Insights"
    Assert-ProviderRegistered "Microsoft.OperationalInsights"
  }

  Invoke-Step "Creating Application Insights" {
    if (Test-AppInsightsExists) {
      Write-Host "Application Insights already exists: $APP_INSIGHTS_NAME" -ForegroundColor Green
    } else {
      Invoke-NativeCommand "az" @(
        "monitor", "app-insights", "component", "create",
        "--app", $APP_INSIGHTS_NAME,
        "--location", $LOCATION,
        "--resource-group", $RESOURCE_GROUP,
        "--application-type", "web",
        "--query", "{name:name, location:location, provisioningState:provisioningState}",
        "--output", "table"
      )
    }

    $script:APPINSIGHTS_CONNECTION_STRING = Invoke-NativeOutput "az" @(
      "monitor", "app-insights", "component", "show",
      "--app", $APP_INSIGHTS_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "connectionString",
      "--output", "tsv"
    )
  }

  Invoke-Step "Configuring Container App telemetry env vars" {
    Invoke-NativeCommand "az" @(
      "containerapp", "secret", "set",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--secrets", "appinsights-connection-string=$script:APPINSIGHTS_CONNECTION_STRING"
    )

    Invoke-NativeCommand "az" @(
      "containerapp", "update",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--set-env-vars",
        "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string",
        "ENABLE_APP_INSIGHTS=true",
        "LOG_LEVEL=INFO",
      "--output", "table"
    )
  }

  Invoke-Step "Building and pushing backend image phase7" {
    Invoke-NativeCommand "az" @("acr", "login", "--name", $ACR_NAME)
    Invoke-NativeCommand "docker" @("build", "-t", $FULL_IMAGE_NAME, "./backend")
    Invoke-NativeCommand "docker" @("push", $FULL_IMAGE_NAME)
  }

  Invoke-Step "Updating Container App image phase7" {
    Invoke-NativeCommand "az" @(
      "containerapp", "update",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--image", $FULL_IMAGE_NAME,
      "--output", "table"
    )
  }

  Invoke-Step "Validating health endpoints" {
    Invoke-HttpWithRetry -Url "$APP_URL/health" -Name "/health" | ConvertTo-Json -Depth 8 | Write-Host
    Invoke-HttpWithRetry -Url "$APP_URL/ready" -Name "/ready" | ConvertTo-Json -Depth 8 | Write-Host
  }

  Invoke-Step "Writing phase7 outputs" {
    [ordered]@{
      resourceGroup = $RESOURCE_GROUP
      location = $LOCATION
      applicationInsightsName = $APP_INSIGHTS_NAME
      containerAppName = $CONTAINER_APP_NAME
      image = $FULL_IMAGE_NAME
      appUrl = $APP_URL
      healthUrl = "$APP_URL/health"
      readyUrl = "$APP_URL/ready"
      docsUrl = "$APP_URL/docs"
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $PHASE7_OUTPUT_FILE -Encoding UTF8
    Write-Host "Outputs written to $PHASE7_OUTPUT_FILE" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
