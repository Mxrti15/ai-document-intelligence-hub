Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$OUTPUT_DIR = Join-Path $PROJECT_ROOT "outputs"
$OUTPUT_FILE = Join-Path $OUTPUT_DIR "azure-phase2-deployment.json"

$RESOURCE_GROUP = "rg-ai-doc-intel-dev"
$LOCATION = "swedencentral"
$ACR_NAME = "acidocintel$((Get-Random -Minimum 10000 -Maximum 99999))"
$CONTAINER_APP_ENV = "cae-ai-doc-intel-dev"
$CONTAINER_APP_NAME = "aca-ai-doc-intel-api-dev"
$USER_ASSIGNED_IDENTITY = "id-ai-doc-intel-aca-pull-dev"
$IMAGE_NAME = "ai-doc-intel-backend"
$IMAGE_TAG = "phase2"
$TARGET_PORT = 8000

$ACR_LOGIN_SERVER = "$ACR_NAME.azurecr.io"
$FULL_IMAGE_NAME = "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"
$ACR_ID = $null
$IDENTITY_ID = $null
$IDENTITY_PRINCIPAL_ID = $null
$FQDN = $null
$APP_URL = $null
$HEALTH_URL = $null
$READY_URL = $null

function Assert-Command {
  param([Parameter(Mandatory = $true)][string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found. Install it or run this script from an environment where it is available."
  }
}

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
      if ($text -match "^WARNING:") {
        continue
      }

      $text
    } else {
      [string]$item
    }
  }

  return (($cleanOutput | Out-String).Trim())
}

function Assert-ProviderRegistered {
  param([Parameter(Mandatory = $true)][string]$Namespace)

  $state = Invoke-NativeOutput "az" @(
    "provider", "show",
    "--namespace", $Namespace,
    "--only-show-errors",
    "--query", "registrationState",
    "--output", "tsv"
  )

  if ($state -ne "Registered") {
    throw "Azure provider '$Namespace' is not Registered. Current state: '$state'. Stop here and retry after registration completes."
  }

  Write-Host "$Namespace is Registered" -ForegroundColor Green
}

function Invoke-HttpWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Name,
    [int]$Attempts = 12,
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

function Grant-AcrPullWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$PrincipalId,
    [Parameter(Mandatory = $true)][string]$AcrId,
    [int]$Attempts = 8,
    [int]$DelaySeconds = 15
  )

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $existingRoleAssignment = Invoke-NativeOutput "az" @(
      "role", "assignment", "list",
      "--assignee-object-id", $PrincipalId,
      "--role", "AcrPull",
      "--scope", $AcrId,
      "--only-show-errors",
      "--query", "[0].id",
      "--output", "tsv"
    )

    if (-not [string]::IsNullOrWhiteSpace($existingRoleAssignment)) {
      Write-Host "AcrPull role assignment already exists." -ForegroundColor Green
      return
    }

    try {
      Write-Host "Creating AcrPull role assignment ($attempt/$Attempts)..." -ForegroundColor Cyan
      Invoke-NativeCommand "az" @(
        "role", "assignment", "create",
        "--assignee-object-id", $PrincipalId,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", "AcrPull",
        "--scope", $AcrId,
        "--output", "table"
      )
      return
    } catch {
      if ($attempt -eq $Attempts) {
        throw "Could not create AcrPull role assignment after $Attempts attempts. Last error: $($_.Exception.Message)"
      }

      Write-Warning "AcrPull assignment failed, likely due to managed identity propagation. Retrying in $DelaySeconds seconds..."
      Start-Sleep -Seconds $DelaySeconds
    }
  }
}

function Show-ContainerAppDiagnostics {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ResourceGroup
  )

  try {
    Invoke-NativeOutput "az" @(
      "containerapp", "show",
      "--name", $Name,
      "--resource-group", $ResourceGroup,
      "--only-show-errors",
      "--query", "name",
      "--output", "tsv"
    ) | Out-Null
  } catch {
    Write-Warning "Container App '$Name' does not exist or cannot be read. Skipping diagnostics."
    return
  }

  Write-Host ""
  Write-Host "==> Container App revisions after endpoint validation failure" -ForegroundColor Yellow
  try {
    Invoke-NativeCommand "az" @(
      "containerapp", "revision", "list",
      "--name", $Name,
      "--resource-group", $ResourceGroup,
      "--only-show-errors",
      "--output", "table"
    )
  } catch {
    Write-Warning "Could not list Container App revisions: $($_.Exception.Message)"
  }

  Write-Host ""
  Write-Host "==> Container App logs after endpoint validation failure" -ForegroundColor Yellow
  try {
    Invoke-NativeCommand "az" @(
      "containerapp", "logs", "show",
      "--name", $Name,
      "--resource-group", $ResourceGroup,
      "--follow", "false"
    )
  } catch {
    Write-Warning "Could not read Container App logs: $($_.Exception.Message)"
  }
}

