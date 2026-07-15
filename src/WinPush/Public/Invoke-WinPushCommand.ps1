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
