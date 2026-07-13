# WinPush

## Overview

`WinPush` is a PowerShell 7.6 script module for Windows administrators and automation engineers. The MVP will use PSRP over WinRM to test targets, run command text and local scripts, transfer individual files, and retrieve text logs from an explicit remote directory.

The module currently exports completed PSRP connectivity checks, `Invoke-WinPushCommand` execution for direct, pipeline, or host-file targets with optional captured-output artifacts, and single-target local `.ps1` execution through `Invoke-WinPushScript`.

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
| `Invoke-WinPushCommand` | Runs non-empty PowerShell command text on direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP sequentially using the current Windows identity or an optional `-Credential`, and returns one `WinPush.ExecutionResult` summary per resolved target. Explicit command-shell invocations such as `cmd.exe /d /s /c "echo winpush"` are accepted as caller-supplied PowerShell command text; WinPush does not add automatic `cmd.exe` wrapping. Command output and command errors are preserved together; command errors set `Succeeded = $false` and `ExitCode = 1`. `-CaptureOutput` writes output to `stdout.txt` and errors to `stderr.txt` under one shared timestamped `-OutputRoot` run folder with one child folder per target. |
| `Invoke-WinPushScript` | Runs one existing local `.ps1` file on one direct `-ComputerName` target through PSRP using `Invoke-Command -FilePath` and the current Windows identity. Invalid, missing, directory, and non-`.ps1` paths fail before a session is opened. Success returns `Transport = Psrp`, `Operation = RunScript`, and `ExitCode = 0`. Raw script output is returned inside the result object rather than emitted as separate terminal output. `-CaptureOutput` writes output to `stdout.txt` and errors to `stderr.txt` under the target artifact folder. Script arguments, host files, pipeline targets, credentials, and logs are not implemented for script execution yet. |
| `Test-WinPushTarget` | Tests PSRP session creation for direct `-ComputerName`, pipeline, or `-HostFile` targets sequentially using the current Windows identity or an optional `-Credential` and returns one `WinPush.ExecutionResult` per resolved target. |

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
Invoke-WinPushCommand
Invoke-WinPushScript
Test-WinPushTarget
```

## Output

`Test-WinPushTarget`, `Invoke-WinPushCommand`, and `Invoke-WinPushScript` return structured PowerShell objects with `PSTypeName = WinPush.ExecutionResult`.

| Contract | Purpose |
| --- | --- |
| `WinPush.ExecutionResult` | Per-target operation result envelope. |
| `WinPush.LogResult` | Per-file remote log read result. |

## Side Effects

Importing the module loads functions from the module-local `Private` and `Public` folders. It does not open network connections, create remote sessions, write generated runtime output, or persist state. `Invoke-WinPushCommand -CaptureOutput` and `Invoke-WinPushScript -CaptureOutput` write local `stdout.txt` and `stderr.txt` artifacts under `C:\WinPush` by default, or under the caller-supplied `-OutputRoot`.

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

The module foundation, result contracts, target resolution, connectivity checks across direct, pipeline, and host-file targets, credential pass-through behavior, direct, pipeline, and host-file target command summary execution with credential support, explicit cmd.exe command text through PSRP, command error-stream semantics, command capture-output artifacts, and single-target local `.ps1` execution exist. Script target-source expansion, script credential parity, later script error semantics, automatic cmd.exe wrapping, native command transports, file transfer, and log collection are not yet implemented.

## Version

Current version: `0.1.0`

Version source: `src/WinPush/WinPush.psd1`

## Ownership And Support

- Owner: Endpoint Engineering
- Repository path: `Modules/WinPush`
