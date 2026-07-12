$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:ArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Write-WinPushCommandOutputArtifact.ps1'
$script:PsrpCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Invoke-WinPushPsrpCommand.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Invoke-WinPushCommand.ps1'
$script:FixtureRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\Fixtures\TargetResolution')

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:ArtifactPath
. $script:PsrpCommandPath
. $script:CommandPath

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

Describe 'Invoke-WinPushCommand' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:InvokedSessionComputerNames = @()
        $script:InvokedScriptBlocks = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 202; ComputerName = 'PC-001' }
        $script:InvokeCommandOutput = @('remote output')
        $script:InvokeCommandErrors = @()
        $script:NewPSSessionError = $null
        $script:InvokeCommandError = $null
        $script:SessionIdByComputerName = @{}
        $script:NewPSSessionErrorsByComputerName = @{}
        $script:InvokeCommandOutputsByComputerName = @{}
        $script:InvokeCommandErrorsByComputerName = @{}
        $script:InvokeCommandThrowsByComputerName = @{}
        $script:NewPSSessionCredentialSupplied = @()
        $script:NewPSSessionCredentials = @()
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

    Mock Invoke-WinPushPsrpCommand {
        param(
            $Session,
            [scriptblock] $ScriptBlock
        )

        if ($null -ne $Session -and -not [string]::IsNullOrWhiteSpace($Session.ComputerName)) {
            $script:InvokedSessionComputerNames += $Session.ComputerName
        }

        $script:InvokedScriptBlocks += $ScriptBlock.ToString()

        if ($null -ne $script:InvokeCommandError) {
            throw $script:InvokeCommandError
        }

        if ($script:InvokeCommandThrowsByComputerName.ContainsKey($Session.ComputerName)) {
            throw $script:InvokeCommandThrowsByComputerName[$Session.ComputerName]
        }

        $output = $script:InvokeCommandOutput
        if ($script:InvokeCommandOutputsByComputerName.ContainsKey($Session.ComputerName)) {
            $output = $script:InvokeCommandOutputsByComputerName[$Session.ComputerName]
        }

        $errors = $script:InvokeCommandErrors
        if ($script:InvokeCommandErrorsByComputerName.ContainsKey($Session.ComputerName)) {
            $errors = $script:InvokeCommandErrorsByComputerName[$Session.ComputerName]
        }

        return [pscustomobject] [ordered] @{
            PSTypeName = 'WinPush.PsrpCommandResult'
            Output     = @($output)
            Errors     = @($errors)
        }
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

    It 'has an optional credential parameter' {
        $command = Get-Command -Name Invoke-WinPushCommand

        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
    }

    It 'does not send a credential argument to New-PSSession when omitted' {
        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' | Out-Null

        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $false
        @($script:NewPSSessionCredentials).Count | Should Be 0
    }

    It 'passes the supplied credential object unchanged for direct ComputerName targets' {
        $credential = New-TestCredential -Secret 'Distinctive-4.3-Credential-Secret!'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Credential $credential

        $result.Succeeded | Should Be $true
        @($script:NewPSSessionCredentials).Count | Should Be 1
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
    }

    It 'passes the supplied credential object unchanged for pipeline targets' {
        $credential = New-TestCredential -Secret 'Distinctive-4.3-Credential-Secret!'
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }

        $results = @(@('PC-001', 'PC-002') | Invoke-WinPushCommand -Command 'hostname' -Credential $credential)

        @($results).Count | Should Be 2
        @($script:NewPSSessionCredentials).Count | Should Be 2
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[1], $credential) | Should Be $true
    }

    It 'passes the supplied credential object unchanged for host file targets' {
        $credential = New-TestCredential -Secret 'Distinctive-4.3-Credential-Secret!'
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' -Credential $credential)

        @($results).Count | Should Be 2
        @($script:NewPSSessionCredentials).Count | Should Be 2
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[1], $credential) | Should Be $true
    }

    It 'normalizes credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-4.3-Credential-Secret!'
        $credential = New-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Credential $credential 5>&1 4>&1 3>&1
        $diagnosticText = @(
            $result.ErrorMessage
            @($result.Errors)
            @($result.Output)
            @($result.Logs)
        ) -join "`n"

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'PSRP command session creation failed for the target with the supplied credential.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
    }

    It 'preserves post-session command failures when a credential is supplied' {
        $credential = New-TestCredential -Secret 'Distinctive-4.3-Credential-Secret!'
        $script:InvokeCommandError = 'command invocation failed'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Credential $credential

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'command invocation failed'
    }

    It 'runs direct ComputerName arrays in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
            'PC-003' = 203
        }

        $results = @(Invoke-WinPushCommand -ComputerName @(' PC-001 ', 'pc-001', 'PC-002', 'PC-003') -Command 'hostname')

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,202,203'
    }

    It 'runs pipeline ComputerName strings in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
            'PC-003' = 203
        }

        $results = @(@(' PC-001 ', 'pc-001', 'PC-002', 'PC-003') | Invoke-WinPushCommand -Command 'hostname')

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,202,203'
    }

    It 'runs pipeline objects with ComputerName property in resolved order without duplicate targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
            'PC-003' = 203
        }
        $pipelineTargets = @(
            [pscustomobject] @{ ComputerName = ' PC-001 ' }
            [pscustomobject] @{ ComputerName = 'pc-001' }
            [pscustomobject] @{ ComputerName = 'PC-002' }
            [pscustomobject] @{ ComputerName = 'PC-003' }
        )

        $results = @($pipelineTargets | Invoke-WinPushCommand -Command 'hostname')

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,202,203'
    }

    It 'continues to later direct ComputerName targets after one target fails' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-003' = 203
        }
        $script:NewPSSessionErrorsByComputerName = @{
            'PC-002' = 'connection failed'
        }

        $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002', 'PC-003') -Command 'hostname')

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[1].ErrorMessage | Should Be 'connection failed'
        $results[2].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,203'
    }

    It 'continues to later pipeline ComputerName targets after one target fails' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-003' = 203
        }
        $script:NewPSSessionErrorsByComputerName = @{
            'PC-002' = 'connection failed'
        }

        $results = @(@('PC-001', 'PC-002', 'PC-003') | Invoke-WinPushCommand -Command 'hostname')

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[1].ErrorMessage | Should Be 'connection failed'
        $results[2].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,203'
    }

    It 'runs host file targets in resolved order without duplicate targets or comments' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname')

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002'
        ($script:RemovedSessionIds -join ',') | Should Be '201,202'
    }

    It 'continues to later host file targets after one target fails' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'valid-hosts.txt'
        $utf8Target = 'pc-utf8-{0}01' -f [char] 0x00e9
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-003' = 203
        }
        $script:NewPSSessionErrorsByComputerName = @{
            $utf8Target = "connection failed for $utf8Target"
        }

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname')

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be "PC-001,$utf8Target,PC-003"
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[1].ErrorMessage | Should Be "connection failed for $utf8Target"
        $results[2].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be "PC-001,$utf8Target,PC-003"
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,203'
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

    It 'captures direct ComputerName array output under one shared run folder' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }
        $script:InvokeCommandOutputsByComputerName = @{
            'PC-001' = @('first target')
            'PC-002' = @('second target')
        }
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002') -Command 'hostname' -CaptureOutput -OutputRoot $outputRoot)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        (Get-Content -LiteralPath $results[0].StdOutPath) -join ',' | Should Be 'first target'
        (Get-Content -LiteralPath $results[1].StdOutPath) -join ',' | Should Be 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
    }

    It 'captures pipeline ComputerName output under one shared run folder' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }
        $script:InvokeCommandOutputsByComputerName = @{
            'PC-001' = @('first target')
            'PC-002' = @('second target')
        }
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(@('PC-001', 'PC-002') | Invoke-WinPushCommand -Command 'hostname' -CaptureOutput -OutputRoot $outputRoot)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        (Get-Content -LiteralPath $results[0].StdOutPath) -join ',' | Should Be 'first target'
        (Get-Content -LiteralPath $results[1].StdOutPath) -join ',' | Should Be 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
    }

    It 'captures host file target output under one shared run folder' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }
        $script:InvokeCommandOutputsByComputerName = @{
            'PC-001' = @('first target')
            'PC-002' = @('second target')
        }
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' -CaptureOutput -OutputRoot $outputRoot)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        (Get-Content -LiteralPath $results[0].StdOutPath) -join ',' | Should Be 'first target'
        (Get-Content -LiteralPath $results[1].StdOutPath) -join ',' | Should Be 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
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
        $script:InvokeCommandOutput = @()
        $script:InvokeCommandErrors = @('command failed')
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

    It 'returns command output and command errors together when both are emitted' {
        $script:InvokeCommandOutput = @('before error')
        $script:InvokeCommandErrors = @('command failed')

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Output "before error"; Write-Error "command failed"'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'command failed'
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'before error'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'command failed'
    }

    It 'captures command output to stdout and command errors to stderr when both are emitted' {
        $script:InvokeCommandOutput = @('before error')
        $script:InvokeCommandErrors = @('command failed')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Output "before error"; Write-Error "command failed"' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        (Get-Content -LiteralPath $result.StdOutPath) -join ',' | Should Be 'before error'
        (Get-Content -LiteralPath $result.StdErrPath) -join ',' | Should Be 'command failed'
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

    It 'rejects invalid host files before opening a session' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'missing-hosts.txt'

        { Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' } | Should Throw 'Host file was not found:'

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
