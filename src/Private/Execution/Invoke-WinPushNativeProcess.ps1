function Invoke-WinPushNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [AllowNull()]
        [string[]] $ArgumentList = @(),

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800,

        [scriptblock] $OutputCallback,

        [scriptblock] $ErrorCallback
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
        $outputLines = [System.Collections.Generic.List[string]]::new()
        $errorLines = [System.Collections.Generic.List[string]]::new()
        $outputTask = $process.StandardOutput.ReadLineAsync()
        $errorTask = $process.StandardError.ReadLineAsync()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false
        $activeCaptureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
            Get-WinPushActiveCaptureContext
        }

        while ($null -ne $outputTask -or $null -ne $errorTask) {
            if (-not $timedOut -and $TimeoutSeconds -gt 0 -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                $timeoutMessage = 'Process timed out after {0} seconds.' -f $TimeoutSeconds
                Publish-WinPushNativeRecord -Type Error -Value $timeoutMessage -Callback $ErrorCallback -CaptureContext $activeCaptureContext
                $process.Kill($true)
            }

            [System.Threading.Tasks.Task[]] $pendingTasks = @($outputTask, $errorTask | Where-Object { $null -ne $_ })
            $completedIndex = [System.Threading.Tasks.Task]::WaitAny($pendingTasks, 50)
            if ($completedIndex -lt 0) {
                continue
            }

            $completedTask = $pendingTasks[$completedIndex]
            if ($null -ne $outputTask -and $completedTask.Id -eq $outputTask.Id) {
                $line = $outputTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $outputTask = $null
                }
                else {
                    $outputLines.Add($line)
                    Publish-WinPushNativeRecord -Type Output -Value $line -Callback $OutputCallback -CaptureContext $activeCaptureContext
                    $outputTask = $process.StandardOutput.ReadLineAsync()
                }
            }
            else {
                $line = $errorTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $errorTask = $null
                }
                else {
                    $errorLines.Add($line)
                    Publish-WinPushNativeRecord -Type Error -Value $line -Callback $ErrorCallback -CaptureContext $activeCaptureContext
                    $errorTask = $process.StandardError.ReadLineAsync()
                }
            }
        }

        $process.WaitForExit()
        if ($timedOut) {
            $errorLines.Insert(0, ('Process timed out after {0} seconds.' -f $TimeoutSeconds))
        }

        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }

        [pscustomobject] [ordered] @{
            PSTypeName     = 'WinPush.NativeProcessResult'
            FilePath       = $FilePath
            ArgumentList   = @($ArgumentList)
            Succeeded      = $exitCode -eq 0
            TimedOut       = $timedOut
            ExitCode       = $exitCode
            StandardOutput = $outputLines.ToArray()
            StandardError  = $errorLines.ToArray()
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Publish-WinPushNativeRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Output', 'Error')]
        [string] $Type,

        [Parameter(Mandatory)]
        [string] $Value,

        [scriptblock] $Callback,

        [AllowNull()]
        [psobject] $CaptureContext
    )

    if ($null -ne $Callback) {
        try {
            & $Callback $Value
        }
        catch {
            return
        }
        return
    }

    if ($null -ne $CaptureContext) {
        Write-WinPushCaptureRecord -Context $CaptureContext -Type $Type -Value $Value
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
