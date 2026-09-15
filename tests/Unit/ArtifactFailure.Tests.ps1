$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Targeting\Resolve-WinPushTarget.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\Add-WinPushExecutionArtifact.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Write-WinPushCommandOutputArtifact.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushWinRsCommand.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Invoke-WinPushCommand.ps1')

Describe 'Artifact failure isolation' {
    BeforeEach {
        $script:OperationOrder = @()

        Mock New-WinPushArtifactRunDirectory {
            $script:OperationOrder += 'RunDirectory'
            Join-Path -Path $OutputRoot -ChildPath 'shared-run'
        }
        Mock Invoke-WinPushWinRsCommand {
            param([string] $ComputerName, [string] $Command)

            $null = $Command
            $script:OperationOrder += "Execute:$ComputerName"
            [pscustomobject] @{
                ExitCode = 0
                Output   = @("output:$ComputerName")
                Errors   = @("warning:$ComputerName")
            }
        }
        Mock Write-WinPushCommandOutputArtifact {
            $script:OperationOrder += 'Artifact'
            throw 'artifact disk is full'
        }
    }

    It 'preserves remote results, disables failed output writes, and continues in target order' {
        $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002') -Command 'hostname' -Transport WinRM -CaptureOutput -OutputRoot $TestDrive)

        ($script:OperationOrder -join ',') | Should Be 'RunDirectory,Execute:PC-001,Artifact,Execute:PC-002'
        Assert-MockCalled Write-WinPushCommandOutputArtifact -Times 1 -Exactly
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'

        foreach ($result in $results) {
            $result.Succeeded | Should Be $true
            $result.ExitCode | Should Be 0
            $result.Output[0] | Should Be "output:$($result.ComputerName)"
            $result.Errors[0] | Should Be "warning:$($result.ComputerName)"
            $result.ArtifactError | Should Be 'artifact disk is full'
            $result.RunDirectory | Should Be (Join-Path -Path $TestDrive -ChildPath 'shared-run')
            $result.ComputerDirectory | Should BeNullOrEmpty
            $result.ResultPath | Should BeNullOrEmpty
            $result.StdOutPath | Should BeNullOrEmpty
            $result.StdErrPath | Should BeNullOrEmpty
        }
    }
}
