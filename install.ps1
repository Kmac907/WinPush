[CmdletBinding()]
param(
    [string] $Scope
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Select-WinPushInstallScope {
    [CmdletBinding()]
    param(
        [scriptblock] $Prompt = {
            $choices = @(
                [System.Management.Automation.Host.ChoiceDescription]::new(
                    '&1 CurrentUser',
                    'Install only for your account.'
                )
                [System.Management.Automation.Host.ChoiceDescription]::new(
                    '&2 AllUsers',
                    'Install for every account; requires elevation.'
                )
            )
            $Host.UI.PromptForChoice('Select installation scope:', '', $choices, 0)
        }
    )

    switch (& $Prompt) {
        0 { 'CurrentUser' }
        1 { 'AllUsers' }
        default { throw 'Installation scope selection was cancelled or invalid.' }
    }
}

function Test-WinPushAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinPushInstallRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string] $Scope,

        [string] $DocumentsPath = [Environment]::GetFolderPath('MyDocuments'),

        [string] $ProgramFilesPath = $env:ProgramFiles
    )

    $root = if ($Scope -eq 'CurrentUser') {
        if ([string]::IsNullOrWhiteSpace($DocumentsPath)) {
            throw 'Could not resolve the current user My Documents directory.'
        }
        Join-Path -Path $DocumentsPath -ChildPath 'PowerShell\Modules\WinPush'
    }
    else {
        if ([string]::IsNullOrWhiteSpace($ProgramFilesPath)) {
            throw 'Could not resolve the Program Files directory.'
        }
        Join-Path -Path $ProgramFilesPath -ChildPath 'PowerShell\Modules\WinPush'
    }

    $root
}

function Get-WinPushReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Release
    )

    if ($Release.draft -or $Release.prerelease) {
        throw 'The latest GitHub release is not a stable published release.'
    }

    if ([string] $Release.tag_name -notmatch '^v(?<Version>\d+\.\d+\.\d+)$') {
        throw "Release tag '$($Release.tag_name)' must use v<major>.<minor>.<patch>."
    }

    $version = [version] $Matches.Version
    $assetName = "WinPush-$version.zip"
    $assets = @($Release.assets | Where-Object { $_.name -eq $assetName })
    if ($assets.Count -ne 1) {
        throw "Release v$version must contain exactly one '$assetName' asset; found $($assets.Count)."
    }

    $asset = $assets[0]
    if ([string] $asset.digest -notmatch '^sha256:(?<Hash>[A-Fa-f0-9]{64})$') {
        throw "Release asset '$assetName' must provide a GitHub SHA-256 digest."
    }

    $uri = [uri] $asset.browser_download_url
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https') {
        throw "Release asset '$assetName' must have an HTTPS download URL."
    }

    [pscustomobject] @{
        Version = $version
        Name    = $assetName
        Uri     = $uri
        Sha256  = $Matches.Hash.ToUpperInvariant()
    }
}

function Test-WinPushInstalledModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [version] $Version
    )

    $manifestPath = Join-Path -Path $Path -ChildPath 'WinPush.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $false
    }

    try {
        $module = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        $module.Version -eq $Version
    }
    catch {
        $false
    }
}

function Install-WinPushRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string] $Scope,

        [string] $TemporaryRoot = [IO.Path]::GetTempPath()
    )

    if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version] '7.6' -or -not $IsWindows) {
        throw 'WinPush installation requires Windows and PowerShell 7.6 Core or later.'
    }
    if ($Scope -eq 'AllUsers' -and -not (Test-WinPushAdministrator)) {
        throw 'AllUsers installation requires elevation. Rerun the same installer from an elevated PowerShell session.'
    }

    $release = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/Kmac907/WinPush/releases/latest' `
        -Headers @{
            Accept                 = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
        }
    $asset = Get-WinPushReleaseAsset -Release $release
    $moduleParent = Get-WinPushInstallRoot -Scope $Scope
    $destinationPath = Join-Path -Path $moduleParent -ChildPath $asset.Version.ToString()

    if (Test-Path -LiteralPath $destinationPath) {
        if (Test-WinPushInstalledModule -Path $destinationPath -Version $asset.Version) {
            "WinPush $($asset.Version) installed for $Scope. Run: Import-Module WinPush"
            return
        }
        throw "Installation destination '$destinationPath' already exists but is not a valid WinPush $($asset.Version) module."
    }

    $identifier = [guid]::NewGuid().ToString('N')
    $temporaryPath = Join-Path -Path $TemporaryRoot -ChildPath "WinPush-install-$identifier"
    $archivePath = Join-Path -Path $temporaryPath -ChildPath $asset.Name
    $extractPath = Join-Path -Path $temporaryPath -ChildPath 'extracted'
    $stagePath = Join-Path -Path $moduleParent -ChildPath ".WinPush-$($asset.Version)-$identifier"

    try {
        New-Item -Path $temporaryPath, $extractPath -ItemType Directory -Force | Out-Null
        Invoke-WebRequest -Uri $asset.Uri -OutFile $archivePath

        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ne $asset.Sha256) {
            throw "Downloaded release asset SHA-256 does not match GitHub's digest."
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
        $extractedModulePath = Join-Path -Path $extractPath -ChildPath 'WinPush'
        $extractedManifestPath = Join-Path -Path $extractedModulePath -ChildPath 'WinPush.psd1'
        if (-not (Test-Path -LiteralPath $extractedManifestPath -PathType Leaf)) {
            throw 'Release archive does not contain WinPush\WinPush.psd1.'
        }

        $extractedModule = Test-ModuleManifest -Path $extractedManifestPath -ErrorAction Stop
        if ($extractedModule.Version -ne $asset.Version) {
            throw "Release manifest version '$($extractedModule.Version)' does not match release tag v$($asset.Version)."
        }

        New-Item -Path $moduleParent -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $extractedModulePath -Destination $stagePath -Recurse
        if (-not (Test-WinPushInstalledModule -Path $stagePath -Version $asset.Version)) {
            throw 'Staged WinPush module failed manifest validation.'
        }
        Move-Item -LiteralPath $stagePath -Destination $destinationPath
    }
    finally {
        foreach ($path in @($stagePath, $temporaryPath)) {
            if (Test-Path -LiteralPath $path) {
                try {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Warning "Could not remove temporary path '$path': $($_.Exception.Message)"
                }
            }
        }
    }

    "WinPush $($asset.Version) installed for $Scope. Run: Import-Module WinPush"
}

function Start-WinPushInstaller {
    [CmdletBinding()]
    param(
        [string] $Scope
    )

    if ([string]::IsNullOrWhiteSpace($Scope)) {
        $Scope = Select-WinPushInstallScope
    }
    Install-WinPushRelease -Scope $Scope
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-WinPushInstaller -Scope $Scope
}
