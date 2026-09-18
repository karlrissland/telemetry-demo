#!/usr/bin/env pwsh
# Builds and zip-deploys the Function App. Called by deploy.ps1 (or run standalone after 'azd provision').
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$functionProject = Join-Path $repoRoot "src/function/function.csproj"
$publishDir = Join-Path $repoRoot "src/function/bin/publish"
$zipPath = Join-Path $repoRoot "src/function/bin/publish.zip"

if (-not $env:functionAppName) {
    throw "functionAppName environment variable is not set. Run 'azd provision' first."
}
if (-not $env:AZURE_RESOURCE_GROUP) {
    throw "AZURE_RESOURCE_GROUP environment variable is not set. Run 'azd provision' first."
}

Write-Host "Publishing $functionProject..."
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
$dotnetPath = Join-Path ${env:ProgramFiles} 'dotnet\dotnet.exe'
if (-not (Test-Path $dotnetPath)) {
    $dotnetPath = (Get-Command dotnet -ErrorAction Stop).Source
}

& $dotnetPath publish $functionProject -c Release -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -Force

Write-Host "Deploying to Function App '$env:functionAppName' in resource group '$env:AZURE_RESOURCE_GROUP'..."
$storageAccountName = az webapp config appsettings list `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:functionAppName `
    --query "[?name=='AzureWebJobsStorage__accountName'].value | [0]" `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $storageAccountName) {
    throw "Could not determine the Function App storage account."
}

$storageKey = az storage account keys list `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --account-name $storageAccountName `
    --query "[0].value" `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $storageKey) {
    throw "Could not obtain the Function App storage account key."
}

$containerName = "function-releases"
$blobName = "function-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).zip"
$expiry = [DateTime]::UtcNow.AddHours(24).ToString('yyyy-MM-ddTHH:mmZ')

az storage container create `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --name $containerName `
    --public-access off `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Could not create the Function App deployment container." }

az storage blob upload `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --container-name $containerName `
    --name $blobName `
    --file $zipPath `
    --overwrite true `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Could not upload the Function App package." }

$packageUrl = az storage blob generate-sas `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --container-name $containerName `
    --name $blobName `
    --permissions r `
    --expiry $expiry `
    --https-only `
    --full-uri `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $packageUrl) { throw "Could not generate a SAS URL for the Function App package." }

$appId = az functionapp show `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:functionAppName `
    --query id `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $appId) { throw "Could not determine the Function App resource ID." }

$appSettingsBodyPath = Join-Path $env:TEMP "function-appsettings-$([Guid]::NewGuid()).json"
$currentAppSettings = az rest `
    --method post `
    --url "https://management.azure.com${appId}/config/appsettings/list?api-version=2022-03-01" `
    --query properties `
    --output json | ConvertFrom-Json -AsHashtable
if ($LASTEXITCODE -ne 0 -or -not $currentAppSettings) { throw "Could not read existing Function App settings." }

$currentAppSettings['WEBSITE_RUN_FROM_PACKAGE'] = $packageUrl
@{
    properties = $currentAppSettings
} | ConvertTo-Json -Depth 20 -Compress | Set-Content -Path $appSettingsBodyPath -Encoding utf8NoBOM

try {
    az rest `
        --method put `
        --url "https://management.azure.com${appId}/config/appsettings?api-version=2022-03-01" `
        --body "@$appSettingsBodyPath" `
        --headers Content-Type=application/json `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "Could not configure the Function App remote package." }
} finally {
    Remove-Item $appSettingsBodyPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Function app deployment complete."