Push-Location $PROJECT_ROOT
try {
  Invoke-Step "Checking local tooling" {
    Assert-Command "docker"
    Assert-Command "az"
    Invoke-NativeCommand "docker" @("--version")
    Invoke-NativeCommand "az" @("version", "--output", "table")

    try {
      Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    } catch {
      Write-Warning "Azure CLI is not logged in. Starting az login..."
      Invoke-NativeCommand "az" @("login")
      Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    }
  }

  Invoke-Step "Preparing Azure CLI for Container Apps" {
    Invoke-NativeCommand "az" @("extension", "add", "--name", "containerapp", "--upgrade")
    Invoke-NativeCommand "az" @("provider", "register", "--namespace", "Microsoft.ContainerRegistry", "--wait")
    Invoke-NativeCommand "az" @("provider", "register", "--namespace", "Microsoft.App", "--wait")
    Invoke-NativeCommand "az" @("provider", "register", "--namespace", "Microsoft.OperationalInsights", "--wait")
    Invoke-NativeCommand "az" @("provider", "register", "--namespace", "Microsoft.ManagedIdentity", "--wait")
  }

  Invoke-Step "Validating Azure provider registration" {
    Assert-ProviderRegistered "Microsoft.ContainerRegistry"
    Assert-ProviderRegistered "Microsoft.App"
    Assert-ProviderRegistered "Microsoft.OperationalInsights"
    Assert-ProviderRegistered "Microsoft.ManagedIdentity"
  }

  Invoke-Step "Creating resource group" {
    Invoke-NativeCommand "az" @(
      "group", "create",
      "--name", $RESOURCE_GROUP,
      "--location", $LOCATION,
      "--output", "table"
    )
  }

  Invoke-Step "Creating Azure Container Registry Basic" {
    Invoke-NativeCommand "az" @(
      "acr", "create",
      "--resource-group", $RESOURCE_GROUP,
      "--name", $ACR_NAME,
      "--sku", "Basic",
      "--admin-enabled", "false",
      "--output", "table"
    )

    $script:ACR_ID = Invoke-NativeOutput "az" @(
      "acr", "show",
      "--resource-group", $RESOURCE_GROUP,
      "--name", $ACR_NAME,
      "--only-show-errors",
      "--query", "id",
      "--output", "tsv"
    )

    $acrProvisioningState = Invoke-NativeOutput "az" @(
      "acr", "show",
      "--resource-group", $RESOURCE_GROUP,
      "--name", $ACR_NAME,
      "--only-show-errors",
      "--query", "provisioningState",
      "--output", "tsv"
    )

    if ($acrProvisioningState -ne "Succeeded") {
      throw "ACR creation did not succeed. Provisioning state: '$acrProvisioningState'. Stopping before login, docker push, or Container Apps."
    }
  }

  Invoke-Step "Creating user-assigned managed identity for ACR pull" {
    $script:IDENTITY_ID = Invoke-NativeOutput "az" @(
      "identity", "create",
      "--name", $USER_ASSIGNED_IDENTITY,
      "--resource-group", $RESOURCE_GROUP,
      "--location", $LOCATION,
      "--only-show-errors",
      "--query", "id",
      "--output", "tsv"
    )

    $script:IDENTITY_PRINCIPAL_ID = Invoke-NativeOutput "az" @(
      "identity", "show",
      "--name", $USER_ASSIGNED_IDENTITY,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "principalId",
      "--output", "tsv"
    )

    if ([string]::IsNullOrWhiteSpace($script:IDENTITY_ID) -or [string]::IsNullOrWhiteSpace($script:IDENTITY_PRINCIPAL_ID)) {
      throw "Managed identity was created, but id or principalId could not be resolved."
    }
  }

  Invoke-Step "Granting AcrPull to managed identity before Container App creation" {
    Grant-AcrPullWithRetry `
      -PrincipalId $script:IDENTITY_PRINCIPAL_ID `
      -AcrId $script:ACR_ID

    Write-Host "Waiting 45 seconds for Azure RBAC propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 45
  }

  Invoke-Step "Logging in to ACR" {
    Invoke-NativeCommand "az" @("acr", "login", "--name", $ACR_NAME)
  }

  Invoke-Step "Building backend Docker image" {
    Invoke-NativeCommand "docker" @("build", "-t", $FULL_IMAGE_NAME, "./backend")
  }

  Invoke-Step "Pushing backend Docker image to ACR" {
    Invoke-NativeCommand "docker" @("push", $FULL_IMAGE_NAME)
  }

  Invoke-Step "Creating Container Apps Environment" {
    Invoke-NativeCommand "az" @(
      "containerapp", "env", "create",
      "--name", $CONTAINER_APP_ENV,
      "--resource-group", $RESOURCE_GROUP,
      "--location", $LOCATION,
      "--output", "table"
    )

    $containerAppEnvProvisioningState = Invoke-NativeOutput "az" @(
      "containerapp", "env", "show",
      "--name", $CONTAINER_APP_ENV,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "properties.provisioningState",
      "--output", "tsv"
    )

    if ($containerAppEnvProvisioningState -ne "Succeeded") {
      throw "Container Apps Environment creation did not succeed. Provisioning state: '$containerAppEnvProvisioningState'. Stopping before Container App creation."
    }
  }

  Invoke-Step "Creating Azure Container App" {
    Invoke-NativeCommand "az" @(
      "containerapp", "create",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--environment", $CONTAINER_APP_ENV,
      "--image", $FULL_IMAGE_NAME,
      "--target-port", "$TARGET_PORT",
      "--ingress", "external",
      "--registry-server", $ACR_LOGIN_SERVER,
      "--registry-identity", $script:IDENTITY_ID,
      "--user-assigned", $script:IDENTITY_ID,
      "--min-replicas", "0",
      "--max-replicas", "1",
      "--cpu", "0.25",
      "--memory", "0.5Gi",
      "--env-vars",
        "APP_NAME=AI Document Intelligence Hub",
        "ENVIRONMENT=azure-dev",
        "DATABASE_URL=sqlite:///./data/app.db",
        "STORAGE_MODE=local",
        "LOCAL_STORAGE_PATH=./data/documents",
        "MAX_UPLOAD_SIZE_MB=10",
        "ALLOWED_EXTENSIONS=pdf",
      "--output", "table"
    )
  }

  Invoke-Step "Reading public URL" {
    $script:FQDN = Invoke-NativeOutput "az" @(
      "containerapp", "show",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "properties.configuration.ingress.fqdn",
      "--output", "tsv"
    )

    if ([string]::IsNullOrWhiteSpace($script:FQDN)) {
      throw "Container App FQDN was not returned."
    }

    $script:APP_URL = "https://$script:FQDN"
    $script:HEALTH_URL = "$script:APP_URL/health"
    $script:READY_URL = "$script:APP_URL/ready"

    Write-Host "Container App URL: $script:APP_URL" -ForegroundColor Green
    Write-Host "Health URL: $script:HEALTH_URL" -ForegroundColor Green
    Write-Host "Ready URL: $script:READY_URL" -ForegroundColor Green
  }

  Invoke-Step "Showing Container App revisions" {
    Invoke-NativeCommand "az" @(
      "containerapp", "revision", "list",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--output", "table"
    )
  }

  Invoke-Step "Validating public health endpoints" {
    try {
      Invoke-HttpWithRetry -Url $script:HEALTH_URL -Name "/health" | ConvertTo-Json -Depth 8 | Write-Host
      Invoke-HttpWithRetry -Url $script:READY_URL -Name "/ready" | ConvertTo-Json -Depth 8 | Write-Host
    } catch {
      Show-ContainerAppDiagnostics -Name $CONTAINER_APP_NAME -ResourceGroup $RESOURCE_GROUP
      throw
    }
  }

  Invoke-Step "Writing local deployment outputs" {
    New-Item -ItemType Directory -Force -Path $OUTPUT_DIR | Out-Null

    [ordered]@{
      resourceGroup = $RESOURCE_GROUP
      location = $LOCATION
      acrName = $ACR_NAME
      acrLoginServer = $ACR_LOGIN_SERVER
      containerAppEnvironment = $CONTAINER_APP_ENV
      containerAppName = $CONTAINER_APP_NAME
      image = $FULL_IMAGE_NAME
      appUrl = $script:APP_URL
      healthUrl = $script:HEALTH_URL
      readyUrl = $script:READY_URL
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $OUTPUT_FILE -Encoding UTF8

    Write-Host "Outputs written to $OUTPUT_FILE" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
