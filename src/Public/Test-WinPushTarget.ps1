<#
.SYNOPSIS
Tests PSRP session creation for one or more Windows targets.

.DESCRIPTION
Resolves direct, pipeline, or host-file targets and sequentially attempts to create a temporary PSSession for each one. The command returns a structured reachability result per target and removes every created session.

.PARAMETER ComputerName
Target names supplied directly, through pipeline strings, or through pipeline objects with a ComputerName property. Use this parameter or HostFile.

.PARAMETER HostFile
A UTF-8 target file. Blank lines and full-line comments beginning with # are ignored, and duplicate targets are removed case-insensitively.

.PARAMETER Credential
An optional credential for PSRP session creation. The current Windows identity is used when omitted.

.EXAMPLE
Test-WinPushTarget -ComputerName PC01, PC02

Tests PSRP session creation for two targets.

.EXAMPLE
Get-Content .\hosts.txt | Test-WinPushTarget

Tests the unique usable target names received from the pipeline.

.INPUTS
System.String and objects with a ComputerName property.

.OUTPUTS
WinPush.ExecutionResult

.NOTES
This command tests PSRP session creation only. It does not configure WinRM, firewall rules, TrustedHosts, certificates, endpoints, or policy.

.LINK
docs/commands.md#target-input-and-host-file-resolution
#>
function Test-WinPushTarget {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'HostFile')]
        [string] $HostFile,

        [System.Management.Automation.PSCredential] $Credential
    )

    begin {
        $pendingComputerNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ComputerName') {
            foreach ($target in @($ComputerName)) {
                $pendingComputerNames.Add($target)
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'HostFile') {
            $targets = Resolve-WinPushTarget -HostFile $HostFile
        }
        else {
            $targets = Resolve-WinPushTarget -ComputerName $pendingComputerNames.ToArray()
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

            try {
                $session = New-PSSession @sessionParameters

                New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport 'Psrp' `
                    -Operation 'TestTarget' `
                    -Succeeded $true `
                    -ExitCode $null
            }
            catch {
                $errorMessage = if ($PSBoundParameters.ContainsKey('Credential')) {
                    'PSRP session creation failed for the target with the supplied credential.'
                }
                else {
                    $_.Exception.Message
                }

                New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport 'Psrp' `
                    -Operation 'TestTarget' `
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
