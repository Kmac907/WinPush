$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:FactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1'

. $script:FactoryPath

Describe 'New-WinPushExecutionResult' {
    It 'creates a WinPush.ExecutionResult with the exact result properties' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-001' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0
        $propertyNames = @($result.PSObject.Properties.Name)

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        ($propertyNames -join ',') | Should Be 'ComputerName,Transport,Operation,Succeeded,ExitCode,ErrorMessage,Output,Errors,Logs,RunDirectory,ComputerDirectory,ResultPath,StdOutPath,StdErrPath,CopiedLogPaths'
        ($propertyNames -contains 'Credential') | Should Be $false
        ($propertyNames -contains 'Password') | Should Be $false
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
            -ResultPath 'C:\WinPush\10-07-2026-143012\PC-007\result.txt' `
            -StdOutPath 'C:\WinPush\10-07-2026-143012\PC-007\stdout.txt' `
            -StdErrPath 'C:\WinPush\10-07-2026-143012\PC-007\stderr.txt'

        $result.RunDirectory | Should Be 'C:\WinPush\10-07-2026-143012'
        $result.ComputerDirectory | Should Be 'C:\WinPush\10-07-2026-143012\PC-007'
        $result.ResultPath | Should Be 'C:\WinPush\10-07-2026-143012\PC-007\result.txt'
        $result.StdOutPath | Should Be 'C:\WinPush\10-07-2026-143012\PC-007\stdout.txt'
        $result.StdErrPath | Should Be 'C:\WinPush\10-07-2026-143012\PC-007\stderr.txt'
    }
}
