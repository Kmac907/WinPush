[CmdletBinding()]
param(
    [string] $ArtifactsPath,

    [string] $PsrpTarget,

    [string] $WinRsTarget,

    [string] $PsExecTarget,

    [string] $PsExecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'WinPush.psd1'
$moduleName = 'WinPush'
$srcPath = Join-Path -Path $repoRoot -ChildPath 'src'
$testsPath = Join-Path -Path $repoRoot -ChildPath 'tests'
$buildPath = Join-Path -Path $repoRoot -ChildPath 'build'
$installerPath = Join-Path -Path $repoRoot -ChildPath 'install.ps1'
$settingsPath = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$smokeScriptPath = Join-Path -Path $testsPath -ChildPath 'Integration\Invoke-WinPushTransportSmoke.ps1'
$requiredPesterVersion = [version] '3.4.0'
$minimumCoveragePercent = 82.09

if ([string]::IsNullOrWhiteSpace($ArtifactsPath)) {
    $ArtifactsPath = Join-Path -Path $repoRoot -ChildPath 'artifacts\build'
}

$ArtifactsPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArtifactsPath)
$testResultsPath = Join-Path -Path $ArtifactsPath -ChildPath 'pester-results.xml'
$coverageSummaryPath = Join-Path -Path $ArtifactsPath -ChildPath 'coverage-summary.txt'

if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version] '7.6') {
    throw 'WinPush build requires PowerShell 7.6 Core or later.'
}

foreach ($requiredCommand in @('Test-ModuleManifest', 'Import-Module', 'Invoke-ScriptAnalyzer')) {
    if (-not (Get-Command -Name $requiredCommand -ErrorAction SilentlyContinue)) {
        throw "Required command '$requiredCommand' is not available. Install the required module before running the build gate."
    }
}

$availablePester = Get-Module -Name Pester -ListAvailable |
    Where-Object { $_.Version -eq $requiredPesterVersion } |
    Select-Object -First 1
if ($null -eq $availablePester) {
    throw "Required Pester version $requiredPesterVersion is not available. Install Pester $requiredPesterVersion before running the build gate."
}

$pesterModule = Import-Module -Name $availablePester.Path -Force -PassThru
$invokePester = $pesterModule.ExportedCommands['Invoke-Pester']
if ($null -eq $invokePester) {
    throw "Pester $requiredPesterVersion did not export Invoke-Pester."
}

if (-not [string]::IsNullOrWhiteSpace($PsExecPath) -and [string]::IsNullOrWhiteSpace($PsExecTarget)) {
    throw 'PsExecPath requires PsExecTarget.'
}

if (-not [string]::IsNullOrWhiteSpace($PsExecTarget)) {
    if ([string]::IsNullOrWhiteSpace($PsExecPath)) {
        throw 'PsExecTarget requires an explicit PsExecPath.'
    }

    $psExecItem = Get-Item -LiteralPath $PsExecPath -ErrorAction SilentlyContinue
    if ($null -eq $psExecItem -or $psExecItem.PSIsContainer -or $psExecItem.Extension -ne '.exe') {
        throw "PsExecPath must reference an existing .exe file: $PsExecPath"
    }

    $PsExecPath = $psExecItem.FullName
}

New-Item -Path $ArtifactsPath -ItemType Directory -Force | Out-Null

Test-ModuleManifest -Path $manifestPath | Out-Null

Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
Import-Module -Name $manifestPath -Force

$analysisTargets = @($srcPath, $testsPath, $buildPath, $installerPath)
$analysisResults = foreach ($analysisTarget in $analysisTargets) {
    Invoke-ScriptAnalyzer -Path $analysisTarget -Settings $settingsPath -Recurse
}
if ($analysisResults) {
    $analysisResults | Format-Table -AutoSize | Out-String | Write-Error
}

$coverageTargets = Get-ChildItem -Path $srcPath -Filter '*.ps1' -File -Recurse |
    Select-Object -ExpandProperty FullName

$pesterParameters = @{
    Script       = Join-Path -Path $testsPath -ChildPath 'Unit'
    PassThru     = $true
    OutputFormat = 'NUnitXml'
    OutputFile   = $testResultsPath
}

if ($coverageTargets) {
    $pesterParameters['CodeCoverage'] = $coverageTargets
}

$testResult = & $invokePester @pesterParameters

if ($testResult.FailedCount -gt 0) {
    throw "Pester reported $($testResult.FailedCount) failing test(s)."
}

if ($testResult.PSObject.Properties.Name -notcontains 'CodeCoverage' -or $null -eq $testResult.CodeCoverage) {
    throw 'Pester did not return code coverage results.'
}

$coverage = $testResult.CodeCoverage
$coverage | Out-File -FilePath $coverageSummaryPath -Encoding utf8
if ($coverage.NumberOfCommandsAnalyzed -eq 0) {
    throw 'Pester code coverage analyzed no commands.'
}

$coveragePercent = 100 * $coverage.NumberOfCommandsExecuted / $coverage.NumberOfCommandsAnalyzed
if ($coveragePercent -lt $minimumCoveragePercent) {
    throw "Code coverage $coveragePercent percent is below the required $minimumCoveragePercent percent."
}

if (-not [string]::IsNullOrWhiteSpace($PsrpTarget)) {
    & $smokeScriptPath -ComputerName $PsrpTarget -Transport Psrp | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($WinRsTarget)) {
    & $smokeScriptPath -ComputerName $WinRsTarget -Transport WinRM | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($PsExecTarget)) {
    & $smokeScriptPath -ComputerName $PsExecTarget -Transport PsExec -PsExecPath $PsExecPath | Out-Null
}

[pscustomobject] @{
    Manifest       = $manifestPath
    AnalyzerConfig = $settingsPath
    TestResults    = $testResultsPath
    Coverage       = $coverageSummaryPath
    Passed         = $true
}
