$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PackagePath = Join-Path -Path $script:RepoRoot -ChildPath 'build\package.ps1'
$script:InstallerPath = Join-Path -Path $script:RepoRoot -ChildPath 'install.ps1'
$script:Version = (Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:RepoRoot -ChildPath 'WinPush.psd1')).ModuleVersion.ToString()
$script:PackageResult = & $script:PackagePath
$script:Tag = "v$script:Version"
$script:AssetName = "WinPush-$script:Version.zip"
. $script:InstallerPath

function New-TestRelease {
    param(
        [string] $Tag = $script:Tag,
        [string] $Name = $script:AssetName,
        [string] $Digest = "sha256:$((Get-FileHash -LiteralPath $script:PackageResult.ZipPath -Algorithm SHA256).Hash)",
        [object[]] $Assets
    )

    if (-not $PSBoundParameters.ContainsKey('Assets')) {
        $Assets = @(
            [pscustomobject] @{
                name                 = $Name
                digest               = $Digest
                browser_download_url = "https://github.com/Kmac907/WinPush/releases/download/$Tag/$Name"
            }
        )
    }

    [pscustomobject] @{
        draft      = $false
        prerelease = $false
        tag_name   = $Tag
        assets     = $Assets
    }
}

function New-TestPackageArchive {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ManifestContent
    )

    $root = Join-Path -Path $TestDrive -ChildPath $Name
    $extractPath = Join-Path -Path $root -ChildPath 'source'
    $archivePath = Join-Path -Path $root -ChildPath "$Name.zip"
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
    Expand-Archive -LiteralPath $script:PackageResult.ZipPath -DestinationPath $extractPath
    Set-Content -LiteralPath (Join-Path -Path $extractPath -ChildPath 'WinPush\WinPush.psd1') -Value $ManifestContent -Encoding utf8NoBOM
    Compress-Archive -LiteralPath (Join-Path -Path $extractPath -ChildPath 'WinPush') -DestinationPath $archivePath
    $archivePath
}

function Test-WinPushInstallerExpression {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingInvokeExpression',
        '',
        Justification = 'Exercises the documented irm pipeline regression.'
    )]
    [CmdletBinding()]
    param()

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($script:InstallerPath, [ref] $tokens, [ref] $errors)
    New-Variable -Name Scope -Value ''
    $null = $tokens

    Invoke-Expression "$($ast.ParamBlock.Extent.Text)`n'loaded'"
}

