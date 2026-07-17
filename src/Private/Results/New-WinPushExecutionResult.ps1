function New-WinPushExecutionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $Transport,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter(Mandatory)]
        [bool] $Succeeded,

        [Parameter(Mandatory)]
        [AllowNull()]
        [Nullable[int]] $ExitCode,

        [AllowNull()]
        [string] $ErrorMessage = $null,

        [AllowNull()]
        [object[]] $Output = @(),

        [AllowNull()]
        [object[]] $Errors = @(),

        [AllowNull()]
        [object[]] $Logs = @(),

        [AllowNull()]
        [string] $RunDirectory = $null,

        [AllowNull()]
        [string] $ComputerDirectory = $null,

        [AllowNull()]
        [string] $ResultPath = $null,

        [AllowNull()]
        [string] $StdOutPath = $null,

        [AllowNull()]
        [string] $StdErrPath = $null,

        [AllowNull()]
        [object[]] $CopiedLogPaths = @(),

        [AllowNull()]
        [object] $PackageMetadata = $null
    )

    [object[]] $normalizedOutput = @()
    if ($null -ne $Output) {
        $normalizedOutput = @($Output)
    }

    [object[]] $normalizedErrors = @()
    if ($null -ne $Errors) {
        $normalizedErrors = @($Errors)
    }

    [object[]] $normalizedLogs = @()
    if ($null -ne $Logs) {
        $normalizedLogs = @($Logs)
    }

    [object[]] $normalizedCopiedLogPaths = @()
    if ($null -ne $CopiedLogPaths) {
        $normalizedCopiedLogPaths = @($CopiedLogPaths)
    }

    if (-not $Succeeded -and [string]::IsNullOrWhiteSpace($ErrorMessage) -and $normalizedErrors.Count -gt 0) {
        $ErrorMessage = [string] $normalizedErrors[0]
    }

    $normalizedRunDirectory = if ([string]::IsNullOrWhiteSpace($RunDirectory)) { $null } else { $RunDirectory }
    $normalizedComputerDirectory = if ([string]::IsNullOrWhiteSpace($ComputerDirectory)) { $null } else { $ComputerDirectory }
    $normalizedResultPath = if ([string]::IsNullOrWhiteSpace($ResultPath)) { $null } else { $ResultPath }
    $normalizedStdOutPath = if ([string]::IsNullOrWhiteSpace($StdOutPath)) { $null } else { $StdOutPath }
    $normalizedStdErrPath = if ([string]::IsNullOrWhiteSpace($StdErrPath)) { $null } else { $StdErrPath }

    [pscustomobject] [ordered] @{
        PSTypeName        = 'WinPush.ExecutionResult'
        ComputerName      = $ComputerName
        Transport         = $Transport
        Operation         = $Operation
        Succeeded         = $Succeeded
        ExitCode          = $ExitCode
        ErrorMessage      = $ErrorMessage
        Output            = $normalizedOutput
        Errors            = $normalizedErrors
        Logs              = $normalizedLogs
        RunDirectory      = $normalizedRunDirectory
        ComputerDirectory = $normalizedComputerDirectory
        ResultPath        = $normalizedResultPath
        StdOutPath        = $normalizedStdOutPath
        StdErrPath        = $normalizedStdErrPath
        CopiedLogPaths    = $normalizedCopiedLogPaths
        PackageMetadata   = $PackageMetadata
    }
}
