<#
.SYNOPSIS
    Deploys the Logic App Standard project to Azure.

.DESCRIPTION
    Packages src/logicapps/td-lg (host.json plus one folder per workflow) into a
    zip and pushes it to the Logic App via the Kudu zipdeploy endpoint.

    Basic publishing credentials (SCM/FTP) are disabled on the site by the Bicep
    template, so this script authenticates to Kudu with an Entra ID bearer token
    rather than a publishing profile. That keeps deployment consistent with the
    demo's no-keys rule.

    The script is idempotent: re-running it redeploys the current contents of the
    project folder.

.PARAMETER ProjectPath
    Path to the Logic App project folder containing host.json. Defaults to
    src/logicapps/td-lg.

.PARAMETER LogicAppName
    Overrides the Logic App name. Defaults to the LOGIC_APP_NAME azd output.
#>

[CmdletBinding()]
param(
    [Parameter()][string] $ProjectPath,
    [Parameter()][string] $LogicAppName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

$repoRoot = Get-RepoRoot
$env_ = Get-AzdEnvironment

if ([string]::IsNullOrWhiteSpace($LogicAppName)) {
    Assert-AzdValue -Environment $env_ -Name @('LOGIC_APP_NAME')
    $LogicAppName = $env_.LOGIC_APP_NAME
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $repoRoot 'src/logicapps/td-lg'
}

Write-Step "Deploying Logic App Standard '$LogicAppName'"

if (-not (Test-Path (Join-Path $ProjectPath 'host.json'))) {
    throw "No host.json found in '$ProjectPath'. This does not look like a Logic App Standard project."
}

$workflows = @(
    Get-ChildItem -Path $ProjectPath -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'workflow.json') } |
        Select-Object -ExpandProperty Name
)

if ($workflows.Count -eq 0) {
    Write-Skipped "No workflow.json found under '$ProjectPath'. Deploying host configuration only."
}
else {
    Write-Detail "Workflows: $($workflows -join ', ')"
}

# --- Package -----------------------------------------------------------------
# Exclude local-only artifacts so they never reach the cloud host.
$excludedNames = @('local.settings.json', '.debug', 'workflow-designtime', '.vscode', '.git')

$staging = Join-Path ([System.IO.Path]::GetTempPath()) "logicapp-$([guid]::NewGuid().ToString('N'))"
$zipPath = "$staging.zip"

try {
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    Get-ChildItem -Path $ProjectPath -Force | Where-Object { $excludedNames -notcontains $_.Name } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $staging -Recurse -Force
    }

    # Remove any excluded artifacts that were nested inside copied workflow folders.
    foreach ($name in $excludedNames) {
        Get-ChildItem -Path $staging -Filter $name -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Detail "Packaging '$ProjectPath'"
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -Force

    # --- Publish -------------------------------------------------------------
    # Kudu accepts an ARM bearer token, which is what lets this work with basic
    # publishing credentials disabled.
    Write-Detail "Requesting Entra ID token for the Kudu endpoint"
    $token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to acquire an access token. Run 'az login'."
    }

    $kuduUri = "https://$LogicAppName.scm.azurewebsites.net/api/zipdeploy"
    Write-Detail "POST $kuduUri"

    $response = Invoke-WebRequest -Uri $kuduUri `
        -Method Post `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType 'application/zip' `
        -InFile $zipPath `
        -TimeoutSec 300 `
        -SkipHttpErrorCheck

    if ($response.StatusCode -ge 400) {
        throw "Kudu zipdeploy failed with HTTP $($response.StatusCode): $($response.Content)"
    }

    Write-Detail "Deployed successfully (HTTP $($response.StatusCode))."
    if ($env_.ContainsKey('LOGIC_APP_URL')) {
        Write-Detail "Logic App: $($env_.LOGIC_APP_URL)"
    }
}
finally {
    Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
}