Describe 'WinPush release package' {
    It 'contains exactly the module, documentation, license, and complete src tree' {
        $archive = [IO.Compression.ZipFile]::OpenRead($script:PackageResult.ZipPath)
        try {
            $actual = @($archive.Entries |
                    Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
                    ForEach-Object { $_.FullName.Replace('\', '/') } |
                    Sort-Object)
        }
        finally {
            $archive.Dispose()
        }

        $expected = @(
            'WinPush/CHANGELOG.md'
            'WinPush/LICENSE'
            'WinPush/README.md'
            'WinPush/WinPush.format.ps1xml'
            'WinPush/WinPush.psd1'
            'WinPush/WinPush.psm1'
        ) + @(Get-ChildItem -LiteralPath (Join-Path -Path $script:RepoRoot -ChildPath 'src') -File -Recurse |
                ForEach-Object {
                    'WinPush/src/' + $_.FullName.Substring((Join-Path -Path $script:RepoRoot -ChildPath 'src').Length + 1).Replace('\', '/')
                })

        ($actual -join '|') | Should Be (($expected | Sort-Object) -join '|')
        $script:PackageResult.Version | Should Be $script:Version
    }

    It 'validates and imports the staged manifest' {
        $manifestPath = Join-Path -Path $script:PackageResult.StagedModulePath -ChildPath 'WinPush.psd1'

        (Test-ModuleManifest -Path $manifestPath).Version.ToString() | Should Be $script:Version
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        (Import-Module -Name $manifestPath -Force -PassThru).Version.ToString() | Should Be $script:Version
        Remove-Module -Name WinPush -Force
    }
}

Describe 'WinPush installer scope selection' {
    It 'loads through Invoke-Expression when the caller has a blank Scope variable' {
        Test-WinPushInstallerExpression | Should Be 'loaded'
    }

    It 'maps prompt choice 1 to CurrentUser' {
        Select-WinPushInstallScope -Prompt { 0 } | Should Be 'CurrentUser'
    }

    It 'maps prompt choice 2 to AllUsers' {
        Select-WinPushInstallScope -Prompt { 1 } | Should Be 'AllUsers'
    }

    It 'uses CurrentUser for the native prompt default' {
        $installerText = Get-Content -LiteralPath $script:InstallerPath -Raw

        $installerText | Should Match 'PromptForChoice\(''Select installation scope:'', '''', \$choices, 0\)'
        Select-WinPushInstallScope -Prompt { 0 } | Should Be 'CurrentUser'
    }

    It 'bypasses the prompt for an explicit scope' {
        Mock Select-WinPushInstallScope { throw 'prompt should not run' }
        Mock Install-WinPushRelease {}

        Start-WinPushInstaller -Scope AllUsers

        Assert-MockCalled Select-WinPushInstallScope -Times 0 -Exactly -Scope It
        Assert-MockCalled Install-WinPushRelease -Times 1 -Exactly -Scope It -ParameterFilter { $Scope -eq 'AllUsers' }
    }

    It 'prompts before validating a blank scope from Invoke-Expression' {
        Mock Select-WinPushInstallScope { 'CurrentUser' }
        Mock Install-WinPushRelease {}

        Start-WinPushInstaller -Scope ''

        Assert-MockCalled Select-WinPushInstallScope -Times 1 -Exactly -Scope It
        Assert-MockCalled Install-WinPushRelease -Times 1 -Exactly -Scope It -ParameterFilter { $Scope -eq 'CurrentUser' }
    }

    It 'resolves redirected Documents and Program Files module roots' {
        Get-WinPushInstallRoot -Scope CurrentUser -DocumentsPath 'D:\Profiles\Operator\Documents' -ProgramFilesPath 'E:\Programs' |
            Should Be 'D:\Profiles\Operator\Documents\PowerShell\Modules\WinPush'
        Get-WinPushInstallRoot -Scope AllUsers -DocumentsPath 'D:\Profiles\Operator\Documents' -ProgramFilesPath 'E:\Programs' |
            Should Be 'E:\Programs\PowerShell\Modules\WinPush'
    }
}

Describe 'WinPush release metadata validation' {
    It 'rejects a missing matching release asset' {
        { Get-WinPushReleaseAsset -Release (New-TestRelease -Assets @()) } |
            Should Throw "must contain exactly one '$script:AssetName' asset; found 0"
    }

    It 'rejects duplicate matching release assets' {
        $asset = (New-TestRelease).assets[0]

        { Get-WinPushReleaseAsset -Release (New-TestRelease -Assets @($asset, $asset)) } |
            Should Throw "must contain exactly one '$script:AssetName' asset; found 2"
    }

    It 'rejects invalid release tags' {
        { Get-WinPushReleaseAsset -Release (New-TestRelease -Tag 'release-invalid') } |
            Should Throw 'must use v<major>.<minor>.<patch>'
    }

    It 'rejects a mismatched asset filename' {
        { Get-WinPushReleaseAsset -Release (New-TestRelease -Name 'WinPush.zip') } |
            Should Throw "must contain exactly one '$script:AssetName' asset; found 0"
    }

    It 'rejects a missing or malformed GitHub digest' {
        { Get-WinPushReleaseAsset -Release (New-TestRelease -Digest '') } |
            Should Throw 'must provide a GitHub SHA-256 digest'
    }
}

Describe 'WinPush release installation' {
    BeforeEach {
        $caseId = [guid]::NewGuid().ToString('N')
        $script:InstallParent = Join-Path -Path $TestDrive -ChildPath "$caseId\Modules\WinPush"
        $script:TemporaryRoot = Join-Path -Path $TestDrive -ChildPath "$caseId\Temp"
        $script:DownloadArchive = $script:PackageResult.ZipPath
        $script:Release = New-TestRelease
        New-Item -Path $script:TemporaryRoot -ItemType Directory -Force | Out-Null

        Mock Test-WinPushAdministrator { $true }
        Mock Get-WinPushInstallRoot { $script:InstallParent }
        Mock Invoke-RestMethod { $script:Release }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $script:DownloadArchive -Destination $OutFile }
    }

    It 'rejects a non-elevated AllUsers installation before querying GitHub' {
        Mock Test-WinPushAdministrator { $false }

        { Install-WinPushRelease -Scope AllUsers -TemporaryRoot $script:TemporaryRoot } |
            Should Throw 'requires elevation'
        Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly -Scope It
    }

    It 'installs a verified release and removes temporary and staging directories' {
        Install-WinPushRelease -Scope CurrentUser -TemporaryRoot $script:TemporaryRoot |
            Should Be "WinPush $script:Version installed for CurrentUser. Run: Import-Module WinPush"

        Test-Path -LiteralPath (Join-Path -Path $script:InstallParent -ChildPath "$script:Version\WinPush.psd1") | Should Be $true
        @(Get-ChildItem -LiteralPath $script:TemporaryRoot -Force).Count | Should Be 0
        @(Get-ChildItem -LiteralPath $script:InstallParent -Force | Where-Object Name -Like '.WinPush-*').Count | Should Be 0
    }

    It 'treats an existing valid same-version module as success without downloading' {
        $destinationPath = Join-Path -Path $script:InstallParent -ChildPath $script:Version
        New-Item -Path $script:InstallParent -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $script:PackageResult.StagedModulePath -Destination $destinationPath -Recurse

        Install-WinPushRelease -Scope CurrentUser -TemporaryRoot $script:TemporaryRoot |
            Should Be "WinPush $script:Version installed for CurrentUser. Run: Import-Module WinPush"

        Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly -Scope It
    }

    It 'rejects an occupied invalid destination without overwriting it' {
        $destinationPath = Join-Path -Path $script:InstallParent -ChildPath $script:Version
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'keep.txt') -Value 'keep'
        Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'WinPush.psd1') -Value '@{'

        { Install-WinPushRelease -Scope CurrentUser -TemporaryRoot $script:TemporaryRoot } |
            Should Throw "already exists but is not a valid WinPush $script:Version module"
        Get-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'keep.txt') | Should Be 'keep'
        Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly -Scope It
    }

    It 'rejects a downloaded asset whose digest differs and cleans temporary files' {
        $script:Release = New-TestRelease -Digest ('sha256:' + ('0' * 64))

        { Install-WinPushRelease -Scope CurrentUser -TemporaryRoot $script:TemporaryRoot } |
            Should Throw "SHA-256 does not match GitHub's digest"
        @(Get-ChildItem -LiteralPath $script:TemporaryRoot -Force).Count | Should Be 0
    }

    It 'rejects a manifest version that differs from the release tag and cleans temporary files' {
        $manifest = Get-Content -LiteralPath (Join-Path -Path $script:RepoRoot -ChildPath 'WinPush.psd1') -Raw
        $mismatchedVersion = [version]::new(0, 0, ([version] $script:Version).Build + 1)
        $manifest = $manifest.Replace("ModuleVersion        = '$script:Version'", "ModuleVersion        = '$mismatchedVersion'")
        $script:DownloadArchive = New-TestPackageArchive -Name 'wrong-version' -ManifestContent $manifest
        $script:Release = New-TestRelease -Digest "sha256:$((Get-FileHash -LiteralPath $script:DownloadArchive -Algorithm SHA256).Hash)"

        { Install-WinPushRelease -Scope CurrentUser -TemporaryRoot $script:TemporaryRoot } |
            Should Throw "does not match release tag $script:Tag"
        @(Get-ChildItem -LiteralPath $script:TemporaryRoot -Force).Count | Should Be 0
    }
}
