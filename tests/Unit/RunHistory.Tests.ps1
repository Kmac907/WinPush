$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:LogArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1'
$script:RunHistoryPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Public\Get-WinPushRun.ps1'

. $script:LogArtifactPath
. $script:RunHistoryPath

Describe 'Get-WinPushRun' {
    It 'requires an existing run directory containing summary.csv' {
        $missingDirectory = Join-Path -Path $TestDrive -ChildPath 'missing'
        { Get-WinPushRun -Path $missingDirectory } |
            Should Throw "Run directory was not found or is not a directory: $missingDirectory"

        $runDirectory = Join-Path -Path $TestDrive -ChildPath 'run'
        New-Item -ItemType Directory -Path $runDirectory | Out-Null
        { Get-WinPushRun -Path $runDirectory } |
            Should Throw "summary.csv was not found in run directory: $runDirectory"
    }

    It 'returns no results for an empty summary' {
        $runDirectory = Join-Path -Path $TestDrive -ChildPath 'empty'
        New-Item -ItemType Directory -Path $runDirectory | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $runDirectory -ChildPath 'summary.csv') `
            -Value '"ComputerName","Operation","Transport","Succeeded","ExitCode","ErrorMessage","ResultPath","StdOutPath","StdErrPath"'

        @(Get-WinPushRun -Path $runDirectory).Count | Should Be 0
    }

    It 'restores types, preserves row order and maps target log paths safely' {
        $runDirectory = Join-Path -Path $TestDrive -ChildPath 'rows'
        New-Item -ItemType Directory -Path $runDirectory | Out-Null
        @(
            [pscustomobject] [ordered] @{
                ComputerName = 'fe80::1'; Operation = 'RunCommand'; Transport = 'Psrp'
                Succeeded = 'True'; ExitCode = '0'; ErrorMessage = ''; ResultPath = 'original-one'
                StdOutPath = 'stdout-one'; StdErrPath = 'stderr-one'
            }
            [pscustomobject] [ordered] @{
                ComputerName = 'PC-002'; Operation = 'RunScript'; Transport = 'WinRs'
                Succeeded = 'False'; ExitCode = ''; ErrorMessage = 'failed'; ResultPath = 'original-two'
                StdOutPath = 'stdout-two'; StdErrPath = 'stderr-two'
            }
        ) | Export-Csv -LiteralPath (Join-Path -Path $runDirectory -ChildPath 'summary.csv') -NoTypeInformation

        $firstLog = Join-Path -Path $runDirectory -ChildPath 'fe80__1-6d6dc150\run.log'
        New-Item -ItemType Directory -Path (Split-Path -Path $firstLog -Parent) | Out-Null
        Set-Content -LiteralPath $firstLog -Value 'result'

        $results = @(Get-WinPushRun -Path (Join-Path -Path $runDirectory -ChildPath '.'))

        @($results).Count | Should Be 2
        ($results.ComputerName -join ',') | Should Be 'fe80::1,PC-002'
        $results[0].PSTypeNames[0] | Should Be 'WinPush.RunResult'
        $results[1].PSTypeNames[0] | Should Be 'WinPush.RunResult'
        $results[0].Succeeded.GetType().FullName | Should Be 'System.Boolean'
        $results[1].TargetLogExists.GetType().FullName | Should Be 'System.Boolean'
        $results[0].Succeeded | Should Be $true
        $results[1].Succeeded | Should Be $false
        $results[0].ExitCode.GetType().FullName | Should Be 'System.Int32'
        $results[0].ExitCode | Should Be 0
        $null -eq $results[1].ExitCode | Should Be $true
        $results[0].RunDirectory | Should Be (Resolve-Path -LiteralPath $runDirectory).Path
        $results[0].TargetLogPath | Should Be $firstLog
        $results[0].TargetLogExists | Should Be $true
        $results[1].TargetLogPath | Should Be (Join-Path -Path $runDirectory -ChildPath 'PC-002\run.log')
        $results[1].TargetLogExists | Should Be $false
        $results[0].Operation | Should Be 'RunCommand'
        $results[1].ErrorMessage | Should Be 'failed'
        $results[0].ResultPath | Should Be 'original-one'
        $results[1].StdErrPath | Should Be 'stderr-two'
    }

    It 'rejects malformed boolean and integer values with row context' {
        $runDirectory = Join-Path -Path $TestDrive -ChildPath 'malformed'
        New-Item -ItemType Directory -Path $runDirectory | Out-Null
        $summaryPath = Join-Path -Path $runDirectory -ChildPath 'summary.csv'

        [pscustomobject] @{ ComputerName = 'PC-001'; Succeeded = 'yes'; ExitCode = '0' } |
            Export-Csv -LiteralPath $summaryPath -NoTypeInformation
        { Get-WinPushRun -Path $runDirectory } |
            Should Throw "summary.csv row 1 has invalid Succeeded value 'yes'; expected True or False."

        [pscustomobject] @{ ComputerName = 'PC-001'; Succeeded = 'True'; ExitCode = 'not-an-int' } |
            Export-Csv -LiteralPath $summaryPath -NoTypeInformation
        { Get-WinPushRun -Path $runDirectory } |
            Should Throw "summary.csv row 1 has invalid ExitCode value 'not-an-int'; expected a 32-bit integer or an empty value."
    }
}
