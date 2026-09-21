<#
.SYNOPSIS
Reads the summary from a captured WinPush run.

.DESCRIPTION
Imports summary.csv from an existing run directory, restores typed success and exit-code values, preserves the remaining row fields, and adds the run directory plus the mapped per-target log path and its availability.

.PARAMETER Path
An existing captured run directory containing summary.csv.

.EXAMPLE
Get-WinPushRun -Path C:\WinPush\20-09-2026-120000-00000000-0000-0000-0000-000000000000

Reads the captured summary and resolves each target log path.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
WinPush.RunResult

.NOTES
TargetLogPath uses the same safe target-directory mapping as artifact capture. Invalid boolean or integer values in summary.csv cause a terminating error.

.LINK
docs/commands.md#capture-layout-and-safe-target-paths
#>
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
