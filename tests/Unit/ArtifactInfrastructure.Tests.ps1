$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:LogArtifactPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1'
$script:ArtifactWriterPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Write-WinPushCommandOutputArtifact.ps1'

. $script:LogArtifactPath
. $script:ArtifactWriterPath

Describe 'Artifact infrastructure' {
    It 'allocates unique timestamp-guid run directories concurrently' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'ConcurrentRuns'
        $jobs = @()

        try {
            $jobs = @(1..8 | ForEach-Object {
                    Start-Job -ScriptBlock {
                        . $args[0]
                        New-WinPushArtifactRunDirectory -OutputRoot $args[1]
                    } -ArgumentList $script:LogArtifactPath, $outputRoot
                })
            $jobs | Wait-Job | Out-Null
            $runDirectories = @($jobs | Receive-Job)
        }
        finally {
            $jobs | Remove-Job -Force
        }

        @($runDirectories).Count | Should Be 8
        @($runDirectories | Select-Object -Unique).Count | Should Be 8
        foreach ($runDirectory in $runDirectories) {
            (Split-Path -Path $runDirectory -Leaf) | Should Match '^\d{2}-\d{2}-\d{4}-\d{6}-[0-9a-f]{32}$'
            Test-Path -LiteralPath $runDirectory -PathType Container | Should Be $true
        }
    }

    It 'leaves safe target names unchanged' {
        ConvertTo-WinPushArtifactTargetName -ComputerName 'safe-host.example' | Should Be 'safe-host.example'

        $boundaryName = 'a' * 255
        ConvertTo-WinPushArtifactTargetName -ComputerName $boundaryName | Should Be $boundaryName
    }

    It 'sanitizes unsafe and reserved target names with deterministic SHA-256 suffixes' {
        ConvertTo-WinPushArtifactTargetName -ComputerName 'fe80::1' | Should Be 'fe80__1-6d6dc150'
        ConvertTo-WinPushArtifactTargetName -ComputerName 'fe80::1' | Should Be 'fe80__1-6d6dc150'
        ConvertTo-WinPushArtifactTargetName -ComputerName 'CON' | Should Be 'CON-a3dbc4b6'
        ConvertTo-WinPushArtifactTargetName -ComputerName 'bad/name' | Should Match '^bad_name-[0-9a-f]{8}$'
    }

    It 'truncates overlong safe and unsafe names to valid component lengths' {
        foreach ($computerName in @(('b' * 256), (('c' * 255) + ':'))) {
            $targetName = ConvertTo-WinPushArtifactTargetName -ComputerName $computerName

            $targetName.Length | Should Be 255
            $targetName | Should Match '^[bc]{246}-[0-9a-f]{8}$'
        }
    }

    It 'uses the truncated tail when hashing otherwise identical prefixes' {
        $prefix = 'd' * 246
        $first = ConvertTo-WinPushArtifactTargetName -ComputerName ($prefix + 'tail-alpha')
        $second = ConvertTo-WinPushArtifactTargetName -ComputerName ($prefix + 'tail-bravo')

        $first.Substring(0, 246) | Should Be $second.Substring(0, 246)
        $first | Should Not Be $second
    }

    It 'sanitizes superscript COM and LPT reserved names case-insensitively with extensions' {
        foreach ($deviceName in @('COM', 'LPT')) {
            foreach ($superscript in @([char] 0x00b9, [char] 0x00b2, [char] 0x00b3)) {
                $reservedName = $deviceName + $superscript
                foreach ($computerName in @($reservedName, ($reservedName.ToLowerInvariant() + '.txt'))) {
                    $targetName = ConvertTo-WinPushArtifactTargetName -ComputerName $computerName
                    $expectedPrefix = $computerName.Replace('.', '_')
                    $targetName | Should Match ('^{0}-[0-9a-f]{{8}}$' -f [regex]::Escape($expectedPrefix))
                }
            }
        }
    }

    It 'contains traversal-like target artifacts and preserves the original ComputerName' {
        $runDirectory = Join-Path -Path $TestDrive -ChildPath 'TraversalRun'
        [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
        $computerName = '..\..\escaped'

        $artifact = Write-WinPushCommandOutputArtifact `
            -OutputRoot $TestDrive `
            -RunDirectory $runDirectory `
            -ComputerName $computerName `
            -Output 'done' `
            -Succeeded $true `
            -ExitCode 0

        $canonicalRunDirectory = [System.IO.Path]::GetFullPath($runDirectory).TrimEnd('\') + '\'
        $canonicalComputerDirectory = [System.IO.Path]::GetFullPath($artifact.ComputerDirectory)
        $canonicalComputerDirectory.StartsWith($canonicalRunDirectory, [System.StringComparison]::OrdinalIgnoreCase) |
            Should Be $true
        (Split-Path -Path $artifact.ComputerDirectory -Leaf) | Should Match '^\.\._\.\._escaped-[0-9a-f]{8}$'
        (Import-Csv -LiteralPath $artifact.SummaryPath).ComputerName | Should Be $computerName
        (Get-Content -LiteralPath $artifact.ResultPath -Raw) | Should Match 'ComputerName : \.\.\\\.\.\\escaped'
    }

    It 'uses a valid artifact directory for an IPv6 target' {
        $artifact = New-WinPushLogArtifactDirectory -OutputRoot $TestDrive -ComputerName 'fe80::1'

        (Split-Path -Path $artifact.ComputerDirectory -Leaf) | Should Be 'fe80__1-6d6dc150'
        Test-Path -LiteralPath $artifact.LogDirectory -PathType Container | Should Be $true
    }

    It 'keeps scalar text and serializes nested values as compact depth-five JSON' {
        $nested = [pscustomobject] [ordered] @{
            Name  = 'root'
            Child = [pscustomobject] [ordered] @{
                Level2 = [pscustomobject] [ordered] @{
                    Level3 = [pscustomobject] [ordered] @{
                        Value = 'deep'
                    }
                }
            }
        }

        @(ConvertTo-WinPushCommandArtifactText -Value 'plain text')[0] | Should Be 'plain text'
        @(ConvertTo-WinPushCommandArtifactText -Value $nested)[0] |
            Should Be '{"Name":"root","Child":{"Level2":{"Level3":{"Value":"deep"}}}}'
    }

    It 'appends complete rows to an existing summary' {
        $runDirectory = Join-Path -Path $TestDrive -ChildPath 'SharedRun'
        [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null

        Write-WinPushCommandOutputArtifact `
            -OutputRoot $TestDrive `
            -RunDirectory $runDirectory `
            -ComputerName 'PC-001' `
            -Operation 'RunCommand' `
            -Transport 'Psrp' `
            -Succeeded $true `
            -ExitCode 0 | Out-Null
        Write-WinPushCommandOutputArtifact `
            -OutputRoot $TestDrive `
            -RunDirectory $runDirectory `
            -ComputerName 'PC-002' `
            -Operation 'RunCommand' `
            -Transport 'Psrp' `
            -Succeeded $false `
            -ExitCode 1 `
            -ErrorMessage 'failed' | Out-Null

        $rows = @(Import-Csv -LiteralPath (Join-Path -Path $runDirectory -ChildPath 'summary.csv'))
        @($rows).Count | Should Be 2
        ($rows.ComputerName -join ',') | Should Be 'PC-001,PC-002'
        $rows[1].Operation | Should Be 'RunCommand'
        $rows[1].Transport | Should Be 'Psrp'
        $rows[1].Succeeded | Should Be 'False'
        $rows[1].ExitCode | Should Be '1'
        $rows[1].ErrorMessage | Should Be 'failed'
        $rows[1].ResultPath | Should Match 'PC-002\\run.log$'
    }
}
