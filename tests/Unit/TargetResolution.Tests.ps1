$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ResolverPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private\Targeting\Resolve-WinPushTarget.ps1'
$script:FixtureRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\Fixtures\TargetResolution')

. $script:ResolverPath

Describe 'Resolve-WinPushTarget' {
    It 'resolves one direct computer name' {
        $targets = @(Resolve-WinPushTarget -ComputerName 'PC-001')

        $targets.Count | Should Be 1
        $targets[0] | Should Be 'PC-001'
    }

    It 'resolves multiple direct computer names in input order' {
        $targets = @(Resolve-WinPushTarget -ComputerName @('PC-001', 'PC-002', 'PC-003'))

        $targets.Count | Should Be 3
        ($targets -join ',') | Should Be 'PC-001,PC-002,PC-003'
    }

    It 'trims leading and trailing whitespace from direct computer names' {
        $targets = @(Resolve-WinPushTarget -ComputerName @(' PC-001 ', "`tPC-002`r`n"))

        $targets.Count | Should Be 2
        ($targets -join ',') | Should Be 'PC-001,PC-002'
    }

    It 'removes unusable blank direct values without changing useful target order' {
        $targets = @(Resolve-WinPushTarget -ComputerName @('', ' ', 'PC-001', "`t", 'PC-002'))

        $targets.Count | Should Be 2
        ($targets -join ',') | Should Be 'PC-001,PC-002'
    }

    It 'fails locally when no usable direct target remains' {
        { Resolve-WinPushTarget -ComputerName @('', ' ', "`t") } | Should Throw 'At least one usable computer name is required.'
    }

    It 'resolves pipeline string computer names in input order' {
        $targets = @(@('PC-001', 'PC-002', 'PC-003') | Resolve-WinPushTarget)

        $targets.Count | Should Be 3
        ($targets -join ',') | Should Be 'PC-001,PC-002,PC-003'
    }

    It 'trims and removes unusable blank pipeline string values' {
        $targets = @(@(' PC-001 ', '', "`t", "`r`nPC-002 ") | Resolve-WinPushTarget)

        $targets.Count | Should Be 2
        ($targets -join ',') | Should Be 'PC-001,PC-002'
    }

    It 'resolves pipeline objects by ComputerName property in input order' {
        $inputObjects = @(
            [pscustomobject] @{ ComputerName = 'PC-001' }
            [pscustomobject] @{ ComputerName = ' PC-002 ' }
            [pscustomobject] @{ ComputerName = 'PC-003' }
        )

        $targets = @($inputObjects | Resolve-WinPushTarget)

        $targets.Count | Should Be 3
        ($targets -join ',') | Should Be 'PC-001,PC-002,PC-003'
    }

    It 'removes unusable blank pipeline property values without changing useful target order' {
        $inputObjects = @(
            [pscustomobject] @{ ComputerName = '' }
            [pscustomobject] @{ ComputerName = 'PC-001' }
            [pscustomobject] @{ ComputerName = ' ' }
            [pscustomobject] @{ ComputerName = 'PC-002' }
        )

        $targets = @($inputObjects | Resolve-WinPushTarget)

        $targets.Count | Should Be 2
        ($targets -join ',') | Should Be 'PC-001,PC-002'
    }

    It 'resolves mixed pipeline batches in pipeline order' {
        $targets = @(
            'PC-001'
            [pscustomobject] @{ ComputerName = ' PC-002 ' }
            ''
            ' PC-003 '
            [pscustomobject] @{ ComputerName = 'PC-004' }
        ) | Resolve-WinPushTarget

        $targets.Count | Should Be 4
        ($targets -join ',') | Should Be 'PC-001,PC-002,PC-003,PC-004'
    }

    It 'fails locally when no usable pipeline target remains' {
        { @('', ' ', "`t") | Resolve-WinPushTarget } | Should Throw 'At least one usable computer name is required.'
    }

    It 'resolves UTF-8 host file targets in file order' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'valid-hosts.txt'
        $utf8Target = 'pc-utf8-{0}01' -f [char] 0x00e9

        $targets = @(Resolve-WinPushTarget -HostFile $hostFile)

        $targets.Count | Should Be 3
        ($targets -join ',') | Should Be "PC-001,$utf8Target,PC-003"
    }

    It 'ignores host file comments and blanks without removing duplicates' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'duplicate-comment-hosts.txt'

        $targets = @(Resolve-WinPushTarget -HostFile $hostFile)

        $targets.Count | Should Be 3
        ($targets -join ',') | Should Be 'PC-001,PC-001,PC-002'
    }

    It 'fails locally when the host file path is missing' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'missing-hosts.txt'

        { Resolve-WinPushTarget -HostFile $hostFile } | Should Throw 'Host file was not found:'
    }

    It 'fails locally when the host file path is a directory' {
        { Resolve-WinPushTarget -HostFile $script:FixtureRoot } | Should Throw 'Host file path must reference a file:'
    }

    It 'fails locally when the host file is empty' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'empty-hosts.txt'

        { Resolve-WinPushTarget -HostFile $hostFile } | Should Throw 'At least one usable computer name is required.'
    }

    It 'fails locally when the host file contains only comments and blanks' {
        $hostFile = Join-Path -Path $script:FixtureRoot -ChildPath 'comments-only-hosts.txt'

        { Resolve-WinPushTarget -HostFile $hostFile } | Should Throw 'At least one usable computer name is required.'
    }

    It 'does not contain network or remoting calls' {
        $source = Get-Content -LiteralPath $script:ResolverPath -Raw

        $source | Should Not Match 'New-PSSession|Invoke-Command|Test-Connection|Resolve-DnsName|Test-WSMan|winrs|psexec'
    }
}
