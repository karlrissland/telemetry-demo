<#
.SYNOPSIS
    Pre-teardown cleanup, invoked by the azd `predown` hook.

.DESCRIPTION
    Releases resources that can otherwise slow down or block deletion of the
    resource group. This script is best-effort: it never fails the teardown, so
    `azd down` always proceeds.

    Currently it soft-deletes the API Management service so the name is released
    promptly rather than being held in the soft-delete state.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
# Best-effort by design: a failure here must never block `azd down`.
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot/common.ps1"

try {
    $env_ = Get-AzdEnvironment
}
catch {
    Write-Host "No azd environment available; nothing to clean up." -ForegroundColor Yellow
    return
}

Write-Step "Pre-teardown cleanup"

if ($env_.ContainsKey('APIM_SERVICE_NAME') -and -not [string]::IsNullOrWhiteSpace($env_.APIM_SERVICE_NAME)) {
    $apimName = $env_.APIM_SERVICE_NAME
    $rg = $env_.AZURE_RESOURCE_GROUP
    Write-Detail "Purging soft-deleted API Management service '$apimName' if present."

    # Consumption-tier APIM still enters a soft-deleted state on delete, which
    # blocks re-creating the same name. Purge it so redeploys are clean.
    az apim deletedservice purge --service-name $apimName --location $env_.AZURE_LOCATION 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Detail "Nothing to purge for '$apimName' in '$rg' (this is normal on a first teardown)."
    }
}
else {
    Write-Skipped "APIM_SERVICE_NAME not present in the environment."
}

Write-Detail "Cleanup complete."
