#!/usr/bin/env pwsh
# Orchestrates app code deployment after 'azd provision': Function App then Logic App.
$ErrorActionPreference = "Stop"

Write-Host "=== Deploying Function App ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "functiondeploy.ps1")
if ($LASTEXITCODE -ne 0) { throw "functiondeploy.ps1 failed with exit code $LASTEXITCODE" }

Write-Host "=== Deploying Logic App ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "logicappdeploy.ps1")
if ($LASTEXITCODE -ne 0) { throw "logicappdeploy.ps1 failed with exit code $LASTEXITCODE" }

Write-Host "Deployment complete." -ForegroundColor Green
