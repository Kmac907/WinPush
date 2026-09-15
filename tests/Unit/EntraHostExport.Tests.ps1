$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Export-WinPushHostFileFromEntraGroup.ps1'

. $script:CommandPath

function Get-MgContext {
    [CmdletBinding()]
    param()
}

function Get-MgGroup {
    [CmdletBinding()]
    param(
        [string] $Filter,
        [switch] $All
    )

    $null = $Filter
    $null = $All
}

function Get-MgGroupMember {
    [CmdletBinding()]
    param(
        [string] $GroupId,
        [switch] $All
    )

    $null = $GroupId
    $null = $All
}

function Get-MgGroupTransitiveMember {
    [CmdletBinding()]
    param(
        [string] $GroupId,
        [switch] $All
    )

    $null = $GroupId
    $null = $All
}

function New-TestEntraMember {
    param(
        [string] $DisplayName,
        [bool] $AccountEnabled = $true,
        [string] $Type = '#microsoft.graph.device'
    )

    [pscustomobject] @{
        AdditionalProperties = @{
            '@odata.type'   = $Type
            'displayName'    = $DisplayName
            'accountEnabled' = $AccountEnabled
        }
    }
}

Describe 'Export-WinPushHostFileFromEntraGroup' {
    BeforeEach {
        $script:GraphContext = [pscustomobject] @{ Account = 'operator@contoso.com' }
        $script:Groups = @([pscustomobject] @{ Id = 'group-from-name' })
        $script:DirectMembers = @(New-TestEntraMember -DisplayName 'PC-001')
        $script:TransitiveMembers = @(New-TestEntraMember -DisplayName 'PC-TRANSITIVE')
        $script:DirectGroupIds = @()
        $script:TransitiveGroupIds = @()
        $script:GroupFilters = @()
        $script:DirectError = $null
        $script:GroupError = $null
    }

    Mock Get-MgContext {
        $script:GraphContext
    }

    Mock Get-MgGroup {
        if ($null -ne $script:GroupError) {
            throw $script:GroupError
        }

        $script:GroupFilters += $Filter
        $script:Groups
    }

    Mock Get-MgGroupMember {
        if ($null -ne $script:DirectError) {
            throw $script:DirectError
        }

        $script:DirectGroupIds += $GroupId
        $script:DirectMembers
    }

    Mock Get-MgGroupTransitiveMember {
        $script:TransitiveGroupIds += $GroupId
        $script:TransitiveMembers
    }

    It 'exposes mutually exclusive ID and name parameter sets with the requested switches' {
        $command = Get-Command -Name Export-WinPushHostFileFromEntraGroup
        $parameterSets = @($command.ParameterSets)

        $parameterSets.Count | Should Be 2
        ($parameterSets.Name -contains 'GroupId') | Should Be $true
        ($parameterSets.Name -contains 'GroupName') | Should Be $true
        (($parameterSets | Where-Object Name -eq 'GroupId').Parameters.Name -contains 'GroupId') | Should Be $true
        (($parameterSets | Where-Object Name -eq 'GroupName').Parameters.Name -contains 'GroupName') | Should Be $true

        foreach ($parameterName in @('OutputPath', 'IncludeDisabled', 'Append', 'PassThru', 'Transitive')) {
            ($command.Parameters.Keys -contains $parameterName) | Should Be $true
        }
    }

    It 'uses a supplied group ID with direct membership by default' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'direct.txt'

        Export-WinPushHostFileFromEntraGroup -GroupId 'direct-group' -OutputPath $outputPath

        @(Get-Content -LiteralPath $outputPath) | Should Be @('PC-001')
        $script:DirectGroupIds | Should Be @('direct-group')
        Assert-MockCalled Get-MgGroup -Times 0 -Scope It
        Assert-MockCalled Get-MgGroupTransitiveMember -Times 0 -Scope It
    }

    It 'resolves one exact group name and escapes apostrophes in the Graph filter' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'named.txt'

        Export-WinPushHostFileFromEntraGroup -GroupName "Ops' Group" -OutputPath $outputPath

        $script:GroupFilters | Should Be @("displayName eq 'Ops'' Group'")
        $script:DirectGroupIds | Should Be @('group-from-name')
        @(Get-Content -LiteralPath $outputPath) | Should Be @('PC-001')
    }

    It 'rejects a missing group name before changing the output file' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing.txt'
        Set-Content -LiteralPath $outputPath -Value 'keep-me'
        $script:Groups = @()

        { Export-WinPushHostFileFromEntraGroup -GroupName 'Missing' -OutputPath $outputPath } |
            Should Throw "No Entra group named 'Missing' was found."

        Get-Content -Raw -LiteralPath $outputPath | Should Match '^keep-me'
        Assert-MockCalled Get-MgGroupMember -Times 0 -Scope It
    }

    It 'rejects an ambiguous group name before changing the output file' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'ambiguous.txt'
        Set-Content -LiteralPath $outputPath -Value 'keep-me'
        $script:Groups = @(
            [pscustomobject] @{ Id = 'group-1' }
            [pscustomobject] @{ Id = 'group-2' }
        )

        { Export-WinPushHostFileFromEntraGroup -GroupName 'Duplicate' -OutputPath $outputPath } |
            Should Throw "More than one Entra group named 'Duplicate' was found"

        Get-Content -Raw -LiteralPath $outputPath | Should Match '^keep-me'
        Assert-MockCalled Get-MgGroupMember -Times 0 -Scope It
    }

    It 'uses flattened transitive membership only when requested' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'transitive.txt'

        Export-WinPushHostFileFromEntraGroup -GroupId 'nested-group' -OutputPath $outputPath -Transitive

        $script:TransitiveGroupIds | Should Be @('nested-group')
        @(Get-Content -LiteralPath $outputPath) | Should Be @('PC-TRANSITIVE')
        Assert-MockCalled Get-MgGroupMember -Times 0 -Scope It
    }

    It 'writes unique enabled device names and discards other directory objects and blanks' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'filtered.txt'
        $script:DirectMembers = @(
            (New-TestEntraMember -DisplayName ' PC-001 ')
            (New-TestEntraMember -DisplayName 'pc-001')
            (New-TestEntraMember -DisplayName 'PC-DISABLED' -AccountEnabled $false)
            (New-TestEntraMember -DisplayName 'someone@contoso.com' -Type '#microsoft.graph.user')
            (New-TestEntraMember -DisplayName '   ')
            [pscustomobject] @{ DisplayName = 'PC-NOT-A-GRAPH-DEVICE' }
            (New-TestEntraMember -DisplayName 'PC-002')
        )

        $written = @(Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath -PassThru)

        @(Get-Content -LiteralPath $outputPath) | Should Be @('PC-001', 'PC-002')
        $written | Should Be @('PC-001', 'PC-002')
    }

    It 'includes disabled device names only when requested' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'disabled.txt'
        $script:DirectMembers = @(
            (New-TestEntraMember -DisplayName 'PC-ENABLED')
            (New-TestEntraMember -DisplayName 'PC-DISABLED' -AccountEnabled $false)
        )

        Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath -IncludeDisabled

        @(Get-Content -LiteralPath $outputPath) | Should Be @('PC-ENABLED', 'PC-DISABLED')
    }

    It 'appends only new names case-insensitively and passes through only names written' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'append.txt'
        Set-Content -LiteralPath $outputPath -Value @('PC-001', 'keep-existing')
        $script:DirectMembers = @(
            (New-TestEntraMember -DisplayName 'pc-001')
            (New-TestEntraMember -DisplayName 'PC-002')
            (New-TestEntraMember -DisplayName 'pc-002')
        )

        $written = @(Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath -Append -PassThru)

        @(Get-Content -LiteralPath $outputPath) | Should Be @('PC-001', 'keep-existing', 'PC-002')
        $written | Should Be @('PC-002')
    }

    It 'fails without an authenticated Graph context before changing the output file' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-context.txt'
        Set-Content -LiteralPath $outputPath -Value 'keep-me'
        $script:GraphContext = $null

        { Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath } |
            Should Throw 'No authenticated Microsoft Graph context is available.'

        Get-Content -Raw -LiteralPath $outputPath | Should Match '^keep-me'
        Assert-MockCalled Get-MgGroupMember -Times 0 -Scope It
    }

    It 'propagates Graph authorization failures before changing the output file' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'forbidden.txt'
        Set-Content -LiteralPath $outputPath -Value 'keep-me'
        $script:DirectError = 'Authorization_RequestDenied'

        { Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath } |
            Should Throw 'Authorization_RequestDenied'

        Get-Content -Raw -LiteralPath $outputPath | Should Match '^keep-me'
    }

    It 'does not declare Microsoft Graph as a manifest dependency' {
        $manifestText = Get-Content -Raw -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.psd1')

        $manifestText | Should Not Match 'Microsoft\.Graph'
    }

    It 'fails on missing required Graph commands before changing the output file' {
        Mock Get-Command {
            if ($Name -eq $script:MissingCommand) {
                return $null
            }

            [pscustomobject] @{ Name = $Name }
        }

        foreach ($missingCommand in @('Get-MgContext', 'Get-MgGroup', 'Get-MgGroupMember', 'Get-MgGroupTransitiveMember')) {
            $script:MissingCommand = $missingCommand
            $outputPath = Join-Path -Path $TestDrive -ChildPath "$missingCommand.txt"
            Set-Content -LiteralPath $outputPath -Value 'keep-me'

            $invocation = switch ($missingCommand) {
                'Get-MgGroup' {
                    { Export-WinPushHostFileFromEntraGroup -GroupName 'Group' -OutputPath $outputPath }
                }
                'Get-MgGroupTransitiveMember' {
                    { Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath -Transitive }
                }
                default {
                    { Export-WinPushHostFileFromEntraGroup -GroupId 'group-id' -OutputPath $outputPath }
                }
            }

            $invocation | Should Throw "Required Microsoft Graph command '$missingCommand' is not available."
            Get-Content -Raw -LiteralPath $outputPath | Should Match '^keep-me'
        }

        Assert-MockCalled Get-MgContext -Times 0 -Scope It
    }
}
