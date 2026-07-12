function Test-WinPushTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ComputerName,

        [System.Management.Automation.PSCredential] $Credential
    )

    $targets = Resolve-WinPushTarget -ComputerName $ComputerName

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
