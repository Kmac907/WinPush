$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1'
$script:PackageInfoPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushPackageInfo.ps1'
$script:PsrpCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Copy-WinPushPsrpItem.ps1'
$script:PackageStagePath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\New-WinPushPackageStagePlan.ps1'
$script:PackageCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Invoke-WinPushPackage.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:PackageInfoPath
. $script:PsrpCopyPath
. $script:PackageStagePath
. $script:PackageCommandPath

function Get-TestCredential {
    param(
        [Parameter(Mandatory)]
        [string] $Secret
    )

    $secureSecret = New-Object -TypeName System.Security.SecureString
    foreach ($character in $Secret.ToCharArray()) {
        $secureSecret.AppendChar($character)
    }
    $secureSecret.MakeReadOnly()

    return New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @(
        'CONTOSO\operator',
        $secureSecret
    )
}

Describe 'Invoke-WinPushPackage contract' {
    It 'defines the planned package source and target parameter sets' {
        $command = Get-Command Invoke-WinPushPackage
        $parameterSetNames = @($command.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object)

        ($parameterSetNames -join ',') | Should Be 'PathComputerName,PathHostFile,UriComputerName,UriHostFile'
    }

    It 'exposes only the planned package workflow parameters for item 11.1' {
        $command = Get-Command Invoke-WinPushPackage
        $parameterNames = @($command.Parameters.Keys | Sort-Object)

        foreach ($expectedParameter in @(
            'CaptureOutput',
            'Cleanup',
            'ComputerName',
            'Credential',
            'EntryPoint',
            'Extract',
            'HostFile',
            'Logs',
            'OutputRoot',
            'PackageCacheRoot',
            'Path',
            'RemoteStageRoot',
            'Uri'
        )) {
            ($parameterNames -contains $expectedParameter) | Should Be $true
        }

        ($parameterNames -contains 'PackageManifest') | Should Be $false
        ($parameterNames -contains 'Hash') | Should Be $false
        ($parameterNames -contains 'ArgumentList') | Should Be $false
        ($parameterNames -contains 'Transport') | Should Be $false
    }

    It 'keeps Path and Uri mutually exclusive' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -Uri 'https://storage.contoso.example/packages/EA.zip' -EntryPoint '.\Install-EA.ps1' } |
            Should Throw 'Parameter set cannot be resolved'
    }

    It 'rejects empty entry points before package workflow execution' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '   ' } |
            Should Throw 'EntryPoint must not be empty.'
    }

    It 'rejects empty output roots before package workflow execution when artifacts are requested' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '.\Install-EA.ps1' -CaptureOutput -OutputRoot '   ' } |
            Should Throw 'OutputRoot must not be empty.'
    }

    It 'guards package features that belong to later roadmap slices' {
        $packagePath = Join-Path -Path $TestDrive -ChildPath 'Package.zip'
        Set-Content -LiteralPath $packagePath -Value 'package' -Encoding utf8NoBOM

        { Invoke-WinPushPackage -HostFile '.\hosts.txt' -Path $packagePath -EntryPoint '.\Install-EA.ps1' } |
            Should Throw 'HostFile package target input is not supported until roadmap item 11.11.'
        { Invoke-WinPushPackage -HostFile '.\hosts.txt' -Uri 'https://storage.contoso.example/packages/EA.zip' -EntryPoint '.\Install-EA.ps1' } |
            Should Throw 'HostFile package target input is not supported until roadmap item 11.11.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path $packagePath -EntryPoint '.\Install-EA.ps1' -Extract } |
            Should Throw 'Extract is not supported until roadmap item 11.6.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path $packagePath -EntryPoint '.\Install-EA.ps1' -CaptureOutput } |
            Should Throw 'CaptureOutput is not supported until roadmap item 11.8.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path $packagePath -EntryPoint '.\Install-EA.ps1' -Logs } |
            Should Throw 'Logs is not supported until roadmap item 11.9.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path $packagePath -EntryPoint '.\Install-EA.ps1' -Cleanup Always } |
            Should Throw 'Cleanup policies other than Never are not supported until roadmap item 11.10.'
    }
}

