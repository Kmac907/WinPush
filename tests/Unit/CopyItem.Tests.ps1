$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:PsrpCopyPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Execution\Copy-WinPushPsrpItem.ps1'
$script:CopyCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Copy-WinPushItem.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:PsrpCopyPath
. $script:CopyCommandPath

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

Describe 'Copy-WinPushPsrpItem' {
    BeforeEach {
        $script:CopyItemLiteralPaths = @()
        $script:CopyItemDestinations = @()
        $script:CopyItemSessions = @()
        $script:CopyItemErrorActions = @()
        $script:CopyItemError = $null
    }

    Mock Copy-Item {
        param(
            [string] $LiteralPath,
            [string] $Destination,
            $ToSession,
            $ErrorAction
        )

        $script:CopyItemLiteralPaths += $LiteralPath
        $script:CopyItemDestinations += $Destination
        $script:CopyItemSessions += $ToSession
        $script:CopyItemErrorActions += $ErrorAction

        if ($null -ne $script:CopyItemError) {
            throw $script:CopyItemError
        }
    }

    It 'copies one local file to the destination through the supplied PSSession' {
        $session = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )

        Copy-WinPushPsrpItem -Session $session -Path 'C:\Temp\fixture.txt' -Destination 'C:\Remote\fixture.txt'

        @($script:CopyItemLiteralPaths).Count | Should Be 1
        $script:CopyItemLiteralPaths[0] | Should Be 'C:\Temp\fixture.txt'
        $script:CopyItemDestinations[0] | Should Be 'C:\Remote\fixture.txt'
        [object]::ReferenceEquals($script:CopyItemSessions[0], $session) | Should Be $true
        $script:CopyItemErrorActions[0] | Should Be 'Stop'
    }
}

