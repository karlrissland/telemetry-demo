<#
.SYNOPSIS
    Common helpers for the telemetry demo deployment scripts.

.DESCRIPTION
    Loads azd environment values into a hashtable and provides small utilities
    used by every deployment script. Dot-source this from other scripts:

        . "$PSScriptRoot/common.ps1"

    Nothing here writes to Azure; it only reads the azd environment.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message
    )
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Detail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message
    )
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Skipped {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message
    )
    Write-Host "    SKIPPED: $Message" -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Reads `azd env get-values` into a hashtable.

.DESCRIPTION
    These values come from the Bicep outputs in infra/main.bicep and are the
    contract between infrastructure and application deployment. Never hard-code
    a resource name in a deployment script; read it from here.
#>
function Get-AzdEnvironment {
    [CmdletBinding()]
    param()

    $raw = azd env get-values 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read the azd environment. Run 'azd env select <name>' first."
    }

    $values = @{}
    foreach ($line in $raw) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            # azd quotes values; strip a single layer of surrounding quotes.
            if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$key] = $value
        }
    }
    return $values
}

<#
.SYNOPSIS
    Throws unless every named key is present and non-empty in the environment.
#>
function Assert-AzdValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Environment,
        [Parameter(Mandatory)][string[]] $Name
    )

    $missing = @()
    foreach ($key in $Name) {
        if (-not $Environment.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($Environment[$key])) {
            $missing += $key
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing azd environment value(s): $($missing -join ', '). Run 'azd provision' first."
    }
}

<#
.SYNOPSIS
    Runs a native command and throws if it returns a non-zero exit code.

.DESCRIPTION
    PowerShell does not fail on non-zero exit codes from native executables, so
    every az/docker/func call in these scripts goes through this wrapper.
#>
function Invoke-Native {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Command,
        [Parameter(ValueFromRemainingArguments)][string[]] $Arguments
    )

    Write-Detail "$Command $($Arguments -join ' ')"
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Command $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

<#
.SYNOPSIS
    Returns the absolute path to the repository root.
#>
function Get-RepoRoot {
    [CmdletBinding()]
    param()
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
