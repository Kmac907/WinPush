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
        elseif ($item -is [string] -or $item.GetType().IsValueType) {
            [string] $item
        }
        else {
            ConvertTo-Json -InputObject $item -Compress -Depth 5
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

        [string] $ArtifactIdentity = '',

        [AllowNull()]
        [bool] $Succeeded,

        [AllowNull()]
        [int] $ExitCode,

        [AllowNull()]
        [string] $ErrorMessage = $null,

        [AllowNull()]
        [object[]] $Output = @(),

        [AllowNull()]
        [object[]] $Errors = @(),

        [Parameter(Mandatory)]
        [System.Text.Encoding] $Encoding,

        [switch] $Append
    )

    [string[]] $resultLines = @(
        'WinPush Run Log'
        '==============='
        ''
        ('Timestamp    : {0}' -f (Get-Date -Format 'o'))
        ('ComputerName : {0}' -f $ComputerName)
        ('Operation    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Operation))
        ('Transport    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Transport))
        ('Identity     : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ArtifactIdentity))
        ('Succeeded    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Succeeded))
        ('ExitCode     : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ExitCode))
        ('ErrorMessage : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ErrorMessage))
        ''
        'Output:'
        (ConvertTo-WinPushCommandArtifactText -Value $Output)
        ''
        'Errors:'
        (ConvertTo-WinPushCommandArtifactText -Value $Errors)
        ''
        'ErrorMessage Detail:'
        (ConvertTo-WinPushResultArtifactValue -Value $ErrorMessage)
    )

    if ($Append) {
        $writer = [System.IO.StreamWriter]::new($ResultPath, $true, $Encoding)
        try {
            $writer.WriteLine()
            foreach ($line in $resultLines) {
                $writer.WriteLine($line)
            }
        }
        finally {
            $writer.Dispose()
        }
        return
    }

    [System.IO.File]::WriteAllLines($ResultPath, $resultLines, $Encoding)
}

function Write-WinPushCorrelatedRunLogArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunLogPath,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [string] $Operation = '',

        [string] $Transport = '',

        [string] $ArtifactIdentity = '',

        [AllowNull()]
        [bool] $Succeeded,

        [AllowNull()]
        [int] $ExitCode,

        [AllowNull()]
        [string] $ErrorMessage = $null,

        [AllowNull()]
        [object[]] $Output = @(),

        [AllowNull()]
        [object[]] $Errors = @(),

        [Parameter(Mandatory)]
        [string] $TargetResultPath,

        [Parameter(Mandatory)]
        [System.Text.Encoding] $Encoding
    )

    [string[]] $targetLines = @(
        'Target Result'
        '============='
        ''
        ('Timestamp    : {0}' -f (Get-Date -Format 'o'))
        ('ComputerName : {0}' -f $ComputerName)
        ('Operation    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Operation))
        ('Transport    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Transport))
        ('Identity     : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ArtifactIdentity))
        ('Succeeded    : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $Succeeded))
        ('ExitCode     : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ExitCode))
        ('ErrorMessage : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $ErrorMessage))
        ('TargetRunLog : {0}' -f (ConvertTo-WinPushResultArtifactValue -Value $TargetResultPath))
        ''
        'Output:'
        (ConvertTo-WinPushCommandArtifactText -Value $Output)
        ''
        'Errors:'
        (ConvertTo-WinPushCommandArtifactText -Value $Errors)
        ''
        'ErrorMessage Detail:'
        (ConvertTo-WinPushResultArtifactValue -Value $ErrorMessage)
    )

    if (Test-Path -LiteralPath $RunLogPath -PathType Leaf) {
        $appendLines = [string[]] @(
            ''
            '---'
            ''
        ) + $targetLines
        $writer = [System.IO.StreamWriter]::new($RunLogPath, $true, $Encoding)
        try {
            foreach ($line in $appendLines) {
                $writer.WriteLine($line)
            }
        }
        finally {
            $writer.Dispose()
        }
        return
    }

    [string[]] $runLines = @(
        'WinPush Correlated Run Log'
        '=========================='
        ''
    ) + $targetLines

    [System.IO.File]::WriteAllLines($RunLogPath, $runLines, $Encoding)
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
        $row | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8 -Append
        return
    }

    $row | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8
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

        [string] $ArtifactIdentity = '',

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
        $runDirectory = New-WinPushArtifactRunDirectory -OutputRoot $OutputRoot
    }

    $targetName = ConvertTo-WinPushArtifactTargetName -ComputerName $ComputerName
    $computerDirectory = Join-Path -Path $runDirectory -ChildPath $targetName
    $summaryPath = Join-Path -Path $runDirectory -ChildPath 'summary.csv'
    $runLogPath = Join-Path -Path $runDirectory -ChildPath 'run.log'
    $resultPath = Join-Path -Path $computerDirectory -ChildPath 'run.log'

    $null = New-Item -Path $computerDirectory -ItemType Directory -Force

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    $activeCaptureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
        Get-WinPushActiveCaptureContext
    }
    if ($null -ne $activeCaptureContext -and
        $activeCaptureContext.RunDirectory -eq $runDirectory -and
        $activeCaptureContext.ComputerName -eq $ComputerName) {
        foreach ($item in @($Output | Select-Object -Skip $activeCaptureContext.OutputRecordCount)) {
            Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Output -Value $item
        }
        foreach ($item in @($Errors | Select-Object -Skip $activeCaptureContext.ErrorRecordCount)) {
            Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Error -Value $item
        }
        if ($activeCaptureContext.ErrorRecordCount -eq 0 -and -not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
            Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Error -Value $ErrorMessage
        }
        Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Stage -Value 'Completed'

        if (-not $activeCaptureContext.FailedArtifacts.ContainsKey($resultPath)) {
            try {
                Write-WinPushResultArtifact `
                    -ResultPath $resultPath `
                    -ComputerName $ComputerName `
                    -Operation $Operation `
                    -Transport $Transport `
                    -ArtifactIdentity $ArtifactIdentity `
                    -Succeeded $Succeeded `
                    -ExitCode $ExitCode `
                    -ErrorMessage $ErrorMessage `
                    -Output $Output `
                    -Errors $Errors `
                    -Encoding $utf8NoBom `
                    -Append
            }
            catch {
                Set-WinPushCaptureArtifactFailure -Context $activeCaptureContext -Path $resultPath -Message $_.Exception.Message
            }
        }

        if (-not $activeCaptureContext.FailedArtifacts.ContainsKey($runLogPath)) {
            try {
                Write-WinPushCorrelatedRunLogArtifact `
                    -RunLogPath $runLogPath `
                    -ComputerName $ComputerName `
                    -Operation $Operation `
                    -Transport $Transport `
                    -ArtifactIdentity $ArtifactIdentity `
                    -Succeeded $Succeeded `
                    -ExitCode $ExitCode `
                    -ErrorMessage $ErrorMessage `
                    -Output $Output `
                    -Errors $Errors `
                    -TargetResultPath $resultPath `
                    -Encoding $utf8NoBom
            }
            catch {
                Set-WinPushCaptureArtifactFailure -Context $activeCaptureContext -Path $runLogPath -Message $_.Exception.Message
            }
        }

        if (-not $activeCaptureContext.FailedArtifacts.ContainsKey($summaryPath)) {
            try {
                Write-WinPushSummaryArtifact `
                    -SummaryPath $summaryPath `
                    -ComputerName $ComputerName `
                    -Operation $Operation `
                    -Transport $Transport `
                    -Succeeded $Succeeded `
                    -ExitCode $ExitCode `
                    -ErrorMessage $ErrorMessage `
                    -ResultPath $resultPath
            }
            catch {
                Set-WinPushCaptureArtifactFailure -Context $activeCaptureContext -Path $summaryPath -Message $_.Exception.Message
            }
        }

        return [pscustomobject] @{
            RunDirectory      = $runDirectory
            ComputerDirectory = $computerDirectory
            ResultPath        = $resultPath
            SummaryPath       = $summaryPath
            RunLogPath        = $runLogPath
            StdOutPath        = $null
            StdErrPath        = $null
        }
    }

    Write-WinPushResultArtifact `
        -ResultPath $resultPath `
        -ComputerName $ComputerName `
        -Operation $Operation `
        -Transport $Transport `
        -ArtifactIdentity $ArtifactIdentity `
        -Succeeded $Succeeded `
        -ExitCode $ExitCode `
        -ErrorMessage $ErrorMessage `
        -Output $Output `
        -Errors $Errors `
        -Encoding $utf8NoBom
    Write-WinPushCorrelatedRunLogArtifact `
        -RunLogPath $runLogPath `
        -ComputerName $ComputerName `
        -Operation $Operation `
        -Transport $Transport `
        -ArtifactIdentity $ArtifactIdentity `
        -Succeeded $Succeeded `
        -ExitCode $ExitCode `
        -ErrorMessage $ErrorMessage `
        -Output $Output `
        -Errors $Errors `
        -TargetResultPath $resultPath `
        -Encoding $utf8NoBom
    Write-WinPushSummaryArtifact `
        -SummaryPath $summaryPath `
        -ComputerName $ComputerName `
        -Operation $Operation `
        -Transport $Transport `
        -Succeeded $Succeeded `
        -ExitCode $ExitCode `
        -ErrorMessage $ErrorMessage `
        -ResultPath $resultPath

    [pscustomobject] @{
        RunDirectory      = $runDirectory
        ComputerDirectory = $computerDirectory
        ResultPath        = $resultPath
        SummaryPath       = $summaryPath
        RunLogPath        = $runLogPath
        StdOutPath        = $null
        StdErrPath        = $null
    }
}
