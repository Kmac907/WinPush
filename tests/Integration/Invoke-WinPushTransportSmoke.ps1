#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ComputerName,

    [Parameter(Mandatory)]
    [ValidateSet('Psrp', 'WinRM', 'PsExec')]
    [string] $Transport,

    [string] $PsExecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Transport -eq 'PsExec') {
    if ([string]::IsNullOrWhiteSpace($PsExecPath)) {
        throw 'PsExec transport smoke requires an explicit PsExecPath.'
    }

    $psExecItem = Get-Item -LiteralPath $PsExecPath -ErrorAction SilentlyContinue
    if ($null -eq $psExecItem -or $psExecItem.PSIsContainer -or $psExecItem.Extension -ne '.exe') {
        throw "PsExecPath must reference an existing .exe file: $PsExecPath"
    }

    $PsExecPath = $psExecItem.FullName
}
elseif (-not [string]::IsNullOrWhiteSpace($PsExecPath)) {
    throw 'PsExecPath is only valid for the PsExec transport smoke.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'WinPush.psd1') -Force

$commandParameters = @{
    ComputerName = $ComputerName
    Command      = 'hostname'
    Transport    = $Transport
}
if ($Transport -eq 'PsExec') {
    $commandParameters['PsExecPath'] = $PsExecPath
}

$results = @(Invoke-WinPushCommand @commandParameters)
if ($results.Count -ne 1 -or -not $results[0].Succeeded) {
    $errorMessage = if ($results.Count -eq 1) { $results[0].ErrorMessage } else { "returned $($results.Count) results" }
    throw "$Transport smoke failed for '$ComputerName': $errorMessage"
}

$results[0]
