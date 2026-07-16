# WinPush

## Overview

`WinPush` is a PowerShell 7.6 script module for Windows administrators and automation engineers. The MVP uses PSRP over WinRM to test targets, run command text and local scripts, transfer individual files, and retrieve text logs from an explicit remote directory.

The module currently exports completed PSRP connectivity checks, `Invoke-WinPushCommand` execution for direct, pipeline, or host-file targets with optional captured-output artifacts and command-attached logs, direct, pipeline, or host-file local `.ps1` execution through `Invoke-WinPushScript` with optional credential support, captured-output artifacts, and script-attached logs, single-file PSRP upload/download through `Copy-WinPushItem`, and direct, pipeline, or host-file remote log directory copy through `Get-WinPushLog`.

The module provides:

- PSRP target connectivity checks
- remote command and local script execution
- single-file upload and download
- remote log retrieval
- structured per-target result objects

---

## Purpose

This module exists to provide a repeatable PowerShell 7 controller workflow for Windows endpoint administration over PSRP/WinRM.

Operationally, it is intended to:

- validate whether Windows targets can accept PSRP sessions
- run controlled command text or local `.ps1` files on one or more targets
- copy single files to or from a target
- retrieve immediate files from an explicit remote log directory
- write optional local execution artifacts for review

Out of scope:

- automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration
- credential storage
- broad package orchestration until `Invoke-WinPushPackage` is implemented
- recursive transfer, parallel fan-out, retries, or SSH transport

---

## Scope

In scope for the MVP:

- PowerShell 7.6 `Core` controller support on Windows.
- PSRP over WinRM using the current identity or a caller-supplied `PSCredential`.
- Deterministic target input from direct values, pipeline input, and UTF-8 host files.
- Structured per-target execution and log results.

Out of scope:

- Windows PowerShell 5.1 compatibility guarantees.
- SSH, retries, parallel fan-out, persistent sessions, or transport fallback.
- Credential storage or plain-text password parameters.
- Automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration.

## Repository Layout

```text
WinPush/
├─ README.md
├─ src/
│  ├─ Public/
│  └─ Private/
├─ WinPush.psd1
├─ WinPush.psm1
├─ build/
│  └─ build.ps1
└─ tests/
   └─ Unit/
```

`build/build.ps1` is a module-local quality gate for developer and CI validation. It is not runtime code and does not contain Azure DevOps pipeline-only logic.

Runtime implementation is isolated to this module folder under `src/`. Runtime code must not import helper code from sibling module folders. `packaging/` is not used.

Generated build and validation output is written under `artifacts/`, which is ignored and should not be committed.

## Public Commands

