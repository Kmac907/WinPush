function Invoke-WinPushWinRsCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $Command,

        [ValidateSet('Auto', 'PowerShell', 'Cmd')]
        [string] $Shell = 'Auto',

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    $nativeCommand = switch ($Shell) {
        'PowerShell' { New-WinPushNativePowerShellEncodedCommand -Command $Command }
        'Cmd' { 'cmd.exe /d /s /c {0}' -f $Command }
        default { $Command }
    }

    $nativeResult = Invoke-WinPushNativeProcess `
        -FilePath 'winrs.exe' `
        -ArgumentList @(
            ('-r:{0}' -f $ComputerName)
            $nativeCommand
        ) `
        -TimeoutSeconds $TimeoutSeconds

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.WinRsCommandResult'
        ExitCode   = $nativeResult.ExitCode
        Output     = @(ConvertTo-WinPushNativeTextArray -Text $nativeResult.StandardOutput)
        Errors     = @(ConvertTo-WinPushNativeTextArray -Text $nativeResult.StandardError)
    }
}
