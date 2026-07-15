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

    if ($nativeResult.ExitCode -ne 0) {
        throw [System.InvalidOperationException]::new('WinRS command did not complete successfully.')
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.WinRsCommandResult'
        ExitCode   = 0
    }
}
