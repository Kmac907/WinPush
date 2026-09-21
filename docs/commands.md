# WinPush command guide

This guide describes behavior shared across commands. For authoritative parameter syntax, validation, and examples, use `Get-Help <command> -Full`.

## Command index

| Command | Purpose | Result |
| --- | --- | --- |
| `Test-WinPushTarget` | Test PSRP session creation for each resolved target. | `WinPush.ExecutionResult` |
| `Invoke-WinPushCommand` | Run non-empty command text through PSRP, WinRS, or PsExec. | `WinPush.ExecutionResult` |
| `Invoke-WinPushScript` | Run one existing local `.ps1` file through PSRP, WinRS, or PsExec. | `WinPush.ExecutionResult` |
| `Copy-WinPushItem` | Upload or download one file through PSRP. | `WinPush.ExecutionResult` |
| `Get-WinPushLog` | Copy immediate files from an absolute remote directory through PSRP. | `WinPush.ExecutionResult` |
| `Invoke-WinPushPackage` | Stage and run a local or cached HTTPS package through PSRP. | `WinPush.ExecutionResult` |
| `Get-WinPushRun` | Read and type a captured run's `summary.csv`. | `WinPush.RunResult` |
| `Test-WinPushRemediation` | Parse a detect/remediate pair with Windows PowerShell 5.1 without executing it. | `WinPush.RemediationValidationResult` |
| `Invoke-WinPushRemediation` | Validate, stage, and run a detect/remediate pair. | `WinPush.ExecutionResult` |
| `Export-WinPushHostFileFromEntraGroup` | Write unique Entra device display names to a host file. | `string` only with `-PassThru` |

## Transport compatibility

| Command | `Psrp` | `WinRM` | `PsExec` | Non-transport execution |
| --- | --- | --- | --- | --- |
| `Test-WinPushTarget` | Yes | No | No | No |
| `Invoke-WinPushCommand` | Yes | Yes | Yes | No |
| `Invoke-WinPushScript` | Yes | Yes | Yes | No |
| `Copy-WinPushItem` | Yes | No | No | No |
| `Get-WinPushLog` | Yes | No | No | No |
| `Invoke-WinPushPackage` | Yes | No | No | No |
| `Get-WinPushRun` | No | No | No | Local files |
| `Test-WinPushRemediation` | No | No | No | Windows PowerShell 5.1 parser |
| `Invoke-WinPushRemediation` | Yes | Yes | Yes | No |
| `Export-WinPushHostFileFromEntraGroup` | No | No | No | Microsoft Graph |

`Psrp` is the default for commands that expose `-Transport`. It creates a temporary PSSession over WinRM. The public `WinRM` value means native `winrs.exe`, not PSRP.

WinRS launches `winrs.exe` once per resolved target. PsExec launches an operator-supplied or PATH-discovered `PsExec.exe`, passes `-h` to request an elevated remote token when available, and does not download, bundle, license, or redistribute PsExec.

Native script and remediation transports stage script content under `C:\Windows\Temp\WinPush\<stage-id>\` through small native PowerShell commands. Script stages are removed by default; `Invoke-WinPushScript -KeepStagedScript` retains its stage for troubleshooting. Remediation stages are always removed after execution.

## Target input and host-file resolution

`Test-WinPushTarget`, `Invoke-WinPushCommand`, `Invoke-WinPushScript`, `Get-WinPushLog`, `Invoke-WinPushPackage`, and `Invoke-WinPushRemediation` accept either `-ComputerName` or `-HostFile`. Their `ComputerName` parameter accepts pipeline strings and objects with a `ComputerName` property.

Resolution follows these rules:

- Trim target names and discard empty values.
- Remove duplicates case-insensitively while preserving first-seen order.
- Read host files as UTF-8.
- Ignore blank host-file lines and lines whose trimmed value starts with `#`.
- Fail before remote work when no usable target remains.

