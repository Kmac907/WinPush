$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1'
$script:LogResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushLogResult.ps1'
$script:PackageInfoPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushPackageInfo.ps1'
$script:PsrpCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Copy-WinPushPsrpItem.ps1'
$script:PackageStagePath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\New-WinPushPackageStagePlan.ps1'
$script:ArtifactWriterPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Write-WinPushCommandOutputArtifact.ps1'
$script:ScriptLogDirectoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\Get-WinPushScriptLogDirectory.ps1'
$script:LogArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1'
$script:PsrpLogCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\Copy-WinPushPsrpLogDirectory.ps1'
$script:PackageCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Invoke-WinPushPackage.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:LogResultFactoryPath
. $script:PackageInfoPath
. $script:PsrpCopyPath
. $script:PackageStagePath
. $script:ArtifactWriterPath
. $script:ScriptLogDirectoryPath
. $script:LogArtifactPath
. $script:PsrpLogCopyPath
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

    It 'rejects unsafe entry point paths before package workflow execution' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint 'C:\Temp\Install-EA.ps1' } |
            Should Throw 'EntryPoint must be relative to the staged package root.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '..\Install-EA.ps1' } |
            Should Throw 'EntryPoint must not contain parent traversal.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint 'tools\..\Install-EA.ps1' } |
            Should Throw 'EntryPoint must not contain parent traversal.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint 'tools\\Install-EA.ps1' } |
            Should Throw 'EntryPoint must not contain empty path segments.'
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '.\Install-EA.cmd' } |
            Should Throw 'EntryPoint must refer to a .ps1 file.'
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
        $script:RemoteExtractions = @()
        $script:PackageExecutionSessions = @()
        $script:PackageExecutionRoots = @()
        $script:PackageExecutionEntryPoints = @()
        $script:PackageExecutionOutput = @('package output')
        $script:PackageExecutionErrors = @()
        $script:PackageExecutionError = $null
        $script:PackageOperationOrder = @()
        $script:CopiedSessions = @()
        $script:CopiedPaths = @()
        $script:CopiedDestinations = @()
        $script:CopiedDirections = @()
        $script:CopiedLogSessions = @()
        $script:CopiedLogComputerNames = @()
        $script:CopiedLogRemoteDirectories = @()
        $script:CopiedLogRunDirectories = @()
        $script:CopiedLogComputerDirectories = @()
        $script:LogCopyError = $null
        $script:LogCopyReturnedLogs = $null
        $script:LogCopyReturnedCopiedLogPaths = $null
        $script:DownloadUris = @()
        $script:DownloadOutFiles = @()
        $script:RemovedSessionIds = @()
        $script:SessionToReturn = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )
        $script:NewPSSessionError = $null
        $script:RemoteDirectoryError = $null
        $script:RemoteExtractionError = $null
        $script:CopyError = $null
        $script:DownloadError = $null
        $script:FixturePackage = Join-Path -Path $TestDrive -ChildPath 'Package.zip'
        Set-Content -LiteralPath $script:FixturePackage -Value 'package' -Encoding utf8NoBOM
        $script:FixtureScriptPackage = Join-Path -Path $TestDrive -ChildPath 'Install-EA.ps1'
        Set-Content -LiteralPath $script:FixtureScriptPackage -Value "Write-Output 'package output'" -Encoding utf8NoBOM
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

        if (@($ArgumentList).Count -ge 2) {
            $script:RemoteExtractions += [pscustomobject] @{
                ArchivePath     = [string] $ArgumentList[0]
                DestinationPath = [string] $ArgumentList[1]
            }

            if ($null -ne $script:RemoteExtractionError) {
                throw $script:RemoteExtractionError
            }

            return
        }

        $script:RemoteDirectoriesCreated += [string] $ArgumentList[0]
        if ($null -ne $script:RemoteDirectoryError) {
            throw $script:RemoteDirectoryError
        }
    }

    Mock Invoke-WinPushPsrpPackageEntryPoint {
        param(
            $Session,
            [string] $PackageRoot,
            [string] $EntryPoint
        )

        $script:PackageExecutionSessions += $Session
        $script:PackageExecutionRoots += $PackageRoot
        $script:PackageExecutionEntryPoints += $EntryPoint
        $script:PackageOperationOrder += 'Package'
        if ($null -ne $script:PackageExecutionError) {
            throw $script:PackageExecutionError
        }

        [pscustomobject] [ordered] @{
            PSTypeName = 'WinPush.PsrpPackageEntryPointResult'
            Output     = @($script:PackageExecutionOutput)
            Errors     = @($script:PackageExecutionErrors)
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

    Mock Copy-WinPushPsrpLogDirectory {
        param(
            $Session,
            [string] $ComputerName,
            [string] $RemoteDirectory,
            [string] $OutputRoot,
            [AllowNull()]
            [string] $RunDirectory,
            [AllowNull()]
            [string] $ComputerDirectory
        )

        $script:CopiedLogSessions += $Session
        $script:CopiedLogComputerNames += $ComputerName
        $script:CopiedLogRemoteDirectories += $RemoteDirectory
        $script:CopiedLogRunDirectories += $RunDirectory
        $script:CopiedLogComputerDirectories += $ComputerDirectory
        $script:PackageOperationOrder += 'Logs'

        if ($null -ne $script:LogCopyError) {
            throw $script:LogCopyError
        }

        $effectiveRunDirectory = if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
            Join-Path -Path $OutputRoot -ChildPath 'run-logs'
        }
        else {
            $RunDirectory
        }

        $effectiveComputerDirectory = if ([string]::IsNullOrWhiteSpace($ComputerDirectory)) {
            Join-Path -Path $effectiveRunDirectory -ChildPath $ComputerName
        }
        else {
            $ComputerDirectory
        }

        $remotePath = Join-Path -Path $RemoteDirectory -ChildPath 'package.log'
        $localPath = Join-Path -Path (Join-Path -Path $effectiveComputerDirectory -ChildPath 'Logs') -ChildPath 'package.log'
        $logResult = New-WinPushLogResult `
            -ComputerName $ComputerName `
            -RemotePath $remotePath `
            -LocalPath $localPath `
            -Copied $true
        $logs = if ($null -ne $script:LogCopyReturnedLogs) {
            @($script:LogCopyReturnedLogs)
        }
        else {
            @($logResult)
        }
        $copiedLogPaths = if ($null -ne $script:LogCopyReturnedCopiedLogPaths) {
            @($script:LogCopyReturnedCopiedLogPaths)
        }
        else {
            @($logs | Where-Object { $_.Copied } | ForEach-Object { $_.LocalPath })
        }

        [pscustomobject] [ordered] @{
            FileMetadata      = @(
                [pscustomobject] [ordered] @{
                    ComputerName      = $ComputerName
                    RemotePath        = $remotePath
                    Name              = 'package.log'
                    Length            = 12
                    LastWriteTimeUtc  = [datetime]::UtcNow
                }
            )
            Logs              = $logs
            Errors            = @($logs | Where-Object { -not $_.Copied } | ForEach-Object { $_.Error })
            CopiedLogPaths    = $copiedLogPaths
            RunDirectory      = $effectiveRunDirectory
            ComputerDirectory = $effectiveComputerDirectory
            LogDirectory      = Join-Path -Path $effectiveComputerDirectory -ChildPath 'Logs'
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
        $result = Invoke-WinPushPackage -ComputerName ' PC-001 ' -Path $script:FixtureScriptPackage -EntryPoint '.\Install-EA.ps1'
        $resolvedPackagePath = (Get-Item -LiteralPath $script:FixtureScriptPackage).FullName

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
        $script:CopiedDestinations[0] | Should Match ([regex]::Escape('\Install-EA.ps1'))
        [object]::ReferenceEquals($script:CopiedSessions[0], $script:SessionToReturn) | Should Be $true
        $result.PackageMetadata.PSTypeNames[0] | Should Be 'WinPush.PackageMetadata'
        $result.PackageMetadata.PackageSourceType | Should Be 'Path'
        $result.PackageMetadata.PackageSource | Should Be $resolvedPackagePath
        $result.PackageMetadata.LocalPackagePath | Should Be $resolvedPackagePath
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        $result.PackageMetadata.EntryPoint | Should Be '.\Install-EA.ps1'
        $result.PackageMetadata.Extracted | Should Be $false
        $null -eq $result.PackageMetadata.ExecutionStarted | Should Be $false
        $null -eq $result.PackageMetadata.ExecutionEnded | Should Be $false
        $result.PackageMetadata.ExecutionEnded -ge $result.PackageMetadata.ExecutionStarted | Should Be $true
        $result.PackageMetadata.CleanupPolicy | Should Be 'Never'
        $result.PackageMetadata.CleanupSucceeded | Should BeNullOrEmpty
        $result.PackageMetadata.LogsCopied | Should Be $false
        @($result.PackageMetadata.CopiedLogPaths).Count | Should Be 0
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'package output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 0
        @($result.CopiedLogPaths).Count | Should Be 0
        $result.RunDirectory | Should BeNullOrEmpty
        $result.ComputerDirectory | Should BeNullOrEmpty
        $result.ResultPath | Should BeNullOrEmpty
        $result.StdOutPath | Should BeNullOrEmpty
        $result.StdErrPath | Should BeNullOrEmpty
        @($script:PackageExecutionRoots).Count | Should Be 1
        $script:PackageExecutionRoots[0] | Should Be $script:RemoteDirectoriesCreated[0]
        $script:PackageExecutionEntryPoints[0] | Should Be '.\Install-EA.ps1'
    }

    It 'writes summary and run log artifacts for successful package capture output' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'PackageArtifacts'
        $result = Invoke-WinPushPackage `
            -ComputerName ' PC-001 ' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -CaptureOutput `
            -OutputRoot $outputRoot
        $resolvedPackagePath = (Get-Item -LiteralPath $script:FixtureScriptPackage).FullName

        $result.Succeeded | Should Be $true
        $result.Output[0] | Should Be 'package output'
        $result.RunDirectory | Should Match ([regex]::Escape($outputRoot))
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $result.StdOutPath | Should BeNullOrEmpty
        $result.StdErrPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $result.ResultPath | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') | Should Be $false

        $summary = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summary).Count | Should Be 1
        $summary[0].ComputerName | Should Be 'PC-001'
        $summary[0].Operation | Should Be 'RunPackage'
        $summary[0].Transport | Should Be 'Psrp'
        $summary[0].Succeeded | Should Be 'True'
        $summary[0].ExitCode | Should Be '0'
        $summary[0].ResultPath | Should Be $result.ResultPath
        $summary[0].StdOutPath | Should Be ''
        $summary[0].StdErrPath | Should Be ''

        $runLog = Get-Content -LiteralPath $result.ResultPath -Raw
        $runLog | Should Match ([regex]::Escape('Operation    : RunPackage'))
        $runLog | Should Match ([regex]::Escape('Transport    : Psrp'))
        $runLog | Should Match ([regex]::Escape("Identity     : Path: $resolvedPackagePath; EntryPoint: .\Install-EA.ps1"))
        $runLog | Should Match ([regex]::Escape('Succeeded    : True'))
        $runLog | Should Match ([regex]::Escape('ExitCode     : 0'))
        $runLog | Should Match ([regex]::Escape('Output:'))
        $runLog | Should Match ([regex]::Escape('package output'))
        $runLog | Should Match ([regex]::Escape('Errors:'))
    }

    It 'copies package logs after successful package execution' {
        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -Logs `
            -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.Output[0] | Should Be 'package output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].PSTypeNames[0] | Should Be 'WinPush.LogResult'
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\Install-EA\package.log'
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.PackageMetadata.LogsCopied | Should Be $true
        $result.PackageMetadata.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.RunDirectory | Should Be (Join-Path -Path $TestDrive -ChildPath 'run-logs')
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        @($script:CopiedLogSessions).Count | Should Be 1
        [object]::ReferenceEquals($script:PackageExecutionSessions[0], $script:CopiedLogSessions[0]) | Should Be $true
        [object]::ReferenceEquals($script:CopiedLogSessions[0], $script:SessionToReturn) | Should Be $true
        $script:CopiedLogRemoteDirectories[0] | Should Be 'C:\ProgramData\EA\Logs\Install-EA'
        ($script:PackageOperationOrder -join ',') | Should Be 'Package,Logs'
    }

    It 'writes package logs under the captured package artifact folder' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCaptureAndLogs'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -CaptureOutput `
            -Logs `
            -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        Test-Path -LiteralPath $result.ResultPath -PathType Leaf | Should Be $true
        $script:CopiedLogComputerDirectories[0] | Should Be $result.ComputerDirectory
        $result.Logs[0].LocalPath | Should Be (Join-Path -Path (Join-Path -Path $result.ComputerDirectory -ChildPath 'Logs') -ChildPath 'package.log')
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.PackageMetadata.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
    }

    It 'returns a failed package result when the PowerShell entry point fails without discarding output' {
        $script:PackageExecutionOutput = @('started package work')
        $script:PackageExecutionErrors = @('entry point failed')

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixtureScriptPackage -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'entry point failed'
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'started package work'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'entry point failed'
        $null -eq $result.PackageMetadata.ExecutionStarted | Should Be $false
        $null -eq $result.PackageMetadata.ExecutionEnded | Should Be $false
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'copies package logs after a failed package execution without discarding output or errors' {
        $script:PackageExecutionOutput = @('started package work')
        $script:PackageExecutionErrors = @('entry point failed')

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Fail-EA.ps1' `
            -Logs `
            -OutputRoot $TestDrive

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'entry point failed'
        $result.Output[0] | Should Be 'started package work'
        $result.Errors[0] | Should Be 'entry point failed'
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\Fail-EA\package.log'
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.PackageMetadata.LogsCopied | Should Be $true
        $result.PackageMetadata.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        ($script:PackageOperationOrder -join ',') | Should Be 'Package,Logs'
    }

    It 'records package log source failures without changing primary package success' {
        $script:LogCopyError = 'RemoteDirectory was not found or is not a directory: C:\ProgramData\EA\Logs\Install-EA'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -Logs `
            -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        $result.Output[0] | Should Be 'package output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].Copied | Should Be $false
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\Install-EA'
        $result.Logs[0].Error | Should Be 'RemoteDirectory was not found or is not a directory: C:\ProgramData\EA\Logs\Install-EA'
        @($result.CopiedLogPaths).Count | Should Be 0
        $result.PackageMetadata.LogsCopied | Should Be $false
        @($result.PackageMetadata.CopiedLogPaths).Count | Should Be 0
        ($script:PackageOperationOrder -join ',') | Should Be 'Package,Logs'
    }

    It 'keeps package success when one attached package log file copy fails' {
        $script:LogCopyReturnedLogs = @(
            New-WinPushLogResult `
                -ComputerName 'PC-001' `
                -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\package.log' `
                -Copied $false `
                -ErrorMessage 'Copy failed for package.log'
        )

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -Logs `
            -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        $result.Output[0] | Should Be 'package output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].Copied | Should Be $false
        $result.Logs[0].Error | Should Be 'Copy failed for package.log'
        @($result.CopiedLogPaths).Count | Should Be 0
        $result.PackageMetadata.LogsCopied | Should Be $false
        @($result.PackageMetadata.CopiedLogPaths).Count | Should Be 0
        ($script:PackageOperationOrder -join ',') | Should Be 'Package,Logs'
    }

    It 'writes summary and run log artifacts for captured package errors' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'PackageErrorArtifacts'
        $script:PackageExecutionOutput = @('started package work')
        $script:PackageExecutionErrors = @('entry point failed')

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -CaptureOutput `
            -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'entry point failed'
        $result.Output[0] | Should Be 'started package work'
        $result.Errors[0] | Should Be 'entry point failed'
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $result.StdOutPath | Should BeNullOrEmpty
        $result.StdErrPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $result.ResultPath | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') | Should Be $false

        $summary = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summary).Count | Should Be 1
        $summary[0].Succeeded | Should Be 'False'
        $summary[0].ExitCode | Should Be '1'
        $summary[0].ErrorMessage | Should Be 'entry point failed'
        $summary[0].ResultPath | Should Be $result.ResultPath

        $runLog = Get-Content -LiteralPath $result.ResultPath -Raw
        $runLog | Should Match ([regex]::Escape('Succeeded    : False'))
        $runLog | Should Match ([regex]::Escape('ExitCode     : 1'))
        $runLog | Should Match ([regex]::Escape('ErrorMessage : entry point failed'))
        $runLog | Should Match ([regex]::Escape('started package work'))
        $runLog | Should Match ([regex]::Escape('entry point failed'))
    }

    It 'returns a failed package result when entry point invocation fails and removes the session' {
        $script:PackageExecutionError = 'entry point invocation failed'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixtureScriptPackage -EntryPoint '.\Install-EA.ps1'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'entry point invocation failed'
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        $null -eq $result.PackageMetadata.ExecutionStarted | Should Be $false
        $null -eq $result.PackageMetadata.ExecutionEnded | Should Be $false
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'writes summary and run log artifacts when captured entry point invocation throws' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'PackageInvocationErrorArtifacts'
        $script:PackageExecutionError = 'entry point invocation failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -CaptureOutput `
            -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'entry point invocation failed'
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $result.StdOutPath | Should BeNullOrEmpty
        $result.StdErrPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $result.ResultPath | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') | Should Be $false

        $summary = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summary).Count | Should Be 1
        $summary[0].Succeeded | Should Be 'False'
        $summary[0].ExitCode | Should Be '1'
        $summary[0].ErrorMessage | Should Be 'entry point invocation failed'

        $runLog = Get-Content -LiteralPath $result.ResultPath -Raw
        $runLog | Should Match ([regex]::Escape('Operation    : RunPackage'))
        $runLog | Should Match ([regex]::Escape('Succeeded    : False'))
        $runLog | Should Match ([regex]::Escape('entry point invocation failed'))
    }

    It 'extracts one staged local zip package on the endpoint and returns extracted metadata' {
        $result = Invoke-WinPushPackage -ComputerName ' PC-001 ' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1' -Extract
        $resolvedPackagePath = (Get-Item -LiteralPath $script:FixturePackage).FullName

        $result.Succeeded | Should Be $true
        $result.Operation | Should Be 'RunPackage'
        @($script:RemoteDirectoriesCreated).Count | Should Be 1
        @($script:CopiedPaths).Count | Should Be 1
        $script:CopiedPaths[0] | Should Be $resolvedPackagePath
        @($script:RemoteExtractions).Count | Should Be 1
        $script:RemoteExtractions[0].ArchivePath | Should Be $script:CopiedDestinations[0]
        $script:RemoteExtractions[0].DestinationPath | Should Be $script:RemoteDirectoriesCreated[0]
        $result.PackageMetadata.Extracted | Should Be $true
        $result.PackageMetadata.RemoteStagePath | Should Be $script:RemoteDirectoriesCreated[0]
        $result.Output[0] | Should Be 'package output'
        $script:PackageExecutionRoots[0] | Should Be $script:RemoteDirectoriesCreated[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed package result when local zip extraction fails and removes the session' {
        $script:RemoteExtractionError = 'remote zip extraction failed'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixturePackage -EntryPoint '.\Install-EA.ps1' -Extract

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'remote zip extraction failed'
        @($script:RemoteExtractions).Count | Should Be 1
        $result.PackageMetadata.Extracted | Should Be $false
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'rejects Extract for local non-zip packages before opening a session' {
        $packagePath = Join-Path -Path $TestDrive -ChildPath 'Package.txt'
        Set-Content -LiteralPath $packagePath -Value 'package' -Encoding utf8NoBOM

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $packagePath -EntryPoint '.\Install-EA.ps1' -Extract

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Extract requires a staged .zip package file.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemoteDirectoriesCreated).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
        @($script:RemoteExtractions).Count | Should Be 0
    }

    It 'rejects Extract for local directory packages before opening a session' {
        $directoryPath = Join-Path -Path $TestDrive -ChildPath 'PackageDirectoryExtractRejection'
        New-Item -ItemType Directory -Path $directoryPath | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $directoryPath -ChildPath 'Install-EA.ps1') -Value 'Write-Output package' -Encoding utf8NoBOM

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $directoryPath -EntryPoint '.\Install-EA.ps1' -Extract

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Extract requires a staged .zip package file.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemoteDirectoriesCreated).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
        @($script:RemoteExtractions).Count | Should Be 0
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
        $result.Output[0] | Should Be 'package output'
        $script:PackageExecutionRoots[0] | Should Be $remoteStageRoot
    }

    It 'uses the supplied remote stage root' {
        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixtureScriptPackage `
            -EntryPoint '.\Install-EA.ps1' `
            -RemoteStageRoot 'D:\WinPushStage\'

        $result.Succeeded | Should Be $true
        $script:RemoteDirectoriesCreated[0] | Should Match ([regex]::Escape('D:\WinPushStage\package-'))
        $result.PackageMetadata.RemoteStagePath | Should Match ([regex]::Escape('D:\WinPushStage\package-'))
    }

    It 'passes the supplied credential object unchanged to New-PSSession' {
        $credential = Get-TestCredential -Secret 'Distinctive-Package-Credential-Secret!'

        $result = Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixtureScriptPackage -EntryPoint '.\Install-EA.ps1' -Credential $credential

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

    It 'writes summary and run log artifacts for captured session failures' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'PackageSessionFailureArtifacts'
        $script:NewPSSessionError = 'package session failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Path $script:FixturePackage `
            -EntryPoint '.\Install-EA.ps1' `
            -CaptureOutput `
            -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'package session failed'
        $result.RunDirectory | Should Match ([regex]::Escape($outputRoot))
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $result.StdOutPath | Should BeNullOrEmpty
        $result.StdErrPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $result.ResultPath | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') | Should Be $false

        $summary = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summary).Count | Should Be 1
        $summary[0].Succeeded | Should Be 'False'
        $summary[0].ExitCode | Should Be '1'
        $summary[0].ErrorMessage | Should Be 'package session failed'

        $runLog = Get-Content -LiteralPath $result.ResultPath -Raw
        $runLog | Should Match ([regex]::Escape('Operation    : RunPackage'))
        $runLog | Should Match ([regex]::Escape('Succeeded    : False'))
        $runLog | Should Match ([regex]::Escape('package session failed'))
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
        Invoke-WinPushPackage -ComputerName 'PC-001' -Path $script:FixtureScriptPackage -EntryPoint '.\Install-EA.ps1' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'downloads one URI package to the admin workstation cache, stages it to one target, and returns package metadata' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCache'
        $uri = 'https://storage.contoso.example/packages/Install-EA.ps1'

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
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:RemoteDirectoriesCreated).Count | Should Be 1
        $script:RemoteDirectoriesCreated[0] | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        @($script:CopiedPaths).Count | Should Be 1
        $script:CopiedPaths[0] | Should Be $script:DownloadOutFiles[0]
        $script:CopiedDirections[0] | Should Be 'Upload'
        $script:CopiedDestinations[0] | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        $script:CopiedDestinations[0] | Should Match ([regex]::Escape('\Install-EA.ps1'))
        [object]::ReferenceEquals($script:CopiedSessions[0], $script:SessionToReturn) | Should Be $true
        @($script:DownloadUris).Count | Should Be 1
        $script:DownloadUris[0].OriginalString | Should Be $uri
        $script:DownloadOutFiles[0] | Should Match ([regex]::Escape($cacheRoot))
        $script:DownloadOutFiles[0] | Should Match ([regex]::Escape('Install-EA.ps1'))
        Test-Path -LiteralPath $script:DownloadOutFiles[0] | Should Be $true
        $result.PackageMetadata.PSTypeNames[0] | Should Be 'WinPush.PackageMetadata'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.PackageSource | Should Be $uri
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        $result.PackageMetadata.EntryPoint | Should Be '.\Install-EA.ps1'
        $result.PackageMetadata.Extracted | Should Be $false
        $result.PackageMetadata.CleanupPolicy | Should Be 'Never'
        $result.PackageMetadata.LogsCopied | Should Be $false
        $null -eq $result.PackageMetadata.ExecutionStarted | Should Be $false
        $null -eq $result.PackageMetadata.ExecutionEnded | Should Be $false
        $result.Output[0] | Should Be 'package output'
        $script:PackageExecutionRoots[0] | Should Be $script:RemoteDirectoriesCreated[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'writes summary and run log artifacts for cached URI package capture output' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'UriPackageArtifacts'
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCacheArtifacts'
        $uri = 'https://storage.contoso.example/packages/Install-EA.ps1'

        $result = Invoke-WinPushPackage `
            -ComputerName ' PC-001 ' `
            -Uri $uri `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot `
            -CaptureOutput `
            -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        $result.Output[0] | Should Be 'package output'
        $result.RunDirectory | Should Match ([regex]::Escape($outputRoot))
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $result.StdOutPath | Should BeNullOrEmpty
        $result.StdErrPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $result.ResultPath | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') | Should Be $false

        $summary = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summary).Count | Should Be 1
        $summary[0].ComputerName | Should Be 'PC-001'
        $summary[0].Operation | Should Be 'RunPackage'
        $summary[0].ResultPath | Should Be $result.ResultPath

        $runLog = Get-Content -LiteralPath $result.ResultPath -Raw
        $runLog | Should Match ([regex]::Escape("Identity     : Uri: $uri; EntryPoint: .\Install-EA.ps1"))
        $runLog | Should Match ([regex]::Escape('package output'))
    }

    It 'extracts one staged cached URI zip package on the endpoint and returns extracted metadata' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCacheExtract'
        $uri = 'https://storage.contoso.example/packages/EA%20Install.zip'

        $result = Invoke-WinPushPackage `
            -ComputerName ' PC-001 ' `
            -Uri $uri `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot `
            -Extract

        $result.Succeeded | Should Be $true
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.Extracted | Should Be $true
        $result.PackageMetadata.RemoteStagePath | Should Be $script:RemoteDirectoriesCreated[0]
        @($script:RemoteExtractions).Count | Should Be 1
        $script:RemoteExtractions[0].ArchivePath | Should Be $script:CopiedDestinations[0]
        $script:RemoteExtractions[0].DestinationPath | Should Be $script:RemoteDirectoriesCreated[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed URI package result when cached zip extraction fails and removes the session' {
        $script:RemoteExtractionError = 'uri package extraction failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -Extract

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'uri package extraction failed'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.Extracted | Should Be $false
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        @($script:RemoteExtractions).Count | Should Be 1
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'rejects Extract for URI non-zip packages before downloading or opening an endpoint session' {
        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.txt' `
            -EntryPoint '.\Install-EA.ps1' `
            -Extract

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Extract requires a staged .zip package file.'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Match ([regex]::Escape('EA.txt'))
        $result.PackageMetadata.RemoteStagePath | Should BeNullOrEmpty
        @($script:DownloadUris).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemoteExtractions).Count | Should Be 0
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

    It 'returns a failed URI package result when session creation fails after download' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCacheSessionFailure'
        $script:NewPSSessionError = 'uri package session failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'uri package session failed'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.RemoteStagePath | Should BeNullOrEmpty
        @($script:DownloadUris).Count | Should Be 1
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        @($script:RemoteDirectoriesCreated).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'passes the supplied credential object unchanged when staging a cached URI package' {
        $credential = Get-TestCredential -Secret 'Distinctive-Uri-Package-Credential-Secret!'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -Credential $credential

        $result.Succeeded | Should Be $true
        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
    }

    It 'normalizes cached URI package credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-Uri-Package-Session-Secret!'
        $credential = Get-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -Credential $credential
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

    It 'returns a failed URI package result when remote staging directory creation fails and removes the session' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCacheStageFailure'
        $script:RemoteDirectoryError = 'uri remote staging directory failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'uri remote staging directory failed'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.RemoteStagePath | Should Match ([regex]::Escape('C:\ProgramData\WinPush\Staging\package-'))
        @($script:DownloadUris).Count | Should Be 1
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        @($script:CopiedPaths).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed URI package result when cached package upload fails and removes the session' {
        $cacheRoot = Join-Path -Path $TestDrive -ChildPath 'PackageCacheUploadFailure'
        $script:CopyError = 'uri cached package upload failed'

        $result = Invoke-WinPushPackage `
            -ComputerName 'PC-001' `
            -Uri 'https://storage.contoso.example/packages/EA.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -PackageCacheRoot $cacheRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'uri cached package upload failed'
        $result.PackageMetadata.PackageSourceType | Should Be 'Uri'
        $result.PackageMetadata.LocalPackagePath | Should Be $script:DownloadOutFiles[0]
        $result.PackageMetadata.RemoteStagePath | Should Be $script:CopiedDestinations[0]
        @($script:DownloadUris).Count | Should Be 1
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        @($script:CopiedPaths).Count | Should Be 1
        $script:CopiedPaths[0] | Should Be $script:DownloadOutFiles[0]
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
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

Describe 'WinPush package entry point helpers' {
    BeforeEach {
        $script:InvokeCommandSessions = @()
        $script:InvokeCommandArgumentLists = @()
        $script:InvokeCommandScriptBlocks = @()
        $script:InvokeCommandError = $null
        $script:SessionToReturn = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )
    }

    Mock Invoke-Command {
        param(
            $Session,
            [scriptblock] $ScriptBlock,
            [object[]] $ArgumentList,
            $ErrorAction
        )

        $null = $ErrorAction
        $script:InvokeCommandSessions += $Session
        $script:InvokeCommandArgumentLists += , $ArgumentList
        $script:InvokeCommandScriptBlocks += [string] $ScriptBlock
        if ($null -ne $script:InvokeCommandError) {
            throw $script:InvokeCommandError
        }

        @(
            [pscustomobject] [ordered] @{
                Stream = 'Output'
                Value  = 'helper output'
            }
            [pscustomobject] [ordered] @{
                Stream = 'Error'
                Value  = 'helper error'
            }
        )
    }

    It 'normalizes a relative PowerShell entry point beneath the package root' {
        $plan = Resolve-WinPushPackageEntryPoint -PackageRoot 'C:\Stage\Package\' -EntryPoint '.\tools/Install-EA.ps1'

        $plan.PSTypeNames[0] | Should Be 'WinPush.PackageEntryPointPlan'
        $plan.PackageRoot | Should Be 'C:\Stage\Package'
        $plan.RelativePath | Should Be 'tools\Install-EA.ps1'
        $plan.RemotePath | Should Be 'C:\Stage\Package\tools\Install-EA.ps1'
    }

    It 'passes the package root as the remote working directory argument and separates streams' {
        $result = Invoke-WinPushPsrpPackageEntryPoint `
            -Session $script:SessionToReturn `
            -PackageRoot 'C:\Stage\Package' `
            -EntryPoint '.\Install-EA.ps1'

        [object]::ReferenceEquals($script:InvokeCommandSessions[0], $script:SessionToReturn) | Should Be $true
        $script:InvokeCommandArgumentLists[0][0] | Should Be 'C:\Stage\Package'
        $script:InvokeCommandArgumentLists[0][1] | Should Be 'Install-EA.ps1'
        $script:InvokeCommandScriptBlocks[0] | Should Match ([regex]::Escape('Set-Location -LiteralPath $WorkingDirectory'))
        $script:InvokeCommandScriptBlocks[0] | Should Match ([regex]::Escape('Test-Path -LiteralPath $entryPointPath -PathType Leaf'))
        $script:InvokeCommandScriptBlocks[0] | Should Match ([regex]::Escape('& $entryPointPath 2>&1'))
        $script:InvokeCommandScriptBlocks[0] | Should Match ([regex]::Escape("Stream = 'Error'"))
        $result.PSTypeNames[0] | Should Be 'WinPush.PsrpPackageEntryPointResult'
        $result.Output[0] | Should Be 'helper output'
        $result.Errors[0] | Should Be 'helper error'
    }
}
