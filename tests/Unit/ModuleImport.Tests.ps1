$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.psd1'

Describe 'WinPush module import foundation' {
    It 'uses an explicit manifest export list' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        @($manifest.FunctionsToExport).Count | Should Be 5
        ($manifest.FunctionsToExport -join ',') | Should Be 'Copy-WinPushItem,Get-WinPushLog,Invoke-WinPushCommand,Invoke-WinPushScript,Test-WinPushTarget'
        ($manifest.FunctionsToExport -notcontains '*') | Should Be $true
    }

    It 'declares the approved PowerShell runtime and edition' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        $manifest.ModuleVersion | Should Be '0.1.0'
        $manifest.PowerShellVersion | Should Be '7.6'
        ($manifest.CompatiblePSEditions -join ',') | Should Be 'Core'
    }

    It 'registers the execution result status table format' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        ($manifest.FormatsToProcess -join ',') | Should Be 'WinPush.format.ps1xml'
        Test-Path -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.format.ps1xml') | Should Be $true
    }

    It 'keeps every manifest-declared format file in the package root' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        foreach ($fileName in @($manifest.FormatsToProcess)) {
            $filePath = Join-Path -Path $script:ModuleRoot -ChildPath $fileName

            Test-Path -LiteralPath $filePath -PathType Leaf | Should Be $true
        }
    }

    It 'formats uncaptured execution results as a readable status list with output preview' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $result = [pscustomobject] [ordered] @{
            PSTypeName        = 'WinPush.ExecutionResult'
            ComputerName      = 'PC01'
            Transport         = 'Psrp'
            Operation         = 'RunCommand'
            Succeeded         = $true
            ExitCode          = 0
            ErrorMessage      = $null
            Output            = @('first remote output', 'last remote output')
            Errors            = @()
            Logs              = @()
            RunDirectory      = $null
            ComputerDirectory = $null
            ResultPath        = $null
            StdOutPath        = $null
            StdErrPath        = $null
            CopiedLogPaths    = @()
        }

        $formatted = $result | Out-String

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Operation'
        $formatted | Should Match 'Succeeded'
        $formatted | Should Match 'ExitCode'
        $formatted | Should Match 'ErrorMessage'
        $formatted | Should Match 'OutputPreview'
        $formatted | Should Match 'PC01'
        $formatted | Should Match 'RunCommand'
        $formatted | Should Match 'last remote output'
        $formatted | Should Not Match 'first remote output'
        $formatted | Should Not Match 'Transport'
        $formatted | Should Not Match 'StdOutPath'
        $formatted | Should Not Match 'StdErrPath'
        $formatted | Should Not Match '^Output\s+:'
    }

    It 'formats captured execution results with output preview and artifact paths' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $result = [pscustomobject] [ordered] @{
            PSTypeName        = 'WinPush.ExecutionResult'
            ComputerName      = 'PC01'
            Transport         = 'Psrp'
            Operation         = 'RunCommand'
            Succeeded         = $true
            ExitCode          = 0
            ErrorMessage      = $null
            Output            = @('captured remote output')
            Errors            = @()
            Logs              = @()
            RunDirectory      = 'C:\WinPush\20260716-100000'
            ComputerDirectory = 'C:\WinPush\20260716-100000\PC01'
            ResultPath        = 'C:\WinPush\20260716-100000\PC01\result.txt'
            StdOutPath        = 'C:\WinPush\20260716-100000\PC01\stdout.txt'
            StdErrPath        = 'C:\WinPush\20260716-100000\PC01\stderr.txt'
            CopiedLogPaths    = @()
        }

        $formatted = $result | Out-String

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Operation'
        $formatted | Should Match 'Succeeded'
        $formatted | Should Match 'ExitCode'
        $formatted | Should Match 'OutputPreview'
        $formatted | Should Match 'captured remote output'
        $formatted | Should Match 'ErrorMessage'
        $formatted | Should Match 'StdOutPath'
        $formatted | Should Match 'stdout.txt'
        $formatted | Should Match 'StdErrPath'
        $formatted | Should Match 'stderr.txt'
        $formatted | Should Not Match 'Transport'
        $formatted | Should Not Match 'ComputerDirectory'
    }

    It 'does not truncate long execution error messages in the default view' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $errorMessage = 'Connecting to remote server JK148H4 failed with the following error message: WinRM cannot complete the operation. Verify that the specified computer name is valid, that the computer is accessible over the network, and that a firewall exception for the WinRM service is enabled.'
        $result = [pscustomobject] [ordered] @{
            PSTypeName        = 'WinPush.ExecutionResult'
            ComputerName      = 'JK148H4'
            Transport         = 'Psrp'
            Operation         = 'RunCommand'
            Succeeded         = $false
            ExitCode          = 1
            ErrorMessage      = $errorMessage
            Output            = @()
            Errors            = @($errorMessage)
            Logs              = @()
            RunDirectory      = $null
            ComputerDirectory = $null
            ResultPath        = $null
            StdOutPath        = $null
            StdErrPath        = $null
            CopiedLogPaths    = @()
        }

        $formatted = $result | Out-String -Width 72
        $normalized = $formatted -replace '\s+', ' '

        $formatted | Should Match 'ErrorMessage'
        $normalized | Should Match 'Connecting to remote server JK148H4 failed'
        $normalized | Should Match 'firewall exception for the WinRM service is enabled'
        $formatted | Should Not Match ([regex]::Escape([string] [char] 0x2026))
    }

    It 'keeps transport implementation out of the root module' {
        $rootModule = Get-Content -Raw -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.psm1')

        $rootModule | Should Not Match 'New-PSSession'
        $rootModule | Should Not Match 'Invoke-Command'
        $rootModule | Should Not Match 'Copy-Item'
        $rootModule | Should Not Match 'winrs'
        $rootModule | Should Not Match 'PsExec'
    }
}
