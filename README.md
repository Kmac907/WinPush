# WinPush

## Overview

`WinPush` is a PowerShell 7.6 script module for Windows administrators and automation engineers. The MVP will use PSRP over WinRM to test targets, run command text and local scripts, transfer individual files, and retrieve text logs from an explicit remote directory.

The module currently exports the first completed public command, `Test-WinPushTarget`, for single-target PSRP connectivity checks with the current Windows identity.

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
| `Test-WinPushTarget` | Tests PSRP session creation for one direct `-ComputerName` using the current Windows identity and returns a `WinPush.ExecutionResult`. |

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
Test-WinPushTarget
```

## Output

`Test-WinPushTarget` returns a structured PowerShell object with `PSTypeName = WinPush.ExecutionResult`.

| Contract | Purpose |
| --- | --- |
| `WinPush.ExecutionResult` | Per-target operation result envelope. |
| `WinPush.LogResult` | Per-file remote log read result. |

## Side Effects

Importing the module loads functions from the module-local `Private` and `Public` folders. It does not open network connections, create remote sessions, write generated runtime output, or persist state.

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

The module foundation, result contracts, target resolution, and single-target current-identity connectivity command exist. Credentialed connectivity, multi-target connectivity, command/script execution, file transfer, and log collection are not yet implemented.

## Version

Current version: `0.1.0`

Version source: `src/WinPush/WinPush.psd1`

## Ownership And Support

- Owner: Endpoint Engineering
- Repository path: `Modules/WinPush`
