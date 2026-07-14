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

        [System.Management.Automation.PSCredential] $Credential,

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
            $sessionParameters = @{
                ComputerName = $target
                ErrorAction  = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $sessionParameters['Credential'] = $Credential
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
}
