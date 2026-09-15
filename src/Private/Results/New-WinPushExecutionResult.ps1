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
        [string] $ArtifactError = $null,

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
        [object] $PackageMetadata = $null,

        [AllowNull()]
        [string] $Script = $null
    )

    [object[]] $normalizedOutput = @($Output | Where-Object { $null -ne $_ })
    [object[]] $normalizedErrors = @($Errors | Where-Object { $null -ne $_ })
    [object[]] $normalizedLogs = @($Logs | Where-Object { $null -ne $_ })
    [object[]] $normalizedCopiedLogPaths = @($CopiedLogPaths | Where-Object { $null -ne $_ })

    if (-not $Succeeded -and [string]::IsNullOrWhiteSpace($ErrorMessage) -and $normalizedErrors.Count -gt 0) {
        $ErrorMessage = [string] $normalizedErrors[0]
    }

    $normalizedRunDirectory = if ([string]::IsNullOrWhiteSpace($RunDirectory)) { $null } else { $RunDirectory }
    $normalizedComputerDirectory = if ([string]::IsNullOrWhiteSpace($ComputerDirectory)) { $null } else { $ComputerDirectory }
    $normalizedResultPath = if ([string]::IsNullOrWhiteSpace($ResultPath)) { $null } else { $ResultPath }
    $normalizedStdOutPath = if ([string]::IsNullOrWhiteSpace($StdOutPath)) { $null } else { $StdOutPath }
    $normalizedStdErrPath = if ([string]::IsNullOrWhiteSpace($StdErrPath)) { $null } else { $StdErrPath }
    $normalizedScript = if ([string]::IsNullOrWhiteSpace($Script)) { $null } else { $Script }

    $result = [pscustomobject] [ordered] @{
        PSTypeName        = 'WinPush.ExecutionResult'
        ComputerName      = $ComputerName
        Transport         = $Transport
        Operation         = $Operation
        Succeeded         = $Succeeded
        ExitCode          = $ExitCode
        ErrorMessage      = $ErrorMessage
        ArtifactError     = $ArtifactError
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
        Script            = $normalizedScript
    }

    $operationTypeName = switch ($Operation) {
        'RunCommand' { 'WinPush.ExecutionResult.RunCommand' }
        'RunScript' { 'WinPush.ExecutionResult.RunScript' }
        'RunPackage' { 'WinPush.ExecutionResult.RunPackage' }
        'CopyFile' { 'WinPush.ExecutionResult.CopyFile' }
        'GetLogs' { 'WinPush.ExecutionResult.GetLogs' }
        'TestTarget' { 'WinPush.ExecutionResult.TestTarget' }
        default { $null }
    }

    if ($null -ne $operationTypeName) {
        $result.PSTypeNames.Insert(1, $operationTypeName)
    }

    $result
}
