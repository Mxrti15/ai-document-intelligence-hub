Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE3_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase3-storage.json"
$PHASE4_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase4-sql.json"
$PHASE5_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase5-openai.json"

foreach ($file in @($PHASE2_OUTPUT_FILE, $PHASE3_OUTPUT_FILE, $PHASE4_OUTPUT_FILE)) {
  if (-not (Test-Path $file)) {
    throw "Missing output file: $file. Ejecuta primero las fases anteriores."
  }
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase3 = Get-Content -Path $PHASE3_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase4 = Get-Content -Path $PHASE4_OUTPUT_FILE -Raw | ConvertFrom-Json
$existingPhase5 = if (Test-Path $PHASE5_OUTPUT_FILE) {
  Get-Content -Path $PHASE5_OUTPUT_FILE -Raw | ConvertFrom-Json
} else {
  $null
}

$RESOURCE_GROUP = $phase2.resourceGroup
$LOCATION = $phase2.location
$ACR_NAME = $phase2.acrName
$ACR_LOGIN_SERVER = $phase2.acrLoginServer
$CONTAINER_APP_NAME = $phase2.containerAppName
$APP_URL = $phase4.appUrl
$AZURE_CLIENT_ID = $phase3.azureClientId

$AOAI_LOCATION = $LOCATION
$AOAI_DEPLOYMENT_NAME = "gpt-4o"
$AOAI_MODEL_NAME = "gpt-4o"
$AOAI_MODEL_VERSION = "2024-11-20"
$AOAI_API_VERSION = "2024-10-21"
$IMAGE_NAME = "ai-doc-intel-backend"
$IMAGE_TAG = "phase5"
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

function Test-AzOpenAIAccountExists {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & az cognitiveservices account show `
      --name $script:AOAI_ACCOUNT_NAME `
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

  throw "Could not check Azure OpenAI account existence. az exit code: ${exitCode}`n$text"
}

function Grant-OpenAIRoleWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$PrincipalId,
    [Parameter(Mandatory = $true)][string]$Scope,
    [int]$Attempts = 8,
    [int]$DelaySeconds = 15
  )

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $existingRoleAssignment = Invoke-NativeOutput "az" @(
      "role", "assignment", "list",
      "--assignee-object-id", $PrincipalId,
      "--role", "Cognitive Services OpenAI User",
      "--scope", $Scope,
      "--only-show-errors",
      "--query", "[0].id",
      "--output", "tsv"
    )

    if (-not [string]::IsNullOrWhiteSpace($existingRoleAssignment)) {
      Write-Host "Cognitive Services OpenAI User role assignment already exists." -ForegroundColor Green
      return
    }

    try {
      Write-Host "Creating Cognitive Services OpenAI User role assignment ($attempt/$Attempts)..." -ForegroundColor Cyan
      Invoke-NativeCommand "az" @(
        "role", "assignment", "create",
        "--assignee-object-id", $PrincipalId,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", "Cognitive Services OpenAI User",
        "--scope", $Scope,
        "--output", "table"
      )
      return
    } catch {
      if ($attempt -eq $Attempts) {
        throw "Could not create OpenAI RBAC role assignment after $Attempts attempts. Last error: $($_.Exception.Message)"
      }
      Write-Warning "Role assignment failed, likely due to identity propagation. Retrying in $DelaySeconds seconds..."
      Start-Sleep -Seconds $DelaySeconds
    }
  }
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

function Assert-ProviderRegistered {
  param([Parameter(Mandatory = $true)][string]$Namespace)
  Invoke-NativeCommand "az" @("provider", "register", "--namespace", $Namespace, "--wait")
  $state = Invoke-NativeOutput "az" @(
    "provider", "show",
    "--namespace", $Namespace,
    "--only-show-errors",
    "--query", "registrationState",
    "--output", "tsv"
  )
  if ($state -ne "Registered") {
    throw "Azure provider '$Namespace' is not Registered. Current state: '$state'."
  }
  Write-Host "$Namespace is Registered" -ForegroundColor Green
}

function Resolve-AzureOpenAIAccountName {
  if ($null -ne $existingPhase5 -and $existingPhase5.azureOpenAIAccountName) {
    return $existingPhase5.azureOpenAIAccountName
  }

  $existingAccountName = Invoke-NativeOutput "az" @(
    "cognitiveservices", "account", "list",
    "--resource-group", $RESOURCE_GROUP,
    "--only-show-errors",
    "--query", "[?kind=='OpenAI'] | [0].name",
    "--output", "tsv"
  )

  if (-not [string]::IsNullOrWhiteSpace($existingAccountName)) {
    Write-Host "Reusing existing Azure OpenAI resource: $existingAccountName" -ForegroundColor Green
    return $existingAccountName
  }

  return "aidocopenai$((Get-Random -Minimum 10000 -Maximum 99999))"
}

function New-AzureOpenAIDeployment {
  try {
    Invoke-NativeCommand "az" @(
      "cognitiveservices", "account", "deployment", "create",
      "--name", $script:AOAI_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--deployment-name", $AOAI_DEPLOYMENT_NAME,
      "--model-name", $AOAI_MODEL_NAME,
      "--model-version", $AOAI_MODEL_VERSION,
      "--model-format", "OpenAI",
      "--sku-name", "Standard",
      "--sku-capacity", "1",
      "--output", "table"
    )
  } catch {
    throw @"
Could not create Azure OpenAI deployment '$AOAI_DEPLOYMENT_NAME' for model '$AOAI_MODEL_NAME'.
Possible causes: region not supported, quota missing, model unavailable, or CLI syntax changed.
Create a deployment manually in Azure AI Foundry/Azure Portal, or change AOAI_LOCATION/AOAI_MODEL_NAME in this script, then re-run.
Original error: $($_.Exception.Message)
"@
  }
}

