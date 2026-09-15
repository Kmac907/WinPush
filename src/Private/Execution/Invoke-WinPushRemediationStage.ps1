function Invoke-WinPushRemediationStage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemoteScriptPath,

        [Parameter(Mandatory)]
        [ValidateSet('Psrp', 'WinRM', 'PsExec')]
        [string] $Transport,

        [AllowNull()]
        [string] $PsExecPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    $command = New-WinPushNativeStagedScriptCommand -RemoteScriptPath $RemoteScriptPath
    $result = switch ($Transport) {
        'Psrp' {
            Invoke-WinPushPsrpCommand -Session $Session -Command $command -Shell Cmd
        }
        'WinRM' {
            Invoke-WinPushWinRsCommand `
                -ComputerName $ComputerName `
                -Command $command `
                -TimeoutSeconds $TimeoutSeconds
        }
        'PsExec' {
            Invoke-WinPushPsExecCommand `
                -ComputerName $ComputerName `
                -Command $command `
                -PsExecPath $PsExecPath `
                -TimeoutSeconds $TimeoutSeconds
        }
    }

    if ($Transport -ne 'Psrp') {
        $activeCaptureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
            Get-WinPushActiveCaptureContext
        }
        if ($null -ne $activeCaptureContext) {
            foreach ($item in @($result.Output)) {
                Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Output -Value $item
            }
            foreach ($item in @($result.Errors)) {
                Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Error -Value $item
            }
        }
    }

    $result
}
