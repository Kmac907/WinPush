$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:ArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Write-WinPushCommandOutputArtifact.ps1'
$script:PsrpCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Invoke-WinPushPsrpCommand.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Invoke-WinPushCommand.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:ArtifactPath
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
        $null -eq $result.RunDirectory | Should Be $true
        $null -eq $result.ComputerDirectory | Should Be $true
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
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

    It 'captures command output to one target artifact folder when requested' {
        $script:InvokeCommandOutput = @('first line', 'second line')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Output "remote output"' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        $result.RunDirectory.StartsWith($outputRoot) | Should Be $true
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.StdOutPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt')
        $result.StdErrPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt')
        Test-Path -LiteralPath $result.StdOutPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdErrPath -PathType Leaf | Should Be $true
        (Get-Content -LiteralPath $result.StdOutPath) -join ',' | Should Be 'first line,second line'
        @(Get-Content -LiteralPath $result.StdErrPath).Count | Should Be 0
        @($result.Output).Count | Should Be 2
        $result.Output[0] | Should Be 'first line'
    }

    It 'captures custom object output without replacing the result object payload' {
        $customObject = [pscustomobject] [ordered] @{
            Name  = 'Alpha'
            Count = 2
        }
        $script:InvokeCommandOutput = @($customObject)
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '[pscustomobject] @{ Name = "Alpha"; Count = 2 }' -CaptureOutput -OutputRoot $outputRoot
        $stdoutText = Get-Content -LiteralPath $result.StdOutPath -Raw

        @($result.Output).Count | Should Be 1
        $result.Output[0].Name | Should Be 'Alpha'
        $result.Output[0].Count | Should Be 2
        $stdoutText | Should Match 'Alpha'
        $stdoutText | Should Match '2'
    }

    It 'creates empty stdout and stderr artifacts when captured command output is empty' {
        $script:InvokeCommandOutput = @()
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '$null' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        @($result.Output).Count | Should Be 0
        Test-Path -LiteralPath $result.StdOutPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdErrPath -PathType Leaf | Should Be $true
        @(Get-Content -LiteralPath $result.StdOutPath).Count | Should Be 0
        @(Get-Content -LiteralPath $result.StdErrPath).Count | Should Be 0
    }

    It 'uses a unique run folder when capture output is invoked more than once in the same second' {
        $script:InvokeCommandOutput = @('first')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $firstResult = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '"first"' -CaptureOutput -OutputRoot $outputRoot

        $script:InvokeCommandOutput = @('second')
        $secondResult = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '"second"' -CaptureOutput -OutputRoot $outputRoot

        $firstResult.RunDirectory -eq $secondResult.RunDirectory | Should Be $false
        (Get-Content -LiteralPath $firstResult.StdOutPath) -join ',' | Should Be 'first'
        (Get-Content -LiteralPath $secondResult.StdOutPath) -join ',' | Should Be 'second'
    }

    It 'captures failed command errors to stderr artifact when requested' {
        $script:InvokeCommandError = 'command failed'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'throw "command failed"' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'command failed'
        Test-Path -LiteralPath $result.StdOutPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdErrPath -PathType Leaf | Should Be $true
        @(Get-Content -LiteralPath $result.StdOutPath).Count | Should Be 0
        (Get-Content -LiteralPath $result.StdErrPath) -join ',' | Should Be 'command failed'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'command failed'
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

    It 'rejects whitespace output root before opening a session when capture output is requested' {
        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -CaptureOutput -OutputRoot '   ' } | Should Throw 'OutputRoot must not be empty.'

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
