$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:LogResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushLogResult.ps1'
$script:PsrpCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Copy-WinPushPsrpItem.ps1'
$script:PsrpLogMetadataPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Logs\Get-WinPushPsrpLogFileInfo.ps1'
$script:LogArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Logs\New-WinPushLogArtifactDirectory.ps1'
$script:PsrpLogCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Logs\Copy-WinPushPsrpLogDirectory.ps1'
$script:LogCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Get-WinPushLog.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:LogResultFactoryPath
. $script:PsrpCopyPath
. $script:PsrpLogMetadataPath
. $script:LogArtifactPath
. $script:PsrpLogCopyPath
. $script:LogCommandPath

function Get-TestCredential {
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

Describe 'Get-WinPushPsrpLogFileInfo' {
    BeforeEach {
        $script:InvokeCommandSessions = @()
        $script:InvokeCommandArguments = @()
    }

    Mock Invoke-Command {
        param(
            $Session,
            [scriptblock] $ScriptBlock,
            [object[]] $ArgumentList,
            $ErrorAction
        )

        $null = $ErrorAction
        $script:InvokeCommandSessions += $Session
        $script:InvokeCommandArguments += , $ArgumentList

        & $ScriptBlock @ArgumentList
    }

    It 'enumerates immediate regular files and excludes nested files' {
        $remoteDirectory = Join-Path -Path $TestDrive -ChildPath 'Logs'
        $nestedDirectory = Join-Path -Path $remoteDirectory -ChildPath 'Nested'
        New-Item -ItemType Directory -Path $nestedDirectory | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $remoteDirectory -ChildPath 'install.log') -Value 'install' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path -Path $remoteDirectory -ChildPath 'repair.log') -Value 'repair' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path -Path $nestedDirectory -ChildPath 'nested.log') -Value 'nested' -Encoding utf8NoBOM

        $session = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )
        $result = @(Get-WinPushPsrpLogFileInfo -Session $session -RemoteDirectory $remoteDirectory)

        @($script:InvokeCommandSessions).Count | Should Be 1
        [object]::ReferenceEquals($script:InvokeCommandSessions[0], $session) | Should Be $true
        $script:InvokeCommandArguments[0][0] | Should Be $remoteDirectory
        @($result).Count | Should Be 2
        ($result.Name | Sort-Object) -join ',' | Should Be 'install.log,repair.log'
        ($result.RemotePath -join ',') | Should Not Match 'nested\.log'
        $result[0].RemoteDirectory | Should Be $remoteDirectory
        $result[0].Length | Should BeGreaterThan 0
        $null -eq $result[0].LastWriteTimeUtc | Should Be $false
    }

    It 'returns no metadata for an empty valid directory' {
        $remoteDirectory = Join-Path -Path $TestDrive -ChildPath 'EmptyLogs'
        New-Item -ItemType Directory -Path $remoteDirectory | Out-Null

        $session = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )

        $result = @(Get-WinPushPsrpLogFileInfo -Session $session -RemoteDirectory $remoteDirectory)

        @($result).Count | Should Be 0
    }

    It 'fails when the remote path is missing or is not a directory' {
        $missingDirectory = Join-Path -Path $TestDrive -ChildPath 'MissingLogs'

        $session = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )

        { Get-WinPushPsrpLogFileInfo -Session $session -RemoteDirectory $missingDirectory } |
            Should Throw "RemoteDirectory was not found or is not a directory: $missingDirectory"
    }
}