Describe 'Copy-WinPushItem' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:CopiedSessions = @()
        $script:CopiedPaths = @()
        $script:CopiedDestinations = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 602; ComputerName = 'PC-001' }
        $script:NewPSSessionError = $null
        $script:CopyError = $null
        $script:NewPSSessionCredentialSupplied = @()
        $script:NewPSSessionCredentials = @()
        $script:TargetName = 'PC-001'
        $script:OtherTargetName = 'PC-002'
        $script:BlankTargetName = ' '
        $script:FixtureFile = Join-Path -Path $TestDrive -ChildPath 'Copy-WinPushItem-Fixture.txt'
        Set-Content -LiteralPath $script:FixtureFile -Value 'copy me' -Encoding utf8NoBOM
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

    Mock Copy-WinPushPsrpItem {
        param(
            $Session,
            [string] $Path,
            [string] $Destination
        )

        $script:CopiedSessions += $Session
        $script:CopiedPaths += $Path
        $script:CopiedDestinations += $Destination

        if ($null -ne $script:CopyError) {
            throw $script:CopyError
        }
    }

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'has the upload-only public parameter contract' {
        $command = Get-Command -Name Copy-WinPushItem
        $computerNameParameterAttribute = $command.Parameters['ComputerName'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1

        ($command.Parameters.Keys -contains 'ComputerName') | Should Be $true
        $command.Parameters['ComputerName'].ParameterType.FullName | Should Not Be 'System.String[]'
        $computerNameParameterAttribute.ValueFromPipeline | Should Be $false
        $computerNameParameterAttribute.ValueFromPipelineByPropertyName | Should Be $false
        ($command.Parameters.Keys -contains 'Path') | Should Be $true
        $command.Parameters['Path'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'Destination') | Should Be $true
        $command.Parameters['Destination'].ParameterType.FullName | Should Be 'System.String'
        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
        ($command.Parameters.Keys -contains 'HostFile') | Should Be $false
        ($command.Parameters.Keys -contains 'Recurse') | Should Be $false
    }

    It 'validates an empty path before opening a session' {
        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path ' ' -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'Path must not be empty.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'validates a missing path before opening a session' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.txt'

        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $missingPath -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be "File was not found: $missingPath"
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'validates a directory path before opening a session' {
        $directoryPath = Join-Path -Path $TestDrive -ChildPath 'DirectorySource'
        New-Item -ItemType Directory -Path $directoryPath | Out-Null

        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $directoryPath -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be "Path must refer to a file: $directoryPath"
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'validates an empty destination before opening a session' {
        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination "`t"

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Destination must not be empty.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'requires exactly one resolved target' {
        $result = Copy-WinPushItem -ComputerName $script:BlankTargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'At least one usable computer name is required.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'rejects array ComputerName input before opening a session' {
        $result = Copy-WinPushItem -ComputerName @($script:TargetName, $script:OtherTargetName) -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'Copy-WinPushItem requires exactly one target.'
        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:CopiedPaths).Count | Should Be 0
    }

    It 'uploads one validated file and returns success metadata' {
        $result = Copy-WinPushItem -ComputerName " $($script:TargetName) " -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt'
        $resolvedPath = (Get-Item -LiteralPath $script:FixtureFile).FullName

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'CopyFile'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        @($script:CopiedPaths).Count | Should Be 1
        $script:CopiedPaths[0] | Should Be $resolvedPath
        $script:CopiedDestinations[0] | Should Be 'C:\Remote\fixture.txt'
        $metadata = $result.Output[0]
        $metadata.Direction | Should Be 'Upload'
        $metadata.Source | Should Be $resolvedPath
        $metadata.Destination | Should Be 'C:\Remote\fixture.txt'
        $metadata.FileName | Should Be 'Copy-WinPushItem-Fixture.txt'
        $metadata.Length | Should Be (Get-Item -LiteralPath $script:FixtureFile).Length
    }

    It 'passes destination unchanged to the remote copy helper' {
        $destination = ' C:\Remote Folder\fixture.txt '

        Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination $destination | Out-Null

        $script:CopiedDestinations[0] | Should Be $destination
    }

    It 'returns a failed result when the copy fails and cleans up the session' {
        $script:CopyError = 'remote copy failed'

        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'remote copy failed'
        $result.Errors[0] | Should Be 'remote copy failed'
        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be 602
    }

    It 'returns a failed result when session creation fails' {
        $script:NewPSSessionError = 'connection failed'

        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt'

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'connection failed'
        $result.Errors[0] | Should Be 'connection failed'
        @($script:CopiedPaths).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'normalizes credential session failures without leaking distinctive secret material' {
        $secret = 'Distinctive-6.1-Credential-Secret!'
        $credential = Get-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt' -Credential $credential
        $diagnosticText = @(
            $result.ErrorMessage
            @($result.Errors)
            @($result.Output)
            @($result.Logs)
        ) -join "`n"

        $result.Succeeded | Should Be $false
        $result.ErrorMessage | Should Be 'PSRP file upload session creation failed for the target with the supplied credential.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
    }

    It 'does not send a credential argument to New-PSSession when omitted' {
        Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt' | Out-Null

        @($script:NewPSSessionCredentialSupplied).Count | Should Be 1
        $script:NewPSSessionCredentialSupplied[0] | Should Be $false
        @($script:NewPSSessionCredentials).Count | Should Be 0
    }

    It 'passes the supplied credential object unchanged to New-PSSession' {
        $credential = Get-TestCredential -Secret 'Distinctive-6.1-Credential-Secret!'

        $result = Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt' -Credential $credential

        $result.Succeeded | Should Be $true
        @($script:NewPSSessionCredentials).Count | Should Be 1
        [object]::ReferenceEquals($script:NewPSSessionCredentials[0], $credential) | Should Be $true
    }

    It 'removes the session after a successful upload' {
        Copy-WinPushItem -ComputerName $script:TargetName -Path $script:FixtureFile -Destination 'C:\Remote\fixture.txt' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be 602
    }
}
