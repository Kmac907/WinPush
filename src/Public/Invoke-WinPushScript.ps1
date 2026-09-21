<#
.SYNOPSIS
Runs a local PowerShell script on one or more Windows targets.

.DESCRIPTION
Validates one existing local .ps1 file, resolves direct, pipeline, or host-file targets, and runs the script through PSRP, native WinRS, or PsExec. Native transports stage the script under C:\Windows\Temp\WinPush before execution. Each target produces a structured result.

.PARAMETER ComputerName
Target names supplied directly, through pipeline strings, or through pipeline objects with a ComputerName property. Use this parameter or HostFile.

.PARAMETER HostFile
A UTF-8 target file. Blank lines and full-line comments beginning with # are ignored, and duplicate targets are removed case-insensitively.

.PARAMETER ScriptPath
An existing local filesystem .ps1 file.

.PARAMETER Transport
The execution transport: Psrp, WinRM, or PsExec. The default is Psrp. WinRM selects native winrs.exe.

.PARAMETER TimeoutSeconds
The native staging and execution timeout from 0 through 2147483647 seconds. The default is 1800. Zero disables the timeout.

.PARAMETER PsExecPath
An optional path to PsExec.exe. This parameter is valid only with the PsExec transport; PATH discovery is used when omitted.

.PARAMETER Credential
An optional credential for PSRP session creation. This parameter is not supported with WinRM or PsExec.

.PARAMETER CaptureOutput
Writes one shared summary.csv, one correlated root run.log, and one per-target run.log beneath OutputRoot.

.PARAMETER Logs
Copies immediate convention-based script log files through the PSRP session. This parameter is not supported with WinRM or PsExec.

.PARAMETER KeepStagedScript
Retains the native-transport stage on the target for troubleshooting. Native stages are removed by default. This switch has no effect on PSRP file-path execution.

.PARAMETER OutputRoot
The local artifact root used by capture and log collection. The default is C:\WinPush.

.EXAMPLE
Invoke-WinPushScript -ComputerName PC01 -ScriptPath .\Inventory.ps1 -CaptureOutput

Runs Inventory.ps1 through PSRP and captures its result.

.EXAMPLE
Invoke-WinPushScript -ComputerName PC01 -ScriptPath .\Inventory.ps1 -Transport PsExec -PsExecPath C:\Tools\PsExec.exe

Stages and runs Inventory.ps1 through PsExec, then removes the generated stage.

.INPUTS
System.String and objects with a ComputerName property.

.OUTPUTS
WinPush.ExecutionResult

.NOTES
Script arguments are not supported. Credential and Logs are PSRP-only.

