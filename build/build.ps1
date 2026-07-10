[CmdletBinding()]
param(
    [string] $ArtifactsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'src\WinPush\WinPush.psd1'
$moduleName = 'WinPush'
$srcPath = Join-Path -Path $repoRoot -ChildPath 'src'
$testsPath = Join-Path -Path $repoRoot -ChildPath 'tests'
$buildPath = Join-Path -Path $repoRoot -ChildPath 'build'
$settingsPath = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'

if ([string]::IsNullOrWhiteSpace($ArtifactsPath)) {
    $ArtifactsPath = Join-Path -Path $repoRoot -ChildPath 'artifacts\build'
}

$ArtifactsPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArtifactsPath)
$testResultsPath = Join-Path -Path $ArtifactsPath -ChildPath 'pester-results.xml'
$coverageSummaryPath = Join-Path -Path $ArtifactsPath -ChildPath 'coverage-summary.txt'

if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version] '7.6') {
    throw 'WinPush build requires PowerShell 7.6 Core or later.'
}

foreach ($requiredCommand in @('Test-ModuleManifest', 'Import-Module', 'Invoke-Pester', 'Invoke-ScriptAnalyzer')) {
    if (-not (Get-Command -Name $requiredCommand -ErrorAction SilentlyContinue)) {
        throw "Required command '$requiredCommand' is not available. Install the required module before running the build gate."
    }
}

New-Item -Path $ArtifactsPath -ItemType Directory -Force | Out-Null

Test-ModuleManifest -Path $manifestPath | Out-Null

Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
Import-Module -Name $manifestPath -Force
Import-Module -Name $manifestPath -Force

$analysisTargets = @($srcPath, $testsPath, $buildPath)
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

$testResult = Invoke-Pester @pesterParameters

if ($testResult.PSObject.Properties.Name -contains 'CodeCoverage') {
    $testResult.CodeCoverage | Out-File -FilePath $coverageSummaryPath -Encoding utf8
}
else {
    'Code coverage summary was not exposed by the installed Pester version.' |
        Out-File -FilePath $coverageSummaryPath -Encoding utf8
}

if ($testResult.FailedCount -gt 0) {
    throw "Pester reported $($testResult.FailedCount) failing test(s)."
}

[pscustomobject] @{
    Manifest       = $manifestPath
    AnalyzerConfig = $settingsPath
    TestResults    = $testResultsPath
    Coverage       = $coverageSummaryPath
    Passed         = $true
}
