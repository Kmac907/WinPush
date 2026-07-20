# WinPush

## Overview

`WinPush` is a PowerShell 7.6 module for Windows endpoint administration. It uses PSRP over WinRM by default to test targets, run command text, run local PowerShell scripts, transfer individual files, retrieve text logs, and run simple package workflows. Command and script execution can also use WinRS or PsExec when those native tools are already available.

The module provides:

- PSRP target connectivity checks
- remote command and local script execution
- single-file upload and download
- remote log retrieval
- package staging, execution, output capture, log copy, and cleanup through PSRP
- structured per-target result objects

## Purpose

This module exists to provide a repeatable PowerShell controller workflow for Windows endpoint administration.

Use this module when you need to:

- validate whether Windows targets can accept PSRP sessions
- run controlled command text or local `.ps1` files on one or more targets
- copy one file to or from a target
- retrieve immediate files from a known remote log directory
- stage and run a local or URI package with one package-relative PowerShell entry point
- optionally write local execution artifacts for review

Out of scope:

- automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration
- credential storage
- recursive transfer, recursive log copy, retries, parallel fan-out, SSH transport, package manifests, package dependency graphs, or package integrity policy

## Repository Layout

```text
WinPush/
├─ README.md
├─ WinPush.psd1
├─ WinPush.psm1
├─ WinPush.format.ps1xml
├─ src/
│  ├─ Public/
│  └─ Private/
├─ docs/
├─ tests/
│  ├─ Fixtures/
│  ├─ Integration/
│  └─ Unit/
└─ build/
   └─ build.ps1
```

Notes:

- `WinPush.psd1` and `WinPush.psm1` are the PowerShell module entry points required for normal `Import-Module` behavior.
- Runtime implementation must stay inside this module folder, normally under `src/` and optional module-local `lib/`.
- Runtime code must not import helper code from sibling module folders.
- `docs/` is for human-facing supporting material only.
- `tests/` is for validation and regression coverage.
- `build/` is for the module-local build and validation entry point; it is not runtime code or pipeline-only deployment logic.
- `packaging/` is not currently used.
- Generated build, test, package, log, or report output must be written outside committed source folders, normally under the ignored `artifacts/` folder.

## Install

Published modules are installed from the private `SCFModules` Azure Artifacts NuGet feed.

Register the repository once per machine from an elevated PowerShell 7 session:

```powershell
$FeedUri = 'https://pkgs.dev.azure.com/scfitops/_packaging/SCFModules/nuget/v3/index.json'

Install-Module Microsoft.PowerShell.PSResourceGet -Scope AllUsers -Force -AllowClobber

Register-PSResourceRepository `
    -Name SCFModules `
    -Uri $FeedUri `
    -Trusted `
    -ApiVersion V3 `
    -Force
```

Install WinPush for all users:

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

Verify installation:

```powershell
Get-Module -ListAvailable WinPush |
    Select-Object Name, Version, ModuleBase

Get-InstalledPSResource -Name WinPush -Scope AllUsers
Get-Command -Module WinPush
```

For local development from this module folder:

```powershell
Import-Module .\WinPush.psd1 -Force
Get-Command -Module WinPush
```

WinPush is installed with `-Scope AllUsers` only. Run installation and updates from an elevated PowerShell 7 session.

## Quickstart

```powershell
Import-Module WinPush

Invoke-WinPushCommand -ComputerName PC01 -Command 'whoami'
```

Expected result:

```text
ComputerName Status ExitCode ErrorSummary
------------ ------ -------- ------------
PC01         OK     0
```

## Command Summary

| Command | Purpose |
| --- | --- |
| `Test-WinPushTarget` | Tests whether one or more targets can create PSRP sessions. |
| `Invoke-WinPushCommand` | Runs command text on one or more targets through PSRP, WinRS, or PsExec. |
| `Invoke-WinPushScript` | Runs an existing local `.ps1` file on one or more targets through PSRP, WinRS, or PsExec. |
| `Copy-WinPushItem` | Uploads or downloads one file through PSRP. |
| `Get-WinPushLog` | Copies immediate files from an explicit remote log directory. |
| `Invoke-WinPushPackage` | Stages a local or cached URI package through PSRP, runs one package-relative `.ps1` entry point, and can capture output, copy logs, and clean remote staging. |

Command standards:

- public commands use approved PowerShell verbs
- exported commands are explicit in the module manifest
- command details are documented in [docs/commands.md](docs/commands.md)

## Common Examples

Test a target:

```powershell
Test-WinPushTarget -ComputerName PC01
```

Run command text:

```powershell
Invoke-WinPushCommand -ComputerName PC01 -Command 'hostname'
```

Run command text and capture output files:

```powershell
Invoke-WinPushCommand `
    -ComputerName PC01 `
    -Command 'hostname' `
    -CaptureOutput `
    -OutputRoot C:\WinPush
```

Run a local script:

```powershell
Invoke-WinPushScript `
    -ComputerName PC01 `
    -ScriptPath .\Install-EA.ps1
```

Run a local script through WinRS:

```powershell
Invoke-WinPushScript `
    -ComputerName PC01 `
    -ScriptPath .\Install-EA.ps1 `
    -Transport WinRM
```

