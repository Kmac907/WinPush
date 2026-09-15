# WinPush Examples

The examples below assume `PC01` is a Windows target reachable over WinRM/PSRP and that the caller is authorized to create files under `C:\Windows\Temp` and `C:\ProgramData\EA\Logs` on that target. Replace `PC01` with a reachable target in your environment.

## Session Setup

```powershell
Import-Module .\WinPush.psd1 -Force

$ComputerName = 'PC01'
$OutputRoot = 'C:\WinPush'
```

WinPush commands return structured objects. The default terminal view is a compact operation-specific table; successful rows leave `ErrorSummary` blank. Command, script, and package output stays on the result object and in root/per-target `run.log` files when `-CaptureOutput` is used.

## Authentication

Use the current Windows identity:

```powershell
Test-WinPushTarget -ComputerName $ComputerName
```

Use a supplied `PSCredential`:

```powershell
$Credential = Get-Credential

Test-WinPushTarget -ComputerName $ComputerName -Credential $Credential

Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Credential $Credential `
    -Command '$env:COMPUTERNAME'
```

## Command Execution

Run command text through PSRP and capture output artifacts:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Run command text through PSRP across resolved targets and capture one shared artifact run:

```powershell
Invoke-WinPushCommand `
    -ComputerName @('PC01', 'PC02') `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot $OutputRoot

Get-Content .\hosts.txt |
    Invoke-WinPushCommand `
        -Command 'hostname' `
        -CaptureOutput `
        -OutputRoot $OutputRoot

Invoke-WinPushCommand `
    -HostFile .\hosts.txt `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Run command text through WinRS:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'hostname' `
    -Transport WinRM
```

Choose `cmd.exe` explicitly and bound native execution time:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'ver' `
    -Transport WinRM `
    -Shell Cmd `
    -TimeoutSeconds 120
```

Run command text through WinRS and capture output artifacts:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'hostname' `
    -Transport WinRM `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Run command text through WinRS across resolved targets:

```powershell
Invoke-WinPushCommand `
    -ComputerName @('PC01', 'PC02') `
    -Command 'hostname' `
    -Transport WinRM

Get-Content .\hosts.txt |
    Invoke-WinPushCommand `
        -Command 'hostname' `
        -Transport WinRM

Invoke-WinPushCommand `
    -HostFile .\hosts.txt `
    -Command 'hostname' `
    -Transport WinRM
```

Run command text through PsExec:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'hostname' `
    -Transport PsExec `
    -PsExecPath 'C:\Tools\PsExec.exe'
```

## Script Execution

Run a local script through PSRP and capture output artifacts:

```powershell
$ScriptPath = Join-Path $env:TEMP 'WinPush-Example.ps1'

@'
Write-Output "WinPush script ran on $env:COMPUTERNAME"
'@ | Set-Content -LiteralPath $ScriptPath -Encoding UTF8

Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $ScriptPath `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Run a local script through PSRP across a host file and capture one shared artifact run:

```powershell
Invoke-WinPushScript `
    -HostFile .\hosts.txt `
    -ScriptPath $ScriptPath `
    -CaptureOutput `
    -OutputRoot $OutputRoot
```

Run a local script through WinRS:

```powershell
Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $ScriptPath `
    -Transport WinRM
```

Run a local script through WinRS and leave the staged file for troubleshooting:

```powershell
Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $ScriptPath `
    -Transport WinRM `
    -KeepStagedScript
```

Run a local script through PsExec:

```powershell
Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $ScriptPath `
    -Transport PsExec `
    -PsExecPath 'C:\Tools\PsExec.exe'
```

## File Transfer

Upload and then download one file:

```powershell
Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command 'New-Item -ItemType Directory -Force -Path C:\Windows\Temp\WinPushExample | Out-Null'

$LocalFile = Join-Path $env:TEMP 'WinPush-Payload.txt'
$RemoteFile = 'C:\Windows\Temp\WinPushExample\payload.txt'
$DownloadedFile = Join-Path $env:TEMP 'WinPush-Payload.downloaded.txt'

