function Invoke-WinPushScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $ScriptPath,

        [switch] $CaptureOutput,

        [string] $OutputRoot = 'C:\WinPush'
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            throw [System.ArgumentException]::new('ScriptPath must not be empty.')
        }

        if ($CaptureOutput -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
            throw [System.ArgumentException]::new('OutputRoot must not be empty.')
        }

        if (-not (Test-Path -LiteralPath $ScriptPath)) {
            throw [System.IO.FileNotFoundException]::new("Script file was not found: $ScriptPath")
        }

        $scriptItem = Get-Item -LiteralPath $ScriptPath
        if ($scriptItem.PSIsContainer) {
            throw [System.ArgumentException]::new("ScriptPath must refer to a file: $ScriptPath")
        }

        if ($scriptItem.Extension -ne '.ps1') {
            throw [System.ArgumentException]::new("ScriptPath must refer to a .ps1 file: $ScriptPath")
        }

        $resolvedScriptPath = $scriptItem.FullName
    }

    end {
        $targets = @(Resolve-WinPushTarget -ComputerName @($ComputerName))
        $target = $targets[0]
        $session = $null
        $runDirectory = $null
        $computerDirectory = $null
        $resultPath = $null
        $stdOutPath = $null
        $stdErrPath = $null

        try {
            $session = New-PSSession -ComputerName $target -ErrorAction Stop
            $scriptResult = Invoke-WinPushPsrpScript -Session $session -FilePath $resolvedScriptPath
            $output = @($scriptResult.Output)
            $errors = @($scriptResult.Errors)
            $succeeded = $errors.Count -eq 0
            $exitCode = if ($succeeded) { 0 } else { 1 }
            $errorMessage = if ($errors.Count -gt 0) { [string] $errors[0] } else { $null }

            if ($CaptureOutput) {
                $artifact = Write-WinPushCommandOutputArtifact `
                    -OutputRoot $OutputRoot `
                    -ComputerName $target `
                    -Output $output `
                    -Errors $errors `
                    -Operation 'RunScript' `
                    -Transport 'Psrp' `
                    -Succeeded $succeeded `
                    -ExitCode $exitCode `
                    -ErrorMessage $errorMessage
                $runDirectory = $artifact.RunDirectory
                $computerDirectory = $artifact.ComputerDirectory
                $resultPath = $artifact.ResultPath
                $stdOutPath = $artifact.StdOutPath
                $stdErrPath = $artifact.StdErrPath
            }

            New-WinPushExecutionResult `
                -ComputerName $target `
                -Transport 'Psrp' `
                -Operation 'RunScript' `
                -Succeeded $succeeded `
                -ExitCode $exitCode `
                -ErrorMessage $errorMessage `
                -Output $output `
                -Errors $errors `
                -RunDirectory $runDirectory `
                -ComputerDirectory $computerDirectory `
                -ResultPath $resultPath `
                -StdOutPath $stdOutPath `
                -StdErrPath $stdErrPath
        }
        catch {
            $errorMessage = $_.Exception.Message

            if ($CaptureOutput) {
                $artifact = Write-WinPushCommandOutputArtifact `
                    -OutputRoot $OutputRoot `
                    -ComputerName $target `
                    -Errors $errorMessage `
                    -Operation 'RunScript' `
                    -Transport 'Psrp' `
                    -Succeeded $false `
                    -ExitCode 1 `
                    -ErrorMessage $errorMessage
                $runDirectory = $artifact.RunDirectory
                $computerDirectory = $artifact.ComputerDirectory
                $resultPath = $artifact.ResultPath
                $stdOutPath = $artifact.StdOutPath
                $stdErrPath = $artifact.StdErrPath
            }

            New-WinPushExecutionResult `
                -ComputerName $target `
                -Transport 'Psrp' `
                -Operation 'RunScript' `
                -Succeeded $false `
                -ExitCode 1 `
                -ErrorMessage $errorMessage `
                -Errors $errorMessage `
                -RunDirectory $runDirectory `
                -ComputerDirectory $computerDirectory `
                -ResultPath $resultPath `
                -StdOutPath $stdOutPath `
                -StdErrPath $stdErrPath
        }
        finally {
            if ($null -ne $session) {
                Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
            }
        }
    }
}
