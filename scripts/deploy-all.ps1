<#
.SYNOPSIS
    Deploys all application code onto the infrastructure provisioned by azd.

.DESCRIPTION
    Invoked by the azd `postprovision` hook. azd's built-in service deployment is
    deliberately not used, because it does not cover Logic App Standard workflows
    or APIM API definitions.

    Every stage is idempotent and skips itself cleanly when the corresponding
    source directory does not exist yet, so this script is safe to run against a
    partially built demo.

.NOTES
    Stages run in dependency order:
      1. Function      (.NET 8 isolated, C#)
      2. Logic App     (Standard workflows)
      3. Container App (Python image -> ACR -> revision)
      4. APIM          (extractor/publisher artifacts)
#>

[CmdletBinding()]
param(
    [Parameter()][switch] $SkipFunction,
    [Parameter()][switch] $SkipLogicApp,
    [Parameter()][switch] $SkipContainerApp,
    [Parameter()][switch] $SkipApim
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

$repoRoot = Get-RepoRoot
$env_ = Get-AzdEnvironment

Assert-AzdValue -Environment $env_ -Name @(
    'AZURE_SUBSCRIPTION_ID',
    'AZURE_RESOURCE_GROUP'
)

Write-Step "Deploying applications to '$($env_.AZURE_RESOURCE_GROUP)'"
Write-Detail "Subscription : $($env_.AZURE_SUBSCRIPTION_ID)"
Write-Detail "Location     : $($env_.AZURE_LOCATION)"

# --- 1. Azure Function --------------------------------------------------------
if ($SkipFunction) {
    Write-Step "Function"; Write-Skipped "-SkipFunction was specified."
}
elseif (-not (Test-Path (Join-Path $repoRoot 'src/function'))) {
    Write-Step "Function"; Write-Skipped "src/function does not exist yet."
}
else {
    & "$PSScriptRoot/deploy-function.ps1"
}

# --- 2. Logic App Standard ----------------------------------------------------
if ($SkipLogicApp) {
    Write-Step "Logic App"; Write-Skipped "-SkipLogicApp was specified."
}
elseif (-not (Test-Path (Join-Path $repoRoot 'src/logicapp'))) {
    Write-Step "Logic App"; Write-Skipped "src/logicapp does not exist yet."
}
else {
    & "$PSScriptRoot/deploy-logicapp.ps1"
}

# --- 3. Container App ---------------------------------------------------------
if ($SkipContainerApp) {
    Write-Step "Container App"; Write-Skipped "-SkipContainerApp was specified."
}
elseif (-not (Test-Path (Join-Path $repoRoot 'src/containerapp'))) {
    Write-Step "Container App"; Write-Skipped "src/containerapp does not exist yet."
}
else {
    & "$PSScriptRoot/deploy-containerapp.ps1"
}

# --- 4. APIM ------------------------------------------------------------------
if ($SkipApim) {
    Write-Step "APIM"; Write-Skipped "-SkipApim was specified."
}
elseif (-not (Test-Path (Join-Path $repoRoot 'apim'))) {
    Write-Step "APIM"; Write-Skipped "apim/ does not exist yet."
}
else {
    & "$PSScriptRoot/deploy-apim.ps1"
}

Write-Step "Application deployment complete"
if ($env_.ContainsKey('APIM_GATEWAY_URL')) {
    Write-Detail "APIM gateway  : $($env_.APIM_GATEWAY_URL)"
}
if ($env_.ContainsKey('CONTAINER_APP_URL')) {
    Write-Detail "Container App : $($env_.CONTAINER_APP_URL)"
}
Write-Host ""
