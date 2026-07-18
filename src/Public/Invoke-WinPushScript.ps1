function Invoke-WinPushScript {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'HostFile')]
        [string] $HostFile,

        [Parameter(Mandatory, Position = 1)]
        [string] $ScriptPath,

        [ValidateSet('Psrp', 'WinRM', 'PsExec')]
        [string] $Transport = 'Psrp',

        [AllowNull()]
        [string] $PsExecPath,

        [System.Management.Automation.PSCredential] $Credential,

        [switch] $CaptureOutput,

        [switch] $Logs,

        [switch] $KeepStagedScript,

        [string] $OutputRoot = 'C:\WinPush'
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            throw [System.ArgumentException]::new('ScriptPath must not be empty.')
        }

        if (($CaptureOutput -or $Logs) -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
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
        $remoteLogDirectory = if ($Logs) { Get-WinPushScriptLogDirectory -ScriptPath $resolvedScriptPath } else { $null }
        $computerNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ComputerName') {
            foreach ($target in @($ComputerName)) {
                $computerNames.Add($target)
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'HostFile') {
            $targets = @(Resolve-WinPushTarget -HostFile $HostFile)
        }
        else {
            $targets = @(Resolve-WinPushTarget -ComputerName $computerNames.ToArray())
        }

        if ($Transport -ne 'PsExec' -and $PSBoundParameters.ContainsKey('PsExecPath')) {
            throw [System.NotSupportedException]::new('PsExecPath is only supported when Transport is PsExec.')
        }

        if ($Transport -eq 'WinRM' -or $Transport -eq 'PsExec') {
            if ($PSBoundParameters.ContainsKey('Credential')) {
                throw [System.NotSupportedException]::new(('Credential is not supported when Transport is {0}.' -f $Transport))
            }

            if ($Logs) {
                throw [System.NotSupportedException]::new(('Logs is not supported when Transport is {0}.' -f $Transport))
            }
        }

        $sharedRunDirectory = $null

        foreach ($target in $targets) {
            $session = $null
            $runDirectory = $null
            $computerDirectory = $null
            $resultPath = $null
            $stdOutPath = $null
            $stdErrPath = $null
            $logResults = @()
            $copiedLogPaths = @()
            $sessionParameters = @{
                ComputerName = $target
                ErrorAction  = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $sessionParameters['Credential'] = $Credential
            }

            if ($Transport -eq 'WinRM' -or $Transport -eq 'PsExec') {
                $stagePlan = $null
                $output = @()
                $errors = @()
                $exitCode = 1
                $succeeded = $false
                $errorMessage = $null

                try {
                    $stagePlan = New-WinPushNativeScriptStagePlan -ComputerName $target -ScriptPath $resolvedScriptPath
                    Copy-WinPushNativeScriptToStage `
                        -ComputerName $target `
                        -ScriptPath $resolvedScriptPath `
                        -StagePlan $stagePlan `
                        -Transport $Transport `
                        -PsExecPath $PsExecPath
                    $nativeScriptCommand = New-WinPushNativeStagedScriptCommand -RemoteScriptPath $stagePlan.RemoteScriptPath

                    $scriptResult = if ($Transport -eq 'WinRM') {
                        Invoke-WinPushWinRsCommand -ComputerName $target -Command $nativeScriptCommand
                    }
                    else {
                        Invoke-WinPushPsExecCommand -ComputerName $target -Command $nativeScriptCommand -PsExecPath $PsExecPath
                    }

                    $exitCode = $scriptResult.ExitCode
                    $output = @($scriptResult.Output)
                    $errors = @($scriptResult.Errors)
                    $succeeded = $exitCode -eq 0
                    $nativeTransportName = if ($Transport -eq 'WinRM') { 'WinRS' } else { $Transport }
                    $errorMessage = if ($succeeded) {
                        $null
                    }
                    else {
                        $firstError = @($errors | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | Select-Object -First 1)
                        if ($firstError.Count -gt 0) {
                            ([string] $firstError[0]).Trim()
                        }
                        else {
                            '{0} script exited with code {1}.' -f $nativeTransportName, $exitCode
                        }
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    $errors = @($errorMessage)
                    $exitCode = 1
                    $succeeded = $false
                }

                if ($null -ne $stagePlan -and -not $KeepStagedScript) {
                    try {
                        Remove-WinPushNativeScriptStage `
                            -ComputerName $target `
                            -StagePlan $stagePlan `
                            -Transport $Transport `
                            -PsExecPath $PsExecPath
                    }
                    catch {
                        $cleanupError = $_.Exception.Message
                        $errors = @($errors) + $cleanupError

                        if ($succeeded) {
                            $succeeded = $false
                            $exitCode = 1
                            $errorMessage = $cleanupError
                        }
                    }
                }

                if ($CaptureOutput) {
                    $artifact = Write-WinPushCommandOutputArtifact `
                        -OutputRoot $OutputRoot `
                        -ComputerName $target `
                        -Output $output `
                        -Errors $errors `
                        -RunDirectory $sharedRunDirectory `
                        -Operation 'RunScript' `
                        -Transport $Transport `
                        -ArtifactIdentity $resolvedScriptPath `
                        -Succeeded $succeeded `
                        -ExitCode $exitCode `
                        -ErrorMessage $errorMessage
                    $sharedRunDirectory = $artifact.RunDirectory
                    $runDirectory = $artifact.RunDirectory
                    $computerDirectory = $artifact.ComputerDirectory
                    $resultPath = $artifact.ResultPath
                    $stdOutPath = $artifact.StdOutPath
                    $stdErrPath = $artifact.StdErrPath
                }

                New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport $Transport `
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

                continue
            }

            try {
                $session = New-PSSession @sessionParameters
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
                        -RunDirectory $sharedRunDirectory `
                        -Operation 'RunScript' `
                        -Transport 'Psrp' `
                        -ArtifactIdentity $resolvedScriptPath `
                        -Succeeded $succeeded `
                        -ExitCode $exitCode `
                        -ErrorMessage $errorMessage
                    $sharedRunDirectory = $artifact.RunDirectory
                    $runDirectory = $artifact.RunDirectory
                    $computerDirectory = $artifact.ComputerDirectory
                    $resultPath = $artifact.ResultPath
                    $stdOutPath = $artifact.StdOutPath
                    $stdErrPath = $artifact.StdErrPath
                }

                if ($Logs) {
                    try {
                        $logCopy = Copy-WinPushPsrpLogDirectory `
                            -Session $session `
                            -ComputerName $target `
                            -RemoteDirectory $remoteLogDirectory `
                            -OutputRoot $OutputRoot `
                            -RunDirectory $sharedRunDirectory `
                            -ComputerDirectory $computerDirectory
                        $sharedRunDirectory = $logCopy.RunDirectory
                        $runDirectory = $logCopy.RunDirectory
                        $computerDirectory = $logCopy.ComputerDirectory
                        $logResults = @($logCopy.Logs)
                        $copiedLogPaths = @($logCopy.CopiedLogPaths)
                    }
                    catch {
                        if ([string]::IsNullOrWhiteSpace($runDirectory) -or [string]::IsNullOrWhiteSpace($computerDirectory)) {
                            $artifactDirectory = New-WinPushLogArtifactDirectory `
                                -OutputRoot $OutputRoot `
                                -ComputerName $target `
                                -RunDirectory $sharedRunDirectory
                            $sharedRunDirectory = $artifactDirectory.RunDirectory
                            $runDirectory = $artifactDirectory.RunDirectory
                            $computerDirectory = $artifactDirectory.ComputerDirectory
                        }

                        $logResults = @(
                            New-WinPushLogResult `
                                -ComputerName $target `
                                -RemotePath $remoteLogDirectory `
                                -Copied $false `
                                -ErrorMessage $_.Exception.Message
                        )
                    }
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
                    -StdErrPath $stdErrPath `
                    -Logs $logResults `
                    -CopiedLogPaths $copiedLogPaths
            }
            catch {
                $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $null -eq $session) {
                    'PSRP script session creation failed for the target with the supplied credential.'
                }
                else {
                    $_.Exception.Message
                }

                if ($CaptureOutput) {
                    $artifact = Write-WinPushCommandOutputArtifact `
                        -OutputRoot $OutputRoot `
                        -ComputerName $target `
                        -Errors $errorMessage `
                        -RunDirectory $sharedRunDirectory `
                        -Operation 'RunScript' `
                        -Transport 'Psrp' `
                        -ArtifactIdentity $resolvedScriptPath `
                        -Succeeded $false `
                        -ExitCode 1 `
                        -ErrorMessage $errorMessage
                    $sharedRunDirectory = $artifact.RunDirectory
                    $runDirectory = $artifact.RunDirectory
                    $computerDirectory = $artifact.ComputerDirectory
                    $resultPath = $artifact.ResultPath
                    $stdOutPath = $artifact.StdOutPath
                    $stdErrPath = $artifact.StdErrPath
                }

                if ($Logs -and $null -ne $session) {
                    try {
                        $logCopy = Copy-WinPushPsrpLogDirectory `
                            -Session $session `
                            -ComputerName $target `
                            -RemoteDirectory $remoteLogDirectory `
                            -OutputRoot $OutputRoot `
                            -RunDirectory $sharedRunDirectory `
                            -ComputerDirectory $computerDirectory
                        $sharedRunDirectory = $logCopy.RunDirectory
                        $runDirectory = $logCopy.RunDirectory
                        $computerDirectory = $logCopy.ComputerDirectory
                        $logResults = @($logCopy.Logs)
                        $copiedLogPaths = @($logCopy.CopiedLogPaths)
                    }
                    catch {
                        if ([string]::IsNullOrWhiteSpace($runDirectory) -or [string]::IsNullOrWhiteSpace($computerDirectory)) {
                            $artifactDirectory = New-WinPushLogArtifactDirectory `
                                -OutputRoot $OutputRoot `
                                -ComputerName $target `
                                -RunDirectory $sharedRunDirectory
                            $sharedRunDirectory = $artifactDirectory.RunDirectory
                            $runDirectory = $artifactDirectory.RunDirectory
                            $computerDirectory = $artifactDirectory.ComputerDirectory
                        }

                        $logResults = @(
                            New-WinPushLogResult `
                                -ComputerName $target `
                                -RemotePath $remoteLogDirectory `
                                -Copied $false `
                                -ErrorMessage $_.Exception.Message
                        )
                    }
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
                    -StdErrPath $stdErrPath `
                    -Logs $logResults `
                    -CopiedLogPaths $copiedLogPaths
            }
            finally {
                if ($null -ne $session) {
                    Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
