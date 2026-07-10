$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:ResultFactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Results\New-WinPushExecutionResult.ps1'
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public\Test-WinPushTarget.ps1'

. $script:ResolverPath
. $script:ResultFactoryPath
. $script:CommandPath

Describe 'Test-WinPushTarget' {
    BeforeEach {
        $script:NewPSSessionComputerNames = @()
        $script:RemovedSessionIds = @()
        $script:SessionToReturn = [pscustomobject] @{ Id = 101; ComputerName = 'PC-001' }
        $script:NewPSSessionError = $null
        $script:NewPSSessionCredentialSupplied = $false
    }

    Mock New-PSSession {
        $script:NewPSSessionComputerNames += $ComputerName
        $script:NewPSSessionCredentialSupplied = $PSBoundParameters.ContainsKey('Credential')

        if ($null -ne $script:NewPSSessionError) {
            throw $script:NewPSSessionError
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
    }

    It 'rejects multiple direct targets without opening a session' {
        $threw = $false
        try {
            Test-WinPushTarget -ComputerName @('PC-001', 'PC-002') -ErrorAction Stop
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Match 'exactly 1|exactly one'
        }

        $threw | Should Be $true
        @($script:NewPSSessionComputerNames).Count | Should Be 0
    }

    It 'has no credential parameter' {
        $command = Get-Command -Name Test-WinPushTarget

        ($command.Parameters.Keys -contains 'Credential') | Should Be $false
    }
}