| Command | Current behavior |
| --- | --- |
| `Copy-WinPushItem` | Uploads one existing local file to one resolved `-ComputerName` target through a temporary PSRP session using `Copy-Item -ToSession`, or downloads one remote file through `Copy-Item -FromSession` when `-Direction Download` is supplied. Upload remains the default direction. For uploads, `-Path` is validated as a non-empty existing local file before any session is opened; directories, missing files, and wildcard-expanded paths are not accepted. For downloads, `-Path` is treated as non-empty remote source text and `-Destination` must be a valid local file, local directory, or missing leaf whose parent directory already exists. `-Destination` is validated as non-empty and then passed to the copy operation unchanged. The command does not support pipeline input, `-HostFile`, arrays, recursion, artifact writing, logs, automatic directory creation, or multi-target transfer. Success returns one `WinPush.ExecutionResult` with `Transport = Psrp`, `Operation = CopyFile`, `ExitCode = 0`, and transfer metadata in `Output`. |
| `Get-WinPushLog` | Validates one explicit absolute Windows `-RemoteDirectory` path for direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets, opens one temporary PSRP session per resolved target, verifies the remote path is an existing directory, enumerates immediate regular files only, and copies each immediate file to that target's local `Logs` folder under `C:\WinPush` by default or the caller-supplied `-OutputRoot`. Multi-target runs execute sequentially, return one `WinPush.ExecutionResult` per target in resolved order, continue after one target fails, and share one timestamped run folder for copied log artifacts with one child folder per `ComputerName`. Success returns `Transport = Psrp`, `Operation = GetLogs`, `ExitCode = 0`, file metadata in `Output`, one `WinPush.LogResult` per attempted file in `Logs`, and successful local file paths in `CopiedLogPaths`. Empty valid directories are successful zero-file outcomes. Missing, inaccessible, or non-directory remote paths return a failed result for that target. If one file copy fails, later files are still attempted, successful copies remain in `Logs` and `CopiedLogPaths`, the failed file has a `WinPush.LogResult` with `Copied = False`, and that target's outer result has `Succeeded = False`. This command does not read copied file contents into memory, traverse nested directories, create remote directories, write `summary.csv` or `result.txt`, or recurse. |
| `Invoke-WinPushCommand` | Runs non-empty PowerShell command text on direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP sequentially by default using the current Windows identity or an optional `-Credential`, and returns one `WinPush.ExecutionResult` summary per resolved target. Explicit command-shell invocations such as `cmd.exe /d /s /c "echo winpush"` are accepted as caller-supplied PowerShell command text; WinPush does not add automatic `cmd.exe` wrapping. Command output and command errors are preserved together; command errors set `Succeeded = $false` and `ExitCode = 1`. `-CaptureOutput` writes `summary.csv`, per-target `result.txt`, `stdout.txt`, and `stderr.txt` under one shared timestamped `-OutputRoot` run folder with one child folder per target. `-Logs` copies immediate regular files from the convention-based remote source `C:\ProgramData\EA\Logs\<command-name>\`, where `<command-name>` is derived from the first command name in the supplied PowerShell source, sanitized for a directory name, and falls back to `Command` when no command name can be derived. Attached command logs reuse the command PSSession, run after the command attempt, write under the target `Logs` folder, populate `Logs` and `CopiedLogPaths`, and do not change the primary command output, errors, or success state. `-Transport WinRM` runs one current-identity command on one direct `-ComputerName` target through `winrs.exe` using the native process boundary; `-Credential`, pipeline targets, `-HostFile`, multiple targets, `-CaptureOutput`, and `-Logs` are rejected for WinRM before launching a process. |
| `Invoke-WinPushScript` | Runs one existing local `.ps1` file on direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP using `Invoke-Command -FilePath` and the current Windows identity or an optional `-Credential`. Direct arrays, pipeline targets, and host-file targets are resolved through the standard target resolver, execute sequentially, return one `WinPush.ExecutionResult` per resolved target in order, and continue after one target fails. Invalid, missing, directory, and non-`.ps1` script paths fail before a session is opened; invalid or missing host files also fail before a session is opened. Success returns `Transport = Psrp`, `Operation = RunScript`, and `ExitCode = 0`; script errors return `Succeeded = $false`, `ExitCode = 1`, and retain script output in `Output` while script errors are kept in `Errors`. Raw script output and errors are returned inside the result object rather than emitted as separate terminal output. `-CaptureOutput` writes retained output to `stdout.txt`, script errors to `stderr.txt`, plus `summary.csv` and per-target `result.txt`; multi-target direct, pipeline, and host-file runs share one timestamped run folder with one child folder per `ComputerName`. `-Logs` copies immediate regular files from the convention-based remote source `C:\ProgramData\EA\Logs\<script-name>\`, where `<script-name>` is the local script file base name such as `Install-EA` for `Install-EA.ps1`. Attached script logs reuse the script PSSession, run after the script attempt, write under the target `Logs` folder, populate `Logs` and `CopiedLogPaths`, and do not change the primary script output, errors, or success state. Script arguments are not implemented. |
| `Test-WinPushTarget` | Tests PSRP session creation for direct `-ComputerName`, pipeline, or `-HostFile` targets sequentially using the current Windows identity or an optional `-Credential` and returns one `WinPush.ExecutionResult` per resolved target. |

## Planned Package Workflow

`Invoke-WinPushPackage` is planned post-MVP work and is not currently exported or implemented.

The planned command is a higher-level workflow built on the primitive commands. It will stage a package, optionally extract it, run a PowerShell entry point from the staged package root, optionally capture output, optionally copy logs/results back, optionally clean up remote staged files, and return `WinPush.ExecutionResult` objects with `Operation = RunPackage`.

Planned local package source:

```powershell
Invoke-WinPushPackage `
  -ComputerName PC01 `
  -Path .\EAInstallPackage `
  -EntryPoint .\Install-EA.ps1
```

Planned local zip package with endpoint extraction:

```powershell
Invoke-WinPushPackage `
  -ComputerName PC01 `
  -Path .\EAInstallPackage.zip `
  -EntryPoint .\Install-EA.ps1 `
  -Extract
```

Planned remote package source downloaded by the admin workstation first:

