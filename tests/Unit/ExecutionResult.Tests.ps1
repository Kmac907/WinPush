$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:FactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1'
$script:PackageMetadataFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushPackageInfo.ps1'

. $script:FactoryPath
. $script:PackageMetadataFactoryPath

Describe 'New-WinPushExecutionResult' {
    It 'creates a WinPush.ExecutionResult with the exact result properties' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-001' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0
        $propertyNames = @($result.PSObject.Properties.Name)

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        ($propertyNames -join ',') | Should Be 'ComputerName,Transport,Operation,Succeeded,ExitCode,ErrorMessage,Output,Errors,Logs,RunDirectory,ComputerDirectory,ResultPath,StdOutPath,StdErrPath,CopiedLogPaths,PackageMetadata'
        ($propertyNames -contains 'Credential') | Should Be $false
        ($propertyNames -contains 'Password') | Should Be $false
    }

    It 'keeps the primary result type and appends operation-specific display types' {
        $operationTypes = @{
            RunCommand = 'WinPush.ExecutionResult.RunCommand'
            RunScript  = 'WinPush.ExecutionResult.RunScript'
            RunPackage = 'WinPush.ExecutionResult.RunPackage'
            CopyFile   = 'WinPush.ExecutionResult.CopyFile'
            GetLogs    = 'WinPush.ExecutionResult.GetLogs'
            TestTarget = 'WinPush.ExecutionResult.TestTarget'
        }

        foreach ($operation in $operationTypes.Keys) {
            $result = New-WinPushExecutionResult -ComputerName 'PC-001' -Transport 'PSRP' -Operation $operation -Succeeded $true -ExitCode 0

            $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
            $result.PSTypeNames[1] | Should Be $operationTypes[$operation]
        }
    }

    It 'does not append operation-specific display types for unknown operations' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-001' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        ($result.PSTypeNames -contains 'WinPush.ExecutionResult.Invoke') | Should Be $false
    }

    It 'captures a successful execution result' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-001' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0 -Output 'done' -Logs 'started'

        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'PSRP'
        $result.Operation | Should Be 'Invoke'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'done'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0] | Should Be 'started'
    }

    It 'captures a failed execution result' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-002' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $false -ExitCode 1 -ErrorMessage 'access denied' -Errors 'failed'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'access denied'
        @($result.Output).Count | Should Be 0
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'failed'
        @($result.Logs).Count | Should Be 0
    }

    It 'uses the first error as the failed result error message when none is supplied' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-002' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $false -ExitCode 1 -Errors @('first failure', 'second failure')

        $result.ErrorMessage | Should Be 'first failure'
    }

    It 'normalizes no output, errors, logs, or copied log paths to empty arrays' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-003' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode $null
        $nullResult = New-WinPushExecutionResult -ComputerName 'PC-003' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode $null -Output $null -Errors $null -Logs $null -CopiedLogPaths $null

        $null -eq $result.ExitCode | Should Be $true
        $result.Output -is [object[]] | Should Be $true
        $result.Errors -is [object[]] | Should Be $true
        $result.Logs -is [object[]] | Should Be $true
        $result.CopiedLogPaths -is [object[]] | Should Be $true
        $result.Output.Count | Should Be 0
        $result.Errors.Count | Should Be 0
        $result.Logs.Count | Should Be 0
        $result.CopiedLogPaths.Count | Should Be 0
        $nullResult.Output.Count | Should Be 0
        $nullResult.Errors.Count | Should Be 0
        $nullResult.Logs.Count | Should Be 0
        $nullResult.CopiedLogPaths.Count | Should Be 0
    }

    It 'normalizes multiple output, error, log, and copied log path entries to arrays' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-004' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0 -Output @('one', 'two') -Errors @('warn', 'retry') -Logs @('start', 'stop') -CopiedLogPaths @('C:\WinPush\run\PC-004\Logs\a.log', 'C:\WinPush\run\PC-004\Logs\b.log')

        $result.Output -is [object[]] | Should Be $true
        $result.Errors -is [object[]] | Should Be $true
        $result.Logs -is [object[]] | Should Be $true
        $result.CopiedLogPaths -is [object[]] | Should Be $true
        ($result.Output -join ',') | Should Be 'one,two'
        ($result.Errors -join ',') | Should Be 'warn,retry'
        ($result.Logs -join ',') | Should Be 'start,stop'
        ($result.CopiedLogPaths -join ',') | Should Be 'C:\WinPush\run\PC-004\Logs\a.log,C:\WinPush\run\PC-004\Logs\b.log'
    }

    It 'captures partial output with errors' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-005' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $false -ExitCode 5 -Output @('line 1', 'line 2') -Errors 'access denied'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 5
        ($result.Output -join ',') | Should Be 'line 1,line 2'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'access denied'
    }

    It 'leaves local artifact paths null when no artifacts are supplied' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-006' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0

        $null -eq $result.RunDirectory | Should Be $true
        $null -eq $result.ComputerDirectory | Should Be $true
        $null -eq $result.ResultPath | Should Be $true
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        $null -eq $result.PackageMetadata | Should Be $true
    }

    It 'captures local artifact paths when supplied' {
        $result = New-WinPushExecutionResult `
            -ComputerName 'PC-007' `
            -Transport 'PSRP' `
            -Operation 'Invoke' `
            -Succeeded $true `
            -ExitCode 0 `
            -RunDirectory 'C:\WinPush\10-07-2026-143012' `
            -ComputerDirectory 'C:\WinPush\10-07-2026-143012\PC-007' `
            -ResultPath 'C:\WinPush\10-07-2026-143012\PC-007\run.log'

        $result.RunDirectory | Should Be 'C:\WinPush\10-07-2026-143012'
        $result.ComputerDirectory | Should Be 'C:\WinPush\10-07-2026-143012\PC-007'
        $result.ResultPath | Should Be 'C:\WinPush\10-07-2026-143012\PC-007\run.log'
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
    }

    It 'carries package metadata when supplied' {
        $metadata = New-WinPushPackageInfo `
            -PackageSourceType Path `
            -PackageSource 'C:\Packages\EAInstallPackage.zip' `
            -LocalPackagePath 'C:\Packages\EAInstallPackage.zip' `
            -RemoteStagePath 'C:\ProgramData\WinPush\Staging\run-001\EAInstallPackage.zip' `
            -EntryPoint '.\Install-EA.ps1' `
            -Extracted $true `
            -CleanupPolicy Always `
            -CleanupSucceeded $true `
            -LogsCopied $true `
            -CopiedLogPaths 'C:\WinPush\run\PC-008\Logs\install.log'

        $result = New-WinPushExecutionResult `
            -ComputerName 'PC-008' `
            -Transport 'Psrp' `
            -Operation 'RunPackage' `
            -Succeeded $true `
            -ExitCode 0 `
            -PackageMetadata $metadata

        $result.Operation | Should Be 'RunPackage'
        $result.PackageMetadata.PSTypeNames[0] | Should Be 'WinPush.PackageMetadata'
        $result.PackageMetadata.PackageSourceType | Should Be 'Path'
        $result.PackageMetadata.PackageSource | Should Be 'C:\Packages\EAInstallPackage.zip'
        $result.PackageMetadata.RemoteStagePath | Should Be 'C:\ProgramData\WinPush\Staging\run-001\EAInstallPackage.zip'
        $result.PackageMetadata.EntryPoint | Should Be '.\Install-EA.ps1'
        $result.PackageMetadata.Extracted | Should Be $true
        $result.PackageMetadata.CleanupPolicy | Should Be 'Always'
        $result.PackageMetadata.CleanupSucceeded | Should Be $true
        $result.PackageMetadata.LogsCopied | Should Be $true
        ($result.PackageMetadata.CopiedLogPaths -join ',') | Should Be 'C:\WinPush\run\PC-008\Logs\install.log'
    }
}

