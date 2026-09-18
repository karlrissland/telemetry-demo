#!/usr/bin/env pwsh
# Applies the MCAPS exemption tag before Azure evaluates the infrastructure deployment.
$ErrorActionPreference = "Stop"

$resourceGroup = azd env get-value AZURE_RESOURCE_GROUP 2>$null
$location = azd env get-value AZURE_LOCATION 2>$null

if (-not $resourceGroup -or $resourceGroup -eq "null") {
    throw "AZURE_RESOURCE_GROUP is not available in the azd environment."
}
if (-not $location -or $location -eq "null") {
    throw "AZURE_LOCATION is not available in the azd environment."
}

$exists = az group exists --name $resourceGroup | ConvertFrom-Json
if ($exists) {
    az group update --name $resourceGroup --set tags.SecurityControl=Ignore --output none
} else {
    az group create --name $resourceGroup --location $location --tags SecurityControl=Ignore --output none
}

Write-Host "Resource group '$resourceGroup' tagged SecurityControl=Ignore."
