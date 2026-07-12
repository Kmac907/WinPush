$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:PsrpCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Invoke-WinPushPsrpCommand.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Invoke-WinPushCommand.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:PsrpCommandPath
. $script:CommandPath

Describe 'Invoke-WinPushCommand' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:InvokedScriptBlocks = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 202; ComputerName = 'PC-001' }
        $script:InvokeCommandOutput = @('remote output')
        $script:NewPSSessionError = $null
        $script:InvokeCommandError = $null
    }

    Mock New-PSSession {
        param(
            [string] $ComputerName,
            $ErrorAction
        )

        $null = $ErrorAction
        $script:NewPSSessionComputerNames += $ComputerName

        if ($null -ne $script:NewPSSessionError) {
            throw $script:NewPSSessionError
        }

        return $script:SessionToReturn
    }

    Mock Invoke-WinPushPsrpCommand {
        param(
            $Session,
            [scriptblock] $ScriptBlock
        )

        $null = $Session
        $script:InvokedScriptBlocks += $ScriptBlock.ToString()

        if ($null -ne $script:InvokeCommandError) {
            throw $script:InvokeCommandError
        }

        return $script:InvokeCommandOutput
    }

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'runs one PowerShell command on one target and returns a summary result' {
        $result = Invoke-WinPushCommand -ComputerName ' PC-001 ' -Command '$env:COMPUTERNAME'

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'remote output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 0
    }

    It 'invokes the supplied text as PowerShell source through the created session' {
        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Get-Date' | Out-Null

        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:InvokedScriptBlocks).Count | Should Be 1
        $script:InvokedScriptBlocks[0] | Should Be 'Get-Date'
    }

    It 'does not emit raw command output as separate pipeline objects' {
        $results = @(Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Output "remote output"')

        @($results).Count | Should Be 1
        $results[0].PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $results[0].Output[0] | Should Be 'remote output'
    }

    It 'returns an empty output array when the command emits nothing' {
        $script:InvokeCommandOutput = @()

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '$null'

        $result.Succeeded | Should Be $true
        @($result.Output).Count | Should Be 0
    }

    It 'rejects whitespace command text before opening a session' {
        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command '   ' } | Should Throw 'Command text must not be empty.'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'removes the created session after command execution' {
        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed result when session creation fails before returning one' {
        $script:NewPSSessionError = 'connection failed'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname'

        $result.ComputerName | Should Be 'PC-001'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'connection failed'
        @($script:RemovedSessionIds).Count | Should Be 0
    }
}
