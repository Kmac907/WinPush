function Test-WinPushAbsoluteWindowsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return ($Path -match '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\[^\\\/]+[\\\/][^\\\/]+([\\\/].*)?$')
}

<#
.SYNOPSIS
Copies immediate files from a remote log directory through PSRP.

.DESCRIPTION
Creates a temporary PSSession for each resolved target and copies the immediate regular files from one explicit absolute Windows directory into a local per-target Logs directory. The command does not recurse or read copied file contents into memory.

.PARAMETER ComputerName
Target names supplied directly, through pipeline strings, or through pipeline objects with a ComputerName property. Use this parameter or HostFile.

.PARAMETER HostFile
A UTF-8 target file. Blank lines and full-line comments beginning with # are ignored, and duplicate targets are removed case-insensitively.

.PARAMETER RemoteDirectory
An absolute drive-rooted or UNC directory on each target.

.PARAMETER OutputRoot
The local artifact root. The default is C:\WinPush.

.PARAMETER Credential
An optional credential for PSRP session creation. The current Windows identity is used when omitted.

.EXAMPLE
Get-WinPushLog -ComputerName PC01 -RemoteDirectory C:\ProgramData\EA\Logs\Inventory

Copies immediate files from the specified directory on PC01.

.EXAMPLE
Get-WinPushLog -HostFile .\hosts.txt -RemoteDirectory C:\ProgramData\EA\Logs\Inventory -OutputRoot D:\WinPush

Copies logs from every resolved host-file target into one shared local run directory.

.INPUTS
System.String and objects with a ComputerName property.

.OUTPUTS
WinPush.ExecutionResult

.NOTES
Only PSRP is supported. This command creates copied-log artifacts but does not write summary.csv or run.log.

.LINK
docs/commands.md#log-conventions
#>
function Get-WinPushLog {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'HostFile')]
        [string] $HostFile,

        [Parameter(Mandatory, Position = 1)]
        [string] $RemoteDirectory,

        [string] $OutputRoot = 'C:\WinPush',

        [System.Management.Automation.PSCredential] $Credential
    )

    begin {
        $localValidationError = $null

        if ([string]::IsNullOrWhiteSpace($RemoteDirectory)) {
            $localValidationError = 'RemoteDirectory must not be empty.'
        }
        elseif ([string]::IsNullOrWhiteSpace($OutputRoot)) {
            $localValidationError = 'OutputRoot must not be empty.'
        }
        elseif (-not (Test-WinPushAbsoluteWindowsPath -Path $RemoteDirectory)) {
            $localValidationError = 'RemoteDirectory must be an absolute Windows path.'
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
        if ($null -ne $localValidationError) {
            $resultComputerName = if ($PSCmdlet.ParameterSetName -eq 'HostFile') {
                $HostFile
            }
            else {
                [string]::Join(',', $computerNames.ToArray())
            }

            New-WinPushExecutionResult `
                -ComputerName $resultComputerName `
                -Transport 'Psrp' `
                -Operation 'GetLogs' `
                -Succeeded $false `
                -ExitCode 1 `
                -ErrorMessage $localValidationError `
                -Errors $localValidationError
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'HostFile') {
            $targets = @(Resolve-WinPushTarget -HostFile $HostFile)
        }
        else {
            $targets = @(Resolve-WinPushTarget -ComputerName $computerNames.ToArray())
        }

        $sharedRunDirectory = $null

        foreach ($target in $targets) {
            $session = $null

            $sessionParameters = @{
                ComputerName = $target
                ErrorAction  = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $sessionParameters['Credential'] = $Credential
            }

            try {
                $session = New-PSSession @sessionParameters
                $logCopy = Copy-WinPushPsrpLogDirectory `
                    -Session $session `
                    -OutputRoot $OutputRoot `
                    -ComputerName $target `
                    -RemoteDirectory $RemoteDirectory `
                    -RunDirectory $sharedRunDirectory
                $sharedRunDirectory = $logCopy.RunDirectory
                $copyErrors = @($logCopy.Errors)
                $copiedLogPaths = @($logCopy.CopiedLogPaths)
                $succeeded = ($copyErrors.Count -eq 0)
                $errorMessage = if ($succeeded) { $null } else { 'One or more log files failed to copy.' }
                $exitCode = if ($succeeded) { 0 } else { 1 }

                New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport 'Psrp' `
                    -Operation 'GetLogs' `
                    -Succeeded $succeeded `
                    -ExitCode $exitCode `
                    -ErrorMessage $errorMessage `
                    -Output $logCopy.FileMetadata `
                    -Errors $copyErrors `
                    -Logs $logCopy.Logs `
                    -RunDirectory $logCopy.RunDirectory `
                    -ComputerDirectory $logCopy.ComputerDirectory `
                    -CopiedLogPaths $copiedLogPaths
            }
            catch {
                $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $null -eq $session) {
                    'PSRP log retrieval session creation failed for the target with the supplied credential.'
                }
                else {
                    $_.Exception.Message
                }

                New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport 'Psrp' `
                    -Operation 'GetLogs' `
                    -Succeeded $false `
                    -ExitCode 1 `
                    -ErrorMessage $errorMessage `
                    -Errors $errorMessage
            }
            finally {
                if ($null -ne $session) {
                    Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
