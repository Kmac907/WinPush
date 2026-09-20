# WinPush

## Overview

`WinPush` is a PowerShell 7.6 module for Windows endpoint administration. It uses PSRP over WinRM by default to test targets, run commands, scripts, packages, and detect/remediate pairs, transfer individual files, retrieve logs, and inspect captured runs. Command, script, and remediation execution can also use WinRS or PsExec when those native tools are already available.

The module provides:

- PSRP target connectivity checks
- remote command and local script execution
- single-file upload and download
- remote log retrieval
- package staging, execution, output capture, log copy, and cleanup through PSRP
- Windows PowerShell 5.1 remediation validation and detect/remediate execution
- captured-run history and Entra group host-file export
- structured per-target result objects

## Purpose

This module exists to provide a repeatable PowerShell controller workflow for Windows endpoint administration.

Use this module when you need to:

- validate whether Windows targets can accept PSRP sessions
- run controlled command text or local `.ps1` files on one or more targets
- copy one file to or from a target
- retrieve immediate files from a known remote log directory
- stage and run a local or URI package with one package-relative PowerShell entry point
- validate and run a detection/remediation script pair
- read a captured `summary.csv` or export Entra device names to a host file
- optionally write local execution artifacts for review

Out of scope:

- automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration
- credential storage
- recursive transfer, recursive log copy, retries, parallel fan-out, SSH transport, package manifests, package dependency graphs, package signing, or mandatory checksum policy

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

WinPush is currently distributed from source. Clone the repository:

```text
git clone https://github.com/Kmac907/WinPush.git
```

Import the module from the cloned directory:

```powershell
Import-Module .\WinPush\WinPush.psd1 -Force
Get-Command -Module WinPush
```

From the repository root, use:

```powershell
Import-Module .\WinPush.psd1 -Force
Get-Command -Module WinPush
```

## Quickstart

```powershell
Import-Module WinPush

Invoke-WinPushCommand -ComputerName PC01 -Command 'whoami'
```

Expected result:

```text
ComputerName Transport Status ExitCode OutputSummary ErrorSummary
------------ -------- ------ -------- ------------- ------------
PC01         Psrp     OK     0        PC01\operator
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
| `Get-WinPushRun` | Reads a captured run's `summary.csv` and maps each row to its safe per-target log path. |
| `Test-WinPushRemediation` | Validates detection and remediation scripts with the Windows PowerShell 5.1 parser without executing them. |
| `Invoke-WinPushRemediation` | Runs a detect/remediate pair through PSRP, WinRS, or PsExec. |
| `Export-WinPushHostFileFromEntraGroup` | Writes enabled Entra device display names from a group to a host file. |

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

Inspect the captured run returned by an execution result:

```powershell
$Run = Invoke-WinPushCommand -ComputerName PC01 -Command 'hostname' -CaptureOutput
Get-WinPushRun -Path $Run.RunDirectory
```

Validate and invoke a remediation pair:

```powershell
Test-WinPushRemediation -DetectScript .\Detect.ps1 -RemediateScript .\Remediate.ps1
Invoke-WinPushRemediation -ComputerName PC01 -DetectScript .\Detect.ps1 -RemediateScript .\Remediate.ps1
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

Remote execution and transfer commands return structured `WinPush.ExecutionResult` objects. `Get-WinPushRun` returns `WinPush.RunResult`, `Test-WinPushRemediation` returns `WinPush.RemediationValidationResult`, and Entra export returns written names only with `-PassThru`.

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
| `ArtifactError` | `string` | Local artifact-write failure, if any. It does not replace the primary remote outcome. |
| `Logs` | `WinPush.LogResult[]` | Per-file log copy results. |
| `CopiedLogPaths` | `string[]` | Local paths for successfully copied logs. |
| `RunDirectory` | `string` | Shared local run directory when artifacts are written. |
| `ComputerDirectory` | `string` | Per-target local artifact directory when artifacts are written. |
| `ResultPath` | `string` | Local per-target `run.log` path when captured output artifacts are written. |
| `StdOutPath` | `string` | Reserved for optional separate stdout diagnostics; blank for the default artifact contract. |
| `StdErrPath` | `string` | Reserved for optional separate stderr diagnostics; blank for the default artifact contract. |
| `Script` | `string` | Script file name for `Invoke-WinPushScript` results. Blank for other operations. |
| `RemediationMetadata` | `WinPush.RemediationMetadata` | Remediation status plus separate detection/remediation exit codes, output, and errors. |