```powershell
Invoke-WinPushPackage `
  -ComputerName PC01 `
  -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
  -EntryPoint .\Install-EA.ps1 `
  -Extract
```

Planned package workflow with artifacts, logs, and cleanup:

```powershell
Invoke-WinPushPackage `
  -ComputerName PC01 `
  -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
  -EntryPoint .\Install-EA.ps1 `
  -Extract `
  -CaptureOutput `
  -Logs `
  -Cleanup Always
```

Planned defaults:

- URI packages download to `C:\WinPush\PackageCache\<run-timestamp>\` on the admin workstation before endpoint staging.
- Endpoint staging uses `C:\ProgramData\WinPush\Staging\<run-id>\`.
- Cleanup defaults to `Never`.
- Initial entry points are PowerShell `.ps1` files only.
- Endpoints do not download package URIs directly.
- The first package workflow scope does not include package integrity switches, native `.exe` or `.cmd` entry points, package manifests, retries, parallel execution, or recursive log copy beyond the approved log behavior.

## Prerequisites

- PowerShell 7.6 or later
- Windows controller
- Windows targets reachable over WinRM/PSRP
- current Windows identity or supplied `PSCredential` authorized on the target
- Azure DevOps feed read access when installing from `SCFModules`
- target-side permissions for the requested command, script, file copy, or log retrieval operation

---

## Installation

### Install From SCFModules Feed

Published modules are installed from the private `SCFModules` Azure Artifacts NuGet feed.

Register the repository once per machine or user profile:

```powershell
$FeedUri = 'https://pkgs.dev.azure.com/scfitops/_packaging/SCFModules/nuget/v3/index.json'

Install-Module Microsoft.PowerShell.PSResourceGet -Scope CurrentUser -Force -AllowClobber

Register-PSResourceRepository `
    -Name SCFModules `
    -Uri $FeedUri `
    -Trusted `
    -ApiVersion V3 `
    -Force
```

Install the module:

```powershell
Install-PSResource `
    -Name WinPush `
    -Repository SCFModules `
    -Scope AllUsers
```

If Azure DevOps authentication fails with `401 Unauthorized`, pass a credential created from a PAT with `Packaging: Read`:

```powershell
$Pat = Read-Host 'Azure DevOps PAT' -AsSecureString
$Credential = [pscredential]::new('AzureDevOps', $Pat)

Install-PSResource `
    -Name WinPush `
    -Repository SCFModules `
    -Scope AllUsers `
    -Credential $Credential
```

Use `-Scope CurrentUser` instead of `-Scope AllUsers` when installing without administrative rights.

Verify installation with the same scope used during install:

```powershell
Get-Module -ListAvailable WinPush |
    Select-Object Name, Version, ModuleBase

Get-InstalledPSResource -Name WinPush -Scope AllUsers
```

For a current-user install, use:

```powershell
Get-InstalledPSResource -Name WinPush -Scope CurrentUser
```

Import the module and verify its exported commands:

```powershell
Import-Module WinPush -Force
Get-Command -Module WinPush
```

### Install From Repository

For repository-based installation, use the shared installer tool from the `Tools` repository:

```powershell
Install-EndpointEngineeringModule -ModuleName WinPush -Force
```

`Install-EndpointEngineeringModule` must be available in the current PowerShell session before running this command. Follow the README under `Tools/Install-EndpointEngineeringModule` for that tool.

### Local Development Import

From this module folder:

```powershell
Import-Module .\WinPush.psd1 -Force
```

Verify exported commands:

```powershell
Get-Command -Module WinPush
```

The current expected result is:

```text
Copy-WinPushItem
Get-WinPushLog
Invoke-WinPushCommand
Invoke-WinPushScript
Test-WinPushTarget
```

### Package Metadata

The module manifest includes package metadata required by PSResourceGet packaging:

- `Description`
- `PrivateData.PSData.Tags`
- `PrivateData.PSData.ProjectUri`

`ProjectUri` must not be empty. Empty package metadata can cause `Compress-PSResource` to fail during CI packaging.

---

## Usage

The examples below assume `PC01` is a Windows target reachable over WinRM/PSRP and that the caller is authorized to create files under `C:\Windows\Temp` and `C:\ProgramData\EA\Logs` on that target. Replace `PC01` with a reachable target in your environment.

Set up the local session:

```powershell
Import-Module .\WinPush.psd1 -Force