Describe 'Get-WinPushLog' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:NewPSSessionCredentialSupplied = @()
        $script:NewPSSessionCredentials = @()
        $script:RemovedSessionIds = @()
        $script:LogMetadataSessions = @()
        $script:LogMetadataRemoteDirectories = @()
        $script:CopySessions = @()
        $script:CopyRemotePaths = @()
        $script:CopyDestinations = @()
        $script:CopyDirections = @()
        $script:CopyFailures = @{}
        $script:SessionToReturn = [pscustomobject] @{ Id = 801; ComputerName = 'PC-001' }
        $script:NewPSSessionError = $null
        $script:NewPSSessionFailures = @{}
        $script:LogMetadataError = $null
        $script:LogMetadataToReturn = @()
        $script:TargetName = 'PC-001'
        $script:OtherTargetName = 'PC-002'
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

        if ($script:NewPSSessionFailures.ContainsKey($ComputerName)) {
            throw $script:NewPSSessionFailures[$ComputerName]
        }

        return $script:SessionToReturn
    }

    Mock Get-WinPushPsrpLogFileInfo {
        param(
            $Session,
            [string] $RemoteDirectory
        )

        $script:LogMetadataSessions += $Session
        $script:LogMetadataRemoteDirectories += $RemoteDirectory

        if ($null -ne $script:LogMetadataError) {
            throw $script:LogMetadataError
        }

        return $script:LogMetadataToReturn
    }

    Mock Copy-WinPushPsrpItem {
        param(
            $Session,
            [string] $Path,
            [string] $Destination,
            [string] $Direction
        )

        $script:CopySessions += $Session
        $script:CopyRemotePaths += $Path
        $script:CopyDestinations += $Destination
        $script:CopyDirections += $Direction

        if ($script:CopyFailures.ContainsKey($Path)) {
            throw $script:CopyFailures[$Path]
        }
    }

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'has the public parameter contract for explicit remote directory retrieval across target sources' {
        $command = Get-Command -Name Get-WinPushLog
        $computerNameParameterAttribute = $command.Parameters['ComputerName'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1

        ($command.Parameters.Keys -contains 'ComputerName') | Should Be $true
        $command.Parameters['ComputerName'].ParameterType.FullName | Should Be 'System.String[]'
        $computerNameParameterAttribute.ValueFromPipeline | Should Be $true
        $computerNameParameterAttribute.ValueFromPipelineByPropertyName | Should Be $true
        ($command.Parameters.Keys -contains 'HostFile') | Should Be $true
        $command.Parameters['HostFile'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'RemoteDirectory') | Should Be $true
        $command.Parameters['RemoteDirectory'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'OutputRoot') | Should Be $true
        $command.Parameters['OutputRoot'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
        ($command.Parameters.Keys -contains 'Recurse') | Should Be $false
        ($command.Parameters.Keys -contains 'LogDirectory') | Should Be $false
    }

    It 'rejects relative remote directory paths before opening a session' {
        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'Logs\App'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'RemoteDirectory must be an absolute Windows path.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:LogMetadataRemoteDirectories).Count | Should Be 0
    }

    It 'rejects empty remote directory paths before opening a session' {
        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory ' '

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'RemoteDirectory must not be empty.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'runs direct ComputerName arrays in resolved order with one shared run folder' {
        $script:LogMetadataToReturn = @(
            [pscustomobject] [ordered] @{
                RemoteDirectory  = 'C:\ProgramData\EA\Logs\App'
                RemotePath       = 'C:\ProgramData\EA\Logs\App\install.log'
                Name             = 'install.log'
                Length           = 12
                LastWriteTimeUtc = [datetime]::UtcNow
            }
        )

        $results = @(Get-WinPushLog -ComputerName @(" $($script:TargetName) ", $script:TargetName.ToLowerInvariant(), $script:OtherTargetName) -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($results.Succeeded -join ',') | Should Be 'True,True'
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        $results[0].ComputerDirectory | Should Be (Join-Path -Path $results[0].RunDirectory -ChildPath 'PC-001')
        $results[1].ComputerDirectory | Should Be (Join-Path -Path $results[1].RunDirectory -ChildPath 'PC-002')
        @($results[0].Logs).Count | Should Be 1
        @($results[1].Logs).Count | Should Be 1
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002'
        @($script:RemovedSessionIds).Count | Should Be 2
    }

    It 'rejects empty output roots before opening a session' {
        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot ' '

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'OutputRoot must not be empty.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'copies immediate files to the local log folder and returns log results' {
        $metadata = @(
            [pscustomobject] [ordered] @{
                RemoteDirectory  = 'C:\ProgramData\EA\Logs\App'
                RemotePath       = 'C:\ProgramData\EA\Logs\App\install.log'
                Name             = 'install.log'
                Length           = 12
                LastWriteTimeUtc = [datetime]::UtcNow
            },
            [pscustomobject] [ordered] @{
                RemoteDirectory  = 'C:\ProgramData\EA\Logs\App'
                RemotePath       = 'C:\ProgramData\EA\Logs\App\repair.log'
                Name             = 'repair.log'
                Length           = 9
                LastWriteTimeUtc = [datetime]::UtcNow
            }
        )
        $script:LogMetadataToReturn = $metadata

        $result = Get-WinPushLog -ComputerName " $($script:TargetName) " -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot $TestDrive

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'GetLogs'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($result.Output).Count | Should Be 2
        ($result.Output.Name -join ',') | Should Be 'install.log,repair.log'
        @($result.Logs).Count | Should Be 2
        @($result.CopiedLogPaths).Count | Should Be 2
        $null -eq $result.ResultPath | Should Be $true
        $result.RunDirectory.StartsWith($TestDrive) | Should Be $true
        $result.ComputerDirectory | Should Be (Join-Path -Path $result.RunDirectory -ChildPath 'PC-001')
        $expectedLogDirectory = Join-Path -Path $result.ComputerDirectory -ChildPath 'Logs'
        (Test-Path -LiteralPath $expectedLogDirectory -PathType Container) | Should Be $true
        $result.Logs[0].PSTypeNames[0] | Should Be 'WinPush.LogResult'
        $result.Logs[0].Copied | Should Be $true
        $result.Logs[0].LocalPath | Should Be (Join-Path -Path $expectedLogDirectory -ChildPath 'install.log')
        $result.Logs[1].LocalPath | Should Be (Join-Path -Path $expectedLogDirectory -ChildPath 'repair.log')
        ($result.CopiedLogPaths -join ',') | Should Be ($result.Logs.LocalPath -join ',')
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:LogMetadataRemoteDirectories).Count | Should Be 1
        $script:LogMetadataRemoteDirectories[0] | Should Be 'C:\ProgramData\EA\Logs\App'
        @($script:CopyRemotePaths).Count | Should Be 2
        ($script:CopyRemotePaths -join ',') | Should Be 'C:\ProgramData\EA\Logs\App\install.log,C:\ProgramData\EA\Logs\App\repair.log'
        ($script:CopyDirections -join ',') | Should Be 'Download,Download'
        $script:CopyDestinations[0] | Should Be $result.Logs[0].LocalPath
    }

    It 'returns success with empty Output and Logs for an empty valid remote directory' {
        $script:LogMetadataToReturn = @()

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\Empty' -OutputRoot $TestDrive

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($result.Output).Count | Should Be 0
        @($result.Logs).Count | Should Be 0
        @($result.CopiedLogPaths).Count | Should Be 0
        $result.RunDirectory.StartsWith($TestDrive) | Should Be $true
        (Test-Path -LiteralPath (Join-Path -Path $result.ComputerDirectory -ChildPath 'Logs') -PathType Container) | Should Be $true
        @($script:CopyRemotePaths).Count | Should Be 0
    }

    It 'continues after one file copy failure and preserves successful copy results' {
        $metadata = @(
            [pscustomobject] [ordered] @{
                RemoteDirectory  = 'C:\ProgramData\EA\Logs\App'
                RemotePath       = 'C:\ProgramData\EA\Logs\App\install.log'
                Name             = 'install.log'
                Length           = 12
                LastWriteTimeUtc = [datetime]::UtcNow
            },
            [pscustomobject] [ordered] @{
                RemoteDirectory  = 'C:\ProgramData\EA\Logs\App'
                RemotePath       = 'C:\ProgramData\EA\Logs\App\repair.log'
                Name             = 'repair.log'
                Length           = 9
                LastWriteTimeUtc = [datetime]::UtcNow
            }
        )
        $script:LogMetadataToReturn = $metadata
        $script:CopyFailures['C:\ProgramData\EA\Logs\App\repair.log'] = 'Access denied copying repair.log'

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot $TestDrive

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'One or more log files failed to copy.'
        @($result.Output).Count | Should Be 2
        @($result.Logs).Count | Should Be 2
        $result.Logs[0].Copied | Should Be $true
        $result.Logs[1].Copied | Should Be $false
        $null -eq $result.Logs[1].LocalPath | Should Be $true
        $result.Logs[1].Error | Should Be 'Access denied copying repair.log'
        @($result.CopiedLogPaths).Count | Should Be 1
        $result.CopiedLogPaths[0] | Should Be $result.Logs[0].LocalPath
        $result.Errors[0] | Should Be 'Access denied copying repair.log'
        @($script:CopyRemotePaths).Count | Should Be 2
        @($script:RemovedSessionIds).Count | Should Be 1
    }

    It 'continues to later direct ComputerName targets after one target session fails' {
        $script:LogMetadataToReturn = @(
            [pscustomobject] [ordered] @{
                RemoteDirectory  = 'C:\ProgramData\EA\Logs\App'
                RemotePath       = 'C:\ProgramData\EA\Logs\App\install.log'
                Name             = 'install.log'
                Length           = 12
                LastWriteTimeUtc = [datetime]::UtcNow
            }
        )
        $script:NewPSSessionFailures[$script:TargetName] = 'Unable to connect to PC-001'

        $results = @(Get-WinPushLog -ComputerName @($script:TargetName, $script:OtherTargetName) -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[0].Succeeded | Should Be $false
        $results[0].ErrorMessage | Should Be 'Unable to connect to PC-001'
        @($results[0].Logs).Count | Should Be 0
        @($results[0].Errors).Count | Should Be 1
        $results[1].ComputerName | Should Be 'PC-002'
        $results[1].Succeeded | Should Be $true
        @($results[1].Logs).Count | Should Be 1
        @($script:RemovedSessionIds).Count | Should Be 1
    }

    It 'runs pipeline ComputerName strings in resolved order' {
        $script:LogMetadataToReturn = @()

        $results = @(@($script:TargetName, $script:OtherTargetName) | Get-WinPushLog -RemoteDirectory 'C:\ProgramData\EA\Logs\Empty' -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($results.Succeeded -join ',') | Should Be 'True,True'
        $results[0].RunDirectory | Should Be $results[1].RunDirectory
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002'
    }

    It 'runs pipeline objects by ComputerName property in resolved order' {
        $script:LogMetadataToReturn = @()
        $targets = @(
            [pscustomobject] @{ ComputerName = $script:TargetName },
            [pscustomobject] @{ ComputerName = $script:OtherTargetName }
        )

        $results = @($targets | Get-WinPushLog -RemoteDirectory 'C:\ProgramData\EA\Logs\Empty' -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'PC-001,PC-002'
    }

    It 'runs host file targets and continues after one failed target' {
        $script:LogMetadataToReturn = @()
        $script:NewPSSessionFailures['WINPUSH-NO-SUCH-7-3'] = 'Host file target failed'
        $hostFile = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        Set-Content -LiteralPath $hostFile -Value @(
            '# comment'
            'WINPUSH-NO-SUCH-7-3'
            $script:TargetName
            $script:TargetName.ToLowerInvariant()
        ) -Encoding UTF8

        $results = @(Get-WinPushLog -HostFile $hostFile -RemoteDirectory 'C:\ProgramData\EA\Logs\Empty' -OutputRoot $TestDrive)

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'WINPUSH-NO-SUCH-7-3'
        $results[0].Succeeded | Should Be $false
        $results[0].ErrorMessage | Should Be 'Host file target failed'
        $results[1].ComputerName | Should Be 'PC-001'
        $results[1].Succeeded | Should Be $true
        ($script:NewPSSessionComputerNames -join ',') | Should Be 'WINPUSH-NO-SUCH-7-3,PC-001'
        @($script:RemovedSessionIds).Count | Should Be 1
    }

    It 'returns a failed result when remote directory validation fails' {
        $script:LogMetadataError = 'RemoteDirectory was not found or is not a directory: C:\Missing'

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\Missing'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'RemoteDirectory was not found or is not a directory: C:\Missing'
        $result.Errors[0] | Should Be 'RemoteDirectory was not found or is not a directory: C:\Missing'
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be 801
    }

    It 'removes the session after successful enumeration' {
        Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot $TestDrive | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be 801
    }

    It 'normalizes credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-7.1-Credential-Secret!'
        $credential = Get-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -Credential $credential -OutputRoot $TestDrive
        $diagnosticText = @(
            $result.ErrorMessage
            @($result.Errors)
            @($result.Output)
            @($result.Logs)
        ) -join "`n"

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'PSRP log retrieval session creation failed for the target with the supplied credential.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
    }

    It 'passes the supplied credential object unchanged to New-PSSession' {
        $credential = Get-TestCredential -Secret 'Distinctive-7.1-Credential-Secret!'

        $results = @(Get-WinPushLog -ComputerName @($script:TargetName, $script:OtherTargetName) -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -Credential $credential -OutputRoot $TestDrive)

        ($results.Succeeded -join ',') | Should Be 'True,True'
        @($script:NewPSSessionCredentials).Count | Should Be 2
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredentials[1], $credential) | Should Be $true
    }

    It 'does not send a credential argument to New-PSSession when omitted' {
        Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -OutputRoot $TestDrive | Out-Null

        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $false
        @($script:NewPSSessionCredentials).Count | Should Be 0
    }
}
