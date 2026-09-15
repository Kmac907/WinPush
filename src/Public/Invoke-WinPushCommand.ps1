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
        $artifactError = $null
        $captureOutputEnabled = [bool] $CaptureOutput
        $logsEnabled = [bool] $Logs
        if ($CaptureOutput -or $Logs) {
            try {
                $sharedRunDirectory = New-WinPushArtifactRunDirectory -OutputRoot $OutputRoot
            }
            catch {
                $artifactError = $_.Exception.Message
                $captureOutputEnabled = $false
                $logsEnabled = $false
            }
        }

        foreach ($target in $targets) {
            $session = $null
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

                    $result = New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport $Transport `
                        -Operation 'RunCommand' `
                        -Succeeded $succeeded `
                        -ExitCode $exitCode `
                        -ErrorMessage $errorMessage `
                        -ArtifactError $artifactError `
                        -Output $output `
                        -Errors $errors `
                        -RunDirectory $sharedRunDirectory
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    $result = New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport $Transport `
                        -Operation 'RunCommand' `
                        -Succeeded $false `
                        -ExitCode 1 `
                        -ErrorMessage $errorMessage `
                        -ArtifactError $artifactError `
                        -Errors $errorMessage `
                        -RunDirectory $sharedRunDirectory
                }

                if ($captureOutputEnabled) {
                    $result = Add-WinPushExecutionArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity $Command
                    if ($null -ne $result.ArtifactError) {
                        $artifactError = $result.ArtifactError
                        $captureOutputEnabled = $false
                    }
                }

                $result
                continue
            }

            try {
                try {
                    $session = New-PSSession @sessionParameters
                    $scriptBlock = [scriptblock]::Create($Command)
                    $commandResult = Invoke-WinPushPsrpCommand -Session $session -ScriptBlock $scriptBlock
                    $output = @($commandResult.Output)
                    $errors = @($commandResult.Errors)
                    $succeeded = $errors.Count -eq 0
                    $exitCode = if ($succeeded) { 0 } else { 1 }
                    $errorMessage = if ($errors.Count -gt 0) { [string] $errors[0] } else { $null }

                    $result = New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport 'Psrp' `
                        -Operation 'RunCommand' `
                        -Succeeded $succeeded `
                        -ExitCode $exitCode `
                        -ErrorMessage $errorMessage `
                        -ArtifactError $artifactError `
                        -Output $output `
                        -Errors $errors `
                        -RunDirectory $sharedRunDirectory
                }
                catch {
                    $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $null -eq $session) {
                        'PSRP command session creation failed for the target with the supplied credential.'
                    }
                    else {
                        $_.Exception.Message
                    }

                    $result = New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport 'Psrp' `
                        -Operation 'RunCommand' `
                        -Succeeded $false `
                        -ExitCode 1 `
                        -ErrorMessage $errorMessage `
                        -ArtifactError $artifactError `
                        -Errors $errorMessage `
                        -RunDirectory $sharedRunDirectory
                }

                if ($captureOutputEnabled) {
                    $previousArtifactError = $result.ArtifactError
                    $result = Add-WinPushExecutionArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity $Command
                    if ($result.ArtifactError -ne $previousArtifactError) {
                        $artifactError = $result.ArtifactError
                        $captureOutputEnabled = $false
                    }
                }

                if ($logsEnabled -and $null -ne $session) {
                    $result = Add-WinPushExecutionLogArtifact `
                        -Result $result `
                        -Session $session `
                        -OutputRoot $OutputRoot `
                        -RemoteLogDirectory $remoteLogDirectory
                }

                $result
            }
            finally {
                if ($null -ne $session) {
                    Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
