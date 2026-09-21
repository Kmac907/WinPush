<p align="center">
  <img src="docs/assets/winpush-logo.svg"
       width="700"
       alt="WinPush">
</p>

<h1 align="center">WinPush</h1>

<p align="center">
  <strong>PSRP-first remote administration for Windows endpoints.</strong><br>
  <em>Run, transfer, capture, remediate, and inspect with structured results.</em>
</p>

<p align="center">
  <img alt="PowerShell 7.6 or newer" src="https://img.shields.io/badge/PowerShell-7.6%2B-2563EB">
  <img alt="Windows platform" src="https://img.shields.io/badge/platform-Windows-0B1220">
</p>

---

WinPush is a PowerShell module for repeatable Windows endpoint administration. It uses PowerShell Remoting Protocol (PSRP) over WinRM by default and returns structured, per-target results. Command, script, and remediation execution can also use WinRS or an operator-supplied PsExec executable.

> [!WARNING]
> WinPush executes caller-supplied commands and scripts on remote computers. Confirm the target list, authorization, package provenance, and requested side effects before running a command. WinPush does not configure WinRM, firewall rules, TrustedHosts, certificates, endpoints, or policy for you.

## Why WinPush

- Test PSRP connectivity before a change.
- Run command text, local PowerShell scripts, packages, and detect/remediate pairs.
- Upload or download one file and retrieve immediate files from a remote log directory.
- Resolve targets consistently from arguments, pipeline input, or host files.
- Capture correlated root and per-target logs without replacing the remote outcome when local artifact writes fail.
- Inspect captured `summary.csv` files and export Entra device names to a host file.
- Use compact default formatting while retaining full output, errors, metadata, and artifact paths.

WinPush intentionally does not implement automatic transport configuration, credential storage, retries, parallel fan-out, SSH, recursive file transfer, recursive log copy, package manifests, dependency graphs, signing, or mandatory checksums.

## Requirements

- PowerShell 7.6 or newer, Core edition, on a Windows controller.
- Windows targets reachable over WinRM/PSRP and an authorized current identity or `PSCredential`.
- Target-side permissions for each requested command, script, file, log, or package operation.
- An elevated controller session for native WinRS or PsExec transports.
- An available `PsExec.exe` when using `-Transport PsExec`; WinPush does not download or redistribute it.
- Installed Microsoft Graph PowerShell commands and an authenticated `Connect-MgGraph` context only for `Export-WinPushHostFileFromEntraGroup`.

## Install

Clone the repository:

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

## First command

```powershell
Import-Module .\WinPush.psd1 -Force
Invoke-WinPushCommand -ComputerName PC01 -Command 'whoami'
```

Representative output:

```text
ComputerName Transport Status ExitCode OutputSummary ErrorSummary
------------ --------- ------ -------- ------------- ------------
PC01         Psrp      OK     0        PC01\operator
```

## Choose a command

| Task | Command |
| --- | --- |
| Test whether targets accept PSRP sessions | `Test-WinPushTarget` |
| Run command text | `Invoke-WinPushCommand` |
| Run an existing local `.ps1` file | `Invoke-WinPushScript` |
| Upload or download one file | `Copy-WinPushItem` |
| Copy immediate files from a remote log directory | `Get-WinPushLog` |
| Stage and run a local or HTTPS package | `Invoke-WinPushPackage` |
| Read a captured run's `summary.csv` | `Get-WinPushRun` |
| Validate a detect/remediate pair without executing it | `Test-WinPushRemediation` |
| Run a detect/remediate pair | `Invoke-WinPushRemediation` |
| Export Entra group device names to a host file | `Export-WinPushHostFileFromEntraGroup` |

## Documentation

- [Command behavior and output](docs/commands.md)
- [Task-oriented examples](docs/examples.md)
- [Package workflow](docs/package-workflow.md)
- [Development, testing, and releases](docs/development.md)
- [Release history](CHANGELOG.md)
- [Security guidance](SECURITY.md)

## Transport support

| Command | PSRP | WinRS (`WinRM`) | PsExec | Local or service API |
| --- | --- | --- | --- | --- |
| `Test-WinPushTarget` | Yes | No | No | No |
| `Invoke-WinPushCommand` | Yes | Yes | Yes | No |
| `Invoke-WinPushScript` | Yes | Yes | Yes | No |
| `Copy-WinPushItem` | Yes | No | No | No |
| `Get-WinPushLog` | Yes | No | No | No |
| `Invoke-WinPushPackage` | Yes | No | No | No |
| `Get-WinPushRun` | No | No | No | Local files |
| `Test-WinPushRemediation` | No | No | No | Local Windows PowerShell 5.1 parser |
| `Invoke-WinPushRemediation` | Yes | Yes | Yes | No |
| `Export-WinPushHostFileFromEntraGroup` | No | No | No | Microsoft Graph |

`Psrp` is the default transport. The public value `WinRM` selects native `winrs.exe`; it does not select the PSRP-over-WinRM default.

## Results and artifacts

Remote operations return `WinPush.ExecutionResult` objects. `Get-WinPushRun` returns `WinPush.RunResult`; `Test-WinPushRemediation` returns `WinPush.RemediationValidationResult`; Entra export emits written names only with `-PassThru`.

Execution results retain `ComputerName`, `Transport`, `Operation`, `Succeeded`, `ExitCode`, `Output`, `Errors`, `ErrorMessage`, `ArtifactError`, `Logs`, `CopiedLogPaths`, and artifact paths. Script, package, and remediation operations add their relevant metadata. Use `Format-List *` to inspect the full object.

With `-CaptureOutput`, WinPush creates a shared run directory whose timestamp and GUID prevent same-second collisions. Unsafe target names are converted to a safe directory component with a stable hash suffix while the result's `ComputerName` stays unchanged.

```text
<OutputRoot>\<timestamp>-<GUID>\
|-- summary.csv
|-- run.log
`-- <safe-target>\
    |-- run.log
    `-- Logs\
        `-- <copied files>
```

Root and per-target `run.log` files are updated gradually. `ArtifactError` reports local write failures without replacing the primary remote result. See [command behavior and output](docs/commands.md#capture-layout-and-safe-target-paths) for the complete contract.

## Native help

Every exported command includes comment-based help:

```powershell
Get-Help Invoke-WinPushCommand -Full
Get-Help Invoke-WinPushPackage -Examples
Get-Help Copy-WinPushItem -Parameter Direction
```

## Develop

Run the offline quality gate from the repository root:

```powershell
.\build\build.ps1
```

The gate validates the manifest, imports the module, runs PSScriptAnalyzer, runs the offline Pester 3.4.0 suite, enforces the coverage threshold defined in build configuration, and writes results under `artifacts\build`. See the [development guide](docs/development.md) for prerequisites, optional live checks, packaging, and releases.

## Support and security

- Review command behavior and current limitations in the [command guide](docs/commands.md).
- Report suspected vulnerabilities privately according to [SECURITY.md](SECURITY.md).
- Review the repository's [GPL-3.0-only license](LICENSE).
- Project source: [github.com/Kmac907/WinPush](https://github.com/Kmac907/WinPush).
