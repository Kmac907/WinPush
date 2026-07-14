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

function New-TestCredential {
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

Describe 'Invoke-WinPushScript' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:InvokedSessionComputerNames = @()
        $script:InvokedScriptPaths = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 302; ComputerName = 'PC-001' }
        $script:InvokeScriptOutput = @('script output')
        $script:InvokeScriptErrors = @()
        $script:NewPSSessionError = $null
        $script:InvokeScriptError = $null
        $script:SessionIdByComputerName = @{}
        $script:NewPSSessionErrorsByComputerName = @{}
        $script:InvokeScriptOutputsByComputerName = @{}
        $script:InvokeScriptErrorsByComputerName = @{}
        $script:InvokeScriptThrowsByComputerName = @{}
        $script:NewPSSessionCredentialSupplied = @()
        $script:NewPSSessionCredentials = @()
        $script:FixtureScript = Join-Path -Path $TestDrive -ChildPath 'Invoke-WinPushScript-Fixture.ps1'
        Set-Content -LiteralPath $script:FixtureScript -Value 'Write-Output "script output"' -Encoding utf8NoBOM
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

        if ($script:NewPSSessionErrorsByComputerName.ContainsKey($ComputerName)) {
            throw $script:NewPSSessionErrorsByComputerName[$ComputerName]
        }

        if ($script:SessionIdByComputerName.ContainsKey($ComputerName)) {
            return [pscustomobject] @{ Id = $script:SessionIdByComputerName[$ComputerName]; ComputerName = $ComputerName }
        }

        return $script:SessionToReturn
    }

    Mock Invoke-WinPushPsrpScript {
        param(
            $Session,
            [string] $FilePath
        )

        $null = $Session
        if ($null -ne $Session -and -not [string]::IsNullOrWhiteSpace($Session.ComputerName)) {
            $script:InvokedSessionComputerNames += $Session.ComputerName
        }

        $script:InvokedScriptPaths += $FilePath

        if ($null -ne $script:InvokeScriptError) {
            throw $script:InvokeScriptError
        }

        if ($script:InvokeScriptThrowsByComputerName.ContainsKey($Session.ComputerName)) {
            throw $script:InvokeScriptThrowsByComputerName[$Session.ComputerName]
        }

        $output = $script:InvokeScriptOutput
        if ($script:InvokeScriptOutputsByComputerName.ContainsKey($Session.ComputerName)) {
            $output = $script:InvokeScriptOutputsByComputerName[$Session.ComputerName]
        }

        $errors = $script:InvokeScriptErrors
        if ($script:InvokeScriptErrorsByComputerName.ContainsKey($Session.ComputerName)) {
            $errors = $script:InvokeScriptErrorsByComputerName[$Session.ComputerName]
        }

        return [pscustomobject] [ordered] @{
            PSTypeName = 'WinPush.PsrpScriptResult'
            Output     = @($output)
            Errors     = @($errors)
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

    It 'has an optional credential parameter' {
        $command = Get-Command -Name Invoke-WinPushScript

        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
    }

    It 'does not send a credential argument to New-PSSession when omitted' {
        Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript | Out-Null

        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $false
        @($script:NewPSSessionCredentials).Count | Should Be 0
    }

    It 'passes the supplied credential object unchanged for direct ComputerName targets' {
        $credential = New-TestCredential -Secret 'Distinctive-5.3-Credential-Secret!'

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -Credential $credential

        $result.Succeeded | Should Be $true
        @($script:NewPSSessionCredentials).Count | Should Be 1
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
    }

    It 'passes the supplied credential object unchanged for pipeline targets' {
        $credential = New-TestCredential -Secret 'Distinctive-5.3-Credential-Secret!'
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
        }

        $results = @(@('PC-001', 'PC-002') | Invoke-WinPushScript -ScriptPath $script:FixtureScript -Credential $credential)

        @($results).Count | Should Be 2
        @($script:NewPSSessionCredentials).Count | Should Be 2
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[1], $credential) | Should Be $true
    }

    It 'passes the supplied credential object unchanged for host file targets' {
        $credential = New-TestCredential -Secret 'Distinctive-5.3-Credential-Secret!'
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
        }
        $hostFile = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        @('PC-001', 'PC-002') | Set-Content -LiteralPath $hostFile -Encoding utf8NoBOM

        $results = @(Invoke-WinPushScript -HostFile $hostFile -ScriptPath $script:FixtureScript -Credential $credential)

        @($results).Count | Should Be 2
        @($script:NewPSSessionCredentials).Count | Should Be 2
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[1], $credential) | Should Be $true
    }

    It 'normalizes credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-5.3-Credential-Secret!'
        $credential = New-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -Credential $credential 5>&1 4>&1 3>&1
        $diagnosticText = @(
            $result.ErrorMessage
            @($result.Errors)
            @($result.Output)
            @($result.Logs)
        ) -join "`n"

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'PSRP script session creation failed for the target with the supplied credential.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
    }

    It 'preserves post-session script failures when a credential is supplied' {
        $credential = New-TestCredential -Secret 'Distinctive-5.3-Credential-Secret!'
        $script:InvokeScriptError = 'script invocation failed'

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -Credential $credential

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'script invocation failed'
    }

    It 'runs direct ComputerName arrays in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
            'PC-003' = 303
        }

        $results = @(Invoke-WinPushScript -ComputerName @(' PC-001 ', 'pc-001', 'PC-002', 'PC-003') -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,302,303'
    }

    It 'runs pipeline ComputerName strings in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
            'PC-003' = 303
        }

        $results = @(@(' PC-001 ', 'pc-001', 'PC-002', 'PC-003') | Invoke-WinPushScript -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,302,303'
    }

    It 'runs pipeline objects with ComputerName property in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
            'PC-003' = 303
        }
        $pipelineTargets = @(
            [pscustomobject] @{ ComputerName = ' PC-001 ' }
            [pscustomobject] @{ ComputerName = 'pc-001' }
            [pscustomobject] @{ ComputerName = 'PC-002' }
            [pscustomobject] @{ ComputerName = 'PC-003' }
        )

        $results = @($pipelineTargets | Invoke-WinPushScript -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,302,303'
    }

    It 'runs HostFile targets in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
            'PC-003' = 303
        }
        $hostFile = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        @(
            ' PC-001 '
            'pc-001'
            '# ignored comment'
            ''
            'PC-002'
            'PC-003'
        ) | Set-Content -LiteralPath $hostFile -Encoding utf8NoBOM

        $results = @(Invoke-WinPushScript -HostFile $hostFile -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,302,303'
    }

    It 'continues to later direct ComputerName targets after one target fails' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-003' = 303
        }
        $script:NewPSSessionErrorsByComputerName = @{
            'PC-002' = 'connection failed'
        }

        $results = @(Invoke-WinPushScript -ComputerName @('PC-001', 'PC-002', 'PC-003') -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[1].ErrorMessage | Should Be 'connection failed'
        $results[2].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,303'
    }

    It 'continues to later pipeline ComputerName targets after one target fails' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-003' = 303
        }
        $script:NewPSSessionErrorsByComputerName = @{
            'PC-002' = 'connection failed'
        }

        $results = @(@('PC-001', 'PC-002', 'PC-003') | Invoke-WinPushScript -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[1].ErrorMessage | Should Be 'connection failed'
        $results[2].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,303'
    }

    It 'continues to later HostFile targets after one target fails' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-003' = 303
        }
        $script:NewPSSessionErrorsByComputerName = @{
            'PC-002' = 'connection failed'
        }
        $hostFile = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        @('PC-001', 'PC-002', 'PC-003') | Set-Content -LiteralPath $hostFile -Encoding utf8NoBOM

        $results = @(Invoke-WinPushScript -HostFile $hostFile -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[1].ErrorMessage | Should Be 'connection failed'
        $results[2].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '301,303'
    }

    It 'does not emit raw script output as separate pipeline objects' {
        $results = @(Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 1
        $results[0].PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $results[0].Output[0] | Should Be 'script output'
    }

    It 'preserves object output inside the script result' {
        $script:InvokeScriptOutput = @(
            [pscustomobject] @{
                Name  = 'Widget'
                Count = 2
            }
        )

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript

        @($result.Output).Count | Should Be 1
        $result.Output[0].Name | Should Be 'Widget'
        $result.Output[0].Count | Should Be 2
        @($result.Errors).Count | Should Be 0
    }

    It 'retains script output when script errors are present' {
        $script:InvokeScriptOutput = @('before error', 'after error')
        $script:InvokeScriptErrors = @('script failed')

        $results = @(Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript)

        @($results).Count | Should Be 1
        $result = $results[0]
        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'script failed'
        @($result.Output).Count | Should Be 2
        $result.Output[0] | Should Be 'before error'
        $result.Output[1] | Should Be 'after error'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'script failed'
    }

    It 'returns a failed result for a terminating script error without discarding prior output' {
        $script:InvokeScriptOutput = @('before throw')
        $script:InvokeScriptErrors = @('terminating script failed')

        $result = Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'terminating script failed'
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'before throw'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'terminating script failed'
    }

    It 'does not emit raw script errors as separate pipeline records' {
        $script:InvokeScriptOutput = @('kept output')
        $script:InvokeScriptErrors = @('kept error')

        $results = @(Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript 2>&1)

        @($results).Count | Should Be 1
        $results[0].PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $results[0].Output[0] | Should Be 'kept output'
        $results[0].Errors[0] | Should Be 'kept error'
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

    It 'captures direct ComputerName array output under one shared run folder' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
        }
        $script:InvokeScriptOutputsByComputerName = @{
            'PC-001' = @('first target')
            'PC-002' = @('second target')
        }
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(Invoke-WinPushScript -ComputerName @('PC-001', 'PC-002') -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot $outputRoot)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        $results[0].ResultPath | Should Be (Join-Path -Path $results[0].ComputerDirectory -ChildPath 'result.txt')
        $results[1].ResultPath | Should Be (Join-Path -Path $results[1].ComputerDirectory -ChildPath 'result.txt')
        (Get-Content -LiteralPath $results[0].StdOutPath) -join ',' | Should Be 'first target'
        (Get-Content -LiteralPath $results[1].StdOutPath) -join ',' | Should Be 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
        Test-Path -LiteralPath $results[0].ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $results[1].ResultPath -PathType Leaf | Should Be $true
        $summaryRows = @(Import-Csv -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'summary.csv'))
        @($summaryRows).Count | Should Be 2
        ($summaryRows.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($summaryRows.Operation -join ',') | Should Be 'RunScript,RunScript'
        ($summaryRows.ResultPath -join ',') | Should Be (($results[0].ResultPath, $results[1].ResultPath) -join ',')
    }

    It 'captures pipeline ComputerName output under one shared run folder' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
        }
        $script:InvokeScriptOutputsByComputerName = @{
            'PC-001' = @('first target')
            'PC-002' = @('second target')
        }
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(@('PC-001', 'PC-002') | Invoke-WinPushScript -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot $outputRoot)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        (Get-Content -LiteralPath $results[0].StdOutPath) -join ',' | Should Be 'first target'
        (Get-Content -LiteralPath $results[1].StdOutPath) -join ',' | Should Be 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
    }

    It 'captures HostFile output under one shared run folder' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 301
            'PC-002' = 302
        }
        $script:InvokeScriptOutputsByComputerName = @{
            'PC-001' = @('first target')
            'PC-002' = @('second target')
        }
        $hostFile = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        @('PC-001', 'PC-002') | Set-Content -LiteralPath $hostFile -Encoding utf8NoBOM
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(Invoke-WinPushScript -HostFile $hostFile -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot $outputRoot)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        (Get-Content -LiteralPath $results[0].StdOutPath) -join ',' | Should Be 'first target'
        (Get-Content -LiteralPath $results[1].StdOutPath) -join ',' | Should Be 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
        $summaryRows = @(Import-Csv -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'summary.csv'))
        @($summaryRows).Count | Should Be 2
        ($summaryRows.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($summaryRows.Operation -join ',') | Should Be 'RunScript,RunScript'
        ($summaryRows.ResultPath -join ',') | Should Be (($results[0].ResultPath, $results[1].ResultPath) -join ',')
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

    It 'captures retained script output to stdout and script errors to stderr when both are present' {
        $script:InvokeScriptOutput = @('first output', 'second output')
        $script:InvokeScriptErrors = @('first error', 'second error')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(Invoke-WinPushScript -ComputerName 'PC-001' -ScriptPath $script:FixtureScript -CaptureOutput -OutputRoot $outputRoot 2>&1)

        @($results).Count | Should Be 1
        $result = $results[0]
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'first error'
        $result.Output[0] | Should Be 'first output'
        $result.Output[1] | Should Be 'second output'
        $result.Errors[0] | Should Be 'first error'
        $result.Errors[1] | Should Be 'second error'
        (Get-Content -LiteralPath $result.StdOutPath) -join ',' | Should Be 'first output,second output'
        (Get-Content -LiteralPath $result.StdErrPath) -join ',' | Should Be 'first error,second error'
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

    It 'rejects a missing host file before opening a session' {
        $missingHostFile = Join-Path -Path $TestDrive -ChildPath 'missing-hosts.txt'

        { Invoke-WinPushScript -HostFile $missingHostFile -ScriptPath $script:FixtureScript } | Should Throw 'Host file was not found:'

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

    It 'exposes HostFile and credential support' {
        $command = Get-Command -Name Invoke-WinPushScript

        ($command.Parameters.Keys -contains 'HostFile') | Should Be $true
        $command.Parameters['HostFile'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
    }
}

Describe 'Invoke-WinPushPsrpScript' {
    It 'uses Invoke-Command FilePath syntax through the supplied session' {
        $source = Get-Content -Raw -LiteralPath $script:PsrpScriptPath

        $source | Should Match ([regex]::Escape('Invoke-Command `'))
        $source | Should Match ([regex]::Escape('-Session $Session'))
        $source | Should Match ([regex]::Escape('-FilePath $FilePath'))
        $source | Should Match ([regex]::Escape('-OutVariable output'))
    }

}
