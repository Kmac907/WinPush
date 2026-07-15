function New-WinPushLogArtifactDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [AllowNull()]
        [string] $RunDirectory = $null,

        [AllowNull()]
        [string] $ComputerDirectory = $null
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        throw [System.ArgumentException]::new('OutputRoot must not be empty.')
    }

    $runDirectory = $RunDirectory
    $computerDirectory = $ComputerDirectory

    if ([string]::IsNullOrWhiteSpace($computerDirectory)) {
        if ([string]::IsNullOrWhiteSpace($runDirectory)) {
            $runName = Get-Date -Format 'dd-MM-yyyy-HHmmss'
            $runDirectory = Join-Path -Path $OutputRoot -ChildPath $runName
            $suffix = 1

            while (Test-Path -LiteralPath $runDirectory) {
                $runDirectory = Join-Path -Path $OutputRoot -ChildPath ('{0}-{1}' -f $runName, $suffix)
                $suffix++
            }
        }

        $computerDirectory = Join-Path -Path $runDirectory -ChildPath $ComputerName
    }
    elseif ([string]::IsNullOrWhiteSpace($runDirectory)) {
        $runDirectory = Split-Path -Path $computerDirectory -Parent
    }

    $logDirectory = Join-Path -Path $computerDirectory -ChildPath 'Logs'
    $null = New-Item -Path $logDirectory -ItemType Directory -Force

    [pscustomobject] [ordered] @{
        RunDirectory      = $runDirectory
        ComputerDirectory = $computerDirectory
        LogDirectory      = $logDirectory
    }
}