Describe 'New-WinPushPackageInfo' {
    It 'creates package metadata with the exact property contract' {
        $metadata = New-WinPushPackageInfo `
            -PackageSourceType Uri `
            -PackageSource 'https://storage.contoso.example/packages/EA.zip' `
            -LocalPackagePath 'C:\WinPush\PackageCache\run-001\EA.zip' `
            -RemoteStagePath 'C:\ProgramData\WinPush\Staging\run-001\EA.zip' `
            -EntryPoint '.\Install-EA.ps1'

        $propertyNames = @($metadata.PSObject.Properties.Name)

        $metadata.PSTypeNames[0] | Should Be 'WinPush.PackageMetadata'
        ($propertyNames -join ',') | Should Be 'PackageSourceType,PackageSource,LocalPackagePath,RemoteStagePath,EntryPoint,Extracted,ExecutionStarted,ExecutionEnded,CleanupPolicy,CleanupSucceeded,LogsCopied,CopiedLogPaths'
        $metadata.PackageSourceType | Should Be 'Uri'
        $metadata.PackageSource | Should Be 'https://storage.contoso.example/packages/EA.zip'
        $metadata.LocalPackagePath | Should Be 'C:\WinPush\PackageCache\run-001\EA.zip'
        $metadata.RemoteStagePath | Should Be 'C:\ProgramData\WinPush\Staging\run-001\EA.zip'
        $metadata.EntryPoint | Should Be '.\Install-EA.ps1'
        $metadata.Extracted | Should Be $false
        $null -eq $metadata.ExecutionStarted | Should Be $true
        $null -eq $metadata.ExecutionEnded | Should Be $true
        $metadata.CleanupPolicy | Should Be 'Never'
        $null -eq $metadata.CleanupSucceeded | Should Be $true
        $metadata.LogsCopied | Should Be $false
        $metadata.CopiedLogPaths -is [object[]] | Should Be $true
        $metadata.CopiedLogPaths.Count | Should Be 0
    }
}
