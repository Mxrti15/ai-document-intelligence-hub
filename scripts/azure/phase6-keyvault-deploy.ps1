Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE3_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase3-storage.json"
$PHASE4_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase4-sql.json"
$PHASE5_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase5-openai.json"
$PHASE6_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase6-keyvault.json"

foreach ($file in @($PHASE2_OUTPUT_FILE, $PHASE3_OUTPUT_FILE, $PHASE4_OUTPUT_FILE, $PHASE5_OUTPUT_FILE)) {
  if (-not (Test-Path $file)) {
    throw "Missing output file: $file. Ejecuta primero las fases anteriores."
  }
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase4 = Get-Content -Path $PHASE4_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase5 = Get-Content -Path $PHASE5_OUTPUT_FILE -Raw | ConvertFrom-Json
$existingPhase6 = if (Test-Path $PHASE6_OUTPUT_FILE) {
  Get-Content -Path $PHASE6_OUTPUT_FILE -Raw | ConvertFrom-Json
} else {
  $null
}

$RESOURCE_GROUP = $phase2.resourceGroup
$LOCATION = $phase2.location
$CONTAINER_APP_NAME = $phase2.containerAppName
$SQL_SERVER_NAME = $phase4.sqlServerName
$APP_URL = $phase5.appUrl
$KEY_VAULT_SECRET_NAME = "sql-password"
$KEY_VAULT_NAME = $null

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
    [int]$DelaySeconds = 15
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

function Test-KeyVaultExists {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & az keyvault show `
      --name $script:KEY_VAULT_NAME `
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

  throw "Could not check Key Vault existence. az exit code: ${exitCode}`n$text"
}

function Resolve-KeyVaultName {
  if ($null -ne $existingPhase6 -and $existingPhase6.keyVaultName) {
    return $existingPhase6.keyVaultName
  }

  $existingKeyVaultName = Invoke-NativeOutput "az" @(
    "keyvault", "list",
    "--resource-group", $RESOURCE_GROUP,
    "--only-show-errors",
    "--query", "[?starts_with(name, 'aidockv')] | [0].name",
    "--output", "tsv"
  )

  if (-not [string]::IsNullOrWhiteSpace($existingKeyVaultName)) {
    Write-Host "Reusing existing Key Vault: $existingKeyVaultName" -ForegroundColor Green
    return $existingKeyVaultName
  }

  return "aidockv$((Get-Random -Minimum 10000 -Maximum 99999))"
}

function Grant-RoleWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$PrincipalId,
    [Parameter(Mandatory = $true)][string]$PrincipalType,
    [Parameter(Mandatory = $true)][string]$Role,
    [Parameter(Mandatory = $true)][string]$Scope,
    [int]$Attempts = 8,
    [int]$DelaySeconds = 15
  )

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $existingRoleAssignment = Invoke-NativeOutput "az" @(
      "role", "assignment", "list",
      "--assignee-object-id", $PrincipalId,
      "--role", $Role,
      "--scope", $Scope,
      "--only-show-errors",
      "--query", "[0].id",
      "--output", "tsv"
    )

    if (-not [string]::IsNullOrWhiteSpace($existingRoleAssignment)) {
      Write-Host "$Role role assignment already exists." -ForegroundColor Green
      return
    }

    try {
      Write-Host "Creating $Role role assignment ($attempt/$Attempts)..." -ForegroundColor Cyan
      Invoke-NativeCommand "az" @(
        "role", "assignment", "create",
        "--assignee-object-id", $PrincipalId,
        "--assignee-principal-type", $PrincipalType,
        "--role", $Role,
        "--scope", $Scope,
        "--output", "table"
      )
      return
    } catch {
      if ($attempt -eq $Attempts) {
        throw "Could not create role assignment '$Role' after $Attempts attempts. Last error: $($_.Exception.Message)"
      }
      Write-Warning "Role assignment failed, likely due to propagation. Retrying in $DelaySeconds seconds..."
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

function New-SqlPassword {
  Add-Type -AssemblyName System.Web
  return ([System.Web.Security.Membership]::GeneratePassword(24, 6) + "aA1!")
}

Push-Location $PROJECT_ROOT
try {
  Invoke-Step "Checking tooling and providers" {
    Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    Assert-ProviderRegistered "Microsoft.KeyVault"
    $script:KEY_VAULT_NAME = Resolve-KeyVaultName
  }

  Invoke-Step "Creating Key Vault with RBAC" {
    if (Test-KeyVaultExists) {
      Write-Host "Key Vault already exists: $script:KEY_VAULT_NAME" -ForegroundColor Green
    } else {
      Invoke-NativeCommand "az" @(
        "keyvault", "create",
        "--name", $script:KEY_VAULT_NAME,
        "--resource-group", $RESOURCE_GROUP,
        "--location", $LOCATION,
        "--sku", "standard",
        "--enable-rbac-authorization", "true",
        "--output", "table"
      )
    }

    $script:KEY_VAULT_ID = Invoke-NativeOutput "az" @(
      "keyvault", "show",
      "--name", $script:KEY_VAULT_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "id",
      "--output", "tsv"
    )
  }

  Invoke-Step "Resolving principals" {
    $script:CURRENT_USER_OBJECT_ID = Invoke-NativeOutput "az" @(
      "ad", "signed-in-user", "show",
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

    $identityJson = Invoke-NativeOutput "az" @(
      "containerapp", "show",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--only-show-errors",
      "--query", "identity.userAssignedIdentities",
      "--output", "json"
    )
    $identityMap = $identityJson | ConvertFrom-Json
    $identityProperties = @($identityMap.PSObject.Properties)
    $script:CONTAINER_APP_IDENTITY_RESOURCE_ID = if ($identityProperties.Length -gt 0) {
      $identityProperties[0].Name
    } else {
      $null
    }

    if ([string]::IsNullOrWhiteSpace($script:CURRENT_USER_OBJECT_ID)) {
      throw "Could not resolve signed-in user object id."
    }
    if ([string]::IsNullOrWhiteSpace($script:CONTAINER_APP_PRINCIPAL_ID)) {
      throw "Could not resolve Container App managed identity principalId."
    }
    if ([string]::IsNullOrWhiteSpace($script:CONTAINER_APP_IDENTITY_RESOURCE_ID)) {
      throw "Could not resolve Container App user-assigned managed identity resource id."
    }
  }

  Invoke-Step "Granting Key Vault RBAC roles" {
    Grant-RoleWithRetry `
      -PrincipalId $script:CURRENT_USER_OBJECT_ID `
      -PrincipalType "User" `
      -Role "Key Vault Secrets Officer" `
      -Scope $script:KEY_VAULT_ID

    Grant-RoleWithRetry `
      -PrincipalId $script:CONTAINER_APP_PRINCIPAL_ID `
      -PrincipalType "ServicePrincipal" `
      -Role "Key Vault Secrets User" `
      -Scope $script:KEY_VAULT_ID

    Write-Host "Waiting 90 seconds for Key Vault RBAC propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 90
  }

  Invoke-Step "Rotating SQL password into Key Vault" {
    $newSqlPassword = New-SqlPassword

    Invoke-NativeCommand "az" @(
      "keyvault", "secret", "set",
      "--vault-name", $script:KEY_VAULT_NAME,
      "--name", $KEY_VAULT_SECRET_NAME,
      "--value", $newSqlPassword,
      "--only-show-errors",
      "--query", "{id:id, enabled:attributes.enabled}",
      "--output", "table"
    )

    $script:SECRET_ID = Invoke-NativeOutput "az" @(
      "keyvault", "secret", "show",
      "--vault-name", $script:KEY_VAULT_NAME,
      "--name", $KEY_VAULT_SECRET_NAME,
      "--only-show-errors",
      "--query", "id",
      "--output", "tsv"
    )

    Invoke-NativeCommand "az" @(
      "sql", "server", "update",
      "--name", $SQL_SERVER_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--admin-password", $newSqlPassword,
      "--only-show-errors",
      "--output", "table"
    )

    Remove-Variable -Name newSqlPassword -ErrorAction SilentlyContinue
  }

  Invoke-Step "Configuring Container App Key Vault secret reference" {
    Invoke-NativeCommand "az" @(
      "containerapp", "secret", "set",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--secrets", "sql-password=keyvaultref:$script:SECRET_ID,identityref:$script:CONTAINER_APP_IDENTITY_RESOURCE_ID"
    )

    Invoke-NativeCommand "az" @(
      "containerapp", "update",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--set-env-vars", "AZURE_SQL_PASSWORD=secretref:sql-password",
      "--output", "table"
    )

    Write-Host "Waiting 60 seconds for Container App revision and Key Vault reference propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
  }

  Invoke-Step "Validating health endpoints" {
    Invoke-HttpWithRetry -Url "$APP_URL/health" -Name "/health" | ConvertTo-Json -Depth 8 | Write-Host
    Invoke-HttpWithRetry -Url "$APP_URL/ready" -Name "/ready" | ConvertTo-Json -Depth 8 | Write-Host
  }

  Invoke-Step "Writing phase6 outputs" {
    [ordered]@{
      resourceGroup = $RESOURCE_GROUP
      location = $LOCATION
      keyVaultName = $script:KEY_VAULT_NAME
      keyVaultSecretName = $KEY_VAULT_SECRET_NAME
      containerAppName = $CONTAINER_APP_NAME
      sqlServerName = $SQL_SERVER_NAME
      appUrl = $APP_URL
      healthUrl = "$APP_URL/health"
      readyUrl = "$APP_URL/ready"
      docsUrl = "$APP_URL/docs"
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $PHASE6_OUTPUT_FILE -Encoding UTF8
    Write-Host "Outputs written to $PHASE6_OUTPUT_FILE" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
