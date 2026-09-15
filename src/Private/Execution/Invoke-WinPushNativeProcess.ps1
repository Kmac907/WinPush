function Invoke-WinPushNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [AllowNull()]
        [string[]] $ArgumentList = @(),

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    $process = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        foreach ($argument in @($ArgumentList)) {
            [void] $startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo

        [void] $process.Start()
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $timedOut = $false

        if ($TimeoutSeconds -eq 0) {
            $process.WaitForExit()
        }
        else {
            $timeoutMilliseconds = [int] [System.Math]::Min(([long] $TimeoutSeconds * 1000), [int]::MaxValue)
            $timedOut = -not $process.WaitForExit($timeoutMilliseconds)
            if ($timedOut) {
                try {
                    $process.Kill($true)
                }
                finally {
                    $process.WaitForExit()
                }
            }
        }

        $outputLines = @(ConvertTo-WinPushNativeTextArray -Text $standardOutput.GetAwaiter().GetResult())
        $errorLines = @(ConvertTo-WinPushNativeTextArray -Text $standardError.GetAwaiter().GetResult())
        if ($timedOut) {
            $errorLines = @('Process timed out after {0} seconds.' -f $TimeoutSeconds) + $errorLines
        }

        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }

        [pscustomobject] [ordered] @{
            PSTypeName     = 'WinPush.NativeProcessResult'
            FilePath       = $FilePath
            ArgumentList   = @($ArgumentList)
            Succeeded      = $exitCode -eq 0
            TimedOut       = $timedOut
            ExitCode       = $exitCode
            StandardOutput = $outputLines
            StandardError  = $errorLines
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function ConvertTo-WinPushNativeTextArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]] $Text
    )

    if ($null -eq $Text -or $Text.Count -eq 0) {
        return @()
    }

    $normalized = (@($Text) -join "`n") -replace "`r`n", "`n" -replace "`r", "`n"
    if ($normalized.Length -eq 0) {
        return @()
    }

    $lines = @($normalized -split "`n")

    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = @($lines[0..($lines.Count - 2)])
    }

    return $lines
}

function New-WinPushNativePowerShellEncodedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Command
    )

    $encodedCommand = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))

    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encodedCommand
}
