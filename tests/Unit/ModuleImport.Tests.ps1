$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.psd1'

function New-TestExecutionResult {
    param(
        [string] $ComputerName = 'PC01',
        [string] $Operation = 'RunCommand',
        [bool] $Succeeded = $true,
        [AllowNull()]
        [Nullable[int]] $ExitCode = 0,
        [AllowNull()]
        [string] $ErrorMessage = $null,
        [object[]] $Output = @(),
        [object[]] $Errors = @(),
        [object[]] $Logs = @(),
        [AllowNull()]
        [string] $ResultPath = $null,
        [AllowNull()]
        [object] $PackageMetadata = $null,
        [object[]] $CopiedLogPaths = @()
    )

    $result = [pscustomobject] [ordered] @{
        PSTypeName        = 'WinPush.ExecutionResult'
        ComputerName      = $ComputerName
        Transport         = 'Psrp'
        Operation         = $Operation
        Succeeded         = $Succeeded
        ExitCode          = $ExitCode
        ErrorMessage      = $ErrorMessage
        Output            = $Output
        Errors            = $Errors
        Logs              = $Logs
        RunDirectory      = if ($ResultPath) { 'C:\WinPush\20260716-100000' } else { $null }
        ComputerDirectory = if ($ResultPath) { 'C:\WinPush\20260716-100000\PC01' } else { $null }
        ResultPath        = $ResultPath
        StdOutPath        = $null
        StdErrPath        = $null
        CopiedLogPaths    = $CopiedLogPaths
        PackageMetadata   = $PackageMetadata
    }

    $operationTypeName = switch ($Operation) {
        'RunCommand' { 'WinPush.ExecutionResult.RunCommand' }
        'RunScript' { 'WinPush.ExecutionResult.RunScript' }
        'RunPackage' { 'WinPush.ExecutionResult.RunPackage' }
        'CopyFile' { 'WinPush.ExecutionResult.CopyFile' }
        'GetLogs' { 'WinPush.ExecutionResult.GetLogs' }
        'TestTarget' { 'WinPush.ExecutionResult.TestTarget' }
        default { $null }
    }

    if ($null -ne $operationTypeName) {
        $result.PSTypeNames.Insert(1, $operationTypeName)
    }

    $result
}

