$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:PsrpLogMetadataPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Logs\Get-WinPushPsrpLogFileInfo.ps1'
$script:LogCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Get-WinPushLog.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:PsrpLogMetadataPath
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
        $script:SessionToReturn = [pscustomobject] @{ Id = 801; ComputerName = 'PC-001' }
        $script:NewPSSessionError = $null
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

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'has the single-target public parameter contract for explicit remote directory enumeration' {
        $command = Get-Command -Name Get-WinPushLog
        $computerNameParameterAttribute = $command.Parameters['ComputerName'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1

        ($command.Parameters.Keys -contains 'ComputerName') | Should Be $true
        $command.Parameters['ComputerName'].ParameterType.FullName | Should Not Be 'System.String[]'
        $computerNameParameterAttribute.ValueFromPipeline | Should Be $false
        $computerNameParameterAttribute.ValueFromPipelineByPropertyName | Should Be $false
        ($command.Parameters.Keys -contains 'RemoteDirectory') | Should Be $true
        $command.Parameters['RemoteDirectory'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
        ($command.Parameters.Keys -contains 'HostFile') | Should Be $false
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

    It 'rejects array ComputerName input before opening a session' {
        $result = Get-WinPushLog -ComputerName @($script:TargetName, $script:OtherTargetName) -RemoteDirectory 'C:\ProgramData\EA\Logs'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Get-WinPushLog requires exactly one target.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'returns immediate file metadata in Output without log copy results' {
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

        $result = Get-WinPushLog -ComputerName " $($script:TargetName) " -RemoteDirectory 'C:\ProgramData\EA\Logs\App'

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'GetLogs'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($result.Output).Count | Should Be 2
        ($result.Output.Name -join ',') | Should Be 'install.log,repair.log'
        @($result.Logs).Count | Should Be 0
        @($result.CopiedLogPaths).Count | Should Be 0
        $null -eq $result.ResultPath | Should Be $true
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:LogMetadataRemoteDirectories).Count | Should Be 1
        $script:LogMetadataRemoteDirectories[0] | Should Be 'C:\ProgramData\EA\Logs\App'
    }

    It 'returns success with empty Output and Logs for an empty valid remote directory' {
        $script:LogMetadataToReturn = @()

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\Empty'

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($result.Output).Count | Should Be 0
        @($result.Logs).Count | Should Be 0
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
        Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be 801
    }

    It 'normalizes credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-7.1-Credential-Secret!'
        $credential = Get-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -Credential $credential
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

        $result = Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' -Credential $credential

        $result.Succeeded | Should Be $true
        @($script:NewPSSessionCredentials).Count | Should Be 1
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
    }

    It 'does not send a credential argument to New-PSSession when omitted' {
        Get-WinPushLog -ComputerName $script:TargetName -RemoteDirectory 'C:\ProgramData\EA\Logs\App' | Out-Null

        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $false
        @($script:NewPSSessionCredentials).Count | Should Be 0
    }
}
