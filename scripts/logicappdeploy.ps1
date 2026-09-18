#!/usr/bin/env pwsh
# Builds and zip-deploys the Standard Logic App workflow. Called by deploy.ps1 (or run standalone after 'azd provision').
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$logicAppSource = Join-Path $repoRoot "src/logicapps/td-lg"
$stagingDir = Join-Path $repoRoot "src/logicapps/td-lg/bin/publish"
$zipPath = Join-Path $repoRoot "src/logicapps/td-lg/bin/publish.zip"

# Matches .funcignore - these are dev-time only artifacts that shouldn't ship to the deployed app.
$excludeNames = @('.debug', '.vscode', '.git', 'bin', 'workflow-designtime', 'local.settings.json')

if (-not $env:logicAppName) {
    throw "logicAppName environment variable is not set. Run 'azd provision' first."
}
if (-not $env:AZURE_RESOURCE_GROUP) {
    throw "AZURE_RESOURCE_GROUP environment variable is not set. Run 'azd provision' first."
}

Write-Host "Staging Logic App content from $logicAppSource..."
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Get-ChildItem -Path $logicAppSource -Force | Where-Object { $_.Name -notin $excludeNames } | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $stagingDir -Recurse -Force
}

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $zipPath -Force

Write-Host "Deploying to Logic App '$env:logicAppName' in resource group '$env:AZURE_RESOURCE_GROUP'..."
$maxAttempts = 3
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    az webapp deploy `
        --resource-group $env:AZURE_RESOURCE_GROUP `
        --name $env:logicAppName `
        --src-path $zipPath `
        --type zip `
        --clean true `
        --restart true

    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -eq $maxAttempts) { throw "az webapp deploy failed with exit code $LASTEXITCODE" }

    Write-Warning "Logic App zip deployment failed on attempt $attempt. Restarting the app and retrying..."
    az webapp restart --resource-group $env:AZURE_RESOURCE_GROUP --name $env:logicAppName --output none
}

Write-Host "Logic App deployment complete."
