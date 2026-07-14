# WinPush

## Overview

`WinPush` is a PowerShell 7.6 script module for Windows administrators and automation engineers. The MVP will use PSRP over WinRM to test targets, run command text and local scripts, transfer individual files, and retrieve text logs from an explicit remote directory.

The module currently exports completed PSRP connectivity checks, `Invoke-WinPushCommand` execution for direct, pipeline, or host-file targets with optional captured-output artifacts, direct, pipeline, or host-file local `.ps1` execution through `Invoke-WinPushScript` with optional credential support, single-file PSRP upload/download through `Copy-WinPushItem`, and single-target remote log directory enumeration through `Get-WinPushLog`.

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
│  └─ WinPush/
│     ├─ WinPush.psd1
│     ├─ WinPush.psm1
│     ├─ Public/
│     └─ Private/
└─ tests/
   └─ Unit/
```

## Public Commands

| Command | Current behavior |
| --- | --- |
| `Copy-WinPushItem` | Uploads one existing local file to one resolved `-ComputerName` target through a temporary PSRP session using `Copy-Item -ToSession`, or downloads one remote file through `Copy-Item -FromSession` when `-Direction Download` is supplied. Upload remains the default direction. For uploads, `-Path` is validated as a non-empty existing local file before any session is opened; directories, missing files, and wildcard-expanded paths are not accepted. For downloads, `-Path` is treated as non-empty remote source text and `-Destination` must be a valid local file, local directory, or missing leaf whose parent directory already exists. `-Destination` is validated as non-empty and then passed to the copy operation unchanged. The command does not support pipeline input, `-HostFile`, arrays, recursion, artifact writing, logs, automatic directory creation, or multi-target transfer. Success returns one `WinPush.ExecutionResult` with `Transport = Psrp`, `Operation = CopyFile`, `ExitCode = 0`, and transfer metadata in `Output`. |
| `Get-WinPushLog` | Validates one explicit absolute Windows `-RemoteDirectory` path for one resolved `-ComputerName` target, opens a temporary PSRP session, verifies the remote path is an existing directory, and enumerates immediate regular files only. Success returns one `WinPush.ExecutionResult` with `Transport = Psrp`, `Operation = GetLogs`, `ExitCode = 0`, and file metadata in `Output`. Empty valid directories are successful zero-file outcomes. Missing, inaccessible, or non-directory remote paths return a failed result. This command does not copy logs, read file contents, traverse nested directories, create remote directories, write local artifacts, or support pipeline input, `-HostFile`, arrays, or recursion yet. |
| `Invoke-WinPushCommand` | Runs non-empty PowerShell command text on direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP sequentially using the current Windows identity or an optional `-Credential`, and returns one `WinPush.ExecutionResult` summary per resolved target. Explicit command-shell invocations such as `cmd.exe /d /s /c "echo winpush"` are accepted as caller-supplied PowerShell command text; WinPush does not add automatic `cmd.exe` wrapping. Command output and command errors are preserved together; command errors set `Succeeded = $false` and `ExitCode = 1`. `-CaptureOutput` writes `summary.csv`, per-target `result.txt`, `stdout.txt`, and `stderr.txt` under one shared timestamped `-OutputRoot` run folder with one child folder per target. |
| `Invoke-WinPushScript` | Runs one existing local `.ps1` file on direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP using `Invoke-Command -FilePath` and the current Windows identity or an optional `-Credential`. Direct arrays, pipeline targets, and host-file targets are resolved through the standard target resolver, execute sequentially, return one `WinPush.ExecutionResult` per resolved target in order, and continue after one target fails. Invalid, missing, directory, and non-`.ps1` script paths fail before a session is opened; invalid or missing host files also fail before a session is opened. Success returns `Transport = Psrp`, `Operation = RunScript`, and `ExitCode = 0`; script errors return `Succeeded = $false`, `ExitCode = 1`, and retain script output in `Output` while script errors are kept in `Errors`. Raw script output and errors are returned inside the result object rather than emitted as separate terminal output. `-CaptureOutput` writes retained output to `stdout.txt`, script errors to `stderr.txt`, plus `summary.csv` and per-target `result.txt`; multi-target direct, pipeline, and host-file runs share one timestamped run folder with one child folder per `ComputerName`. Script arguments and logs are not implemented for script execution yet. |
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

- Windows controller.
- PowerShell 7.6 or later.

## Local Development Import

From this module folder:

```powershell
Import-Module .\src\WinPush\WinPush.psd1 -Force
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

## Output

`Test-WinPushTarget`, `Invoke-WinPushCommand`, `Invoke-WinPushScript`, `Copy-WinPushItem`, and `Get-WinPushLog` return structured PowerShell objects with `PSTypeName = WinPush.ExecutionResult`.

| Contract | Purpose |
| --- | --- |
| `WinPush.ExecutionResult` | Per-target operation result envelope. |
| `WinPush.LogResult` | Per-file remote log read result. |

## Side Effects

Importing the module loads functions from the module-local `Private` and `Public` folders. It does not open network connections, create remote sessions, write generated runtime output, or persist state. `Copy-WinPushItem` creates one temporary PSRP session and uploads or downloads one caller-selected file without writing local artifacts or logs. `Get-WinPushLog` creates one temporary PSRP session and enumerates immediate regular files in one caller-selected remote directory without copying files or writing local artifacts. `Invoke-WinPushCommand -CaptureOutput` and `Invoke-WinPushScript -CaptureOutput` write local run artifacts under `C:\WinPush` by default, or under the caller-supplied `-OutputRoot`. Captured runs include run-level `summary.csv`, per-target `result.txt`, `stdout.txt`, and `stderr.txt`.

## Testing

Run the offline quality gate from this module folder:

```powershell
.\build\build.ps1
```

The gate validates the manifest, imports the module twice, runs PSScriptAnalyzer against `src`, `tests`, and `build`, runs offline unit tests, and writes CI-readable test and coverage artifacts under `artifacts\build`.

The import foundation can also be checked manually with:

```powershell
Test-ModuleManifest .\src\WinPush\WinPush.psd1
Import-Module .\src\WinPush\WinPush.psd1 -Force
```

## Maturity

`Experimental`

The module foundation, result contracts, target resolution, connectivity checks across direct, pipeline, and host-file targets, credential pass-through behavior, direct, pipeline, and host-file target command summary execution with credential support, explicit cmd.exe command text through PSRP, command error-stream semantics, command capture-output artifacts, direct, pipeline, or host-file local `.ps1` execution with credential support, single-file PSRP upload/download transfer, and single-target remote log directory enumeration exist. Automatic cmd.exe wrapping, native command transports, recursive transfer, multi-target transfer, log file copying, recursive log enumeration, and package workflow execution are not yet implemented.

## Version

Current version: `0.1.0`

Version source: `src/WinPush/WinPush.psd1`

## Ownership And Support

- Owner: Endpoint Engineering
- Repository path: `Modules/WinPush`