Push-Location $PROJECT_ROOT
try {
  Invoke-Step "Checking tooling and providers" {
    Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    Invoke-NativeCommand "docker" @("--version")
    Assert-ProviderRegistered "Microsoft.CognitiveServices"
    $script:AOAI_ACCOUNT_NAME = Resolve-AzureOpenAIAccountName
  }

  Invoke-Step "Creating Azure OpenAI resource" {
    if (Test-AzOpenAIAccountExists) {
      Write-Host "Azure OpenAI resource already exists: $script:AOAI_ACCOUNT_NAME" -ForegroundColor Green
    } else {
      Invoke-NativeCommand "az" @(
        "cognitiveservices", "account", "create",
        "--name", $script:AOAI_ACCOUNT_NAME,
        "--resource-group", $RESOURCE_GROUP,
        "--location", $AOAI_LOCATION,
        "--kind", "OpenAI",
        "--sku", "S0",
        "--custom-domain", $script:AOAI_ACCOUNT_NAME,
        "--output", "table"
      )
    }
  }

  Invoke-Step "Creating Azure OpenAI deployment" {
    $deploymentExists = Invoke-NativeOutput "az" @(
      "cognitiveservices", "account", "deployment", "list",
      "--name", $script:AOAI_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "[?name=='$AOAI_DEPLOYMENT_NAME'] | [0].name",
      "--output", "tsv"
    )

    if ([string]::IsNullOrWhiteSpace($deploymentExists)) {
      New-AzureOpenAIDeployment
    } else {
      Write-Host "Azure OpenAI deployment already exists: $AOAI_DEPLOYMENT_NAME" -ForegroundColor Green
    }
  }

  Invoke-Step "Resolving Azure OpenAI endpoint and Container App identity" {
    $script:AOAI_ENDPOINT = Invoke-NativeOutput "az" @(
      "cognitiveservices", "account", "show",
      "--name", $script:AOAI_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "properties.endpoint",
      "--output", "tsv"
    )
    $script:AOAI_ID = Invoke-NativeOutput "az" @(
      "cognitiveservices", "account", "show",
      "--name", $script:AOAI_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "id",
      "--output", "tsv"
    )
    $script:CONTAINER_APP_PRINCIPAL_ID = Invoke-NativeOutput "az" @(
      "containerapp", "show",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "identity.userAssignedIdentities.*.principalId | [0]",
      "--output", "tsv"
    )

    if ([string]::IsNullOrWhiteSpace($script:CONTAINER_APP_PRINCIPAL_ID)) {
      throw "Could not resolve Container App user-assigned managed identity principalId."
    }
  }

  Invoke-Step "Granting Cognitive Services OpenAI User role" {
    Grant-OpenAIRoleWithRetry `
      -PrincipalId $script:CONTAINER_APP_PRINCIPAL_ID `
      -Scope $script:AOAI_ID

    Write-Host "Waiting 90 seconds for Azure RBAC propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 90
  }

  Invoke-Step "Building and pushing backend image phase5" {
    Invoke-NativeCommand "az" @("acr", "login", "--name", $ACR_NAME)
    Invoke-NativeCommand "docker" @("build", "-t", $FULL_IMAGE_NAME, "./backend")
    Invoke-NativeCommand "docker" @("push", $FULL_IMAGE_NAME)
  }

  Invoke-Step "Updating Container App image and Azure OpenAI env vars" {
    Invoke-NativeCommand "az" @(
      "containerapp", "update",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--image", $FULL_IMAGE_NAME,
      "--set-env-vars",
        "AI_ANALYSIS_PROVIDER=azure_openai",
        "AZURE_OPENAI_ENDPOINT=$script:AOAI_ENDPOINT",
        "AZURE_OPENAI_DEPLOYMENT_NAME=$AOAI_DEPLOYMENT_NAME",
        "AZURE_OPENAI_API_VERSION=$AOAI_API_VERSION",
        "AZURE_OPENAI_AUTH_MODE=managed_identity",
        "AI_MAX_INPUT_CHARS=12000",
        "AI_MAX_OUTPUT_TOKENS=800",
        "AZURE_CLIENT_ID=$AZURE_CLIENT_ID",
      "--output", "table"
    )
  }

  Invoke-Step "Validating health endpoints" {
    Invoke-HttpWithRetry -Url "$APP_URL/health" -Name "/health" | ConvertTo-Json -Depth 8 | Write-Host
    Invoke-HttpWithRetry -Url "$APP_URL/ready" -Name "/ready" | ConvertTo-Json -Depth 8 | Write-Host
  }

  Invoke-Step "Writing phase5 outputs" {
    [ordered]@{
      resourceGroup = $RESOURCE_GROUP
      location = $AOAI_LOCATION
      azureOpenAIAccountName = $script:AOAI_ACCOUNT_NAME
      azureOpenAIEndpoint = $script:AOAI_ENDPOINT
      deploymentName = $AOAI_DEPLOYMENT_NAME
      containerAppName = $CONTAINER_APP_NAME
      image = $FULL_IMAGE_NAME
      appUrl = $APP_URL
      healthUrl = "$APP_URL/health"
      readyUrl = "$APP_URL/ready"
      docsUrl = "$APP_URL/docs"
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $PHASE5_OUTPUT_FILE -Encoding UTF8
    Write-Host "Outputs written to $PHASE5_OUTPUT_FILE" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
