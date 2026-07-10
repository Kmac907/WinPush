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
        [object[]] $Output = @(),

        [AllowNull()]
        [object[]] $Errors = @(),

        [AllowNull()]
        [object[]] $Logs = @()
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

    [pscustomobject] @{
        PSTypeName   = 'WinPush.ExecutionResult'
        ComputerName = $ComputerName
        Transport    = $Transport
        Operation    = $Operation
        Succeeded    = $Succeeded
        ExitCode     = $ExitCode
        Output       = $normalizedOutput
        Errors       = $normalizedErrors
        Logs         = $normalizedLogs
    }
}