`Copy-WinPushItem` deliberately accepts exactly one target and one file per call. `Get-WinPushRun` and remediation validation operate on local paths. Entra export obtains targets from Microsoft Graph rather than the shared resolver.

## Authentication and credentials

PSRP commands use the current Windows identity unless `-Credential` is supplied. A supplied `PSCredential` is passed only to PSRP session creation.

`-Credential` is rejected with `-Transport WinRM` and `-Transport PsExec`. Those native transports use the controller process identity. PsExec and WinRS operations require the caller to arrange the relevant local executable, authorization, elevation, network, and target configuration.

`Export-WinPushHostFileFromEntraGroup` requires installed Graph commands and an existing authenticated Graph context. WinPush neither loads Microsoft Graph during import nor declares it as a module dependency.

## Shell and timeout behavior

`Invoke-WinPushCommand -Shell Auto` preserves the selected transport's default:

- PSRP interprets command text as PowerShell source.
- WinRS passes native command text to `winrs.exe`.
- PsExec executes command text through remote `cmd.exe /d /s /c`.

`-Shell PowerShell` forces encoded PowerShell. `-Shell Cmd` forces `cmd.exe /d /s /c`.

`-TimeoutSeconds` applies to native WinRS and PsExec command execution and to native staging or execution for scripts and remediation. It defaults to `1800`, accepts `0` through `2147483647`, and disables the timeout at `0`. A native-process timeout terminates the process tree and returns exit code `124`.

`Invoke-WinPushScript` has no script-argument parameter. `Invoke-WinPushPackage -ArgumentList` passes positional values to the package entry point in its declared parameter order.

## Result types and error handling

### Execution results

Remote operations return one `WinPush.ExecutionResult` per resolved target. Important properties include:

| Property | Meaning |
| --- | --- |
| `ComputerName` | Original target name. |
| `Transport` | `Psrp`, `WinRM`, or `PsExec`. |
| `Operation` | `TestTarget`, `RunCommand`, `RunScript`, `RunPackage`, `RunRemediation`, `CopyFile`, or `GetLogs`. |
| `Succeeded` | Primary operation outcome. |
| `ExitCode` | Process or synthetic operation code, or `$null` where no code applies. |
| `Output` / `Errors` | Full retained output and error records. |
| `ErrorMessage` | Human-readable primary failure when available. |
| `ArtifactError` | Local capture or log-copy failure; it does not replace the primary remote outcome. |
| `Logs` / `CopiedLogPaths` | Per-file copy results and successful local paths. |
| `RunDirectory` / `ComputerDirectory` / `ResultPath` | Local artifact paths when capture is active. |
| `StdOutPath` / `StdErrPath` | Reserved optional diagnostics; blank in the default artifact contract. |

Script results also retain `Script`. Package results carry `WinPush.PackageMetadata`. Remediation results carry `WinPush.RemediationMetadata` with `Status`, separate phase exit codes, output, and errors.

Multi-target operations continue after a per-target failure. Log-copy failures populate artifact and log details without changing the primary execution outcome. Invalid local inputs that affect the entire invocation can fail before any remote session opens.

### Other results

`Get-WinPushRun` preserves each CSV row, restores `Succeeded` to `bool` and `ExitCode` to `int` or `$null`, and adds `RunDirectory`, `TargetLogPath`, and `TargetLogExists`.

`Test-WinPushRemediation` returns `IsValid`, resolved script paths, `Errors`, and `Warnings`. File and Windows PowerShell 5.1 parser failures are errors. Missing literal `exit 0` or `exit 1` detection paths and detected reboot commands are warnings.

Entra export writes a file and normally emits no pipeline output. With `-PassThru`, it emits only device names written by that invocation.

## Output formatting

The module format file presents concise operation-specific tables. Every execution view includes the selected transport. `Invoke-WinPushCommand` adds a short, single-line `OutputSummary`; successful rows leave `ErrorSummary` blank, and failed rows show a normalized summary.

