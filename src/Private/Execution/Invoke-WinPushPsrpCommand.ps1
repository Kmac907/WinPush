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

        $output = [System.Collections.Generic.List[object]]::new()
        $errors = [System.Collections.Generic.List[string]]::new()

        try {
            $streamItems = if ($ShellName -eq 'Cmd') {
                & cmd.exe /d /s /c $CommandText 2>&1
            }
            else {
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
                & $powerShellPath -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1
            }

            $shellExitCode = $LASTEXITCODE
            $streamItems | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errors.Add([string] $_)
                }
                else {
                    $output.Add($_)
                }
            }

            if ($ShellName -ne 'Cmd' -and $shellExitCode -eq 0 -and $errors.Count -gt 0) {
                $shellExitCode = 1
            }
        }
        catch {
            $errors.Add([string] $_)
            $shellExitCode = 1
        }

        [pscustomobject] [ordered] @{
            Output   = $output.ToArray()
            Errors   = $errors.ToArray()
            ExitCode = $shellExitCode
        }
    }

    $remoteResult = @(Invoke-Command `
            -Session $Session `
            -ScriptBlock $remoteScriptBlock `
            -ArgumentList $Command, $Shell `
            -ErrorAction Stop) | Select-Object -First 1

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsrpCommandResult'
        ExitCode   = $remoteResult.ExitCode
        Output     = @($remoteResult.Output)
        Errors     = @($remoteResult.Errors)
    }
}
