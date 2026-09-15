function Invoke-WinPushPsrpCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $Command,

        [ValidateSet('Auto', 'PowerShell', 'Cmd')]
        [string] $Shell = 'Auto'
    )

    $remoteScriptBlock = {
        param(
            [Parameter(Mandatory)]
            [string] $CommandText,

            [Parameter(Mandatory)]
            [string] $ShellName
        )

        $state = [pscustomobject] @{ HadErrors = $false }
        $writeRecord = {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $state.HadErrors = $true
                [pscustomobject] @{ Type = 'Error'; Value = [string] $_ }
            }
            else {
                [pscustomobject] @{ Type = 'Output'; Value = $_ }
            }
        }

        try {
            if ($ShellName -eq 'Cmd') {
                & cmd.exe /d /s /c $CommandText 2>&1 | ForEach-Object $writeRecord
            }
            elseif ($ShellName -eq 'PowerShell') {
                $wrappedCommand = @"
& {
$CommandText
}
`$commandSucceeded = `$?
if (`$null -ne `$LASTEXITCODE) { exit `$LASTEXITCODE }
if (-not `$commandSucceeded) { exit 1 }
"@
                $encodedCommand = [System.Convert]::ToBase64String(
                    [System.Text.Encoding]::Unicode.GetBytes($wrappedCommand)
                )
                $powerShellExecutable = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
                $powerShellPath = Join-Path -Path $PSHOME -ChildPath $powerShellExecutable
                & $powerShellPath -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1 |
                    ForEach-Object $writeRecord
            }
            else {
                & ([scriptblock]::Create($CommandText)) 2>&1 | ForEach-Object $writeRecord
            }

            $shellExitCode = [int] $LASTEXITCODE
            if ($ShellName -ne 'Cmd' -and $shellExitCode -eq 0 -and $state.HadErrors) {
                $shellExitCode = 1
            }
        }
        catch {
            [pscustomobject] @{ Type = 'Error'; Value = [string] $_ }
            $shellExitCode = 1
        }

        [pscustomobject] @{ Type = 'Completed'; Value = $shellExitCode }
    }

    $output = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $state = [pscustomobject] @{ ExitCode = 1 }
    $activeCaptureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
        Get-WinPushActiveCaptureContext
    }

    Invoke-Command `
            -Session $Session `
            -ScriptBlock $remoteScriptBlock `
            -ArgumentList $Command, $Shell `
            -ErrorAction Stop | ForEach-Object {
        if ($_.Type -eq 'Output') {
            $output.Add($_.Value)
            if ($null -ne $activeCaptureContext) {
                Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Output -Value $_.Value
            }
        }
        elseif ($_.Type -eq 'Error') {
            $errors.Add([string] $_.Value)
            if ($null -ne $activeCaptureContext) {
                Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Error -Value $_.Value
            }
        }
        elseif ($_.Type -eq 'Completed') {
            $state.ExitCode = $_.Value
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsrpCommandResult'
        ExitCode   = $state.ExitCode
        Output     = $output.ToArray()
        Errors     = $errors.ToArray()
    }
}