'WinPush file copy example' | Set-Content -LiteralPath $LocalFile -Encoding UTF8

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

## Log Retrieval

Retrieve logs from an explicit remote directory:

```powershell
$StandaloneLogDirectory = 'C:\Windows\Temp\WinPushStandaloneLogs'

Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command "New-Item -ItemType Directory -Force -Path $StandaloneLogDirectory | Out-Null; Set-Content -Path $StandaloneLogDirectory\standalone.log -Value 'standalone log entry'"

Get-WinPushLog `
    -ComputerName $ComputerName `
    -RemoteDirectory $StandaloneLogDirectory `
    -OutputRoot $OutputRoot
```

Run command text with attached command logs:

```powershell
$CommandWithLog = @'
New-Item -ItemType Directory -Force -Path C:\ProgramData\EA\Logs\New-Item | Out-Null
Set-Content -Path C:\ProgramData\EA\Logs\New-Item\command.log -Value "attached command log entry"
hostname
'@

Invoke-WinPushCommand `
    -ComputerName $ComputerName `
    -Command $CommandWithLog `
    -CaptureOutput `
    -Logs `
    -OutputRoot $OutputRoot
```

Run a script with attached script logs:

```powershell
$AttachedScriptPath = Join-Path $env:TEMP 'WinPush-AttachedLogExample.ps1'

@'
$LogDirectory = 'C:\ProgramData\EA\Logs\WinPush-AttachedLogExample'
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
Set-Content -Path (Join-Path $LogDirectory 'script.log') -Value 'attached script log entry'
Write-Output "script attached log example completed"
'@ | Set-Content -LiteralPath $AttachedScriptPath -Encoding UTF8

Invoke-WinPushScript `
    -ComputerName $ComputerName `
    -ScriptPath $AttachedScriptPath `
    -CaptureOutput `
    -Logs `
    -OutputRoot $OutputRoot
```

## Package Workflow

Stage a local package directory, run a package-relative PowerShell entry point, capture output, copy package logs, and remove the remote stage after success:

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

Download only over HTTPS, verify the optional SHA-256, pass positional entry-point arguments, and use an absolute remote stage root:

```powershell
Invoke-WinPushPackage `
    -ComputerName $ComputerName `
    -Uri 'https://packages.example.test/EAInstallPackage.zip' `
    -ExpectedSha256 '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' `
    -EntryPoint .\Install-EA.ps1 `
    -ArgumentList @('Production', $true) `
    -RemoteStageRoot 'C:\ProgramData\WinPush\Staging' `
    -Extract `
    -Cleanup Always
```

The per-invocation URI cache directory beneath `PackageCacheRoot` is temporary and is removed after success or failure.

Run the same package through PSRP across a host file:

```powershell
Invoke-WinPushPackage `
    -HostFile .\hosts.txt `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1 `
    -CaptureOutput `
    -Cleanup OnSuccess `
    -OutputRoot $OutputRoot
```

## Run History

Read `summary.csv` back from a captured run and locate available per-target logs:

```powershell
$Results = Invoke-WinPushCommand `
    -ComputerName @('PC01', 'fe80::1') `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot $OutputRoot

Get-WinPushRun -Path $Results[0].RunDirectory
```

The run directory name contains a timestamp and GUID. Unsafe target names are mapped to safe hashed directory names; use `TargetLogPath` instead of constructing a raw target path.

## Remediation

Validate with the Windows PowerShell 5.1 parser, then invoke detection and remediation:

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

Detection exit `0` returns `Compliant`; exit `1` runs remediation, whose exit `0` returns `Remediated`. Phase details are retained in `RemediationMetadata`.

## Entra Host Export

Install Microsoft Graph separately, authenticate, and export enabled direct device members:

```powershell
Connect-MgGraph

Export-WinPushHostFileFromEntraGroup `
    -GroupName 'Windows Pilot Devices' `
    -OutputPath .\hosts.txt
```

Use `-Transitive` for flattened membership, `-IncludeDisabled` when needed, or `-Append -PassThru` to add and return only new names. WinPush does not declare Microsoft Graph as a required dependency.