.LINK
docs/examples.md#run-a-local-script
#>
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

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800,

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
        $scriptDisplayName = $scriptItem.Name
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
        $captureContext = if ($captureOutputEnabled -and $null -ne $sharedRunDirectory -and
            (Get-Command -Name New-WinPushCaptureContext -ErrorAction SilentlyContinue)) {
            New-WinPushCaptureContext `
                -RunDirectory $sharedRunDirectory `
                -Operation 'RunScript' `
                -Transport $Transport `
                -ArtifactIdentity $resolvedScriptPath
        }
        if ($null -ne $captureContext -and -not [string]::IsNullOrWhiteSpace($captureContext.ArtifactError)) {
            $artifactError = $captureContext.ArtifactError
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

            if ($null -ne $captureContext) {
                $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName $target -Transport $Transport
                Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Started'
                $artifactError = $captureContext.ArtifactError
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
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Upload Started'
                    }
                    Copy-WinPushNativeScriptToStage `
                        -ComputerName $target `
                        -ScriptPath $resolvedScriptPath `
                        -StagePlan $stagePlan `
                        -Transport $Transport `
                        -PsExecPath $PsExecPath `
                        -TimeoutSeconds $TimeoutSeconds
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Upload Completed'
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Execution Started'
                    }
                    $nativeScriptCommand = New-WinPushNativeStagedScriptCommand -RemoteScriptPath $stagePlan.RemoteScriptPath

                    $scriptResult = if ($Transport -eq 'WinRM') {
                        Invoke-WinPushWinRsCommand -ComputerName $target -Command $nativeScriptCommand -TimeoutSeconds $TimeoutSeconds
                    }
                    else {
                        Invoke-WinPushPsExecCommand -ComputerName $target -Command $nativeScriptCommand -PsExecPath $PsExecPath -TimeoutSeconds $TimeoutSeconds
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
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $errorMessage
                    }
                    $errors = @($errorMessage)
                    $exitCode = 1
                    $succeeded = $false
                }

                if ($null -ne $stagePlan -and -not $KeepStagedScript) {
                    try {
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Started'
                        }
                        Remove-WinPushNativeScriptStage `
                            -ComputerName $target `
                            -StagePlan $stagePlan `
                            -Transport $Transport `
                            -PsExecPath $PsExecPath `
                            -TimeoutSeconds $TimeoutSeconds
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Completed'
                        }
                    }
                    catch {
                        $cleanupError = $_.Exception.Message
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $cleanupError
                        }
                        $errors = @($errors) + $cleanupError

                        if ($succeeded) {
                            $succeeded = $false
                            $exitCode = 1
                            $errorMessage = $cleanupError
                        }
                    }
                }

                $result = New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport $Transport `
                    -Operation 'RunScript' `
                    -Succeeded $succeeded `
                    -ExitCode $exitCode `
                    -ErrorMessage $errorMessage `
                    -ArtifactError $artifactError `
                    -Output $output `
                    -Errors $errors `
                    -RunDirectory $sharedRunDirectory `
                    -Script $scriptDisplayName

                if ($captureOutputEnabled) {
                    $result = Add-WinPushExecutionArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity $resolvedScriptPath
                    if ($null -ne $captureContext) {
                        $result.ArtifactError = $captureContext.ArtifactError
                    }
                    elseif ($null -ne $result.ArtifactError) {
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
                    $scriptResult = Invoke-WinPushPsrpScript -Session $session -FilePath $resolvedScriptPath
                    $output = @($scriptResult.Output)
                    $errors = @($scriptResult.Errors)
                    $succeeded = $errors.Count -eq 0
                    $exitCode = if ($succeeded) { 0 } else { 1 }
                    $errorMessage = if ($errors.Count -gt 0) { [string] $errors[0] } else { $null }

                    $result = New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport 'Psrp' `
                        -Operation 'RunScript' `
                        -Succeeded $succeeded `
                        -ExitCode $exitCode `
                        -ErrorMessage $errorMessage `
                        -ArtifactError $artifactError `
                        -Output $output `
                        -Errors $errors `
                        -RunDirectory $sharedRunDirectory `
                        -Script $scriptDisplayName
                }
                catch {
                    $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $null -eq $session) {
                        'PSRP script session creation failed for the target with the supplied credential.'
                    }
                    else {
                        $_.Exception.Message
                    }

                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $errorMessage
                    }

                    $result = New-WinPushExecutionResult `
                        -ComputerName $target `
                        -Transport 'Psrp' `
                        -Operation 'RunScript' `
                        -Succeeded $false `
                        -ExitCode 1 `
                        -ErrorMessage $errorMessage `
                        -ArtifactError $artifactError `
                        -Errors $errorMessage `
                        -RunDirectory $sharedRunDirectory `
                        -Script $scriptDisplayName
                }

                if ($logsEnabled -and $null -ne $session) {
                    if ($null -ne $captureContext) {
                        $result.ComputerDirectory = $captureContext.ComputerDirectory
                        $result.ResultPath = $captureContext.ResultPath
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Started'
                    }
                    $result = Add-WinPushExecutionLogArtifact `
                        -Result $result `
                        -Session $session `
                        -OutputRoot $OutputRoot `
                        -RemoteLogDirectory $remoteLogDirectory
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Completed'
                    }
                }

                if ($captureOutputEnabled) {
                    $previousArtifactError = $result.ArtifactError
                    $result = Add-WinPushExecutionArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity $resolvedScriptPath
                    if ($null -ne $captureContext -and [string]::IsNullOrWhiteSpace($result.ArtifactError)) {
                        $result.ArtifactError = $captureContext.ArtifactError
                    }
                    elseif ($result.ArtifactError -ne $previousArtifactError) {
                        $artifactError = $result.ArtifactError
                        $captureOutputEnabled = $false
                    }
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
