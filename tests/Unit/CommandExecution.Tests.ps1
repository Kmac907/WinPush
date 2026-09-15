$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1'
$script:ResultArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\Add-WinPushExecutionArtifact.ps1'
$script:LogResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushLogResult.ps1'
$script:ArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Write-WinPushCommandOutputArtifact.ps1'
$script:CaptureContextPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\New-WinPushCaptureContext.ps1'
$script:NativeProcessPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushNativeProcess.ps1'
$script:WinRsCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushWinRsCommand.ps1'
$script:PsExecCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushPsExecCommand.ps1'
$script:PsrpCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushPsrpCommand.ps1'
$script:CommandLogDirectoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\Get-WinPushCommandLogDirectory.ps1'
$script:LogArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1'
$script:PsrpLogCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\Copy-WinPushPsrpLogDirectory.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Invoke-WinPushCommand.ps1'
$script:FixtureRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\Fixtures\TargetResolution')

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:ResultArtifactPath
. $script:LogResultFactoryPath
. $script:CaptureContextPath
. $script:ArtifactPath
. $script:NativeProcessPath
. $script:WinRsCommandPath
. $script:PsExecCommandPath
. $script:PsrpCommandPath
. $script:CommandLogDirectoryPath
. $script:LogArtifactPath
. $script:PsrpLogCopyPath
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
        $script:InvokedShells = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 202; ComputerName = 'PC-001' }
        $script:InvokeCommandOutput = @('remote output')
        $script:InvokeCommandErrors = @()
        $script:NewPSSessionError = $null
        $script:InvokeCommandError = $null
        $script:InvokeCommandExitCode = $null
        $script:SessionIdByComputerName = @{}
        $script:NewPSSessionErrorsByComputerName = @{}
        $script:InvokeCommandOutputsByComputerName = @{}
        $script:InvokeCommandErrorsByComputerName = @{}
        $script:InvokeCommandThrowsByComputerName = @{}
        $script:NewPSSessionCredentialSupplied = @()
        $script:NewPSSessionCredentials = @()
        $script:OperationOrder = @()
        $script:CopiedLogSessions = @()
        $script:CopiedLogComputerNames = @()
        $script:CopiedLogRemoteDirectories = @()
        $script:CopiedLogRunDirectories = @()
        $script:CopiedLogComputerDirectories = @()
        $script:LogCopyError = $null
        $script:LogCopyReturnedLogs = $null
        $script:LogCopyReturnedCopiedLogPaths = $null
        $script:NativeProcessFilePaths = @()
        $script:NativeProcessArgumentLists = @()
        $script:NativeProcessTimeouts = @()
        $script:NativeProcessError = $null
        $script:NativeProcessExitCode = 0
        $script:NativeProcessStandardOutput = "winrs output`r`n"
        $script:NativeProcessStandardError = ''
        $script:NativeProcessErrorsByComputerName = @{}
        $script:NativeProcessExitCodesByComputerName = @{}
        $script:NativeProcessStandardOutputsByComputerName = @{}
        $script:NativeProcessStandardErrorsByComputerName = @{}
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
            [string] $Command,
            [string] $Shell
        )

        if ($null -ne $Session -and -not [string]::IsNullOrWhiteSpace($Session.ComputerName)) {
            $script:InvokedSessionComputerNames += $Session.ComputerName
        }

        $script:InvokedScriptBlocks += $Command
        $script:InvokedShells += $Shell
        $script:OperationOrder += ('Command:{0}' -f $Session.ComputerName)

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
            ExitCode   = if ($null -ne $script:InvokeCommandExitCode) { $script:InvokeCommandExitCode } elseif (@($errors).Count -eq 0) { 0 } else { 1 }
            Output     = @($output)
            Errors     = @($errors)
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
        $script:OperationOrder += ('Logs:{0}' -f $Session.ComputerName)

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
        $localPath = Join-Path -Path (Join-Path -Path $effectiveComputerDirectory -ChildPath 'Logs') -ChildPath 'command.log'
        $remotePath = Join-Path -Path $RemoteDirectory -ChildPath 'command.log'
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
                    RemoteDirectory  = $RemoteDirectory
                    RemotePath       = $remotePath
                    Name             = 'command.log'
                    Length           = 12
                    LastWriteTimeUtc = [datetime]::UtcNow
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

    Mock Invoke-WinPushNativeProcess {
        param(
            [string] $FilePath,
            [string[]] $ArgumentList,
            [int] $TimeoutSeconds
        )

        $script:NativeProcessFilePaths += $FilePath
        $script:NativeProcessArgumentLists += , @($ArgumentList)
        $script:NativeProcessTimeouts += $TimeoutSeconds
        $computerName = if ($ArgumentList.Count -gt 0 -and $ArgumentList[0] -like '-r:*') {
            $ArgumentList[0].Substring(3)
        }
        elseif ($ArgumentList.Count -gt 0 -and $ArgumentList[0] -like '\\*') {
            $ArgumentList[0].Substring(2)
        }
        else {
            ''
        }

        if ($null -ne $script:NativeProcessError) {
            throw $script:NativeProcessError
        }

        if ($script:NativeProcessErrorsByComputerName.ContainsKey($computerName)) {
            throw $script:NativeProcessErrorsByComputerName[$computerName]
        }

        $exitCode = $script:NativeProcessExitCode
        if ($script:NativeProcessExitCodesByComputerName.ContainsKey($computerName)) {
            $exitCode = $script:NativeProcessExitCodesByComputerName[$computerName]
        }

        $standardOutput = $script:NativeProcessStandardOutput
        if ($script:NativeProcessStandardOutputsByComputerName.ContainsKey($computerName)) {
            $standardOutput = $script:NativeProcessStandardOutputsByComputerName[$computerName]
        }

        $standardError = $script:NativeProcessStandardError
        if ($script:NativeProcessStandardErrorsByComputerName.ContainsKey($computerName)) {
            $standardError = $script:NativeProcessStandardErrorsByComputerName[$computerName]
        }

        [pscustomobject] [ordered] @{
            PSTypeName      = 'WinPush.NativeProcessResult'
            FilePath        = $FilePath
            ArgumentList    = @($ArgumentList)
            ExitCode        = $exitCode
            StandardOutput  = $standardOutput
            StandardError   = $standardError
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
        @($script:CopiedLogSessions).Count | Should Be 0
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

    It 'passes explicit cmd.exe command text through unchanged as PowerShell source' {
        $commandText = 'cmd.exe /d /s /c "echo winpush"'

        Invoke-WinPushCommand -ComputerName 'PC-001' -Command $commandText | Out-Null

        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:InvokedScriptBlocks).Count | Should Be 1
        $script:InvokedScriptBlocks[0] | Should Be $commandText
    }

    It 'keeps explicit cmd.exe errors in the standard command result' {
        $commandText = 'cmd.exe /d /s /c "echo cmd failed 1>&2"'
        $script:InvokeCommandOutput = @()
        $script:InvokeCommandErrors = @('cmd failed')

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command $commandText

        @($script:InvokedScriptBlocks).Count | Should Be 1
        $script:InvokedScriptBlocks[0] | Should Be $commandText
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'cmd failed'
        $result.Errors[0] | Should Be 'cmd failed'
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

    It 'has an optional transport parameter with PSRP as the default' {
        $command = Get-Command -Name Invoke-WinPushCommand

        ($command.Parameters.Keys -contains 'Transport') | Should Be $true
        $command.Parameters['Transport'].ParameterType.FullName | Should Be 'System.String'
        $validateSet = @($command.Parameters['Transport'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
        @($validateSet).Count | Should Be 1
        ($validateSet[0].ValidValues -join ',') | Should Be 'Psrp,WinRM,PsExec'
        ($command.Parameters.Keys -contains 'PsExecPath') | Should Be $true
        $command.Parameters['PsExecPath'].ParameterType.FullName | Should Be 'System.String'

        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' | Out-Null

        @($script:NewPSSessionComputerNames).Count | Should Be 1
        @($script:NativeProcessFilePaths).Count | Should Be 0
    }

    It 'exposes the shell choices and forwards the default native timeout' {
        $command = Get-Command -Name Invoke-WinPushCommand
        $shellSet = @($command.Parameters['Shell'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })

        ($shellSet[0].ValidValues -join ',') | Should Be 'Auto,PowerShell,Cmd'

        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM | Out-Null

        $script:NativeProcessTimeouts[0] | Should Be 1800
    }

    It 'rejects a negative timeout before starting execution' {
        $timeoutError = $null
        try { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -TimeoutSeconds -1 } catch { $timeoutError = $_ }

        $null -eq $timeoutError | Should Be $false
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:NativeProcessFilePaths).Count | Should Be 0
    }

    It 'encodes injection-shaped PowerShell text for <Transport> without evaluating it locally' -TestCases @(
        @{ Transport = 'WinRM' }
        @{ Transport = 'PsExec' }
    ) {
        param($Transport)

        $marker = Join-Path -Path $TestDrive -ChildPath 'should-not-exist.txt'
        $commandText = "Write-Output `$([System.IO.File]::WriteAllText('$marker', 'injected'))"
        $parameters = @{
            ComputerName   = 'PC-001'
            Command        = $commandText
            Transport      = $Transport
            Shell          = 'PowerShell'
            TimeoutSeconds = 17
        }
        if ($Transport -eq 'PsExec') {
            $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-shell.exe'
            Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
            $parameters['PsExecPath'] = $psExecPath
        }

        Invoke-WinPushCommand @parameters | Out-Null

        $nativeCommand = $script:NativeProcessArgumentLists[0][-1]
        $encodedCommand = $nativeCommand -replace '^.*\s-EncodedCommand\s+', ''
        [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($encodedCommand)) | Should Be $commandText
        Test-Path -LiteralPath $marker | Should Be $false
        $script:NativeProcessTimeouts[0] | Should Be 17
    }

    It 'selects cmd over PSRP and propagates its exit code and streams' {
        $script:InvokeCommandExitCode = 23
        $script:InvokeCommandOutput = @('cmd output')
        $script:InvokeCommandErrors = @('cmd error')

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'echo literal $([invalid])' -Shell Cmd

        $script:InvokedShells[0] | Should Be 'Cmd'
        $script:InvokedScriptBlocks[0] | Should Be 'echo literal $([invalid])'
        $result.ExitCode | Should Be 23
        $result.Output[0] | Should Be 'cmd output'
        $result.Errors[0] | Should Be 'cmd error'
        $result.Succeeded | Should Be $false
        (Get-Content -Raw -LiteralPath $script:PsrpCommandPath) | Should Match ([regex]::Escape('& cmd.exe /d /s /c $CommandText'))
    }

    It 'has optional command-attached log collection without arbitrary log directory passthrough' {
        $command = Get-Command -Name Invoke-WinPushCommand

        ($command.Parameters.Keys -contains 'Logs') | Should Be $true
        $command.Parameters['Logs'].ParameterType.FullName | Should Be 'System.Management.Automation.SwitchParameter'
        ($command.Parameters.Keys -contains 'LogDirectory') | Should Be $false
        ($command.Parameters.Keys -contains 'RemoteDirectory') | Should Be $false
    }

    It 'derives command-attached log directories from the first command name' {
        Get-WinPushCommandLogDirectory -Command 'hostname' | Should Be 'C:\ProgramData\EA\Logs\hostname'
        Get-WinPushCommandLogDirectory -Command 'cmd.exe /d /s /c "echo winpush"' | Should Be 'C:\ProgramData\EA\Logs\cmd'
        Get-WinPushCommandLogDirectory -Command '$value = 1' | Should Be 'C:\ProgramData\EA\Logs\Command'
    }

    It 'does not send a credential argument to New-PSSession when omitted' {
        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' | Out-Null

        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $false
        @($script:NewPSSessionCredentials).Count | Should Be 0
    }

    It 'passes the supplied credential object unchanged for <Source> targets' -TestCases @(
        @{ Source = 'direct ComputerName'; ExpectedCount = 1 }
        @{ Source = 'pipeline'; ExpectedCount = 2 }
        @{ Source = 'host file'; ExpectedCount = 2 }
    ) {
        param($Source, $ExpectedCount)

        $credential = New-TestCredential -Secret 'Distinctive-4.3-Credential-Secret!'
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }

        switch ($Source) {
            'direct ComputerName' { $results = @(Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Credential $credential) }
            'pipeline' { $results = @(@('PC-001', 'PC-002') | Invoke-WinPushCommand -Command 'hostname' -Credential $credential) }
            'host file' {
                $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'
                $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' -Credential $credential)
            }
        }

        @($results).Count | Should Be $ExpectedCount
        @($script:NewPSSessionCredentials).Count | Should Be $ExpectedCount
        foreach ($actualCredential in $script:NewPSSessionCredentials) {
            [object]::ReferenceEquals($actualCredential, $credential) | Should Be $true
        }
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

    It 'runs <Source> targets in resolved order without duplicate targets' -TestCases @(
        @{ Source = 'direct ComputerName' }
        @{ Source = 'pipeline ComputerName strings' }
        @{ Source = 'pipeline objects' }
    ) {
        param($Source)

        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
            'PC-003' = 203
        }

        switch ($Source) {
            'direct ComputerName' { $results = @(Invoke-WinPushCommand -ComputerName @(' PC-001 ', 'pc-001', 'PC-002', 'PC-003') -Command 'hostname') }
            'pipeline ComputerName strings' { $results = @(@(' PC-001 ', 'pc-001', 'PC-002', 'PC-003') | Invoke-WinPushCommand -Command 'hostname') }
            'pipeline objects' {
                $targets = @(
                    [pscustomobject] @{ ComputerName = ' PC-001 ' }
                    [pscustomobject] @{ ComputerName = 'pc-001' }
                    [pscustomobject] @{ ComputerName = 'PC-002' }
                    [pscustomobject] @{ ComputerName = 'PC-003' }
                )
                $results = @($targets | Invoke-WinPushCommand -Command 'hostname')
            }
        }

        @($results).Count | Should Be 3
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:InvokedSessionComputerNames -join ',') | Should Be 'PC-001,PC-002,PC-003'
        ($script:RemovedSessionIds -join ',') | Should Be '201,202,203'
    }

    It 'continues to later <Source> targets after one target fails' -TestCases @(
        @{ Source = 'direct ComputerName' }
        @{ Source = 'pipeline ComputerName' }
    ) {
        param($Source)

        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-003' = 203
        }
        $script:NewPSSessionErrorsByComputerName = @{
            'PC-002' = 'connection failed'
        }

        if ($Source -eq 'direct ComputerName') {
            $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002', 'PC-003') -Command 'hostname')
        }
        else {
            $results = @(@('PC-001', 'PC-002', 'PC-003') | Invoke-WinPushCommand -Command 'hostname')
        }

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

    It 'copies command-attached logs after a successful command using the same PSSession' {
        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Logs -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.Output[0] | Should Be 'remote output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].PSTypeNames[0] | Should Be 'WinPush.LogResult'
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\hostname\command.log'
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.RunDirectory | Should Be $script:CopiedLogRunDirectories[0]
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        @($script:CopiedLogSessions).Count | Should Be 1
        [object]::ReferenceEquals($script:CopiedLogSessions[0], $script:SessionToReturn) | Should Be $true
        $script:CopiedLogRemoteDirectories[0] | Should Be 'C:\ProgramData\EA\Logs\hostname'
        ($script:OperationOrder -join ',') | Should Be 'Command:PC-001,Logs:PC-001'
    }

    It 'copies command-attached logs after an error-emitting command without replacing command output or errors' {
        $script:InvokeCommandOutput = @('before error')
        $script:InvokeCommandErrors = @('command failed')

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Error "command failed"' -Logs -OutputRoot $TestDrive

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'command failed'
        $result.Output[0] | Should Be 'before error'
        $result.Errors[0] | Should Be 'command failed'
        @($result.Logs).Count | Should Be 1
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $script:CopiedLogRemoteDirectories[0] | Should Be 'C:\ProgramData\EA\Logs\Write-Error'
        ($script:OperationOrder -join ',') | Should Be 'Command:PC-001,Logs:PC-001'
    }

    It 'records command-attached log source failures without changing primary command success' {
        $script:LogCopyError = 'RemoteDirectory was not found or is not a directory: C:\ProgramData\EA\Logs\hostname'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Logs -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        @($result.Output).Count | Should Be 1
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].Copied | Should Be $false
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\hostname'
        $result.Logs[0].Error | Should Be 'RemoteDirectory was not found or is not a directory: C:\ProgramData\EA\Logs\hostname'
        @($result.CopiedLogPaths).Count | Should Be 0
    }

    It 'keeps failed command result when command and attached log collection both fail' {
        $script:InvokeCommandOutput = @('before error')
        $script:InvokeCommandErrors = @('command failed')
        $script:LogCopyError = 'RemoteDirectory was not found or is not a directory: C:\ProgramData\EA\Logs\Write-Error'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Error "command failed"' -Logs -OutputRoot $TestDrive

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'command failed'
        $result.Output[0] | Should Be 'before error'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'command failed'
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].Copied | Should Be $false
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\Write-Error'
        $result.Logs[0].Error | Should Be 'RemoteDirectory was not found or is not a directory: C:\ProgramData\EA\Logs\Write-Error'
        @($result.CopiedLogPaths).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
        ($script:OperationOrder -join ',') | Should Be 'Command:PC-001,Logs:PC-001'
    }

    It 'keeps command success when one attached log file copy fails' {
        $script:LogCopyReturnedLogs = @(
            New-WinPushLogResult `
                -ComputerName 'PC-001' `
                -RemotePath 'C:\ProgramData\EA\Logs\hostname\command.log' `
                -Copied $false `
                -ErrorMessage 'Copy failed for command.log'
        )

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Logs -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        $result.Output[0] | Should Be 'remote output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].Copied | Should Be $false
        $result.Logs[0].Error | Should Be 'Copy failed for command.log'
        @($result.CopiedLogPaths).Count | Should Be 0
        ($script:OperationOrder -join ',') | Should Be 'Command:PC-001,Logs:PC-001'
    }

    It 'shares one log run folder across direct ComputerName command targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }

        $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002') -Command 'hostname' -Logs -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        ($script:CopiedLogComputerNames -join ',') | Should Be 'PC-001,PC-002'
        ($script:CopiedLogRemoteDirectories -join ',') | Should Be 'C:\ProgramData\EA\Logs\hostname,C:\ProgramData\EA\Logs\hostname'
    }

    It 'copies command-attached logs for pipeline targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }

        $results = @(@('PC-001', 'PC-002') | Invoke-WinPushCommand -Command 'hostname' -Logs -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($script:CopiedLogComputerNames -join ',') | Should Be 'PC-001,PC-002'
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
    }

    It 'copies command-attached logs for host file targets' {
        $script:SessionIdByComputerName = @{
            'PC-001' = 201
            'PC-002' = 202
        }
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' -Logs -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($script:CopiedLogComputerNames -join ',') | Should Be 'PC-001,PC-002'
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
    }

    It 'captures command output to one target artifact folder when requested' {
        $script:InvokeCommandOutput = @('first line', 'second line')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Output "remote output"' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        $result.RunDirectory.StartsWith($outputRoot) | Should Be $true
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        Test-Path -LiteralPath $result.ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') -PathType Leaf | Should Be $false
        $resultText = Get-Content -LiteralPath $result.ResultPath -Raw
        $resultText | Should Match 'Timestamp    : '
        $resultText | Should Match 'ComputerName : PC-001'
        $resultText | Should Match 'Operation    : RunCommand'
        $resultText | Should Match 'Transport    : Psrp'
        $resultText | Should Match 'Identity     : Write-Output "remote output"'
        $resultText | Should Match 'Succeeded    : True'
        $resultText | Should Match 'ExitCode     : 0'
        $resultText | Should Match 'ErrorMessage : '
        $resultText | Should Match 'Output:'
        $resultText | Should Match 'first line'
        $resultText | Should Match 'second line'
        $resultText | Should Match 'Errors:'
        $resultText | Should Not Match 'StdOutPath'
        $resultText | Should Not Match 'StdErrPath'
        $runLogPath = Join-Path -Path $result.RunDirectory -ChildPath 'run.log'
        Test-Path -LiteralPath $runLogPath -PathType Leaf | Should Be $true
        $runLogText = Get-Content -LiteralPath $runLogPath -Raw
        $runLogText | Should Match 'WinPush Correlated Run Log'
        $runLogText | Should Match 'Target Result'
        $runLogText | Should Match 'ComputerName : PC-001'
        $runLogText | Should Match ([regex]::Escape("TargetRunLog : $($result.ResultPath)"))
        $runLogText | Should Match 'first line'
        $runLogText | Should Match 'second line'
        $summaryPath = Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'
        Test-Path -LiteralPath $summaryPath -PathType Leaf | Should Be $true
        $summaryRows = @(Import-Csv -LiteralPath $summaryPath)
        @($summaryRows).Count | Should Be 1
        $summaryRows[0].ComputerName | Should Be 'PC-001'
        $summaryRows[0].Operation | Should Be 'RunCommand'
        $summaryRows[0].Transport | Should Be 'Psrp'
        $summaryRows[0].Succeeded | Should Be 'True'
        $summaryRows[0].ExitCode | Should Be '0'
        $summaryRows[0].ResultPath | Should Be $result.ResultPath
        $summaryRows[0].StdOutPath | Should Be ''
        $summaryRows[0].StdErrPath | Should Be ''
        @($result.Output).Count | Should Be 2
        $result.Output[0] | Should Be 'first line'
    }

    It 'writes command-attached logs under the captured command artifact folder' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -CaptureOutput -Logs -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        Test-Path -LiteralPath $result.ResultPath -PathType Leaf | Should Be $true
        $script:CopiedLogComputerDirectories[0] | Should Be $result.ComputerDirectory
        $result.Logs[0].LocalPath | Should Be (Join-Path -Path (Join-Path -Path $result.ComputerDirectory -ChildPath 'Logs') -ChildPath 'command.log')
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
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
        $results[0].ResultPath | Should Be (Join-Path -Path $results[0].ComputerDirectory -ChildPath 'run.log')
        $results[1].ResultPath | Should Be (Join-Path -Path $results[1].ComputerDirectory -ChildPath 'run.log')
        $null -eq $results[0].StdOutPath | Should Be $true
        $null -eq $results[1].StdOutPath | Should Be $true
        (Get-Content -LiteralPath $results[0].ResultPath -Raw) | Should Match 'first target'
        (Get-Content -LiteralPath $results[1].ResultPath -Raw) | Should Match 'second target'
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-002') -PathType Container | Should Be $true
        Test-Path -LiteralPath $results[0].ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $results[1].ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $results[0].ComputerDirectory -ChildPath 'stdout.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $results[1].ComputerDirectory -ChildPath 'stderr.txt') -PathType Leaf | Should Be $false
        $summaryRows = @(Import-Csv -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'summary.csv'))
        @($summaryRows).Count | Should Be 2
        ($summaryRows.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($summaryRows.ResultPath -join ',') | Should Be (($results[0].ResultPath, $results[1].ResultPath) -join ',')
        ($summaryRows.StdOutPath -join ',') | Should Be ','
        ($summaryRows.StdErrPath -join ',') | Should Be ','
        $runLogText = Get-Content -LiteralPath (Join-Path -Path $results[0].RunDirectory -ChildPath 'run.log') -Raw
        $runLogText | Should Match 'WinPush Correlated Run Log'
        $runLogText | Should Match 'ComputerName : PC-001'
        $runLogText | Should Match 'ComputerName : PC-002'
        $runLogText | Should Match 'first target'
        $runLogText | Should Match 'second target'
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
        $null -eq $results[0].StdOutPath | Should Be $true
        $null -eq $results[0].StdErrPath | Should Be $true
        (Get-Content -LiteralPath $results[0].ResultPath -Raw) | Should Match 'first target'
        (Get-Content -LiteralPath $results[1].ResultPath -Raw) | Should Match 'second target'
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
        $null -eq $results[0].StdOutPath | Should Be $true
        $null -eq $results[0].StdErrPath | Should Be $true
        (Get-Content -LiteralPath $results[0].ResultPath -Raw) | Should Match 'first target'
        (Get-Content -LiteralPath $results[1].ResultPath -Raw) | Should Match 'second target'
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
        $logText = Get-Content -LiteralPath $result.ResultPath -Raw

        @($result.Output).Count | Should Be 1
        $result.Output[0].Name | Should Be 'Alpha'
        $result.Output[0].Count | Should Be 2
        $logText | Should Match 'Alpha'
        $logText | Should Match '2'
    }

    It 'writes an empty-output command run log without stream files' {
        $script:InvokeCommandOutput = @()
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '$null' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $true
        @($result.Output).Count | Should Be 0
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        Test-Path -LiteralPath $result.ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') -PathType Leaf | Should Be $false
    }

    It 'uses a unique run folder when capture output is invoked more than once in the same second' {
        $script:InvokeCommandOutput = @('first')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $firstResult = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '"first"' -CaptureOutput -OutputRoot $outputRoot

        $script:InvokeCommandOutput = @('second')
        $secondResult = Invoke-WinPushCommand -ComputerName 'PC-001' -Command '"second"' -CaptureOutput -OutputRoot $outputRoot

        $firstResult.RunDirectory -eq $secondResult.RunDirectory | Should Be $false
        (Get-Content -LiteralPath $firstResult.ResultPath -Raw) | Should Match 'first'
        (Get-Content -LiteralPath $secondResult.ResultPath -Raw) | Should Match 'second'
    }

    It 'captures failed command errors to the command run log when requested' {
        $script:InvokeCommandOutput = @()
        $script:InvokeCommandErrors = @('command failed')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'throw "command failed"' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'command failed'
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') -PathType Leaf | Should Be $false
        (Get-Content -LiteralPath $result.ResultPath -Raw) | Should Match 'command failed'
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

    It 'captures command output and command errors to the run log when both are emitted' {
        $script:InvokeCommandOutput = @('before error')
        $script:InvokeCommandErrors = @('command failed')
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'Write-Output "before error"; Write-Error "command failed"' -CaptureOutput -OutputRoot $outputRoot

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        $logText = Get-Content -LiteralPath $result.ResultPath -Raw
        $logText | Should Match 'before error'
        $logText | Should Match 'command failed'
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

    It 'rejects whitespace output root before opening a session when logs are requested' {
        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Logs -OutputRoot '   ' } | Should Throw 'OutputRoot must not be empty.'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedLogSessions).Count | Should Be 0
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

    It 'runs one WinRS command through the native process boundary' {
        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'WinRM'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'winrs output'
        @($result.Errors).Count | Should Be 0
        @($script:NativeProcessFilePaths).Count | Should Be 1
        $script:NativeProcessFilePaths[0] | Should Be 'winrs.exe'
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '-r:PC-001|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'runs one PsExec command through an explicit executable path' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-explicit.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $resolvedPsExecPath = (Get-Item -LiteralPath $psExecPath).FullName
        $script:NativeProcessStandardOutput = "psexec output`r`n"

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'PsExec'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'psexec output'
        @($result.Errors).Count | Should Be 0
        @($script:NativeProcessFilePaths).Count | Should Be 1
        $script:NativeProcessFilePaths[0] | Should Be $resolvedPsExecPath
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '\\PC-001|-h|cmd.exe|/d|/s|/c|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'discovers PsExec.exe from PATH when no explicit path is supplied' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $originalPath = $env:PATH

        try {
            $env:PATH = ('{0};{1}' -f $TestDrive, $originalPath)
            $discoveredPsExecPath = (Get-Command -Name 'PsExec.exe' -CommandType Application).Source

            Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec | Out-Null

            @($script:NativeProcessFilePaths).Count | Should Be 1
            $script:NativeProcessFilePaths[0] | Should Be $discoveredPsExecPath
            ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '\\PC-001|-h|cmd.exe|/d|/s|/c|hostname'
            @($script:NewPSSessionComputerNames).Count | Should Be 0
        }
        finally {
            $env:PATH = $originalPath
        }
    }

    It 'rejects a missing PsExec executable before launching a native process' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'MissingPsExec-missing.exe'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.Succeeded | Should Be $false
        $result.Transport | Should Be 'PsExec'
        $result.ErrorMessage | Should Match 'PsExec executable was not found:'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'rejects a directory PsExec path before launching a native process' {
        $psExecDirectory = Join-Path -Path $TestDrive -ChildPath 'PsExec-directory.exe'
        New-Item -Path $psExecDirectory -ItemType Directory | Out-Null

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecDirectory

        $result.Succeeded | Should Be $false
        $result.Transport | Should Be 'PsExec'
        $result.ErrorMessage | Should Match 'PsExec path must be a file:'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'rejects a non-exe PsExec path before launching a native process' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-non-exe.txt'
        Set-Content -LiteralPath $psExecPath -Value 'not an exe'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.Succeeded | Should Be $false
        $result.Transport | Should Be 'PsExec'
        $result.ErrorMessage | Should Match 'PsExec path must reference an .exe file:'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'rejects PsExec credentials before launching a native process' {
        $credential = New-TestCredential -Secret 'Distinctive-10.1-Credential-Secret!'
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-credential.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'

        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath -Credential $credential } |
            Should Throw 'Credential is not supported when Transport is PsExec.'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'captures PsExec command output to run log artifacts when requested' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-capture.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessStandardOutput = "native output`r`n"
        $script:NativeProcessStandardError = "native warning`r`n"
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath -CaptureOutput -OutputRoot $outputRoot

        $result.Transport | Should Be 'PsExec'
        $result.Succeeded | Should Be $true
        $result.RunDirectory.StartsWith($outputRoot) | Should Be $true
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        $logText = Get-Content -LiteralPath $result.ResultPath -Raw
        $logText | Should Match 'native output'
        $logText | Should Match 'native warning'
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') -PathType Leaf | Should Be $false
        $summaryRows = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summaryRows).Count | Should Be 1
        $summaryRows[0].Transport | Should Be 'PsExec'
        $summaryRows[0].Operation | Should Be 'RunCommand'
        $summaryRows[0].ResultPath | Should Be $result.ResultPath
        $summaryRows[0].StdOutPath | Should Be ''
        $summaryRows[0].StdErrPath | Should Be ''
        @($script:NativeProcessFilePaths).Count | Should Be 1
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'filters PsExec status stderr on successful commands while preserving real stderr' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-status.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessStandardOutput = "native output`r`n"
        $script:NativeProcessStandardError = @(
            'PsExec v2.43 - Execute processes remotely'
            'Copyright (C) 2001-2023 Mark Russinovich'
            'Sysinternals - www.sysinternals.com'
            ''
            'Connecting to PC-001...'
            'Starting PSEXESVC service on PC-001...'
            'Connecting with PsExec service on PC-001...'
            'cmd.exe exited on PC-001 with error code 0.'
            'remote stderr'
            ''
        ) -join "`r`n"

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.Succeeded | Should Be $true
        $result.ErrorMessage | Should BeNullOrEmpty
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'remote stderr'
    }

    It 'runs PsExec direct-array targets sequentially through independent native processes' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-multiple.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessExitCodesByComputerName = @{
            'PC-002' = 9
        }
        $script:NativeProcessStandardOutputsByComputerName = @{
            'PC-001' = "first target`r`n"
            'PC-002' = "second target`r`n"
            'PC-003' = "third target`r`n"
        }
        $script:NativeProcessStandardErrorsByComputerName = @{
            'PC-002' = "target two failed`r`n"
        }

        $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002', 'PC-003', 'pc-001') -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath)

        @($results).Count | Should Be 3
        $results[0].ComputerName | Should Be 'PC-001'
        $results[0].Transport | Should Be 'PsExec'
        $results[0].Succeeded | Should Be $true
        $results[0].ExitCode | Should Be 0
        $results[0].Output[0] | Should Be 'first target'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[1].Transport | Should Be 'PsExec'
        $results[1].Succeeded | Should Be $false
        $results[1].ExitCode | Should Be 9
        $results[1].Output[0] | Should Be 'second target'
        $results[1].Errors[0] | Should Be 'target two failed'
        $results[1].ErrorMessage | Should Be 'target two failed'
        $results[2].ComputerName | Should Be 'PC-003'
        $results[2].Transport | Should Be 'PsExec'
        $results[2].Succeeded | Should Be $true
        $results[2].ExitCode | Should Be 0
        $results[2].Output[0] | Should Be 'third target'
        @($script:NativeProcessFilePaths).Count | Should Be 3
        Split-Path -Path $script:NativeProcessFilePaths[0] -Leaf | Should Be 'PsExec-multiple.exe'
        Split-Path -Path $script:NativeProcessFilePaths[1] -Leaf | Should Be 'PsExec-multiple.exe'
        Split-Path -Path $script:NativeProcessFilePaths[2] -Leaf | Should Be 'PsExec-multiple.exe'
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '\\PC-001|-h|cmd.exe|/d|/s|/c|hostname'
        ($script:NativeProcessArgumentLists[1] -join '|') | Should Be '\\PC-002|-h|cmd.exe|/d|/s|/c|hostname'
        ($script:NativeProcessArgumentLists[2] -join '|') | Should Be '\\PC-003|-h|cmd.exe|/d|/s|/c|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'continues PsExec pipeline targets after one native process launch failure' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-pipeline.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessErrorsByComputerName = @{
            'PC-001' = 'launch failed'
        }
        $script:NativeProcessStandardOutputsByComputerName = @{
            'PC-002' = "later target`r`n"
        }

        $results = @(
            @(
                [pscustomobject] @{ ComputerName = 'PC-001' }
                [pscustomobject] @{ ComputerName = 'PC-002' }
            ) | Invoke-WinPushCommand -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath
        )

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[0].Transport | Should Be 'PsExec'
        $results[0].Succeeded | Should Be $false
        $results[0].ExitCode | Should Be 1
        $results[0].ErrorMessage | Should Be 'launch failed'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[1].Transport | Should Be 'PsExec'
        $results[1].Succeeded | Should Be $true
        $results[1].Output[0] | Should Be 'later target'
        @($script:NativeProcessFilePaths).Count | Should Be 2
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '\\PC-001|-h|cmd.exe|/d|/s|/c|hostname'
        ($script:NativeProcessArgumentLists[1] -join '|') | Should Be '\\PC-002|-h|cmd.exe|/d|/s|/c|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'runs PsExec host-file targets through the shared resolver in order' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-hostfile.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'valid-hosts.txt'
        $utf8Target = 'pc-utf8-{0}01' -f [char] 0x00e9
        $script:NativeProcessStandardOutputsByComputerName = @{
            'PC-001'    = "first target`r`n"
            $utf8Target = "utf8 target`r`n"
            'PC-003'    = "third target`r`n"
        }

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath)

        @($results).Count | Should Be 3
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be $utf8Target
        $results[2].ComputerName | Should Be 'PC-003'
        $results[0].Transport | Should Be 'PsExec'
        $results[1].Transport | Should Be 'PsExec'
        $results[2].Transport | Should Be 'PsExec'
        $results[0].Output[0] | Should Be 'first target'
        $results[1].Output[0] | Should Be 'utf8 target'
        $results[2].Output[0] | Should Be 'third target'
        @($script:NativeProcessFilePaths).Count | Should Be 3
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '\\PC-001|-h|cmd.exe|/d|/s|/c|hostname'
        ($script:NativeProcessArgumentLists[1] -join '|') | Should Be ('\\{0}|-h|cmd.exe|/d|/s|/c|hostname' -f $utf8Target)
        ($script:NativeProcessArgumentLists[2] -join '|') | Should Be '\\PC-003|-h|cmd.exe|/d|/s|/c|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'rejects PsExecPath when the PsExec transport is not selected' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-wrong-transport.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'

        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -PsExecPath $psExecPath } |
            Should Throw 'PsExecPath is only supported when Transport is PsExec.'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'keeps PsExec stdout and stderr in separate arrays when the native process fails' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-streams.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessExitCode = 23
        $script:NativeProcessStandardOutput = "line one`r`nline two`r`n"
        $script:NativeProcessStandardError = "`r`npsexec error  `r`nmore detail`r`n"

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.Transport | Should Be 'PsExec'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 23
        $result.ErrorMessage | Should Be 'psexec error'
        @($result.Output).Count | Should Be 2
        $result.Output[0] | Should Be 'line one'
        $result.Output[1] | Should Be 'line two'
        @($result.Errors).Count | Should Be 3
        $result.Errors[0] | Should Be ''
        $result.Errors[1] | Should Be 'psexec error  '
        $result.Errors[2] | Should Be 'more detail'
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '\\PC-001|-h|cmd.exe|/d|/s|/c|hostname'
    }

    It 'filters PsExec status stderr before choosing the failure error message' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-failed-status.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessExitCode = 6
        $script:NativeProcessStandardError = @(
            'Connecting to PC-001...'
            ''
            "Couldn't access PC-001:"
            'The handle is invalid.'
            'Connecting to PC-001...'
        ) -join "`r`n"

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 6
        $result.ErrorMessage | Should Be "Couldn't access PC-001:"
        ($result.Errors -join '|') | Should Be "|Couldn't access PC-001:|The handle is invalid."
    }

    It 'uses a deterministic PsExec error message when a nonzero exit has no stderr' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-nostderr.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $script:NativeProcessExitCode = 5
        $script:NativeProcessStandardOutput = 'partial output'
        $script:NativeProcessStandardError = ''

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 5
        $result.ErrorMessage | Should Be 'PsExec command exited with code 5.'
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'partial output'
        @($result.Errors).Count | Should Be 0
    }

    It 'passes spaces, quotes, metacharacters, Unicode, and empty quoted arguments as one PsExec command text argument' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-quoting.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
        $unicodeValue = [string] [char] 0x03A9
        $command = 'powershell -NoProfile -Command "Write-Output ''hello world''; Write-Output ''' + $unicodeValue + '''; Write-Output ''''; if ($true) { Write-Output ''a&b|c'' }"'

        Invoke-WinPushCommand -ComputerName 'PC-001' -Command $command -Transport PsExec -PsExecPath $psExecPath | Out-Null

        @($script:NativeProcessArgumentLists).Count | Should Be 1
        @($script:NativeProcessArgumentLists[0]).Count | Should Be 7
        $script:NativeProcessArgumentLists[0][0] | Should Be '\\PC-001'
        $script:NativeProcessArgumentLists[0][1] | Should Be '-h'
        $script:NativeProcessArgumentLists[0][2] | Should Be 'cmd.exe'
        $script:NativeProcessArgumentLists[0][3] | Should Be '/d'
        $script:NativeProcessArgumentLists[0][4] | Should Be '/s'
        $script:NativeProcessArgumentLists[0][5] | Should Be '/c'
        $script:NativeProcessArgumentLists[0][6] | Should Be $command
    }

    It 'rejects PsExec credentials without emitting credential values' {
        $secret = 'Distinctive-10.2-Credential-Secret!'
        $credential = New-TestCredential -Secret $secret
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-redaction.exe'
        Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'

        $diagnosticText = try {
            Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath -Credential $credential
        }
        catch {
            $_.Exception.Message
        }

        $diagnosticText | Should Be 'Credential is not supported when Transport is PsExec.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'keeps WinRS stdout and stderr in separate arrays when the native process fails' {
        $script:NativeProcessExitCode = 7
        $script:NativeProcessStandardOutput = "line one`r`nline two`r`n"
        $script:NativeProcessStandardError = "`r`nnative error  `r`nmore detail`r`n"

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM

        $result.Transport | Should Be 'WinRM'
        $result.Operation | Should Be 'RunCommand'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 7
        $result.ErrorMessage | Should Be 'native error'
        @($result.Output).Count | Should Be 2
        $result.Output[0] | Should Be 'line one'
        $result.Output[1] | Should Be 'line two'
        @($result.Errors).Count | Should Be 3
        $result.Errors[0] | Should Be ''
        $result.Errors[1] | Should Be 'native error  '
        $result.Errors[2] | Should Be 'more detail'
    }

    It 'uses a deterministic WinRS error message when a nonzero exit has no stderr' {
        $script:NativeProcessExitCode = 5
        $script:NativeProcessStandardOutput = 'partial output'
        $script:NativeProcessStandardError = ''

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 5
        $result.ErrorMessage | Should Be 'WinRS command exited with code 5.'
        @($result.Output).Count | Should Be 1
        $result.Output[0] | Should Be 'partial output'
        @($result.Errors).Count | Should Be 0
    }

    It 'passes spaces, quotes, metacharacters, Unicode, and empty quoted arguments as one WinRS command argument' {
        $unicodeValue = [string] [char] 0x03A9
        $command = 'powershell -NoProfile -Command "Write-Output ''hello world''; Write-Output ''' + $unicodeValue + '''; Write-Output ''''; if ($true) { Write-Output ''a&b|c'' }"'

        Invoke-WinPushCommand -ComputerName 'PC-001' -Command $command -Transport WinRM | Out-Null

        @($script:NativeProcessArgumentLists).Count | Should Be 1
        @($script:NativeProcessArgumentLists[0]).Count | Should Be 2
        $script:NativeProcessArgumentLists[0][0] | Should Be '-r:PC-001'
        $script:NativeProcessArgumentLists[0][1] | Should Be $command
    }

    It 'rejects WinRM credentials before launching a native process' {
        $credential = New-TestCredential -Secret 'Distinctive-9.1-Credential-Secret!'

        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM -Credential $credential } |
            Should Throw 'Credential is not supported when Transport is WinRM.'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'runs WinRS direct-array targets sequentially through independent native processes' {
        $script:NativeProcessExitCodesByComputerName = @{
            'PC-002' = 9
        }
        $script:NativeProcessStandardOutputsByComputerName = @{
            'PC-001' = "first target`r`n"
            'PC-002' = "second target`r`n"
        }
        $script:NativeProcessStandardErrorsByComputerName = @{
            'PC-002' = "target two failed`r`n"
        }

        $results = @(Invoke-WinPushCommand -ComputerName @('PC-001', 'PC-002', 'pc-001') -Command 'hostname' -Transport WinRM)

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[0].Succeeded | Should Be $true
        $results[0].ExitCode | Should Be 0
        $results[0].Output[0] | Should Be 'first target'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[1].Succeeded | Should Be $false
        $results[1].ExitCode | Should Be 9
        $results[1].Output[0] | Should Be 'second target'
        $results[1].Errors[0] | Should Be 'target two failed'
        $results[1].ErrorMessage | Should Be 'target two failed'
        @($script:NativeProcessFilePaths).Count | Should Be 2
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '-r:PC-001|hostname'
        ($script:NativeProcessArgumentLists[1] -join '|') | Should Be '-r:PC-002|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'continues WinRS pipeline targets after one native process launch failure' {
        $script:NativeProcessErrorsByComputerName = @{
            'PC-001' = 'launch failed'
        }
        $script:NativeProcessStandardOutputsByComputerName = @{
            'PC-002' = "later target`r`n"
        }

        $results = @(
            @(
                [pscustomobject] @{ ComputerName = 'PC-001' }
                [pscustomobject] @{ ComputerName = 'PC-002' }
            ) | Invoke-WinPushCommand -Command 'hostname' -Transport WinRM
        )

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[0].Succeeded | Should Be $false
        $results[0].ExitCode | Should Be 1
        $results[0].ErrorMessage | Should Be 'launch failed'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[1].Succeeded | Should Be $true
        $results[1].Output[0] | Should Be 'later target'
        @($script:NativeProcessFilePaths).Count | Should Be 2
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '-r:PC-001|hostname'
        ($script:NativeProcessArgumentLists[1] -join '|') | Should Be '-r:PC-002|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'runs WinRS host-file targets through the shared resolver in order' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'valid-hosts.txt'
        $utf8Target = 'pc-utf8-{0}01' -f [char] 0x00e9
        $script:NativeProcessStandardOutputsByComputerName = @{
            'PC-001'     = "first target`r`n"
            $utf8Target  = "utf8 target`r`n"
            'PC-003'     = "third target`r`n"
        }

        $results = @(Invoke-WinPushCommand -HostFile $hostFile -Command 'hostname' -Transport WinRM)

        @($results).Count | Should Be 3
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be $utf8Target
        $results[2].ComputerName | Should Be 'PC-003'
        $results[0].Output[0] | Should Be 'first target'
        $results[1].Output[0] | Should Be 'utf8 target'
        $results[2].Output[0] | Should Be 'third target'
        @($script:NativeProcessFilePaths).Count | Should Be 3
        ($script:NativeProcessArgumentLists[0] -join '|') | Should Be '-r:PC-001|hostname'
        ($script:NativeProcessArgumentLists[1] -join '|') | Should Be ('-r:{0}|hostname' -f $utf8Target)
        ($script:NativeProcessArgumentLists[2] -join '|') | Should Be '-r:PC-003|hostname'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'captures WinRM command output to run log artifacts when requested' {
        $script:NativeProcessStandardOutput = "winrs output`r`n"
        $script:NativeProcessStandardError = "winrs warning`r`n"
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'WinPush'

        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM -CaptureOutput -OutputRoot $outputRoot

        $result.Transport | Should Be 'WinRM'
        $result.Succeeded | Should Be $true
        $result.RunDirectory.StartsWith($outputRoot) | Should Be $true
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'run.log')
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
        $logText = Get-Content -LiteralPath $result.ResultPath -Raw
        $logText | Should Match 'winrs output'
        $logText | Should Match 'winrs warning'
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt') -PathType Leaf | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt') -PathType Leaf | Should Be $false
        $summaryRows = @(Import-Csv -LiteralPath (Join-Path -Path $result.RunDirectory -ChildPath 'summary.csv'))
        @($summaryRows).Count | Should Be 1
        $summaryRows[0].Transport | Should Be 'WinRM'
        $summaryRows[0].Operation | Should Be 'RunCommand'
        $summaryRows[0].ResultPath | Should Be $result.ResultPath
        $summaryRows[0].StdOutPath | Should Be ''
        $summaryRows[0].StdErrPath | Should Be ''
        @($script:NativeProcessFilePaths).Count | Should Be 1
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'rejects <Transport> attached logs before launching a native process' -TestCases @(
        @{ Transport = 'PsExec' }
        @{ Transport = 'WinRM' }
    ) {
        param($Transport)

        if ($Transport -eq 'PsExec') {
            $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec-logs.exe'
            Set-Content -LiteralPath $psExecPath -Value 'test executable placeholder'
            $operation = { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport PsExec -PsExecPath $psExecPath -Logs -OutputRoot $TestDrive }
        }
        else {
            $operation = { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM -Logs -OutputRoot $TestDrive }
        }

        $operation | Should Throw "Logs is not supported when Transport is $Transport."

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }
}