Default formatting does not remove data. Use property access or:

```powershell
$Result | Format-List *
$Result.Output
$Result.Errors
$Result.RemediationMetadata
$Result.PackageMetadata
```

Representative command output:

```text
ComputerName Transport Status ExitCode OutputSummary ErrorSummary
------------ --------- ------ -------- ------------- ------------
PC01         Psrp      OK     0        PC01
PC02         WinRM     Failed 1                      Access denied
```

## Capture layout and safe target paths

`-CaptureOutput` on command, script, package, and remediation execution writes one shared `summary.csv`, one correlated root `run.log`, and a per-target `run.log`:

```text
<OutputRoot>\<dd-MM-yyyy-HHmmss>-<GUID>\
|-- summary.csv
|-- run.log
`-- <safe-target>\
    |-- run.log
    `-- Logs\
        `-- <copied files>
```

Root and per-target logs are created before remote work and receive stage, output, and error records gradually. Run names include a GUID so concurrent same-second invocations do not share files.

Unsafe target names—including separators, traversal-like values, IPv6 addresses, and reserved Windows names—are converted to one bounded safe component with an eight-character SHA-256 suffix. `ComputerName` remains unchanged. `Get-WinPushRun` uses the same mapping when it constructs `TargetLogPath`.

Generated runtime output belongs under the caller-selected `OutputRoot`; WinPush does not write it into committed source folders.

## Log conventions

`Get-WinPushLog` copies immediate regular files only from an explicit absolute drive-rooted or UNC remote directory. It does not recurse, read copied file contents into memory, create remote directories, or write `summary.csv` or `run.log`.

Attached log collection uses these convention directories:

| Command | Remote directory |
| --- | --- |
| `Invoke-WinPushCommand -Logs` | `C:\ProgramData\EA\Logs\<first-command-name>\`, falling back to `Command` |
| `Invoke-WinPushScript -Logs` | `C:\ProgramData\EA\Logs\<script-base-name>\` |
| `Invoke-WinPushPackage -Logs` | `C:\ProgramData\EA\Logs\<entry-point-base-name>\` |
| `Invoke-WinPushRemediation -Logs` | One directory for each detect and remediate script base name |

Attached logs use the existing PSSession and run after the primary execution attempt. `-Logs` is unsupported with native WinRS and PsExec transports.

## Side effects

Importing WinPush only loads module-local functions and formatting. It does not open network connections, persist state, or create output.

Invoked commands can:

- create and remove temporary PSSessions
- execute caller-supplied text or scripts on remote targets
- upload, download, extract, and remove caller-selected files
- write local captures, copied logs, host files, and temporary URI package caches
- query Microsoft Graph through an existing authenticated context

Package-specific staging and cleanup behavior is documented in the [package workflow](package-workflow.md).

## Current limitations

- The supported controller is Windows with PowerShell 7.6 Core or newer; Windows PowerShell 5.1 controller compatibility is not guaranteed.
- SSH, retries, parallel fan-out, persistent sessions, and automatic transport fallback are not implemented.
- WinPush does not configure WinRM, firewall rules, TrustedHosts, certificates, endpoints, or policy.
- File transfer is single-target and single-file; log enumeration and transfer are non-recursive.
- `Invoke-WinPushScript` does not accept script arguments.
- Native script and remediation transports do not support `-Credential` or `-Logs`.
- Package entry points are PowerShell `.ps1` files. Package manifests, dependency graphs, native entry points, mandatory hashes, and signature enforcement are not implemented.
- `ExpectedSha256` is optional; callers remain responsible for provenance and approval policy.

## Get command help

Comment-based help is the parameter reference:

```powershell
Get-Help Test-WinPushTarget -Full
Get-Help Invoke-WinPushCommand -Full
Get-Help Invoke-WinPushPackage -Examples
Get-Help Export-WinPushHostFileFromEntraGroup -Parameter GroupName
```

For task recipes, see [examples](examples.md).