$ComputerName = 'PC01'
$OutputRoot = 'C:\WinPush'
```

Authentication with the current Windows identity:

```powershell
Test-WinPushTarget -ComputerName $ComputerName
```

Authentication with a supplied `PSCredential`:

```powershell
$Credential = Get-Credential
Test-WinPushTarget -ComputerName $ComputerName -Credential $Credential
Invoke-WinPushCommand -ComputerName $ComputerName -Credential $Credential -Command '$env:COMPUTERNAME'
```

Command execution with captured output artifacts:

```powershell
Invoke-WinPushCommand `
  -ComputerName $ComputerName `
  -Command 'hostname' `
  -CaptureOutput `
  -OutputRoot $OutputRoot
```

Command execution through WinRS with the current Windows identity:

```powershell
Invoke-WinPushCommand `
  -ComputerName $ComputerName `
  -Command 'hostname' `
  -Transport WinRM
```

Local script execution with captured output artifacts:

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

Single-file upload and download:

```powershell
Invoke-WinPushCommand `
  -ComputerName $ComputerName `
  -Command 'New-Item -ItemType Directory -Force -Path C:\Windows\Temp\WinPushExample | Out-Null'

$LocalFile = Join-Path $env:TEMP 'WinPush-Payload.txt'
$RemoteFile = 'C:\Windows\Temp\WinPushExample\payload.txt'
$DownloadedFile = Join-Path $env:TEMP 'WinPush-Payload.downloaded.txt'

'WinPush file copy example' | Set-Content -LiteralPath $LocalFile -Encoding UTF8

Copy-WinPushItem -ComputerName $ComputerName -Path $LocalFile -Destination $RemoteFile
Copy-WinPushItem -ComputerName $ComputerName -Path $RemoteFile -Destination $DownloadedFile -Direction Download
```

Standalone log retrieval from an explicit remote directory:

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

Command execution with attached command logs:

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

Script execution with attached script logs:

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

---

## Execution Context

Documented execution assumptions:

- execution mode: interactive or automation
- user context: current Windows user or caller-supplied `PSCredential`
- supported shell: PowerShell 7.6+
- network requirements: controller-to-target WinRM/PSRP connectivity
- authentication model: current identity or explicit `PSCredential`

This module should be run only by operators or automation identities that have permission to create PSRP sessions and perform the requested action on each target.

---

## Parameters And Inputs

| Command | Parameter | Required | Default | Purpose |
| --- | --- | --- | --- | --- |
| `Test-WinPushTarget` | `ComputerName` | Yes for direct or pipeline target input | None | Target names supplied directly, by pipeline string, or by pipeline property name. |
| `Test-WinPushTarget` | `HostFile` | Yes for host-file input | None | UTF-8 file containing target names. |
| `Test-WinPushTarget` | `Credential` | No | Current identity | Credential used for PSRP session creation. |
| `Invoke-WinPushCommand` | `ComputerName` | Yes for direct or pipeline target input | None | Target names supplied directly, by pipeline string, or by pipeline property name. |
| `Invoke-WinPushCommand` | `HostFile` | Yes for host-file input | None | UTF-8 file containing target names. |
| `Invoke-WinPushCommand` | `Command` | Yes | None | PowerShell command text to run remotely. |
| `Invoke-WinPushCommand` | `Transport` | No | `Psrp` | Transport mode: `Psrp` or limited `WinRM`/`winrs.exe`. |
| `Invoke-WinPushCommand` | `Credential` | No | Current identity | Credential used for PSRP session creation. |
| `Invoke-WinPushCommand` | `CaptureOutput` | No | `$false` | Writes summary and per-target output artifacts under `OutputRoot`. |
| `Invoke-WinPushCommand` | `Logs` | No | `$false` | Copies immediate files from the convention-based command log directory. |
| `Invoke-WinPushCommand` | `OutputRoot` | No | `C:\WinPush` | Local root for generated run artifacts. |
| `Invoke-WinPushScript` | `ComputerName` | Yes for direct or pipeline target input | None | Target names supplied directly, by pipeline string, or by pipeline property name. |
| `Invoke-WinPushScript` | `HostFile` | Yes for host-file input | None | UTF-8 file containing target names. |
| `Invoke-WinPushScript` | `ScriptPath` | Yes | None | Existing local `.ps1` file to run remotely through PSRP. |
| `Invoke-WinPushScript` | `Credential` | No | Current identity | Credential used for PSRP session creation. |
| `Invoke-WinPushScript` | `CaptureOutput` | No | `$false` | Writes summary and per-target output artifacts under `OutputRoot`. |
| `Invoke-WinPushScript` | `Logs` | No | `$false` | Copies immediate files from the convention-based script log directory. |
| `Invoke-WinPushScript` | `OutputRoot` | No | `C:\WinPush` | Local root for generated run artifacts. |
| `Copy-WinPushItem` | `ComputerName` | Yes | None | Single target name. |
| `Copy-WinPushItem` | `Path` | Yes | None | Local source path for upload, or remote source path for download. |
| `Copy-WinPushItem` | `Destination` | Yes | None | Remote destination for upload, or local destination for download. |
| `Copy-WinPushItem` | `Direction` | No | `Upload` | Transfer direction: `Upload` or `Download`. |
| `Copy-WinPushItem` | `Credential` | No | Current identity | Credential used for PSRP session creation. |
| `Get-WinPushLog` | `ComputerName` | Yes for direct or pipeline target input | None | Target names supplied directly, by pipeline string, or by pipeline property name. |
| `Get-WinPushLog` | `HostFile` | Yes for host-file input | None | UTF-8 file containing target names. |
| `Get-WinPushLog` | `RemoteDirectory` | Yes | None | Absolute remote Windows directory containing immediate log files to copy. |
| `Get-WinPushLog` | `OutputRoot` | No | `C:\WinPush` | Local root for generated run artifacts. |
| `Get-WinPushLog` | `Credential` | No | Current identity | Credential used for PSRP session creation. |

