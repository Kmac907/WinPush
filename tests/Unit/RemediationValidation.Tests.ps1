$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:CommandPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Test-WinPushRemediation.ps1'

. $script:CommandPath

Describe 'Test-WinPushRemediation' {
    BeforeEach {
        $script:DetectPath = Join-Path -Path $TestDrive -ChildPath 'detect.ps1'
        $script:RemediatePath = Join-Path -Path $TestDrive -ChildPath 'remediate.ps1'
        Set-Content -LiteralPath $script:DetectPath -Value "if (`$true) { exit 0 }`nexit 1"
        Set-Content -LiteralPath $script:RemediatePath -Value "throw 'must not execute'"
    }

    It 'returns a typed valid result with resolved paths and array diagnostics without executing scripts' {
        $result = Test-WinPushRemediation -DetectScript $script:DetectPath -RemediateScript $script:RemediatePath

        $result.PSTypeNames[0] | Should Be 'WinPush.RemediationValidationResult'
        $result.IsValid | Should Be $true
        $result.DetectScriptPath | Should Be $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:DetectPath)
        $result.RemediateScriptPath | Should Be $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:RemediatePath)
        $result.Errors -is [string[]] | Should Be $true
        $result.Warnings -is [string[]] | Should Be $true
        $result.Errors.Count | Should Be 0
        $result.Warnings.Count | Should Be 0
    }

    It 'reports missing paths in input order without opening a session' {
        Mock New-PSSession { throw 'must not open a session' }
        $missingDetect = Join-Path -Path $TestDrive -ChildPath 'missing-detect.ps1'
        $missingRemediate = Join-Path -Path $TestDrive -ChildPath 'missing-remediate.ps1'

        $result = Test-WinPushRemediation -DetectScript $missingDetect -RemediateScript $missingRemediate

        $result.IsValid | Should Be $false
        $result.Errors.Count | Should Be 2
        $result.Errors[0] | Should Be "DetectScript was not found: '$missingDetect'."
        $result.Errors[1] | Should Be "RemediateScript was not found: '$missingRemediate'."
        Assert-MockCalled New-PSSession -Times 0
    }

    It 'reports directories in input order' {
        $result = Test-WinPushRemediation -DetectScript $TestDrive -RemediateScript $TestDrive

        $result.IsValid | Should Be $false
        $result.Errors.Count | Should Be 2
        $result.Errors[0] | Should Be "DetectScript must be a .ps1 file, but a directory was provided: '$TestDrive'."
        $result.Errors[1] | Should Be "RemediateScript must be a .ps1 file, but a directory was provided: '$TestDrive'."
    }

    It 'reports non-ps1 files in input order' {
        $detectText = Join-Path -Path $TestDrive -ChildPath 'detect.txt'
        $remediateText = Join-Path -Path $TestDrive -ChildPath 'remediate.txt'
        Set-Content -LiteralPath $detectText -Value 'exit 0'
        Set-Content -LiteralPath $remediateText -Value 'exit 0'

        $result = Test-WinPushRemediation -DetectScript $detectText -RemediateScript $remediateText

        $result.IsValid | Should Be $false
        $result.Errors.Count | Should Be 2
        $result.Errors[0] | Should Be "DetectScript must have a .ps1 extension: '$detectText'."
        $result.Errors[1] | Should Be "RemediateScript must have a .ps1 extension: '$remediateText'."
    }

    It 'reports an unreadable script' {
        $stream = [System.IO.File]::Open(
            $script:RemediatePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        try {
            $result = Test-WinPushRemediation -DetectScript $script:DetectPath -RemediateScript $script:RemediatePath
        }
        finally {
            $stream.Dispose()
        }

        $result.IsValid | Should Be $false
        $result.Errors.Count | Should Be 1
        $result.Errors[0] | Should Match '^RemediateScript could not be read:'
    }

    It 'returns each Windows PowerShell 5.1 parser error with its script and location' {
        Set-Content -LiteralPath $script:DetectPath -Value 'if ($true) {'

        $result = Test-WinPushRemediation -DetectScript $script:DetectPath -RemediateScript $script:RemediatePath

        $result.IsValid | Should Be $false
        $result.Errors.Count | Should Be 1
        $result.Errors[0] | Should Match '^DetectScript has a Windows PowerShell 5\.1 parser error at line 1, column \d+:'
        $result.Warnings.Count | Should Be 0
    }

    It 'rejects syntax accepted only by newer PowerShell versions' {
        Set-Content -LiteralPath $script:RemediatePath -Value '$value = $true ? 1 : 0'

        $result = Test-WinPushRemediation -DetectScript $script:DetectPath -RemediateScript $script:RemediatePath

        $result.IsValid | Should Be $false
        $result.Errors.Count | Should BeGreaterThan 0
        $result.Errors[0] | Should Match '^RemediateScript has a Windows PowerShell 5\.1 parser error'
    }

    It 'warns for each missing literal detection exit without invalidating the result' {
        Set-Content -LiteralPath $script:DetectPath -Value 'exit $LASTEXITCODE'

        $result = Test-WinPushRemediation -DetectScript $script:DetectPath -RemediateScript $script:RemediatePath

        $result.IsValid | Should Be $true
        $result.Warnings.Count | Should Be 2
        $result.Warnings[0] | Should Be "DetectScript does not contain a literal 'exit 0' path."
        $result.Warnings[1] | Should Be "DetectScript does not contain a literal 'exit 1' path."
    }

    It 'warns about reboot commands without rejecting the scripts' {
        Set-Content -LiteralPath $script:RemediatePath -Value "Restart-Computer -Force`nshutdown.exe /r /t 0"

        $result = Test-WinPushRemediation -DetectScript $script:DetectPath -RemediateScript $script:RemediatePath

        $result.IsValid | Should Be $true
        $result.Warnings.Count | Should Be 2
        $result.Warnings[0] | Should Be 'RemediateScript contains a reboot command at line 1: Restart-Computer -Force'
        $result.Warnings[1] | Should Be 'RemediateScript contains a reboot command at line 2: shutdown.exe /r /t 0'
    }
}
