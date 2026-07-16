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

        $manifest.PowerShellVersion | Should Be '7.6'
        ($manifest.CompatiblePSEditions -join ',') | Should Be 'Core'
    }

    It 'registers the execution result status table format' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        ($manifest.FormatsToProcess -join ',') | Should Be 'WinPush.format.ps1xml'
        Test-Path -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.format.ps1xml') | Should Be $true
    }

    It 'formats execution results as a concise status table without raw output' {
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
            Output            = @('raw remote output')
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
        $formatted | Should Match 'PC01'
        $formatted | Should Match 'RunCommand'
        $formatted | Should Not Match 'Transport'
        $formatted | Should Not Match 'Output'
        $formatted | Should Not Match 'raw remote output'
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
