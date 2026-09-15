$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:BuildPath = Join-Path -Path $script:RepoRoot -ChildPath 'build\build.ps1'
$script:SmokePath = Join-Path -Path $script:RepoRoot -ChildPath 'tests\Integration\Invoke-WinPushTransportSmoke.ps1'
$script:BuildText = Get-Content -LiteralPath $script:BuildPath -Raw

function Invoke-WinPushCommand {
    param(
        [string] $ComputerName,
        [string] $Command,
        [string] $Transport,
        [string] $PsExecPath
    )

    $null = $ComputerName, $Command, $Transport, $PsExecPath
}

Describe 'WinPush build gate' {
    It 'pins and invokes Pester 3.4.0 through the imported module command' {
        $script:BuildText | Should Match 'requiredPesterVersion = \[version\] ''3\.4\.0'''
        $script:BuildText | Should Match 'Where-Object \{ \$_\.Version -eq \$requiredPesterVersion \}'
        $script:BuildText | Should Match 'Import-Module -Name \$availablePester\.Path -Force -PassThru'
        $script:BuildText | Should Match '& \$invokePester @pesterParameters'
        $script:BuildText | Should Match 'Required Pester version \$requiredPesterVersion is not available\.'
        $script:BuildText | Should Not Match '(?i)\b(?:Install-Module|Save-Module|Invoke-WebRequest)\b'
    }

    It 'fails command coverage below 82.09 percent' {
        $script:BuildText | Should Match 'minimumCoveragePercent = 82\.09'
        $script:BuildText | Should Match '100 \* \$coverage\.NumberOfCommandsExecuted / \$coverage\.NumberOfCommandsAnalyzed'
        $script:BuildText | Should Match 'if \(\$coveragePercent -lt \$minimumCoveragePercent\)'
        $script:BuildText | Should Match 'below the required \$minimumCoveragePercent percent\.'
    }

    It 'imports the WinPush manifest once' {
        ([regex]::Matches($script:BuildText, 'Import-Module -Name \$manifestPath -Force')).Count | Should Be 1
    }

    It 'exposes distinct opt-in live target parameters' {
        $parameters = (Get-Command -Name $script:BuildPath).Parameters
        foreach ($name in @('PsrpTarget', 'WinRsTarget', 'PsExecTarget', 'PsExecPath')) {
            $parameters.ContainsKey($name) | Should Be $true
        }
    }

    It 'gates each live smoke on its matching target and passes the selected transport' {
        $script:BuildText | Should Match 'IsNullOrWhiteSpace\(\$PsrpTarget\)[\s\S]+-ComputerName \$PsrpTarget -Transport Psrp'
        $script:BuildText | Should Match 'IsNullOrWhiteSpace\(\$WinRsTarget\)[\s\S]+-ComputerName \$WinRsTarget -Transport WinRM'
        $script:BuildText | Should Match 'IsNullOrWhiteSpace\(\$PsExecTarget\)[\s\S]+-ComputerName \$PsExecTarget -Transport PsExec -PsExecPath \$PsExecPath'
        $script:BuildText | Should Not Match '\$env:'
    }

    It 'requires an explicit existing executable for a PsExec target' {
        $script:BuildText | Should Match 'PsExecTarget requires an explicit PsExecPath\.'
        $script:BuildText | Should Match 'PsExecPath must reference an existing \.exe file'
    }
}

Describe 'WinPush transport smoke command construction' {
    BeforeEach {
        Mock Import-Module {}
        Mock Invoke-WinPushCommand {
            [pscustomobject] @{
                Succeeded    = $true
                ErrorMessage = $null
            }
        }
    }

    It 'constructs a PSRP smoke command' {
        & $script:SmokePath -ComputerName 'psrp-target' -Transport Psrp | Out-Null

        Assert-MockCalled Invoke-WinPushCommand -Times 1 -Exactly -Scope It -ParameterFilter {
            $ComputerName -eq 'psrp-target' -and
            $Command -eq 'hostname' -and
            $Transport -eq 'Psrp'
        }
    }

    It 'constructs a WinRS smoke command' {
        & $script:SmokePath -ComputerName 'winrs-target' -Transport WinRM | Out-Null

        Assert-MockCalled Invoke-WinPushCommand -Times 1 -Exactly -Scope It -ParameterFilter {
            $ComputerName -eq 'winrs-target' -and
            $Command -eq 'hostname' -and
            $Transport -eq 'WinRM'
        }
    }

    It 'constructs a PsExec smoke command with only the explicit executable' {
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec.exe'
        New-Item -Path $psExecPath -ItemType File | Out-Null

        & $script:SmokePath -ComputerName 'psexec-target' -Transport PsExec -PsExecPath $psExecPath | Out-Null

        Assert-MockCalled Invoke-WinPushCommand -Times 1 -Exactly -Scope It -ParameterFilter {
            $ComputerName -eq 'psexec-target' -and
            $Command -eq 'hostname' -and
            $Transport -eq 'PsExec' -and
            $PsExecPath -eq (Get-Item -LiteralPath $psExecPath).FullName
        }
    }

    It 'does not invoke a PsExec smoke without an explicit valid path' {
        { & $script:SmokePath -ComputerName 'psexec-target' -Transport PsExec } |
            Should Throw 'PsExec transport smoke requires an explicit PsExecPath.'

        Assert-MockCalled Invoke-WinPushCommand -Times 0 -Exactly -Scope It
    }
}
