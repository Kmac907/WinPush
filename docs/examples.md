# WinPush examples

These recipes assume `PC01` is reachable and the caller is authorized for the requested operation. Replace example targets, paths, and packages with approved values for your environment.

## Task index

- [Authenticate with the current identity or a credential](#authenticate-with-the-current-identity-or-a-credential)
- [Run command text](#run-command-text)
- [Run a local script](#run-a-local-script)
- [Transfer a file](#transfer-a-file)
- [Retrieve logs](#retrieve-logs)
- [Run a package](#run-a-package)
- [Inspect run history](#inspect-run-history)
- [Validate and run remediation](#validate-and-run-remediation)
- [Export Entra devices](#export-entra-devices)

Start a repository-local session with shared example values:

```powershell
Import-Module .\WinPush.psd1 -Force

$ComputerName = 'PC01'
$OutputRoot = 'C:\WinPush'
```

## Authenticate with the current identity or a credential

**When to use:** Confirm that PSRP authentication and session creation work before remote execution.

Use the controller process identity:

```powershell
Test-WinPushTarget -ComputerName $ComputerName
```

Use an explicit PSRP credential:

```powershell
$Credential = Get-Credential

Test-WinPushTarget `
    -ComputerName $ComputerName `
    -Credential $Credential
```

Representative output:

```text
ComputerName Reachable Transport ErrorSummary
------------ --------- --------- ------------
PC01         True      Psrp
```

**Operational note:** `-Credential` applies only to PSRP. WinRS and PsExec use the controller process identity.

## Run command text

**When to use:** Run a short command without creating a local script file.

Run through PSRP and capture one shared run:

```powershell
$Results = Invoke-WinPushCommand `
    -ComputerName @('PC01', 'PC02') `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Use a host file or pipeline strings:

```powershell
Invoke-WinPushCommand `
    -HostFile .\hosts.txt `
    -Command 'hostname'

Get-Content .\hosts.txt |
    Invoke-WinPushCommand -Command 'hostname'
```

Use native WinRS, select `cmd.exe`, and bound execution time:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'ver' `
    -Transport WinRM `
    -Shell Cmd `
    -TimeoutSeconds 120
```

Use PsExec from an approved local path:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'hostname' `
    -Transport PsExec `
    -PsExecPath 'C:\Tools\PsExec.exe'
```

**Operational note:** `-CaptureOutput` works with all command transports. `-Logs` works only with PSRP. See [shell, timeout, and transport behavior](commands.md#shell-and-timeout-behavior).

## Run a local script

**When to use:** Execute an existing local `.ps1` file on one or more targets.

```powershell
$ScriptPath = Join-Path $env:TEMP 'WinPush-Example.ps1'

@'
Write-Output "WinPush script ran on $env:COMPUTERNAME"
'@ | Set-Content -LiteralPath $ScriptPath -Encoding UTF8

Invoke-WinPushScript `
    -HostFile .\hosts.txt `
    -ScriptPath $ScriptPath `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Run through WinRS and retain the native stage for troubleshooting:

```powershell
Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $ScriptPath `
    -Transport WinRM `
    -KeepStagedScript
```

Run through PsExec:

```powershell
Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $ScriptPath `
    -Transport PsExec `
    -PsExecPath 'C:\Tools\PsExec.exe'
```

**Operational note:** Native transports stage under `C:\Windows\Temp\WinPush\<stage-id>\` and remove the stage unless `-KeepStagedScript` is supplied. Script arguments are not supported.

## Transfer a file

**When to use:** Upload or download one file through PSRP.

```powershell
$LocalFile = Join-Path $env:TEMP 'WinPush-Payload.txt'
$RemoteFile = 'C:\Windows\Temp\payload.txt'
$DownloadedFile = Join-Path $env:TEMP 'WinPush-Payload.downloaded.txt'

'WinPush file copy example' |
    Set-Content -LiteralPath $LocalFile -Encoding UTF8

Copy-WinPushItem `
    -ComputerName $ComputerName `
    -Path $LocalFile `
    -Destination $RemoteFile

Copy-WinPushItem `
    -ComputerName $ComputerName `
    -Path $RemoteFile `
    -Destination $DownloadedFile `
    -Direction Download
```

**Operational note:** The command supports one target and one file per call; it does not recurse or expand wildcards.

## Retrieve logs

**When to use:** Copy immediate files from an explicit remote directory or collect logs attached to an execution.

```powershell
Get-WinPushLog `
    -ComputerName $ComputerName `
    -RemoteDirectory 'C:\ProgramData\EA\Logs\Inventory' `
    -OutputRoot $OutputRoot
```

Create command-convention logs and collect them with the command result:

```powershell
$CommandWithLog = @'
New-Item -ItemType Directory -Force -Path C:\ProgramData\EA\Logs\New-Item | Out-Null
Set-Content -Path C:\ProgramData\EA\Logs\New-Item\command.log -Value 'completed'
hostname
'@

Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command $CommandWithLog `
    -CaptureOutput `
    -Logs `
    -OutputRoot $OutputRoot
```

Create script-convention logs and collect them:

```powershell
$AttachedScript = Join-Path $env:TEMP 'Inventory.ps1'

@'
$LogDirectory = 'C:\ProgramData\EA\Logs\Inventory'
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
Set-Content -Path (Join-Path $LogDirectory 'inventory.log') -Value 'completed'
'@ | Set-Content -LiteralPath $AttachedScript -Encoding UTF8

Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $AttachedScript `
    -CaptureOutput `
    -Logs `
    -OutputRoot $OutputRoot
```

**Operational note:** Log copy is non-recursive and does not change the primary execution result. Directory conventions are listed in [log conventions](commands.md#log-conventions).

## Run a package

**When to use:** Stage a local file, directory, or HTTPS download and run one package-relative PowerShell entry point.

Run a local directory package, capture output, copy logs, and clean a successful stage:

```powershell
Invoke-WinPushPackage `
    -ComputerName $ComputerName `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1 `
    -CaptureOutput `
    -Logs `
    -Cleanup OnSuccess `
    -OutputRoot $OutputRoot
```

Download over HTTPS, verify an optional SHA-256 value, extract the ZIP, and pass positional arguments:

```powershell
Invoke-WinPushPackage `
    -HostFile .\hosts.txt `
    -Uri 'https://packages.example.test/EAInstallPackage.zip' `
    -ExpectedSha256 '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' `
    -EntryPoint .\Install-EA.ps1 `
    -ArgumentList @('Production', $true) `
    -RemoteStageRoot 'C:\ProgramData\WinPush\Staging' `
    -Extract `
    -Cleanup Always
```

**Operational note:** The per-invocation URI cache is removed after success or failure. `ExpectedSha256` remains optional. See the [package workflow](package-workflow.md) for staging, cleanup, and failure semantics.

## Inspect run history

**When to use:** Read a captured `summary.csv` and locate per-target logs without reconstructing safe target paths.

```powershell
$Results = Invoke-WinPushCommand `
    -ComputerName @('PC01', 'fe80::1') `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot $OutputRoot

Get-WinPushRun -Path $Results[0].RunDirectory
```

Representative output:

```text
ComputerName Operation  Status ExitCode TargetLog
------------ ---------  ------ -------- ---------
PC01         RunCommand OK     0        Available
```

**Operational note:** Use `TargetLogPath`; unsafe target names are mapped to safe hashed directory names.

## Validate and run remediation

**When to use:** Check a detection/remediation pair for Windows PowerShell 5.1 parser errors, then execute it when valid.

```powershell
$Validation = Test-WinPushRemediation `
    -DetectScript .\Detect-EA.ps1 `
    -RemediateScript .\Repair-EA.ps1

if ($Validation.IsValid) {
    Invoke-WinPushRemediation `
        -ComputerName $ComputerName `
        -DetectScript $Validation.DetectScriptPath `
        -RemediateScript $Validation.RemediateScriptPath `
        -TimeoutSeconds 300 `
        -CaptureOutput `
        -OutputRoot $OutputRoot
}
```

**Operational note:** Detection exit `0` means `Compliant`; exit `1` runs remediation, whose exit `0` means `Remediated`. Phase details remain in `RemediationMetadata`.

## Export Entra devices

**When to use:** Produce a WinPush host file from enabled device members of an Entra group.

```powershell
Connect-MgGraph

Export-WinPushHostFileFromEntraGroup `
    -GroupName 'Windows Pilot Devices' `
    -OutputPath .\hosts.txt
```

Append unique transitive members and return only newly written names:

```powershell
Export-WinPushHostFileFromEntraGroup `
    -GroupId '00000000-0000-0000-0000-000000000000' `
    -OutputPath .\hosts.txt `
    -Transitive `
    -Append `
    -PassThru
```

**Operational note:** Disabled devices are excluded unless `-IncludeDisabled` is supplied. Microsoft Graph is optional and is not imported with WinPush.
