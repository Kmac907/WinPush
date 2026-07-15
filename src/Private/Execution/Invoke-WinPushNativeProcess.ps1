function Invoke-WinPushNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [AllowNull()]
        [string[]] $ArgumentList = @()
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
        $process.WaitForExit()

        [pscustomobject] [ordered] @{
            PSTypeName    = 'WinPush.NativeProcessResult'
            FilePath      = $FilePath
            ArgumentList  = @($ArgumentList)
            ExitCode      = $process.ExitCode
            StandardOutput = $standardOutput.GetAwaiter().GetResult()
            StandardError  = $standardError.GetAwaiter().GetResult()
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}
