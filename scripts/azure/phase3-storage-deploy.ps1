Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE3_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase3-storage.json"

if (-not (Test-Path $PHASE2_OUTPUT_FILE)) {
  throw "Falta outputs/azure-phase2-deployment.json. Ejecuta primero Fase 2."
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$existingPhase3 = if (Test-Path $PHASE3_OUTPUT_FILE) {
  Get-Content -Path $PHASE3_OUTPUT_FILE -Raw | ConvertFrom-Json
} else {
  $null
}

$RESOURCE_GROUP = $phase2.resourceGroup
$LOCATION = $phase2.location
$ACR_NAME = $phase2.acrName
$ACR_LOGIN_SERVER = $phase2.acrLoginServer
$CONTAINER_APP_NAME = $phase2.containerAppName
$APP_URL = $phase2.appUrl

$STORAGE_ACCOUNT_NAME = if ($null -ne $existingPhase3 -and $existingPhase3.storageAccountName) {
  $existingPhase3.storageAccountName
} else {
  "aidocintel$((Get-Random -Minimum 10000 -Maximum 99999))"
}
$STORAGE_CONTAINER_NAME = if ($null -ne $existingPhase3 -and $existingPhase3.storageContainerName) {
  $existingPhase3.storageContainerName
} else {
  "documents"
}
$IMAGE_NAME = "ai-doc-intel-backend"
$IMAGE_TAG = "phase3"
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

function Grant-StorageBlobRoleWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$PrincipalId,
    [Parameter(Mandatory = $true)][string]$StorageAccountId,
    [int]$Attempts = 8,
    [int]$DelaySeconds = 15
  )

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $existingRoleAssignment = Invoke-NativeOutput "az" @(
      "role", "assignment", "list",
      "--assignee-object-id", $PrincipalId,
      "--role", "Storage Blob Data Contributor",
      "--scope", $StorageAccountId,
      "--only-show-errors",
      "--query", "[0].id",
      "--output", "tsv"
    )

    if (-not [string]::IsNullOrWhiteSpace($existingRoleAssignment)) {
      Write-Host "Storage Blob Data Contributor role assignment already exists." -ForegroundColor Green
      return
    }

    try {
      Write-Host "Creating Storage Blob Data Contributor role assignment ($attempt/$Attempts)..." -ForegroundColor Cyan
      Invoke-NativeCommand "az" @(
        "role", "assignment", "create",
        "--assignee-object-id", $PrincipalId,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", "Storage Blob Data Contributor",
        "--scope", $StorageAccountId,
        "--output", "table"
      )
      return
    } catch {
      if ($attempt -eq $Attempts) {
        throw "Could not create Storage Blob Data Contributor role assignment after $Attempts attempts. Last error: $($_.Exception.Message)"
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
    throw "Azure provider '$Namespace' is not Registered. Current state: '$state'."
  }

  Write-Host "$Namespace is Registered" -ForegroundColor Green
}

