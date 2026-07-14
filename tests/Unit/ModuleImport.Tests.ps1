$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\WinPush')
$script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.psd1'

Describe 'WinPush module import foundation' {
    It 'uses an explicit manifest export list' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        @($manifest.FunctionsToExport).Count | Should Be 4
        ($manifest.FunctionsToExport -join ',') | Should Be 'Copy-WinPushItem,Invoke-WinPushCommand,Invoke-WinPushScript,Test-WinPushTarget'
        ($manifest.FunctionsToExport -notcontains '*') | Should Be $true
    }

    It 'declares the approved PowerShell runtime and edition' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        $manifest.PowerShellVersion | Should Be '7.6'
        ($manifest.CompatiblePSEditions -join ',') | Should Be 'Core'
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
