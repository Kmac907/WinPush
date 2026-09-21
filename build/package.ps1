[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$releasePath = Join-Path -Path $repoRoot -ChildPath 'artifacts\release'
$modulePath = Join-Path -Path $releasePath -ChildPath 'WinPush'
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'WinPush.psd1')
$version = [version] $manifest.ModuleVersion
$zipPath = Join-Path -Path $releasePath -ChildPath "WinPush-$version.zip"

New-Item -Path $releasePath -ItemType Directory -Force | Out-Null
foreach ($path in @($modulePath, $zipPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

New-Item -Path $modulePath -ItemType Directory | Out-Null
Copy-Item -LiteralPath @(
    (Join-Path -Path $repoRoot -ChildPath 'WinPush.psd1')
    (Join-Path -Path $repoRoot -ChildPath 'WinPush.psm1')
    (Join-Path -Path $repoRoot -ChildPath 'WinPush.format.ps1xml')
    (Join-Path -Path $repoRoot -ChildPath 'LICENSE')
    (Join-Path -Path $repoRoot -ChildPath 'README.md')
    (Join-Path -Path $repoRoot -ChildPath 'CHANGELOG.md')
) -Destination $modulePath
Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Destination $modulePath -Recurse

$stagedManifestPath = Join-Path -Path $modulePath -ChildPath 'WinPush.psd1'
Test-ModuleManifest -Path $stagedManifestPath | Out-Null
Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
Import-Module -Name $stagedManifestPath -Force -PassThru | Out-Null
Remove-Module -Name WinPush -Force

Compress-Archive -LiteralPath $modulePath -DestinationPath $zipPath

[pscustomobject] @{
    Version          = $version.ToString()
    StagedModulePath = $modulePath
    ZipPath          = $zipPath
}
