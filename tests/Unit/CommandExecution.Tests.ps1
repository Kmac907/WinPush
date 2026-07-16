$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushExecutionResult.ps1'
$script:LogResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushLogResult.ps1'
$script:ArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Write-WinPushCommandOutputArtifact.ps1'
$script:NativeProcessPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushNativeProcess.ps1'
$script:WinRsCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushWinRsCommand.ps1'
$script:PsrpCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushPsrpCommand.ps1'
$script:CommandLogDirectoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\Get-WinPushCommandLogDirectory.ps1'
$script:LogArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1'
$script:PsrpLogCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\Copy-WinPushPsrpLogDirectory.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Invoke-WinPushCommand.ps1'
$script:FixtureRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\Fixtures\TargetResolution')

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:LogResultFactoryPath
. $script:ArtifactPath
. $script:NativeProcessPath
. $script:WinRsCommandPath
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
            [scriptblock] $ScriptBlock
        )

        if ($null -ne $Session -and -not [string]::IsNullOrWhiteSpace($Session.ComputerName)) {
            $script:InvokedSessionComputerNames += $Session.ComputerName
        }

        $script:InvokedScriptBlocks += $ScriptBlock.ToString()
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
            [string[]] $ArgumentList
        )

        $script:NativeProcessFilePaths += $FilePath
        $script:NativeProcessArgumentLists += , @($ArgumentList)
        $computerName = if ($ArgumentList.Count -gt 0 -and $ArgumentList[0] -like '-r:*') {
            $ArgumentList[0].Substring(3)
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
        ($validateSet[0].ValidValues -join ',') | Should Be 'Psrp,WinRM'

        Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' | Out-Null

        @($script:NewPSSessionComputerNames).Count | Should Be 1
        @($script:NativeProcessFilePaths).Count | Should Be 0
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

    It 'copies command-attached logs after a successful command using the same PSSession' {
        $result = Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Logs -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.Output[0] | Should Be 'remote output'
        @($result.Errors).Count | Should Be 0
        @($result.Logs).Count | Should Be 1
        $result.Logs[0].PSTypeNames[0] | Should Be 'WinPush.LogResult'
        $result.Logs[0].RemotePath | Should Be 'C:\ProgramData\EA\Logs\hostname\command.log'
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.RunDirectory | Should Be (Join-Path -Path $TestDrive -ChildPath 'run-logs')
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
        $result.ResultPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'result.txt')
        $result.StdOutPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'stdout.txt')
        $result.StdErrPath | Should Be (Join-Path -Path $result.ComputerDirectory -ChildPath 'stderr.txt')
        Test-Path -LiteralPath $result.ResultPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdOutPath -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $result.StdErrPath -PathType Leaf | Should Be $true
        $resultText = Get-Content -LiteralPath $result.ResultPath -Raw
        $resultText | Should Match 'ComputerName : PC-001'
        $resultText | Should Match 'Operation    : RunCommand'
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
        $summaryRows[0].Operation | Should Be 'RunCommand'
        $summaryRows[0].Transport | Should Be 'Psrp'
        $summaryRows[0].Succeeded | Should Be 'True'
        $summaryRows[0].ExitCode | Should Be '0'
        $summaryRows[0].ResultPath | Should Be $result.ResultPath
        $summaryRows[0].StdOutPath | Should Be $result.StdOutPath
        $summaryRows[0].StdErrPath | Should Be $result.StdErrPath
        (Get-Content -LiteralPath $result.StdOutPath) -join ',' | Should Be 'first line,second line'
        @(Get-Content -LiteralPath $result.StdErrPath).Count | Should Be 0
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
        ($summaryRows.ResultPath -join ',') | Should Be (($results[0].ResultPath, $results[1].ResultPath) -join ',')
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

    It 'rejects WinRM capture-output artifacts before launching a native process' {
        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM -CaptureOutput -OutputRoot $TestDrive } |
            Should Throw 'CaptureOutput is not supported when Transport is WinRM.'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'rejects WinRM attached logs before launching a native process' {
        { Invoke-WinPushCommand -ComputerName 'PC-001' -Command 'hostname' -Transport WinRM -Logs -OutputRoot $TestDrive } |
            Should Throw 'Logs is not supported when Transport is WinRM.'

        @($script:NativeProcessFilePaths).Count | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }
}