Default formatting displays compact per-command tables. Every command summary includes the selected transport. `Invoke-WinPushCommand` adds `OutputSummary`, a short first-value command-output summary. Successful rows leave `ErrorSummary` blank; failed rows show a short normalized summary. Full output, full errors, logs, package metadata, and artifact paths remain available on the returned object with property access or `Format-List *`. When `-CaptureOutput` is used, detailed output and errors are written to root and per-target `run.log` files.

Generated files, logs, reports, or receipts:

| Artifact | Location | Purpose | Retention |
| --- | --- | --- | --- |
| Run summary | `<OutputRoot>\<timestamp>-<GUID>\summary.csv` | Run-level CSV summary for captured command, script, package, or remediation output. | Operator controlled. |
| Correlated run log | `<OutputRoot>\<timestamp>-<GUID>\run.log` | Human-readable run log updated gradually as stages, output, and errors occur. | Operator controlled. |
| Per-target run log | `<OutputRoot>\<timestamp>-<GUID>\<safe-target>\run.log` | Per-target log created before remote work and updated gradually. | Operator controlled. |
| Copied logs | `<OutputRoot>\<timestamp>-<GUID>\<safe-target>\Logs\` | Immediate files copied from documented remote log directories. | Operator controlled. |

Run names include a timestamp and GUID so concurrent runs cannot collide. Unsafe target names, including IPv6 addresses, reserved Windows names, separators, and traversal-like values, are converted to one safe directory component with a stable hash suffix; `ComputerName` in the result remains unchanged. Artifact failures are reported through `ArtifactError`, and execution continues where possible. This module does not write generated runtime output back into the repository.

## Prerequisites

- PowerShell 7.6 or later
- Windows controller
- Windows targets reachable over WinRM/PSRP
- current Windows identity or supplied `PSCredential` authorized on the target
- target-side permissions for the requested command, script, file copy, or log retrieval operation
- elevated PowerShell when using WinRM or PsExec native transports
- PsExec available locally when using `-Transport PsExec`; WinPush invokes it with `-h` so the remote process uses an elevated token when available
- Microsoft Graph PowerShell commands and an authenticated `Connect-MgGraph` context only when using `Export-WinPushHostFileFromEntraGroup`; Graph is not a required module dependency

## Testing

Run the offline quality gate from this module folder:

```powershell
.\build\build.ps1
```

The gate validates the manifest, imports the module, runs PSScriptAnalyzer, runs the 451-test offline baseline with Pester 3.4.0, and writes test and coverage artifacts under `artifacts\build`. The enforced command-coverage minimum is 82.09 percent; the build fails below it. Live targets are opt-in, so the default gate remains offline.

Install and retain the exact test dependency:

```powershell
Install-Module Pester -RequiredVersion 3.4.0 -Scope CurrentUser
```

Optional transport smoke checks are explicit build parameters:

```powershell
.\build\build.ps1 -PsrpTarget PC01
.\build\build.ps1 -WinRsTarget PC01
.\build\build.ps1 -PsExecTarget PC01 -PsExecPath C:\Tools\PsExec.exe
```

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

## Migrating From 0.1.0

Version 0.2.0 is pre-1.0 and intentionally changes the contract:

- the exported surface grows from six to ten commands with `Get-WinPushRun`, `Test-WinPushRemediation`, `Invoke-WinPushRemediation`, and `Export-WinPushHostFileFromEntraGroup`
- run folders change from timestamp-only names to timestamp/GUID names, and raw target directory names are replaced only when needed with safe hashed names
- command execution adds `-Shell` and native execution adds `-TimeoutSeconds`; timeout failures use exit code `124`
- capture is gradual, and artifact failures are separated from the primary operation in `ArtifactError`
- URI packages require HTTPS, accept optional `-ExpectedSha256`, use temporary per-run cache directories, require an absolute `-RemoteStageRoot`, and accept positional package `-ArgumentList`
- remediation results add `RemediationMetadata`; existing execution result fields remain available

No Microsoft Graph module is loaded or required at import time. Package hashes remain optional, so callers that require content pinning must supply `-ExpectedSha256`.

## Notes

- Keep README content aligned with the module manifest, exported commands, parameters, and output behavior.
- Keep detailed command behavior in [docs/commands.md](docs/commands.md).
- Keep long-form usage examples in [docs/examples.md](docs/examples.md).
- Keep package workflow, versioning, and roadmap details in [docs/packaging.md](docs/packaging.md).
- Do not commit secrets, tokens, private keys, certificates, or credential-bearing connection strings.
- Do not commit runtime-generated logs, exports, receipts, state files, or packages unless they are documented contract examples.
- Prefer explicit parameters, clear failure behavior, and safe defaults.