Describe 'WinPush module import foundation' {
    It 'uses an explicit manifest export list' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath

        @($manifest.FunctionsToExport).Count | Should Be 6
        ($manifest.FunctionsToExport -join ',') | Should Be 'Copy-WinPushItem,Get-WinPushLog,Invoke-WinPushCommand,Invoke-WinPushPackage,Invoke-WinPushScript,Test-WinPushTarget'
        ($manifest.FunctionsToExport -notcontains '*') | Should Be $true
        ($manifest.FunctionsToExport -contains 'Invoke-WinPushPackage') | Should Be $true
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

    It 'formats RunCommand execution results as a concise command table' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $result = New-TestExecutionResult -Output @('first remote output', 'last remote output')

        $formatted = $result | Out-String -Width 220

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Status'
        $formatted | Should Match 'ExitCode'
        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'PC01'
        $formatted | Should Match 'OK'
        $formatted | Should Not Match 'Operation'
        $formatted | Should Not Match 'Details'
        $formatted | Should Not Match 'Artifacts'
        $formatted | Should Not Match 'RunCommand'
        $formatted | Should Not Match 'Succeeded'
        $formatted | Should Not Match 'ErrorMessage'
        $formatted | Should Not Match 'OutputPreview'
        $formatted | Should Not Match 'first remote output'
        $formatted | Should Not Match 'last remote output'
        $formatted | Should Not Match 'Transport'
        $formatted | Should Not Match '^Output\s+:'
        $formatted | Should Not Match '^Errors\s+:'
        $formatted | Should Not Match '^Logs\s+:'
        $formatted | Should Not Match 'RunDirectory'
        $formatted | Should Not Match 'ComputerDirectory'
        $formatted | Should Not Match 'ResultPath'
        $formatted | Should Not Match 'StdOutPath'
        $formatted | Should Not Match 'StdErrPath'

        ($result.Output -join ',') | Should Be 'first remote output,last remote output'
        $result.Transport | Should Be 'Psrp'
    }

    It 'keeps artifact paths off the default command table while preserving result properties' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $result = New-TestExecutionResult `
            -Output @('captured remote output') `
            -ResultPath 'C:\WinPush\20260716-100000\PC01\run.log'

        $formatted = $result | Out-String -Width 220

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Status'
        $formatted | Should Match 'ExitCode'
        $formatted | Should Not Match 'Artifacts'
        $formatted | Should Not Match 'captured remote output'
        $formatted | Should Not Match 'ResultPath'
        $formatted | Should Not Match 'run.log'
        $formatted | Should Not Match 'RunDirectory'
        $formatted | Should Not Match 'ComputerDirectory'
        $formatted | Should Not Match 'StdOutPath'
        $formatted | Should Not Match 'StdErrPath'
        $formatted | Should Not Match 'Transport'

        $result.ResultPath | Should Be 'C:\WinPush\20260716-100000\PC01\run.log'
        $null -eq $result.StdOutPath | Should Be $true
        $null -eq $result.StdErrPath | Should Be $true
    }

    It 'formats RunScript execution results as a concise script table' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $result = New-TestExecutionResult -Operation 'RunScript' -Output @('script output')

        $formatted = $result | Out-String -Width 220

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Status'
        $formatted | Should Match 'ExitCode'
        $formatted | Should Match 'Script'
        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'PC01'
        $formatted | Should Match 'OK'
        $formatted | Should Not Match 'Operation'
        $formatted | Should Not Match 'RunScript'
        $formatted | Should Not Match 'OutputPreview'
        $formatted | Should Not Match 'script output'

        $result.Output[0] | Should Be 'script output'
    }

    It 'formats long WinRM errors with a concise error summary' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $errorMessage = 'Connecting to remote server JK148H4 failed with the following error message: WinRM cannot complete the operation. Verify that the specified computer name is valid, that the computer is accessible over the network, and that a firewall exception for the WinRM service is enabled.'
        $result = New-TestExecutionResult `
            -ComputerName 'JK148H4' `
            -Succeeded $false `
            -ExitCode 1 `
            -ErrorMessage $errorMessage `
            -Errors @($errorMessage)

        $formatted = $result | Out-String -Width 220
        $normalized = $formatted -replace '\s+', ' '

        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'Failed'
        $formatted | Should Match 'WinRM cannot complete the operation'
        $normalized | Should Not Match 'Connecting to remote server JK148H4 failed'
        $normalized | Should Not Match 'firewall exception for the WinRM service is enabled'
        $formatted | Should Not Match 'ErrorMessage'
    }

    It 'formats RunPackage execution results as a package table' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $packageMetadata = [pscustomobject] [ordered] @{
            PSTypeName        = 'WinPush.PackageMetadata'
            PackageSourceType = 'Path'
            PackageSource     = 'C:\Packages\Agent.zip'
            LocalPackagePath  = 'C:\Packages\Agent.zip'
            RemoteStagePath   = 'C:\ProgramData\WinPush\Staging\run\Agent.zip'
            EntryPoint        = 'install.ps1'
            Extracted         = $true
            ExecutionStarted  = $null
            ExecutionEnded    = $null
            CleanupPolicy     = 'Never'
            CleanupSucceeded  = $null
            LogsCopied        = $false
            CopiedLogPaths    = @()
        }
        $result = New-TestExecutionResult -ComputerName 'PC02' -Operation 'RunPackage' -PackageMetadata $packageMetadata

        $formatted = $result | Out-String -Width 260

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Status'
        $formatted | Should Match 'ExitCode'
        $formatted | Should Match 'Package'
        $formatted | Should Match 'Cleanup'
        $formatted | Should Match 'Logs'
        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'PC02'
        $formatted | Should Match 'Agent.zip'
        $formatted | Should Match 'Retained'
        $formatted | Should Match 'No'
        $formatted | Should Not Match 'Details'
        $formatted | Should Not Match 'Artifacts'
        $formatted | Should Not Match 'PackageMetadata'
        $formatted | Should Not Match 'RemoteStagePath'
        $formatted | Should Not Match 'CopiedLogPaths'
        $formatted | Should Not Match 'Transport'
    }

    It 'formats CopyFile execution results as a copy table' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $copyMetadata = [pscustomobject] [ordered] @{
            Direction   = 'Upload'
            Source      = 'C:\Packages\agent.msi'
            Destination = 'C:\Temp\agent.msi'
            FileName    = 'agent.msi'
            Length      = 1024
        }
        $result = New-TestExecutionResult -ComputerName 'PC03' -Operation 'CopyFile' -Output @($copyMetadata)

        $formatted = $result | Out-String -Width 260

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Status'
        $formatted | Should Match 'Source'
        $formatted | Should Match 'Destination'
        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'PC03'
        $formatted | Should Match ([regex]::Escape('C:\Packages\agent.msi'))
        $formatted | Should Match ([regex]::Escape('C:\Temp\agent.msi'))
        $formatted | Should Not Match 'Direction'
        $formatted | Should Not Match 'Length'
        $formatted | Should Not Match 'Details'
        $formatted | Should Not Match 'Artifacts'
        $formatted | Should Not Match 'Transport'
    }

    It 'formats GetLogs execution results as a log table' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $logMetadata = [pscustomobject] [ordered] @{
            RemoteDirectory = 'C:\ProgramData\EA\Logs'
            RemotePath      = 'C:\ProgramData\EA\Logs\install.log'
            FileName        = 'install.log'
            Length          = 1024
        }
        $logResult = [pscustomobject] [ordered] @{
            PSTypeName   = 'WinPush.LogResult'
            ComputerName = 'PC03'
            RemotePath   = 'C:\ProgramData\EA\Logs'
            LocalPath    = 'C:\WinPush\run\PC03\Logs\install.log'
            Copied       = $true
            Error        = $null
        }
        $result = New-TestExecutionResult `
            -ComputerName 'PC04' `
            -Operation 'GetLogs' `
            -Output @($logMetadata) `
            -Logs @($logResult) `
            -CopiedLogPaths @('C:\WinPush\run\PC04\Logs\install.log') `
            -ResultPath 'C:\WinPush\run\PC04\run.log'

        $formatted = $result | Out-String -Width 260

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Status'
        $formatted | Should Match 'LogPath'
        $formatted | Should Match 'Files'
        $formatted | Should Match 'Destination'
        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'PC04'
        $formatted | Should Match ([regex]::Escape('C:\ProgramData\EA\Logs'))
        $formatted | Should Match '1'
        $formatted | Should Match ([regex]::Escape('C:\WinPush\run\PC04\Logs'))
        $formatted | Should Not Match 'Details'
        $formatted | Should Not Match 'Artifacts'
        $formatted | Should Not Match 'CopiedLogPaths'
        $formatted | Should Not Match 'Transport'
    }

    It 'formats TestTarget execution results as a reachability table' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        $result = New-TestExecutionResult -ComputerName 'PC05' -Operation 'TestTarget' -ExitCode $null

        $formatted = $result | Out-String -Width 220

        $formatted | Should Match 'ComputerName'
        $formatted | Should Match 'Reachable'
        $formatted | Should Match 'Transport'
        $formatted | Should Match 'ErrorSummary'
        $formatted | Should Match 'PC05'
        $formatted | Should Match 'True'
        $formatted | Should Match 'Psrp'
        $formatted | Should Not Match 'Status'
        $formatted | Should Not Match 'ExitCode'
        $formatted | Should Not Match 'Operation'
        $formatted | Should Not Match 'Details'
        $formatted | Should Not Match 'Artifacts'
    }

    It 'keeps transport implementation out of the root module' {
        $rootModule = Get-Content -Raw -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'WinPush.psm1')

        $rootModule | Should Not Match 'New-PSSession'
        $rootModule | Should Not Match 'Invoke-Command'
        $rootModule | Should Not Match 'Copy-Item'
        $rootModule | Should Not Match 'winrs'
        $rootModule | Should Not Match 'PsExec'
    }

    It 'exports the package workflow command after local file staging exists' {
        Remove-Module -Name WinPush -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force

        (Get-Command -Module WinPush -Name Invoke-WinPushPackage -ErrorAction Stop).Name | Should Be 'Invoke-WinPushPackage'
    }
}