Describe 'Invoke-WinPushPackage local package preparation and staging' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:NewPSSessionCredentialSupplied = @()
        $script:NewPSSessionCredentials = @()
        $script:RemoteDirectoriesCreated = @()
        $script:CopiedSessions = @()
        $script:CopiedPaths = @()
        $script:CopiedDestinations = @()
        $script:CopiedDirections = @()
        $script:DownloadUris = @()
        $script:DownloadOutFiles = @()
        $script:RemovedSessionIds = @()
        $script:SessionToReturn = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )
        $script:NewPSSessionError = $null
        $script:RemoteDirectoryError = $null
        $script:CopyError = $null
        $script:DownloadError = $null
        $script:FixturePackage = Join-Path -Path $TestDrive -ChildPath 'Package.zip'
        Set-Content -LiteralPath $script:FixturePackage -Value 'package' -Encoding utf8NoBOM
    }

    Mock New-PSSession {
        param(
            [string] $ComputerName,
            [System.Management.Automation.PSCredential] $Credential,
            $ErrorAction
        )

        $null = $ErrorAction
        $script:NewPSSessionComputerNames += $ComputerName
        $credentialSupplied = $PSBoundParameters.ContainsKey('Credential')
        $script:NewPSSessionCredentialSupplied += $credentialSupplied
        if ($credentialSupplied) {
            $script:NewPSSessionCredentials += $Credential
        }

        if ($null -ne $script:NewPSSessionError) {
            throw $script:NewPSSessionError
        }

        return $script:SessionToReturn
    }

    Mock Invoke-Command {
        param(
            $Session,
            [scriptblock] $ScriptBlock,
            [object[]] $ArgumentList,
            $ErrorAction
        )

        $null = $Session
        $null = $ScriptBlock
        $null = $ErrorAction
        $script:RemoteDirectoriesCreated += [string] $ArgumentList[0]
        if ($null -ne $script:RemoteDirectoryError) {
            throw $script:RemoteDirectoryError
        }
    }

    Mock Copy-WinPushPsrpItem {
        param(
            $Session,
            [string] $Path,
            [string] $Destination,
            [string] $Direction = 'Upload'
        )

        $script:CopiedSessions += $Session
        $script:CopiedPaths += $Path
        $script:CopiedDestinations += $Destination
        $script:CopiedDirections += $Direction
        if ($null -ne $script:CopyError) {
            throw $script:CopyError
        }
    }

    Mock Invoke-WebRequest {
        param(
            [uri] $Uri,
            [string] $OutFile,
            $ErrorAction
        )

        $null = $ErrorAction
        $script:DownloadUris += $Uri
        $script:DownloadOutFiles += $OutFile
        if ($null -ne $script:DownloadError) {
            throw $script:DownloadError
        }

        Set-Content -LiteralPath $OutFile -Value 'downloaded package' -Encoding utf8NoBOM
    }

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'validates a missing package file before opening a session' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.zip'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $missingPath -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.Operation | Should Be 'RunPackage'
        $result.ErrorMessage | Should Be "Package file was not found: $missingPath"
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemoteDirectoriesCreated).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'stages one local file package to one target and returns package metadata' {
        $result = Invoke-WinPushPackage -ComputerName ' PC-001 ' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1'
        $resolvedPackagePath = (Get-Item -LiteralPath $script:FixturePackage).FullName

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'RunPackage'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:RemoteDirectoriesCreated).Count | Should Be 1
        $script:RemoteDirectoriesCreated[0] | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        @($script:CopiedPaths).Count | Should Be 1
        $script:CopiedPaths[0] | Should Be $resolvedPackagePath
        $script:CopiedDirections[0] | Should Be 'Upload'
        $script:CopiedDestinations[0] | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        $script:CopiedDestinations[0] | Should Match ([regex]::Escape('\Package.zip'))
        [object]::ReferenceEquals($script:CopiedSessions[0], $script:SessionToReturn) | Should Be $true
        $result.PackageMetadata.PSTypeNames[0] | Should Be 'WinPush.PackageMetadata'
        $result.PackageMetadata.PackageSourceType | Should Be 'Path'
        $result.PackageMetadata.PackageSource | Should Be $resolvedPackagePath
        $result.PackageMetadata.LocalPackagePath | Should Be $resolvedPackagePath
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        $result.PackageMetadata.EntryPoint | Should Be '.\Install-EA.ps1'
        $result.PackageMetadata.Extracted | Should Be $false
        $result.PackageMetadata.CleanupPolicy | Should Be 'Never'
        $result.PackageMetadata.CleanupSucceeded | Should BeNullOrEmpty
        $result.PackageMetadata.LogsCopied | Should Be $false
        $result.Output[0].RemoteStagePath | Should Be $result.PackageMetadata.RemoteStagePath
    }

    It 'stages one local directory package to one target while preserving relative file layout' {
        $directoryPath = Join-Path -Path $TestDrive -ChildPath 'PackageDirectory'
        $configDirectory = Join-Path -Path $directoryPath -ChildPath 'config'
        $emptyDirectory = Join-Path -Path $directoryPath -ChildPath 'empty'
        New-Item -ItemType Directory -Path $configDirectory | Out-Null
        New-Item -ItemType Directory -Path $emptyDirectory | Out-Null
        $entryPointPath = Join-Path -Path $directoryPath -ChildPath 'Install-EA.ps1'
        $configPath = Join-Path -Path $configDirectory -ChildPath 'settings.json'
        Set-Content -LiteralPath $entryPointPath -Value 'Write-Output package' -Encoding utf8NoBOM
        Set-Content -LiteralPath $configPath -Value '{}' -Encoding utf8NoBOM
        $resolvedEntryPointPath = (Get-Item -LiteralPath $entryPointPath).FullName
        $resolvedConfigPath = (Get-Item -LiteralPath $configPath).FullName

        $result = Invoke-WinPushPackage -ComputerName ' PC-001 ' -Path $directoryPath -EntryPoint '.\Install-EA.ps1'
        $resolvedPackagePath = (Get-Item -LiteralPath $directoryPath).FullName

        $result.Succeeded | Should Be $true
        $result.Operation | Should Be 'RunPackage'
        @($script:RemoteDirectoriesCreated).Count | Should Be 3
        $remoteStageRoot = $script:RemoteDirectoriesCreated[0]
        $remoteStageRoot | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        ($script:RemoteDirectoriesCreated -contains ('{0}\config' -f $remoteStageRoot)) | Should Be $true
        ($script:RemoteDirectoriesCreated -contains ('{0}\empty' -f $remoteStageRoot)) | Should Be $true
        @($script:CopiedPaths).Count | Should Be 2
        ($script:CopiedPaths -contains $resolvedEntryPointPath) | Should Be $true
        ($script:CopiedPaths -contains $resolvedConfigPath) | Should Be $true
        ($script:CopiedDestinations -contains ('{0}\Install-EA.ps1' -f $remoteStageRoot)) | Should Be $true
        ($script:CopiedDestinations -contains ('{0}\config\settings.json' -f $remoteStageRoot)) | Should Be $true
        ($script:CopiedDirections -contains 'Upload') | Should Be $true
        $result.PackageMetadata.PackageSource | Should Be $resolvedPackagePath
        $result.PackageMetadata.LocalPackagePath | Should Be $resolvedPackagePath
        $result.PackageMetadata.RemoteStagePath | Should Be $remoteStageRoot
        $result.Output[0].RemoteStagePath | Should Be $remoteStageRoot
    }

    It 'uses the supplied remote stage root' {
        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixturePackage `
            -EntryPoint '.\Install-EA.ps1' `
            -RemoteStageRoot 'D:\WinPushStage\'

        $result.Succeeded | Should Be $true
        $script:RemoteDirectoriesCreated[0] | Should Match ([regex]::Escape('D:\WinPushStage\package-'))
        $result.PackageMetadata.RemoteStagePath | Should Match ([regex]::Escape('D:\WinPushStage\package-'))
    }

    It 'passes the supplied credential object unchanged to New-PSSession' {
        $credential = Get-TestCredential -Secret 'Distinctive-Package-Credential-Secret!'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1' -Credential $credential

        $result.Succeeded | Should Be $true
        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
    }

    It 'normalizes credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-Package-Session-Secret!'
        $credential = Get-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1' -Credential $credential
        $diagnosticText = @(
            $result.ErrorMessage
            @($result.Errors)
            @($result.Output)
            @($result.Logs)
        ) -join "`n"

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'PSRP package staging session creation failed for the target with the supplied credential.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'returns a failed package result when remote staging directory creation fails and removes the session' {
        $script:RemoteDirectoryError = 'remote staging directory failed'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'remote staging directory failed'
        $result.PackageMetadata.RemoteStagePath | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        @($script:CopiedPaths).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed package result when upload fails and removes the session' {
        $script:CopyError = 'package upload failed'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'package upload failed'
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed package result when directory package upload fails and removes the session' {
        $directoryPath = Join-Path -Path $TestDrive -ChildPath 'PackageDirectoryUploadFailure'
        New-Item -ItemType Directory -Path $directoryPath | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $directoryPath -ChildPath 'Install-EA.ps1') -Value 'Write-Output package' -Encoding utf8NoBOM
        $script:CopyError = 'directory package upload failed'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $directoryPath -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'directory package upload failed'
        $result.PackageMetadata.RemoteStagePath | Should Be $script:RemoteDirectoriesCreated[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'requires exactly one resolved target before opening a session' {
        $result = Invoke-WinPushPackage -ComputerName @('PC-001', 'PC-002') -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Invoke-WinPushPackage currently supports exactly one target until roadmap item 11.11.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'removes the session after a successful stage' {
        Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'downloads one URI package to the admin workstation cache without opening an endpoint session' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCache'
        $uri = 'https://storage.contoso.example/packages/EA%20Install.zip'

        $result = Invoke-WinPushPackage `
            -ComputerName ' PC-001 ' `
            -Uri $uri `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'RunPackage'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemoteDirectoriesCreated).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
        @($script:DownloadUris).Count | Should Be 1
        $script:DownloadUris[0].OriginalString | Should Be $uri
        $script:DownloadOutFiles[0] | Should Match ([regex]::Escape($cacheRoot))
        $script:DownloadOutFiles[0] | Should Match ([regex]::Escape('EA Install.zip'))
        Test-Path -LiteralPath $script:DownloadOutFiles[0] | Should Be $true
        $result.PackageMetadata.PSTypeNames[0] | Should Be 'WinPush.PackageMetadata'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.PackageSource | Should Be $uri
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.RemoteStagePath | Should BeNullOrEmpty
        $result.PackageMetadata.EntryPoint | Should Be '.\Install-EA.ps1'
        $result.PackageMetadata.Extracted | Should Be $false
        $result.PackageMetadata.CleanupPolicy | Should Be 'Never'
        $result.PackageMetadata.LogsCopied | Should Be $false
        $result.Output[0].LocalPackagePath | Should Be $result.PackageMetadata.LocalPackagePath
    }

    It 'returns a failed URI package result when download fails before opening an endpoint session' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCacheFailure'
        $script:DownloadError = 'package download failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'package download failed'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Match ([regex]::Escape($cacheRoot))
        $result.PackageMetadata.RemoteStagePath | Should BeNullOrEmpty
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemoteDirectoriesCreated).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
        @($script:DownloadUris).Count | Should Be 1
    }

    It 'rejects relative URI package sources before opening an endpoint session or downloading' {
        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Uri 'packages/EA.zip' -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Uri must be an absolute package URI.'
        @($script:DownloadUris).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'requires exactly one resolved target before downloading a URI package' {
        $result = Invoke-WinPushPackage `
            -ComputerName @('PC-001', 'PC-002') `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Invoke-WinPushPackage currently supports exactly one target until roadmap item 11.11.'
        @($script:DownloadUris).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }
}
