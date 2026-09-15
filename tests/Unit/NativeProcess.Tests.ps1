$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
$script:NativeProcessPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushNativeProcess.ps1'

. $script:NativeProcessPath

Describe 'Invoke-WinPushNativeProcess' {
    BeforeEach {
        $script:PowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    It 'captures complete stdout and stderr arrays and propagates the exit code' {
        $command = '[Console]::Out.WriteLine("out one"); [Console]::Out.WriteLine("out two"); [Console]::Error.WriteLine("error one"); exit 23'

        $result = Invoke-WinPushNativeProcess -FilePath $script:PowerShellPath -ArgumentList @('-NoProfile', '-Command', $command)

        $result.Succeeded | Should Be $false
        $result.TimedOut | Should Be $false
        $result.ExitCode | Should Be 23
        ($result.StandardOutput -join ',') | Should Be 'out one,out two'
        ($result.StandardError -join ',') | Should Be 'error one'
    }

    It 'times out, retains received streams, and kills the descendant process' {
        $childCommand = 'Start-Sleep -Seconds 60'
        $command = '$child = Start-Process -FilePath "{0}" -ArgumentList @(''-NoProfile'', ''-Command'', ''{1}'') -PassThru; [Console]::Out.WriteLine("before timeout"); [Console]::Out.WriteLine($child.Id); [Console]::Error.WriteLine("early error"); Start-Sleep -Seconds 60' -f $script:PowerShellPath, $childCommand

        $result = Invoke-WinPushNativeProcess -FilePath $script:PowerShellPath -ArgumentList @('-NoProfile', '-Command', $command) -TimeoutSeconds 1

        $childId = [int] $result.StandardOutput[1]
        $result.Succeeded | Should Be $false
        $result.TimedOut | Should Be $true
        $result.ExitCode | Should Be 124
        $result.StandardOutput[0] | Should Be 'before timeout'
        $result.StandardError[0] | Should Be 'Process timed out after 1 seconds.'
        $result.StandardError[1] | Should Be 'early error'
        $null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue) | Should Be $true
    }

    It 'disables timeout when zero is supplied' {
        $command = 'Start-Sleep -Seconds 2; [Console]::Out.WriteLine("finished")'

        $result = Invoke-WinPushNativeProcess -FilePath $script:PowerShellPath -ArgumentList @('-NoProfile', '-Command', $command) -TimeoutSeconds 0

        $result.Succeeded | Should Be $true
        $result.TimedOut | Should Be $false
        $result.ExitCode | Should Be 0
        $result.StandardOutput[0] | Should Be 'finished'
    }

    It 'rejects negative timeouts' {
        $timeoutError = $null
        try { Invoke-WinPushNativeProcess -FilePath $script:PowerShellPath -TimeoutSeconds -1 } catch { $timeoutError = $_ }

        $null -eq $timeoutError | Should Be $false
    }
}
