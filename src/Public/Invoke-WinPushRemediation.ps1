<#
.SYNOPSIS
Runs a detection and remediation script pair on Windows targets.

.DESCRIPTION
Validates both local scripts with the Windows PowerShell 5.1 parser, resolves targets, stages the pair, and runs detection through PSRP, WinRS, or PsExec. Detection exit 0 means compliant; exit 1 runs remediation. Staged files are removed after execution, and each target returns phase metadata.

.PARAMETER ComputerName
Target names supplied directly, through pipeline strings, or through pipeline objects with a ComputerName property. Use this parameter or HostFile.

.PARAMETER HostFile
A UTF-8 target file. Blank lines and full-line comments beginning with # are ignored, and duplicate targets are removed case-insensitively.

.PARAMETER DetectScript
An existing local .ps1 detection script. Exit 0 means compliant and exit 1 requests remediation.

.PARAMETER RemediateScript
An existing local .ps1 remediation script. Exit 0 means successfully remediated.

.PARAMETER Transport
The execution transport: Psrp, WinRM, or PsExec. The default is Psrp. WinRM selects native winrs.exe.

.PARAMETER TimeoutSeconds
The native staging and phase timeout from 0 through 2147483647 seconds. The default is 1800. Zero disables the timeout.

.PARAMETER PsExecPath
An optional path to PsExec.exe. This parameter is valid only with the PsExec transport; PATH discovery is used when omitted.

.PARAMETER Credential
An optional credential for PSRP session creation. This parameter is not supported with WinRM or PsExec.

.PARAMETER CaptureOutput
Writes one shared summary.csv, one correlated root run.log, and one per-target run.log beneath OutputRoot.

.PARAMETER Logs
Copies immediate convention-based files for both script base names through PSRP. This parameter is not supported with WinRM or PsExec.

.PARAMETER OutputRoot
The local artifact root used by capture and log collection. The default is C:\WinPush.

.EXAMPLE
Invoke-WinPushRemediation -ComputerName PC01 -DetectScript .\Detect.ps1 -RemediateScript .\Remediate.ps1

Validates and runs the pair through PSRP.

.EXAMPLE
Invoke-WinPushRemediation -HostFile .\hosts.txt -DetectScript .\Detect.ps1 -RemediateScript .\Remediate.ps1 -Transport WinRM -TimeoutSeconds 300 -CaptureOutput

Runs the pair through WinRS for each host-file target and captures one shared run.

.INPUTS
System.String and objects with a ComputerName property.

.OUTPUTS
WinPush.ExecutionResult

.NOTES
Results include WinPush.RemediationMetadata. Staged scripts are removed after execution. Credential and Logs are PSRP-only.