Native script transports copy the script through small native PowerShell staging commands, invoke the staged file under `C:\Windows\Temp\WinPush\<stage-id>\`, and remove the staged folder after execution. Use `-KeepStagedScript` only when you need to inspect the staged file after a run.

Run a package and copy package logs:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1 `
    -CaptureOutput `
    -Logs `
    -Cleanup OnSuccess
```

Copy a file to a target:

```powershell
Copy-WinPushItem `
    -ComputerName PC01 `
    -Path .\payload.txt `
    -Destination C:\Windows\Temp\payload.txt
```

More examples are in [docs/examples.md](docs/examples.md).

## Output Contract

WinPush public commands return structured PowerShell objects with `PSTypeName = WinPush.ExecutionResult`.

| Property Or Output | Type | Meaning |
| --- | --- | --- |
| `ComputerName` | `string` | Target name for the result. |
| `Transport` | `string` | Transport used, such as `Psrp`, `WinRM`, or `PsExec`. |
| `Operation` | `string` | Operation name, such as `TestTarget`, `RunCommand`, `RunScript`, `RunPackage`, `CopyFile`, or `GetLogs`. |
| `Succeeded` | `bool` | Whether the target operation succeeded. |
| `ExitCode` | `int` / `$null` | Command, script, native process, or synthetic operation exit code. |
| `Output` | `object[]` | Captured output records retained in the result object. |
| `Errors` | `object[]` | Captured error records retained in the result object. |
| `ErrorMessage` | `string` | Human-readable failure message when available. |
| `Logs` | `WinPush.LogResult[]` | Per-file log copy results. |
| `CopiedLogPaths` | `string[]` | Local paths for successfully copied logs. |
| `RunDirectory` | `string` | Shared local run directory when artifacts are written. |
| `ComputerDirectory` | `string` | Per-target local artifact directory when artifacts are written. |
| `ResultPath` | `string` | Local per-target `run.log` path when captured output artifacts are written. |
| `StdOutPath` | `string` | Reserved for optional separate stdout diagnostics; blank for the default artifact contract. |
| `StdErrPath` | `string` | Reserved for optional separate stderr diagnostics; blank for the default artifact contract. |

Default formatting displays compact per-command tables. Command and script rows show target status, exit code, and a short error summary without printing remote output. Package rows add package, cleanup, and log-copy columns. Copy, log, and target-test rows show only the fields needed to understand that operation. Full output, errors, logs, package metadata, and artifact paths remain available on the returned object with property access or `Format-List *`. When `-CaptureOutput` is used, detailed output and errors are also written to each target's `run.log`.

Generated files, logs, reports, or receipts:

| Artifact | Location | Purpose | Retention |
| --- | --- | --- | --- |
| Run summary | `<OutputRoot>\<timestamp>\summary.csv` | Run-level CSV summary for captured command, script, or package output. | Operator controlled. |
| Per-target run log | `<OutputRoot>\<timestamp>\<ComputerName>\run.log` | Human-readable per-target status, command/script/package identity, output, and errors. | Operator controlled. |
| Copied logs | `<OutputRoot>\<timestamp>\<ComputerName>\Logs\` | Immediate files copied from documented remote log directories. | Operator controlled. |

This module does not write generated runtime output back into the repository.

## Prerequisites

- PowerShell 7.6 or later
- Windows controller
- Windows targets reachable over WinRM/PSRP
- current Windows identity or supplied `PSCredential` authorized on the target
- Azure DevOps feed read access when installing from `SCFModules`
- target-side permissions for the requested command, script, file copy, or log retrieval operation
- elevated PowerShell when using WinRM or PsExec native transports
- PsExec available locally when using `-Transport PsExec`; WinPush invokes it with `-h` so the remote process uses an elevated token when available

## Testing

Run the offline quality gate from this module folder:

```powershell
.\build\build.ps1
```

The gate validates the manifest, imports the module, runs PSScriptAnalyzer, runs offline unit tests, and writes CI-readable test and coverage artifacts under `artifacts\build`.

The import foundation can also be checked manually with:

```powershell
Test-ModuleManifest .\WinPush.psd1
Import-Module .\WinPush.psd1 -Force
```

Manual validation:

- test a known reachable target with `Test-WinPushTarget`
- run a harmless command with `Invoke-WinPushCommand`
- confirm captured output artifacts when using `-CaptureOutput`
- confirm copied logs when using `-Logs`
- run package workflow integration with `.\tests\Integration\Invoke-WinPushPackageLiveValidation.ps1 -ComputerName PC01`

## Notes

- Keep README content aligned with the module manifest, exported commands, parameters, and output behavior.
- Keep detailed command behavior in [docs/commands.md](docs/commands.md).
- Keep long-form usage examples in [docs/examples.md](docs/examples.md).
- Keep package workflow, versioning, and roadmap details in [docs/packaging.md](docs/packaging.md).
- Do not commit secrets, tokens, private keys, certificates, or credential-bearing connection strings.
- Do not commit runtime-generated logs, exports, receipts, state files, or packages unless they are documented contract examples.
- Prefer explicit parameters, clear failure behavior, and safe defaults.
