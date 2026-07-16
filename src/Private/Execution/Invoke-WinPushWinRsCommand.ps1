function Invoke-WinPushWinRsCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $Command
    )

    $nativeResult = Invoke-WinPushNativeProcess `
        -FilePath 'winrs.exe' `
        -ArgumentList @(
            ('-r:{0}' -f $ComputerName)
            $Command
        )

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.WinRsCommandResult'
        ExitCode   = $nativeResult.ExitCode
        Output     = @(ConvertTo-WinPushWinRsTextArray -Text $nativeResult.StandardOutput)
        Errors     = @(ConvertTo-WinPushWinRsTextArray -Text $nativeResult.StandardError)
    }
}

function ConvertTo-WinPushWinRsTextArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = @($normalized -split "`n")

    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = @($lines[0..($lines.Count - 2)])
    }

    return $lines
}
