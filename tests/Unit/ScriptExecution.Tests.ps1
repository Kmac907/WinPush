$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:ArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Write-WinPushCommandOutputArtifact.ps1'
$script:PsrpScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Invoke-WinPushPsrpScript.ps1'
$script:ScriptCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Invoke-WinPushScript.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:ArtifactPath
. $script:PsrpScriptPath
. $script:ScriptCommandPath

Describe 'Invoke-WinPushScript' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:InvokedScriptPaths = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 302; ComputerName = 'PC-001' }
        $script:InvokeScriptOutput = @('script output')
        $script:InvokeScriptErrors = @()
        $script:NewPSSessionError = $null
        $script:InvokeScriptError = $null
        $script:FixtureScript = Join-Path -Path $TestDrive -ChildPath 'Invoke-WinPushScript-Fixture.ps1'
        Set-Content -LiteralPath $script:FixtureScript -Value 'Write-Output "script output"' -Encoding utf8NoBOM
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

    Mock Invoke-WinPushPsrpScript {
        param(
            $Session,
            [string] $FilePath
        )

        $null = $Session
        $script:InvokedScriptPaths += $FilePath

        if ($null -ne $script:InvokeScriptError) {
            throw $script:InvokeScriptError
        }

        return [pscustomobject] [ordered] @{
            PSTypeName = 'WinPush.PsrpScriptResult'
            Output     = @($script:InvokeScriptOutput)
            Errors     = @($script:InvokeScriptErrors)
        }
    }

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'runs one local PowerShell script on one target and returns a summary result' {
        $result = Invoke-WinPushScript -ComputerName ' PC-001 ' -ScriptPath $script:FixtureScript

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'RunScript'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'script output'
        @($result.Errors).Count | Should Be 0
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
    }

    It 'passes the validated local script file path to PSRP script execution' {
        Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript | Out-Null

        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:InvokedScriptPaths).Count | Should Be 1
        $script:InvokedScriptPaths[0] | Should Be (Get-Item -LiteralPath $script:FixtureScript).FullName
    }

    It 'does not emit raw script output as separate pipeline objects' {
        $results = @(Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 1
        $results[0].PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $results[0].Output[0] | Should Be 'script output'
    }

    It 'captures script output to one target artifact folder when requested' {
        $script:InvokeScriptOutput = @('first line', 'second line')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        $result.RunDirectory.StartsWith($outputRoot) | Should Be $true
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt')
        $result.StdOutPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt')
        $result.StdErrPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt')
        Test-Path -LiteralPath $result.ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdOutPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdErrPath -PathType Leaf | Should Be $true
        $resultText = Get-Content -LiteralPath $result.ResultPath -Raw
        $resultText | Should Match 'ComputerName : PC-001'
        $resultText | Should Match 'Operation    : RunScript'
        $resultText | Should Match 'Transport    : Psrp'
        $resultText | Should Match 'Succeeded    : True'
        $resultText | Should Match 'ExitCode     : 0'
        $resultText | Should Match 'StdOutPath'
        $resultText | Should Match 'StdErrPath'
        $resultText | Should Match 'ErrorMessage:'
        $summaryPath = Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'
        Test-Path -LiteralPath $summaryPath -PathType Leaf | Should Be $true
        $summaryRows = @(Import-Csv -LiteralPath $summaryPath)
        @($summaryRows).Count | Should Be 1
        $summaryRows[0].ComputerName | Should Be 'PC-001'
        $summaryRows[0].Operation | Should Be 'RunScript'
        $summaryRows[0].Transport | Should Be 'Psrp'
        $summaryRows[0].Succeeded | Should Be 'True'
        $summaryRows[0].ExitCode | Should Be '0'
        $summaryRows[0].ResultPath | Should Be $result.ResultPath
        $summaryRows[0].StdOutPath | Should Be $result.StdOutPath
        $summaryRows[0].StdErrPath | Should Be $result.StdErrPath
        (Get-Content -LiteralPath $result.StdOutPath) -join ',' | Should Be 'first line,second line'
        @(Get-Content -LiteralPath $result.StdErrPath).Count | Should Be 0
    }

    It 'captures script errors to stderr artifact when requested' {
        $script:InvokeScriptOutput = @()
        $script:InvokeScriptErrors = @('script failed')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'script failed'
        (Get-Content -LiteralPath $result.StdErrPath) -join ',' | Should Be 'script failed'
    }

    It 'rejects a missing script path before opening a session' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.ps1'

        { Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $missingPath } | Should Throw 'Script file was not found:'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'rejects a directory script path before opening a session' {
        { Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $TestDrive } | Should Throw 'ScriptPath must refer to a file:'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'rejects an existing non-ps1 file before opening a session' {
        $textFile = Join-Path -Path $TestDrive -ChildPath 'not-a-script.txt'
        Set-Content -LiteralPath $textFile -Value 'not script' -Encoding utf8NoBOM

        { Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $textFile } | Should Throw 'ScriptPath must refer to a .ps1 file:'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'rejects whitespace script path before opening a session' {
        { Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath '   ' } | Should Throw 'ScriptPath must not be empty.'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'rejects whitespace output root before opening a session when capture output is requested' {
        { Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot '   ' } | Should Throw 'OutputRoot must not be empty.'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'removes the created session after script execution' {
        Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'returns a failed result when session creation fails before returning one' {
        $script:NewPSSessionError = 'connection failed'

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript

        $result.ComputerName | Should Be 'PC-001'
        $result.Operation | Should Be 'RunScript'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'connection failed'
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'does not expose script argument parameters' {
        $command = Get-Command -Name Invoke-WinPushScript

        ($command.Parameters.Keys -contains 'ArgumentList') | Should Be $false
        ($command.Parameters.Keys -contains 'ScriptArgument') | Should Be $false
        ($command.Parameters.Keys -contains 'Parameters') | Should Be $false
    }
}

Describe 'Invoke-WinPushPsrpScript' {
    It 'uses Invoke-Command FilePath syntax through the supplied session' {
        $source = Get-Content -Raw -LiteralPath $script:PsrpScriptPath

        $source | Should Match ([regex]::Escape('Invoke-Command `'))
        $source | Should Match ([regex]::Escape('-Session $Session'))
        $source | Should Match ([regex]::Escape('-FilePath $FilePath'))
    }
}