.LINK
docs/examples.md#validate-and-run-remediation
#>
function Invoke-WinPushRemediation {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'HostFile')]
        [string] $HostFile,

        [Parameter(Mandatory)]
        [string] $DetectScript,

        [Parameter(Mandatory)]
        [string] $RemediateScript,

        [ValidateSet('Psrp', 'WinRM', 'PsExec')]
        [string] $Transport = 'Psrp',

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800,

        [AllowNull()]
        [string] $PsExecPath,

        [System.Management.Automation.PSCredential] $Credential,

        [switch] $CaptureOutput,

        [switch] $Logs,

        [string] $OutputRoot = 'C:\WinPush'
    )

    begin {
        if (($CaptureOutput -or $Logs) -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
            throw [System.ArgumentException]::new('OutputRoot must not be empty.')
        }

        $validation = Test-WinPushRemediation -DetectScript $DetectScript -RemediateScript $RemediateScript
        if (-not $validation.IsValid) {
            throw [System.ArgumentException]::new(($validation.Errors -join ' '))
        }

        $resolvedDetectScript = $validation.DetectScriptPath
        $resolvedRemediateScript = $validation.RemediateScriptPath
        $artifactIdentity = '{0} | {1}' -f $resolvedDetectScript, $resolvedRemediateScript
        $remoteLogDirectories = if ($Logs) {
            @(
                Get-WinPushScriptLogDirectory -ScriptPath $resolvedDetectScript
                Get-WinPushScriptLogDirectory -ScriptPath $resolvedRemediateScript
            ) | Select-Object -Unique
        }
        else {
            @()
        }
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
        $targets = if ($PSCmdlet.ParameterSetName -eq 'HostFile') {
            @(Resolve-WinPushTarget -HostFile $HostFile)
        }
        else {
            @(Resolve-WinPushTarget -ComputerName $computerNames.ToArray())
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
                -Operation 'RunRemediation' `
                -Transport $Transport `
                -ArtifactIdentity $artifactIdentity
        }
        if ($null -ne $captureContext -and -not [string]::IsNullOrWhiteSpace($captureContext.ArtifactError)) {
            $artifactError = $captureContext.ArtifactError
        }

        foreach ($target in $targets) {
            $session = $null
            $stagePlan = $null
            $status = 'Failed'
            $succeeded = $false
            $exitCode = 1
            $errorMessage = $null
            $output = @()
            $errors = @()
            $detectionExitCode = $null
            $remediationExitCode = $null
            $detectionOutput = @()
            $detectionErrors = @()
            $remediationOutput = @()
            $remediationErrors = @()
            $activePhase = $null
            $resultLogs = @()
            $copiedLogPaths = @()

            try {
                if ($null -ne $captureContext) {
                    $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName $target -Transport $Transport
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Started'
                    $artifactError = $captureContext.ArtifactError
                }

            try {
                $sessionParameters = @{ ComputerName = $target; ErrorAction = 'Stop' }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $sessionParameters['Credential'] = $Credential
                }
                if ($Transport -eq 'Psrp') {
                    $session = New-PSSession @sessionParameters
                }

                $stagePlan = New-WinPushNativeScriptStagePlan `
                    -ComputerName $target `
                    -ScriptPath $resolvedDetectScript `
                    -RemediateScriptPath $resolvedRemediateScript
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Upload Started'
                }
                Copy-WinPushRemediationScriptsToStage `
                    -Session $session `
                    -ComputerName $target `
                    -DetectScriptPath $resolvedDetectScript `
                    -RemediateScriptPath $resolvedRemediateScript `
                    -StagePlan $stagePlan `
                    -Transport $Transport `
                    -PsExecPath $PsExecPath `
                    -TimeoutSeconds $TimeoutSeconds
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Upload Completed'
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Detection Started'
                }

                $activePhase = 'Detection'
                $phaseResult = Invoke-WinPushRemediationStage `
                    -Session $session `
                    -ComputerName $target `
                    -RemoteScriptPath $stagePlan.RemoteDetectionScriptPath `
                    -Transport $Transport `
                    -PsExecPath $PsExecPath `
                    -TimeoutSeconds $TimeoutSeconds
                $detectionExitCode = $phaseResult.ExitCode
                $detectionOutput = @($phaseResult.Output)
                $detectionErrors = @($phaseResult.Errors)
                $output = @($detectionOutput)
                $errors = @($detectionErrors)
                $exitCode = $detectionExitCode
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Detection Completed'
                }

                if ($detectionExitCode -eq 0) {
                    $status = 'Compliant'
                    $succeeded = $true
                }
                elseif ($detectionExitCode -eq 1) {
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Remediation Started'
                    }
                    $activePhase = 'Remediation'
                    $phaseResult = Invoke-WinPushRemediationStage `
                        -Session $session `
                        -ComputerName $target `
                        -RemoteScriptPath $stagePlan.RemoteRemediationScriptPath `
                        -Transport $Transport `
                        -PsExecPath $PsExecPath `
                        -TimeoutSeconds $TimeoutSeconds
                    $remediationExitCode = $phaseResult.ExitCode
                    $remediationOutput = @($phaseResult.Output)
                    $remediationErrors = @($phaseResult.Errors)
                    $output = @($detectionOutput) + @($remediationOutput)
                    $errors = @($detectionErrors) + @($remediationErrors)
                    $exitCode = $remediationExitCode
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Remediation Completed'
                    }

                    if ($remediationExitCode -eq 0) {
                        $status = 'Remediated'
                        $succeeded = $true
                    }
                    else {
                        $errorMessage = if ($remediationErrors.Count -gt 0) {
                            ([string] $remediationErrors[0]).Trim()
                        }
                        else {
                            'Remediation script exited with code {0}.' -f $remediationExitCode
                        }
                    }
                }
                else {
                    $errorMessage = if ($detectionErrors.Count -gt 0) {
                        ([string] $detectionErrors[0]).Trim()
                    }
                    else {
                        'Detection script exited with code {0}.' -f $detectionExitCode
                    }
                }
            }
            catch {
                $phaseError = if ($PSBoundParameters.ContainsKey('Credential') -and $null -eq $session) {
                    'PSRP remediation session creation failed for the target with the supplied credential.'
                }
                else {
                    $_.Exception.Message
                }
                if ($activePhase -eq 'Detection') {
                    $detectionErrors = @($detectionErrors) + $phaseError
                }
                elseif ($activePhase -eq 'Remediation') {
                    $remediationErrors = @($remediationErrors) + $phaseError
                }
                $errors = @($detectionErrors) + @($remediationErrors)
                if ($null -eq $activePhase) {
                    $errors = @($errors) + $phaseError
                }
                $errorMessage = $phaseError
                $status = 'Failed'
                $succeeded = $false
                $exitCode = 1
            }

            if ($null -ne $stagePlan) {
                try {
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Started'
                    }
                    Remove-WinPushRemediationScriptStage `
                        -Session $session `
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
                    $errors = @($errors) + $cleanupError
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $cleanupError
                    }
                    if ($succeeded) {
                        $status = 'Failed'
                        $succeeded = $false
                        $exitCode = 1
                        $errorMessage = $cleanupError
                    }
                }
            }

            if ($logsEnabled -and $null -ne $session) {
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Started'
                }
                foreach ($remoteLogDirectory in $remoteLogDirectories) {
                    try {
                        $logCopy = Copy-WinPushPsrpLogDirectory `
                            -Session $session `
                            -ComputerName $target `
                            -RemoteDirectory $remoteLogDirectory `
                            -OutputRoot $OutputRoot `
                            -RunDirectory $sharedRunDirectory `
                            -ComputerDirectory $(if ($null -eq $captureContext) { $null } else { $captureContext.ComputerDirectory })
                        $resultLogs = @($resultLogs) + @($logCopy.Logs)
                        $copiedLogPaths = @($copiedLogPaths) + @($logCopy.CopiedLogPaths)
                    }
                    catch {
                        $artifactError = if ([string]::IsNullOrWhiteSpace($artifactError)) {
                            $_.Exception.Message
                        }
                        else {
                            '{0}; {1}' -f $artifactError, $_.Exception.Message
                        }
                        $resultLogs = @($resultLogs) + @(New-WinPushLogResult `
                                -ComputerName $target `
                                -RemotePath $remoteLogDirectory `
                                -Copied $false `
                                -ErrorMessage $_.Exception.Message)
                        $logsEnabled = $false
                        break
                    }
                }
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Completed'
                }
            }

            $metadata = [pscustomobject] [ordered] @{
                PSTypeName          = 'WinPush.RemediationMetadata'
                Status              = $status
                DetectionExitCode   = $detectionExitCode
                RemediationExitCode = $remediationExitCode
                DetectionOutput     = @($detectionOutput)
                DetectionErrors     = @($detectionErrors)
                RemediationOutput   = @($remediationOutput)
                RemediationErrors   = @($remediationErrors)
            }
            $result = New-WinPushExecutionResult `
                -ComputerName $target `
                -Transport $Transport `
                -Operation 'RunRemediation' `
                -Succeeded $succeeded `
                -ExitCode $exitCode `
                -ErrorMessage $errorMessage `
                -ArtifactError $artifactError `
                -Output $output `
                -Errors $errors `
                -Logs $resultLogs `
                -RunDirectory $sharedRunDirectory `
                -CopiedLogPaths $copiedLogPaths `
                -RemediationMetadata $metadata

            if ($captureOutputEnabled) {
                $result = Add-WinPushExecutionArtifact `
                    -Result $result `
                    -OutputRoot $OutputRoot `
                    -ArtifactIdentity $artifactIdentity
                if ($null -ne $captureContext) {
                    $result.ArtifactError = $captureContext.ArtifactError
                }
                elseif ($null -ne $result.ArtifactError) {
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