Input behavior:

- direct target arrays, pipeline strings, pipeline `ComputerName` properties, and host files are supported where documented per command
- `Copy-WinPushItem` intentionally supports one target and one file per call
- host files must resolve to deterministic target names before remote work starts
- script execution accepts existing local `.ps1` files only

Avoid:

- passing empty target names, command text, script paths, destination paths, output roots, or remote log directories
- using wildcard-expanded file transfer paths
- assuming WinPush configures WinRM or target firewall policy

## Output

`Test-WinPushTarget`, `Invoke-WinPushCommand`, `Invoke-WinPushScript`, `Copy-WinPushItem`, and `Get-WinPushLog` return structured PowerShell objects with `PSTypeName = WinPush.ExecutionResult`.

| Contract | Purpose |
| --- | --- |
| `WinPush.ExecutionResult` | Per-target operation result envelope. |
| `WinPush.LogResult` | Per-file remote log copy result. |

Generated files, logs, reports, or receipts:

| Artifact | Location | Purpose | Retention |
| --- | --- | --- | --- |
| Run summary | `<OutputRoot>\<timestamp>\summary.csv` | Run-level CSV summary for captured command or script output. | Operator controlled. |
| Per-target result | `<OutputRoot>\<timestamp>\<ComputerName>\result.txt` | Human-readable per-target result detail. | Operator controlled. |
| Per-target output | `<OutputRoot>\<timestamp>\<ComputerName>\stdout.txt` | Captured output stream content. | Operator controlled. |
| Per-target errors | `<OutputRoot>\<timestamp>\<ComputerName>\stderr.txt` | Captured error stream content. | Operator controlled. |
| Copied logs | `<OutputRoot>\<timestamp>\<ComputerName>\Logs\` | Immediate files copied from documented remote log directories. | Operator controlled. |

This module does not write generated runtime output back into the repository.

## Side Effects

Importing the module loads functions from the module-local `Private` and `Public` folders. It does not open network connections, create remote sessions, write generated runtime output, or persist state. `Copy-WinPushItem` creates one temporary PSRP session and uploads or downloads one caller-selected file without writing local artifacts or logs. `Get-WinPushLog` creates one temporary PSRP session per resolved target, enumerates immediate regular files in one caller-selected remote directory, and copies those files under one timestamped local run folder with one `Logs` folder per target. `Invoke-WinPushCommand -Logs` reuses the command PSSession, derives the remote log source from the command name, and copies immediate log files under the target `Logs` folder. `Invoke-WinPushScript -Logs` reuses the script PSSession, derives the remote log source from the local script base name, and copies immediate log files under the target `Logs` folder. `Invoke-WinPushCommand -CaptureOutput` and `Invoke-WinPushScript -CaptureOutput` write local run artifacts under `C:\WinPush` by default, or under the caller-supplied `-OutputRoot`. Captured runs include run-level `summary.csv`, per-target `result.txt`, `stdout.txt`, and `stderr.txt`.

Destructive or persistent behavior:

- remote command and script behavior is determined by caller-supplied command text or script content
- uploads and downloads write to caller-selected paths
- captured output and copied logs persist under the caller-selected local `OutputRoot`
- temporary PSRP sessions are created for the duration of each target operation

---

## Error Handling

The module fails or returns failed per-target results when:

- target names are empty or invalid
- host files are invalid or unavailable
- command text is empty
- script paths are missing, directories, or not `.ps1` files
- copy paths or destinations are empty or unsupported
- remote log directories are empty, non-absolute, missing, inaccessible, or not directories
- PSRP session creation fails
- remote command or script execution returns errors
- file transfer or log copy fails

Recoverable conditions:

- multi-target command, script, connectivity, and log operations continue after one target fails
- log copy attempts continue after an individual file copy fails
- failed target results preserve error detail in the returned object

Errors should be explicit, actionable, and safe for production troubleshooting.

---

## Known Limitations

- PowerShell 7.6 `Core` is the supported controller shell.
- Windows PowerShell 5.1 compatibility is not guaranteed.
- `Invoke-WinPushPackage` is planned but not implemented or exported.
- SSH transport, retries, parallel fan-out, persistent sessions, and transport fallback are not implemented.
- Automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration is not implemented.
- Recursive file transfer, recursive log enumeration, and multi-target file transfer are not implemented.
- Script arguments are not implemented for `Invoke-WinPushScript`.
- `Copy-WinPushItem` supports one target and one file per call.

## Testing

Run the offline quality gate from this module folder:

```powershell
.\build\build.ps1
```

The gate validates the manifest, imports the module twice, runs PSScriptAnalyzer against `src`, `tests`, and `build`, runs offline unit tests, and writes CI-readable test and coverage artifacts under `artifacts\build`.

`artifacts\build` is generated output from the local quality gate, not reviewed source.

The import foundation can also be checked manually with:

```powershell
Test-ModuleManifest .\WinPush.psd1
Import-Module .\WinPush.psd1 -Force
```

Recommended validation:

- parse all `.ps1`, `.psm1`, and `.psd1` files
- import the module from the manifest
- verify exported commands
- validate manifest metadata and required module files
- run mocked or non-destructive unit tests where practical

---

## Rollback Or Recovery

To remove a PSResourceGet installation:

```powershell
Uninstall-PSResource -Name WinPush -Scope AllUsers
```

Use `-Scope CurrentUser` when the module was installed to the current-user scope.

To remove a repository-installed current-user module:

```powershell
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules\WinPush') -Recurse -Force
```

For Windows PowerShell 5.1, also check:

```text
Documents\WindowsPowerShell\Modules\WinPush
```

Additional cleanup:

- remove local captured output or copied logs under `C:\WinPush` or the caller-supplied `OutputRoot` when no longer needed
- remove any remote files or changes created by caller-supplied command text, scripts, or file transfers

---

## Maturity

`Testing`

The module foundation, result contracts, target resolution, connectivity checks across direct, pipeline, and host-file targets, credential pass-through behavior, direct, pipeline, and host-file target command summary execution with credential support, explicit cmd.exe command text through PSRP, command error-stream semantics, command capture-output artifacts, command-attached log copy, direct, pipeline, or host-file local `.ps1` execution with credential support, script capture-output artifacts, script-attached log copy, single-file PSRP upload/download transfer, and direct, pipeline, or host-file remote log directory copy exist. Automatic cmd.exe wrapping, native command transports, recursive transfer, multi-target transfer, recursive log enumeration, and package workflow execution are not yet implemented.

## Version

Current version: `0.1.0`

Version source: `WinPush.psd1`

Release notes: release notes are not tracked separately.

## Ownership And Support

- Owner: Endpoint Engineering
- Support contact: Endpoint Engineering
- Repository path: `Modules/WinPush`

---

## Support Files

- `src/`: runtime entry points and implementation logic
- `src/Public/`: exported command implementations
- `src/Private/`: module-local runtime helper code
- `tests/`: validation and regression coverage
- `build/`: module-local build and quality-gate entry point
- `artifacts/`: ignored generated build, test, coverage, and validation output

---

## Notes

- Keep README content aligned with the module manifest, exported commands, parameters, and output behavior.
- Do not commit secrets, tokens, private keys, certificates, or credential-bearing connection strings.
- Do not commit runtime-generated logs, exports, receipts, state files, or packages unless they are documented contract examples.
- Prefer explicit parameters, clear failure behavior, and safe defaults.