Push-Location $PROJECT_ROOT
try {
  Invoke-Step "Checking tooling and Azure state" {
    Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    Invoke-NativeCommand "docker" @("--version")
  }

  Invoke-Step "Registering Azure Storage provider" {
    Invoke-NativeCommand "az" @("provider", "register", "--namespace", "Microsoft.Storage", "--wait")
    Assert-ProviderRegistered "Microsoft.Storage"
  }

  Invoke-Step "Creating Storage Account" {
    Invoke-NativeCommand "az" @(
      "storage", "account", "create",
      "--name", $STORAGE_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--location", $LOCATION,
      "--sku", "Standard_LRS",
      "--kind", "StorageV2",
      "--min-tls-version", "TLS1_2",
      "--allow-blob-public-access", "false",
      "--output", "table"
    )
  }

  Invoke-Step "Creating Blob container" {
    $storageKey = Invoke-NativeOutput "az" @(
      "storage", "account", "keys", "list",
      "--account-name", $STORAGE_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "[0].value",
      "--output", "tsv"
    )

    Invoke-NativeCommand "az" @(
      "storage", "container", "create",
      "--name", $STORAGE_CONTAINER_NAME,
      "--account-name", $STORAGE_ACCOUNT_NAME,
      "--account-key", $storageKey,
      "--public-access", "off",
      "--output", "table"
    )
  }

  Invoke-Step "Resolving Container App managed identity" {
    $identityPrincipalId = Invoke-NativeOutput "az" @(
      "containerapp", "show",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "identity.principalId",
      "--output", "tsv"
    )

    if ([string]::IsNullOrWhiteSpace($identityPrincipalId)) {
      $identityPrincipalId = Invoke-NativeOutput "az" @(
        "containerapp", "show",
        "--name", $CONTAINER_APP_NAME,
        "--resource-group", $RESOURCE_GROUP,
        "--only-show-errors",
        "--query", "identity.userAssignedIdentities.*.principalId | [0]",
        "--output", "tsv"
      )
    }

    $identityClientId = Invoke-NativeOutput "az" @(
      "containerapp", "show",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "identity.userAssignedIdentities.*.clientId | [0]",
      "--output", "tsv"
    )

    if ([string]::IsNullOrWhiteSpace($identityPrincipalId)) {
      throw "Could not resolve Container App managed identity principalId."
    }

    if ([string]::IsNullOrWhiteSpace($identityClientId)) {
      throw "Could not resolve Container App user-assigned managed identity clientId."
    }

    $script:CONTAINER_APP_PRINCIPAL_ID = $identityPrincipalId
    $script:CONTAINER_APP_CLIENT_ID = $identityClientId
  }

  Invoke-Step "Granting Storage Blob Data Contributor to Container App identity" {
    $storageAccountId = Invoke-NativeOutput "az" @(
      "storage", "account", "show",
      "--name", $STORAGE_ACCOUNT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "id",
      "--output", "tsv"
    )

    Grant-StorageBlobRoleWithRetry `
      -PrincipalId $script:CONTAINER_APP_PRINCIPAL_ID `
      -StorageAccountId $storageAccountId

    Write-Host "Waiting 60 seconds for Azure RBAC propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
  }

  Invoke-Step "Building backend image phase3" {
    Invoke-NativeCommand "az" @("acr", "login", "--name", $ACR_NAME)
    Invoke-NativeCommand "docker" @("build", "-t", $FULL_IMAGE_NAME, "./backend")
  }

  Invoke-Step "Pushing backend image phase3" {
    Invoke-NativeCommand "docker" @("push", $FULL_IMAGE_NAME)
  }

  Invoke-Step "Updating Container App image and Blob env vars" {
    Invoke-NativeCommand "az" @(
      "containerapp", "update",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--image", $FULL_IMAGE_NAME,
      "--set-env-vars",
        "STORAGE_MODE=azure_blob",
        "AZURE_STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME",
        "AZURE_STORAGE_CONTAINER_NAME=$STORAGE_CONTAINER_NAME",
        "AZURE_CLIENT_ID=$script:CONTAINER_APP_CLIENT_ID",
      "--output", "table"
    )
  }

  Invoke-Step "Validating health endpoints" {
    Invoke-HttpWithRetry -Url "$APP_URL/health" -Name "/health" | ConvertTo-Json -Depth 8 | Write-Host
    Invoke-HttpWithRetry -Url "$APP_URL/ready" -Name "/ready" | ConvertTo-Json -Depth 8 | Write-Host
  }

  Invoke-Step "Writing phase3 outputs" {
    [ordered]@{
      resourceGroup = $RESOURCE_GROUP
      location = $LOCATION
      storageAccountName = $STORAGE_ACCOUNT_NAME
      storageContainerName = $STORAGE_CONTAINER_NAME
      azureClientId = $script:CONTAINER_APP_CLIENT_ID
      containerAppName = $CONTAINER_APP_NAME
      image = $FULL_IMAGE_NAME
      appUrl = $APP_URL
      healthUrl = "$APP_URL/health"
      readyUrl = "$APP_URL/ready"
      docsUrl = "$APP_URL/docs"
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $PHASE3_OUTPUT_FILE -Encoding UTF8

    Write-Host "Outputs written to $PHASE3_OUTPUT_FILE" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
