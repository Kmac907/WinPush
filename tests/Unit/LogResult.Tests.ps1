$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:FactoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Results\New-WinPushLogResult.ps1'

. $script:FactoryPath

Describe 'New-WinPushLogResult' {
    It 'creates a WinPush.LogResult with the exact result properties' {
        $result = New-WinPushLogResult -ComputerName 'PC-001' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -LocalPath 'C:\WinPush\10-07-2026-143012\PC-001\Logs\install.log' -Copied $true
        $propertyNames = @($result.PSObject.Properties.Name)

        $result.PSTypeNames[0] | Should Be 'WinPush.LogResult'
        ($propertyNames -join ',') | Should Be 'ComputerName,RemotePath,LocalPath,Copied,Error'
        ($propertyNames -contains 'Credential') | Should Be $false
        ($propertyNames -contains 'Password') | Should Be $false
        ($propertyNames -contains 'Content') | Should Be $false
    }

    It 'represents a successfully copied log file' {
        $result = New-WinPushLogResult -ComputerName 'PC-001' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -LocalPath 'C:\WinPush\10-07-2026-143012\PC-001\Logs\install.log' -Copied $true

        $result.ComputerName | Should Be 'PC-001'
        $result.RemotePath | Should Be 'C:\ProgramData\EA\Logs\Install-EA\install.log'
        $result.LocalPath | Should Be 'C:\WinPush\10-07-2026-143012\PC-001\Logs\install.log'
        $result.Copied | Should Be $true
        $null -eq $result.Error | Should Be $true
    }

    It 'represents a failed log file copy without a local path' {
        $result = New-WinPushLogResult -ComputerName 'PC-002' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -Copied $false -ErrorMessage 'Access denied'

        $result.ComputerName | Should Be 'PC-002'
        $result.RemotePath | Should Be 'C:\ProgramData\EA\Logs\Install-EA\install.log'
        $null -eq $result.LocalPath | Should Be $true
        $result.Copied | Should Be $false
        $result.Error | Should Be 'Access denied'
    }

    It 'rejects a successful copy without a local path' {
        { New-WinPushLogResult -ComputerName 'PC-003' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -Copied $true } | Should Throw 'LocalPath'
    }

    It 'rejects a successful copy with an error' {
        { New-WinPushLogResult -ComputerName 'PC-004' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -LocalPath 'C:\WinPush\run\PC-004\Logs\install.log' -Copied $true -ErrorMessage 'failed' } | Should Throw 'Error'
    }

    It 'rejects a failed copy with a local path' {
        { New-WinPushLogResult -ComputerName 'PC-005' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -LocalPath 'C:\WinPush\run\PC-005\Logs\install.log' -Copied $false -ErrorMessage 'Access denied' } | Should Throw 'LocalPath'
    }

    It 'rejects a failed copy without an error' {
        { New-WinPushLogResult -ComputerName 'PC-006' -RemotePath 'C:\ProgramData\EA\Logs\Install-EA\install.log' -Copied $false } | Should Throw 'Error'
    }
}
