function New-WinPushCaptureContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunDirectory,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter(Mandatory)]
        [string] $Transport,

        [string] $ArtifactIdentity = ''
    )

    $context = [pscustomobject] [ordered] @{
        PSTypeName        = 'WinPush.CaptureContext'
        RunDirectory     = $RunDirectory
        RootLogPath      = Join-Path -Path $RunDirectory -ChildPath 'run.log'
        Operation        = $Operation
        Transport        = $Transport
        ArtifactIdentity = $ArtifactIdentity
        ComputerName     = $null
        ComputerDirectory = $null
        ResultPath       = $null
        ArtifactError    = $null
        FailedArtifacts  = @{}
        OutputRecordCount = 0
        ErrorRecordCount = 0
    }

    try {
        [System.IO.File]::WriteAllLines(
            $context.RootLogPath,
            [string[]] @('WinPush Correlated Run Log', '==========================', ''),
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        Set-WinPushCaptureArtifactFailure -Context $context -Path $context.RootLogPath -Message $_.Exception.Message
    }

    Write-WinPushCaptureRecord -Context $context -Type Operation -Value $Operation -RootOnly
    $context
}

function Start-WinPushCaptureTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [string] $Transport = $Context.Transport
    )

    $Context.ComputerName = $ComputerName
    $Context.Transport = $Transport
    $targetName = ConvertTo-WinPushArtifactTargetName -ComputerName $ComputerName
    $Context.ComputerDirectory = Join-Path -Path $Context.RunDirectory -ChildPath $targetName
    $Context.ResultPath = Join-Path -Path $Context.ComputerDirectory -ChildPath 'run.log'
    $Context.OutputRecordCount = 0
    $Context.ErrorRecordCount = 0

    try {
        [System.IO.Directory]::CreateDirectory($Context.ComputerDirectory) | Out-Null
        [System.IO.File]::WriteAllLines(
            $Context.ResultPath,
            [string[]] @(
                'WinPush Run Log'
                '==============='
                ''
                ('Timestamp    : {0}' -f (Get-Date -Format 'o'))
                ('ComputerName : {0}' -f $ComputerName)
                ('Operation    : {0}' -f $Context.Operation)
                ('Transport    : {0}' -f $Transport)
                ('Identity     : {0}' -f $Context.ArtifactIdentity)
                ''
                'Events:'
            ),
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        Set-WinPushCaptureArtifactFailure -Context $Context -Path $Context.ResultPath -Message $_.Exception.Message
    }

    Write-WinPushCaptureRecord -Context $Context -Type Operation -Value $Context.Operation
    Write-WinPushCaptureRecord -Context $Context -Type Target -Value $ComputerName
    $Context
}

function Write-WinPushCaptureRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateSet('Operation', 'Target', 'Stage', 'Output', 'Error', 'Log')]
        [string] $Type,

        [AllowNull()]
        [object] $Value,

        [switch] $RootOnly
    )

    if (-not $RootOnly -and $Type -eq 'Output') {
        $Context.OutputRecordCount++
    }
    elseif (-not $RootOnly -and $Type -eq 'Error') {
        $Context.ErrorRecordCount++
    }
    $paths = @($Context.RootLogPath)
    if (-not $RootOnly -and -not [string]::IsNullOrWhiteSpace($Context.ResultPath)) {
        $paths += $Context.ResultPath
    }

    foreach ($path in $paths) {
        if ($Context.FailedArtifacts.ContainsKey($path)) {
            continue
        }

        try {
            $text = if ($null -eq $Value) {
                ''
            }
            elseif ($Value -is [string] -or $Value.GetType().IsValueType) {
                [string] $Value
            }
            else {
                ConvertTo-Json -InputObject $Value -Compress -Depth 5
            }
            $line = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'o'), $Type, $text, [Environment]::NewLine
            [System.IO.File]::AppendAllText($path, $line, [System.Text.UTF8Encoding]::new($false))
        }
        catch {
            Set-WinPushCaptureArtifactFailure -Context $Context -Path $path -Message $_.Exception.Message
        }
    }
}

function Set-WinPushCaptureArtifactFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Message
    )

    $Context.FailedArtifacts[$Path] = $true
    $Context.ArtifactError = if ([string]::IsNullOrWhiteSpace($Context.ArtifactError)) {
        $Message
    }
    else {
        '{0}; {1}' -f $Context.ArtifactError, $Message
    }
}

function Get-WinPushActiveCaptureContext {
    [CmdletBinding()]
    param()

    $context = Get-Variable -Name captureContext -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $context -and $context.PSTypeNames -contains 'WinPush.CaptureContext') {
        $context
    }
}
