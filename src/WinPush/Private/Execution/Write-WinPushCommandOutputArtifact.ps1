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

function ConvertTo-WinPushResultArtifactValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    [string] $Value
}

function Write-WinPushResultArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResultPath,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [string] $Operation = '',

        [string] $Transport = '',

        [AllowNull()]
        [bool] $Succeeded,

        [AllowNull()]
        [int] $ExitCode,

        [string] $StdOutPath = '',

        [string] $StdErrPath = '',

        [AllowNull()]
        [string] $ErrorMessage = $null,

        [Parameter(Mandatory)]
        [System.Text.Encoding] $Encoding
    )

    [string[]] $resultLines = @(
        'WinPush Result'
        '=============='
        ''
        ('ComputerName : {0}' -f $ComputerName)
        ('Operation    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Operation))
        ('Transport    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Transport))
        ('Succeeded    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Succeeded))
        ('ExitCode     : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ExitCode))
        ('StdOutPath   : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $StdOutPath))
        ('StdErrPath   : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $StdErrPath))
        ''
        'ErrorMessage:'
        (ConvertTo-WinPushResultArtifactValue -Value $ErrorMessage)
    )

    [System.IO.File]::WriteAllLines($ResultPath, $resultLines, $Encoding)
}

function Write-WinPushSummaryArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SummaryPath,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [string] $Operation = '',

        [string] $Transport = '',

        [AllowNull()]
        [bool] $Succeeded,

        [AllowNull()]
        [int] $ExitCode,

        [AllowNull()]
        [string] $ErrorMessage = $null,

        [string] $ResultPath = '',

        [string] $StdOutPath = '',

        [string] $StdErrPath = ''
    )

    $row = [pscustomobject] [ordered] @{
        ComputerName = $ComputerName
        Operation    = $Operation
        Transport    = $Transport
        Succeeded    = $Succeeded
        ExitCode     = $ExitCode
        ErrorMessage = $ErrorMessage
        ResultPath   = $ResultPath
        StdOutPath   = $StdOutPath
        StdErrPath   = $StdErrPath
    }

    if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
        $rows = @(
            Import-Csv -LiteralPath $SummaryPath
            $row
        )
        $rows | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation
        return
    }

    $row | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation
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
        [string] $RunDirectory = $null,

        [string] $Operation = '',

        [string] $Transport = '',

        [AllowNull()]
        [bool] $Succeeded,

        [AllowNull()]
        [int] $ExitCode,

        [AllowNull()]
        [string] $ErrorMessage = $null
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
    $summaryPath = Join-Path -Path $runDirectory -ChildPath 'summary.csv'
    $resultPath = Join-Path -Path $computerDirectory -ChildPath 'result.txt'
    $stdOutPath = Join-Path -Path $computerDirectory -ChildPath 'stdout.txt'
    $stdErrPath = Join-Path -Path $computerDirectory -ChildPath 'stderr.txt'

    $null = New-Item -Path $computerDirectory -ItemType Directory -Force

    [string[]] $stdOutLines = @(ConvertTo-WinPushCommandArtifactText -Value $Output)
    [string[]] $stdErrLines = @(ConvertTo-WinPushCommandArtifactText -Value $Errors)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    [System.IO.File]::WriteAllLines($stdOutPath, $stdOutLines, $utf8NoBom)
    [System.IO.File]::WriteAllLines($stdErrPath, $stdErrLines, $utf8NoBom)
    Write-WinPushResultArtifact `
        -ResultPath $resultPath `
        -ComputerName $ComputerName `
        -Operation $Operation `
        -Transport $Transport `
        -Succeeded $Succeeded `
        -ExitCode $ExitCode `
        -StdOutPath $stdOutPath `
        -StdErrPath $stdErrPath `
        -ErrorMessage $ErrorMessage `
        -Encoding $utf8NoBom
    Write-WinPushSummaryArtifact `
        -SummaryPath $summaryPath `
        -ComputerName $ComputerName `
        -Operation $Operation `
        -Transport $Transport `
        -Succeeded $Succeeded `
        -ExitCode $ExitCode `
        -ErrorMessage $ErrorMessage `
        -ResultPath $resultPath `
        -StdOutPath $stdOutPath `
        -StdErrPath $stdErrPath

    [pscustomobject] @{
        RunDirectory      = $runDirectory
        ComputerDirectory = $computerDirectory
        ResultPath        = $resultPath
        SummaryPath       = $summaryPath
        StdOutPath        = $stdOutPath
        StdErrPath        = $stdErrPath
    }
}
