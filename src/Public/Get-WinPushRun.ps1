function Get-WinPushRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Run directory was not found or is not a directory: $Path"
    }

    $runDirectory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $summaryPath = Join-Path -Path $runDirectory -ChildPath 'summary.csv'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "summary.csv was not found in run directory: $runDirectory"
    }

    $rowNumber = 0
    foreach ($row in @(Import-Csv -LiteralPath $summaryPath -ErrorAction Stop)) {
        $rowNumber++

        $succeeded = $false
        if (-not [bool]::TryParse([string] $row.Succeeded, [ref] $succeeded)) {
            throw "summary.csv row $rowNumber has invalid Succeeded value '$($row.Succeeded)'; expected True or False."
        }

        $exitCode = $null
        if (-not [string]::IsNullOrWhiteSpace([string] $row.ExitCode)) {
            $parsedExitCode = 0
            if (-not [int]::TryParse([string] $row.ExitCode, [ref] $parsedExitCode)) {
                throw "summary.csv row $rowNumber has invalid ExitCode value '$($row.ExitCode)'; expected a 32-bit integer or an empty value."
            }
            $exitCode = $parsedExitCode
        }

        $values = [ordered] @{}
        foreach ($property in $row.PSObject.Properties) {
            $values[$property.Name] = $property.Value
        }

        $targetLogPath = Join-Path -Path $runDirectory -ChildPath (
            Join-Path -Path (ConvertTo-WinPushArtifactTargetName -ComputerName $row.ComputerName) -ChildPath 'run.log'
        )
        $values['Succeeded'] = $succeeded
        $values['ExitCode'] = $exitCode
        $values['RunDirectory'] = $runDirectory
        $values['TargetLogPath'] = $targetLogPath
        $values['TargetLogExists'] = Test-Path -LiteralPath $targetLogPath -PathType Leaf

        $result = [pscustomobject] $values
        $result.PSObject.TypeNames.Insert(0, 'WinPush.RunResult')
        $result
    }
}
