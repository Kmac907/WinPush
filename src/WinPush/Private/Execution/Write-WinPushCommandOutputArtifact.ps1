function ConvertTo-WinPushCommandArtifactText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]] $Value = @()
    )

    if ($null -eq $Value) {
        return [string[]]@()
    }

    [string[]] $lines = foreach ($item in @($Value)) {
        if ($null -eq $item) {
            ''
        }
        else {
            $text = [string] $item
            if ($text.Length -gt 0) {
                $text
            }
            else {
                $item | Format-List * | Out-String -Stream
            }
        }
    }

    if ($null -eq $lines) {
        return
    }

    $lines
}

function Write-WinPushCommandOutputArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [AllowNull()]
        [object[]] $Output = @(),

        [AllowNull()]
        [object[]] $Errors = @(),

        [AllowNull()]
        [string] $RunDirectory = $null
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        throw [System.ArgumentException]::new('OutputRoot must not be empty.')
    }

    $runDirectory = $RunDirectory

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
    $stdOutPath = Join-Path -Path $computerDirectory -ChildPath 'stdout.txt'
    $stdErrPath = Join-Path -Path $computerDirectory -ChildPath 'stderr.txt'

    $null = New-Item -Path $computerDirectory -ItemType Directory -Force

    [string[]] $stdOutLines = @(ConvertTo-WinPushCommandArtifactText -Value $Output)
    [string[]] $stdErrLines = @(ConvertTo-WinPushCommandArtifactText -Value $Errors)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    [System.IO.File]::WriteAllLines($stdOutPath, $stdOutLines, $utf8NoBom)
    [System.IO.File]::WriteAllLines($stdErrPath, $stdErrLines, $utf8NoBom)

    [pscustomobject] @{
        RunDirectory      = $runDirectory
        ComputerDirectory = $computerDirectory
        StdOutPath        = $stdOutPath
        StdErrPath        = $stdErrPath
    }
}
