function Invoke-WinPushCommand {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'HostFile')]
        [string] $HostFile,

        [Parameter(Mandatory, Position = 1)]
        [string] $Command,

        [ValidateSet('Psrp', 'WinRM', 'PsExec')]
        [string] $Transport = 'Psrp',

        [AllowNull()]
        [string] $PsExecPath,

        [System.Management.Automation.PSCredential] $Credential,

        [switch] $CaptureOutput,

        [switch] $Logs,

        [string] $OutputRoot = 'C:\WinPush'
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($Command)) {
            throw [System.ArgumentException]::new('Command text must not be empty.')
        }

        if (($CaptureOutput -or $Logs) -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
            throw [System.ArgumentException]::new('OutputRoot must not be empty.')
        }

        $remoteLogDirectory = if ($Logs) { Get-WinPushCommandLogDirectory -Command $Command } else { $null }
        $computerNames = [System.Collections.Generic.List[string]]::new()
        $pipelineInputReceived = $false
    }

    process {
        if ($MyInvocation.ExpectingInput) {
            $pipelineInputReceived = $true
        }

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

            if ($CaptureOutput) {
                throw [System.NotSupportedException]::new(('CaptureOutput is not supported when Transport is {0}.' -f $Transport))
            }

            if ($Logs) {
                throw [System.NotSupportedException]::new(('Logs is not supported when Transport is {0}.' -f $Transport))
            }
        }

        if ($Transport -eq 'PsExec') {
            if ($PSCmdlet.ParameterSetName -eq 'HostFile') {
                throw [System.NotSupportedException]::new('HostFile is not supported when Transport is PsExec.')
            }

            if ($pipelineInputReceived) {
                throw [System.NotSupportedException]::new('Pipeline targets are not supported when Transport is PsExec.')
            }

            if ($targets.Count -ne 1) {
                throw [System.NotSupportedException]::new('Transport PsExec supports exactly one target.')
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
                try {
                    $commandResult = if ($Transport -eq 'WinRM') {
                        Invoke-WinPushWinRsCommand -ComputerName $target -Command $Command
                    }
                    else {
                        Invoke-WinPushPsExecCommand -ComputerName $target -Command $Command -PsExecPath $PsExecPath
                    }
                    $exitCode = $commandResult.ExitCode
                    $output = @($commandResult.Output)
                    $errors = @($commandResult.Errors)
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
                            '{0} command exited with code {1}.' -f $nativeTransportName, $exitCode
                        }
                    }

                    New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport $Transport `
                        -Operation 'RunCommand' `
                        -Succeeded $succeeded `
                        -ExitCode $exitCode `
                        -ErrorMessage $errorMessage `
                        -Output $output `
                        -Errors $errors
                }
                catch {
                    New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport $Transport `
                        -Operation 'RunCommand' `
                        -Succeeded $false `
                        -ExitCode 1 `
                        -ErrorMessage $_.Exception.Message `
                        -Errors $_.Exception.Message
                }

                continue
            }

            try {
                $session = New-PSSession @sessionParameters
                $scriptBlock = [scriptblock]::Create($Command)
                $commandResult = Invoke-WinPushPsrpCommand -Session $session -ScriptBlock $scriptBlock
                $output = @($commandResult.Output)
                $errors = @($commandResult.Errors)
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
                        -Operation 'RunCommand' `
                        -Transport 'Psrp' `
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
                    -Operation 'RunCommand' `
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
                    'PSRP command session creation failed for the target with the supplied credential.'
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
                        -Operation 'RunCommand' `
                        -Transport 'Psrp' `
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
                    -Operation 'RunCommand' `
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
