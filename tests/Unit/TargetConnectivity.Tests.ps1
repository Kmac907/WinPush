$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Test-WinPushTarget.ps1'
$script:FixtureRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\Fixtures\TargetResolution')

. $script:ResolverPath
. $script:ResultFactoryPath
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

Describe 'Test-WinPushTarget' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 101; ComputerName = 'PC-001' }
        $script:NewPSSessionError = $null
        $script:NewPSSessionErrorsByComputerName = @{}
        $script:NewPSSessionCredentialSupplied = $false
        $script:NewPSSessionCredential = $null
    }

    Mock New-PSSession {
        param(
            [string] $ComputerName,
            [System.Management.Automation.PSCredential] $Credential
        )

        $script:NewPSSessionComputerNames += $ComputerName
        $script:NewPSSessionCredentialSupplied = $PSBoundParameters.ContainsKey('Credential')
        if ($script:NewPSSessionCredentialSupplied) {
            $script:NewPSSessionCredential = $Credential
        }

        if ($null -ne $script:NewPSSessionError) {
            throw $script:NewPSSessionError
        }

        if ($script:NewPSSessionErrorsByComputerName.ContainsKey($ComputerName)) {
            throw $script:NewPSSessionErrorsByComputerName[$ComputerName]
        }

        return $script:SessionToReturn
    }

    Mock Remove-PSSession {
        $script:RemovedSessionIds += $Id
    }

    It 'returns a successful PSRP test-target result when a session is created' {
        $result = Test-WinPushTarget -ComputerName 'PC-001'

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'TestTarget'
        $result.Succeeded | Should Be $true
        $null -eq $result.ExitCode | Should Be $true
        [string]::IsNullOrEmpty($result.ErrorMessage) | Should Be $true
        @($result.Errors).Count | Should Be 0
        @($result.Output).Count | Should Be 0
        @($result.Logs).Count | Should Be 0
    }

    It 'returns a failed PSRP test-target result when session creation fails' {
        $script:NewPSSessionError = 'connection failed'

        $result = Test-WinPushTarget -ComputerName 'PC-001'

        $result.ComputerName | Should Be 'PC-001'
        $result.Transport | Should Be 'Psrp'
        $result.Operation | Should Be 'TestTarget'
        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'connection failed'
        @($result.Errors).Count | Should Be 1
        $result.Errors[0] | Should Be 'connection failed'
    }

    It 'removes a created session after a successful test' {
        Test-WinPushTarget -ComputerName 'PC-001' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 1
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
    }

    It 'does not remove a session when session creation fails before returning one' {
        $script:NewPSSessionError = 'connection failed'

        Test-WinPushTarget -ComputerName 'PC-001' | Out-Null

        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'resolves direct single-target input before opening a session' {
        $result = Test-WinPushTarget -ComputerName ' PC-001 '

        $result.ComputerName | Should Be 'PC-001'
        @($script:NewPSSessionComputerNames).Count | Should Be 1
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
    }

    It 'does not send a credential argument to New-PSSession' {
        Test-WinPushTarget -ComputerName 'PC-001' | Out-Null

        $script:NewPSSessionCredentialSupplied | Should Be $false
        $null -eq $script:NewPSSessionCredential | Should Be $true
    }

    It 'passes the supplied credential object unchanged to New-PSSession' {
        $credential = New-TestCredential -Secret 'Distinctive-3.2-Secret!'

        $result = Test-WinPushTarget -ComputerName 'PC-001' -Credential $credential

        $result.Succeeded | Should Be $true
        $script:NewPSSessionCredentialSupplied | Should Be $true
        [object]::ReferenceEquals($script:NewPSSessionCredential, $credential) | Should Be $true
    }

    It 'normalizes credential failures without leaking distinctive secret material' {
        $secret = 'Distinctive-3.2-Secret!'
        $credential = New-TestCredential -Secret $secret
        $script:NewPSSessionError = "authentication failed for $secret"

        $result = Test-WinPushTarget -ComputerName 'PC-001' -Credential $credential 5>&1 4>&1 3>&1
        $diagnosticText = @(
            $result.ErrorMessage
            @($result.Errors)
            @($result.Output)
            @($result.Logs)
        ) -join "`n"

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 1
        $result.ErrorMessage | Should Be 'PSRP session creation failed for the target with the supplied credential.'
        $diagnosticText | Should Not Match ([regex]::Escape($secret))
    }

    It 'does not write credential secret material to diagnostic streams' {
        $secret = 'Distinctive-3.2-Secret!'
        $credential = New-TestCredential -Secret $secret

        $diagnostics = Test-WinPushTarget -ComputerName 'PC-001' -Credential $credential 5>&1 4>&1 3>&1
        $diagnosticText = @($diagnostics | ForEach-Object { $_ | Out-String }) -join "`n"

        $diagnosticText | Should Not Match ([regex]::Escape($secret))
    }

    It 'processes multiple direct targets sequentially' {
        $results = @(Test-WinPushTarget -ComputerName @(' PC-001 ', 'PC-002'))

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $true

        @($script:NewPSSessionComputerNames).Count | Should Be 2
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        $script:NewPSSessionComputerNames[1] | Should Be 'PC-002'

        @($script:RemovedSessionIds).Count | Should Be 2
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
        $script:RemovedSessionIds[1] | Should Be $script:SessionToReturn.Id
    }

    It 'continues processing direct targets after a target fails' {
        $script:NewPSSessionErrorsByComputerName['PC-002'] = 'connection failed for PC-002'

        $results = @(Test-WinPushTarget -ComputerName @('PC-001', 'PC-002', 'PC-003'))

        @($results).Count | Should Be 3
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[2].ComputerName | Should Be 'PC-003'

        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[2].Succeeded | Should Be $true
        $results[1].ExitCode | Should Be 1
        $results[1].ErrorMessage | Should Be 'connection failed for PC-002'
        $results[1].Errors[0] | Should Be 'connection failed for PC-002'

        @($script:NewPSSessionComputerNames).Count | Should Be 3
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        $script:NewPSSessionComputerNames[1] | Should Be 'PC-002'
        $script:NewPSSessionComputerNames[2] | Should Be 'PC-003'

        @($script:RemovedSessionIds).Count | Should Be 2
        $script:RemovedSessionIds[0] | Should Be $script:SessionToReturn.Id
        $script:RemovedSessionIds[1] | Should Be $script:SessionToReturn.Id
    }

    It 'processes pipeline string targets sequentially' {
        $results = @(@(' PC-001 ', 'PC-002') | Test-WinPushTarget)

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $true

        @($script:NewPSSessionComputerNames).Count | Should Be 2
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        $script:NewPSSessionComputerNames[1] | Should Be 'PC-002'

        @($script:RemovedSessionIds).Count | Should Be 2
    }

    It 'processes pipeline objects by ComputerName property sequentially' {
        $inputObjects = @(
            [pscustomobject] @{ ComputerName = 'PC-001' }
            [pscustomobject] @{ ComputerName = ' PC-002 ' }
        )

        $results = @($inputObjects | Test-WinPushTarget)

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be 'PC-002'
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        $script:NewPSSessionComputerNames[1] | Should Be 'PC-002'
        @($script:RemovedSessionIds).Count | Should Be 2
    }

    It 'continues processing pipeline targets after a target fails' {
        $script:NewPSSessionErrorsByComputerName['PC-002'] = 'connection failed for PC-002'

        $results = @(@('PC-001', 'PC-002', 'PC-003') | Test-WinPushTarget)

        @($results).Count | Should Be 3
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be 'PC-002'
        $results[2].ComputerName | Should Be 'PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[2].Succeeded | Should Be $true
        $results[1].ExitCode | Should Be 1
        $results[1].ErrorMessage | Should Be 'connection failed for PC-002'
        @($script:RemovedSessionIds).Count | Should Be 2
    }

    It 'processes host file targets sequentially' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'

        $results = @(Test-WinPushTarget -HostFile $hostFile)

        @($results).Count | Should Be 2
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be 'PC-002'
        $script:NewPSSessionComputerNames[0] | Should Be 'PC-001'
        $script:NewPSSessionComputerNames[1] | Should Be 'PC-002'
        @($script:RemovedSessionIds).Count | Should Be 2
    }

    It 'continues processing host file targets after a target fails' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'valid-hosts.txt'
        $utf8Target = 'pc-utf8-{0}01' -f [char] 0x00e9
        $script:NewPSSessionErrorsByComputerName[$utf8Target] = "connection failed for $utf8Target"

        $results = @(Test-WinPushTarget -HostFile $hostFile)

        @($results).Count | Should Be 3
        $results[0].ComputerName | Should Be 'PC-001'
        $results[1].ComputerName | Should Be $utf8Target
        $results[2].ComputerName | Should Be 'PC-003'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[2].Succeeded | Should Be $true
        $results[1].ExitCode | Should Be 1
        $results[1].ErrorMessage | Should Be "connection failed for $utf8Target"
        @($script:RemovedSessionIds).Count | Should Be 2
    }

    It 'fails invalid host files before opening a session' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'missing-hosts.txt'

        { Test-WinPushTarget -HostFile $hostFile } | Should Throw 'Host file was not found:'

        @($script:NewPSSessionComputerNames).Count | Should Be 0
        @($script:RemovedSessionIds).Count | Should Be 0
    }

    It 'has an optional credential parameter' {
        $command = Get-Command -Name Test-WinPushTarget

        ($command.Parameters.Keys -contains 'Credential') | Should Be $true
        $command.Parameters['Credential'].ParameterType.FullName | Should Be 'System.Management.Automation.PSCredential'
    }

    It 'accepts pipeline and host file target sources' {
        $command = Get-Command -Name Test-WinPushTarget
        $computerNameAttributes = @($command.Parameters['ComputerName'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })

        ($command.Parameters.Keys -contains 'HostFile') | Should Be $true
        $command.Parameters['HostFile'].ParameterType.FullName | Should Be 'System.String'
        @($computerNameAttributes | Where-Object { $_.ValueFromPipeline }).Count | Should Be 1
        @($computerNameAttributes | Where-Object { $_.ValueFromPipelineByPropertyName }).Count | Should Be 1
    }
}
