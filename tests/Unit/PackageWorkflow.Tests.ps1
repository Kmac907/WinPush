$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:PackageCommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Invoke-WinPushPackage.ps1'

. $script:PackageCommandPath

Describe 'Invoke-WinPushPackage contract' {
    It 'defines the planned package source and target parameter sets' {
        $command = Get-Command Invoke-WinPushPackage
        $parameterSetNames = @($command.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object)

        ($parameterSetNames -join ',') | Should Be 'PathComputerName,PathHostFile,UriComputerName,UriHostFile'
    }

    It 'exposes only the planned package workflow parameters for item 11.1' {
        $command = Get-Command Invoke-WinPushPackage
        $parameterNames = @($command.Parameters.Keys | Sort-Object)

        foreach ($expectedParameter in @(
            'CaptureOutput',
            'Cleanup',
            'ComputerName',
            'Credential',
            'EntryPoint',
            'Extract',
            'HostFile',
            'Logs',
            'OutputRoot',
            'PackageCacheRoot',
            'Path',
            'RemoteStageRoot',
            'Uri'
        )) {
            ($parameterNames -contains $expectedParameter) | Should Be $true
        }

        ($parameterNames -contains 'PackageManifest') | Should Be $false
        ($parameterNames -contains 'Hash') | Should Be $false
        ($parameterNames -contains 'ArgumentList') | Should Be $false
        ($parameterNames -contains 'Transport') | Should Be $false
    }

    It 'keeps Path and Uri mutually exclusive' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -Uri 'https://storage.contoso.example/packages/EA.zip' -EntryPoint '.\Install-EA.ps1' } |
            Should Throw 'Parameter set cannot be resolved'
    }

    It 'rejects empty entry points before package workflow execution' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '   ' } |
            Should Throw 'EntryPoint must not be empty.'
    }

    It 'rejects empty output roots before package workflow execution when artifacts are requested' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '.\Install-EA.ps1' -CaptureOutput -OutputRoot '   ' } |
            Should Throw 'OutputRoot must not be empty.'
    }

    It 'fails locally until package staging is implemented' {
        { Invoke-WinPushPackage -ComputerName 'PC-001' -Path '.\Package.zip' -EntryPoint '.\Install-EA.ps1' } |
            Should Throw 'Invoke-WinPushPackage is not exported or executable until package staging is implemented in roadmap item 11.2.'
    }
}
