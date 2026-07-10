$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:FactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'

. $script:FactoryPath

Describe 'New-WinPushExecutionResult' {
    It 'creates a WinPush.ExecutionResult with the exact result properties' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-001' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0
        $propertyNames = @($result.PSObject.Properties.Name)

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        ($propertyNames -join ',') | Should Be 'ComputerName,Transport,Operation,Succeeded,ExitCode,Output,Errors,Logs'
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
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'done'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0] | Should Be 'started'
    }

    It 'captures a failed execution result' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-002' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $false -ExitCode 1 -Errors 'failed'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        @($result.Output).Count | Should Be 0
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'failed'
        @($result.Logs).Count | Should Be 0
    }

    It 'normalizes no output, errors, or logs to empty arrays' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-003' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode $null
        $nullResult = New-WinPushExecutionResult -ComputerName 'PC-003' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode $null -Output $null -Errors $null -Logs $null

        $null -eq $result.ExitCode | Should Be $true
        $result.Output -is [object[]] | Should Be $true
        $result.Errors -is [object[]] | Should Be $true
        $result.Logs -is [object[]] | Should Be $true
        $result.Output.Count | Should Be 0
        $result.Errors.Count | Should Be 0
        $result.Logs.Count | Should Be 0
        $nullResult.Output.Count | Should Be 0
        $nullResult.Errors.Count | Should Be 0
        $nullResult.Logs.Count | Should Be 0
    }

    It 'normalizes multiple output, error, and log entries to arrays' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-004' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $true -ExitCode 0 -Output @('one', 'two') -Errors @('warn', 'retry') -Logs @('start', 'stop')

        $result.Output -is [object[]] | Should Be $true
        $result.Errors -is [object[]] | Should Be $true
        $result.Logs -is [object[]] | Should Be $true
        ($result.Output -join ',') | Should Be 'one,two'
        ($result.Errors -join ',') | Should Be 'warn,retry'
        ($result.Logs -join ',') | Should Be 'start,stop'
    }

    It 'captures partial output with errors' {
        $result = New-WinPushExecutionResult -ComputerName 'PC-005' -Transport 'PSRP' -Operation 'Invoke' -Succeeded $false -ExitCode 5 -Output @('line 1', 'line 2') -Errors 'access denied'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 5
        ($result.Output -join ',') | Should Be 'line 1,line 2'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'access denied'
    }
}
