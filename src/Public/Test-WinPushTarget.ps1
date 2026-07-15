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
