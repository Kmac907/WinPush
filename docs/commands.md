# WinPush Command Reference

## Command Behavior

| Command | Behavior |
| --- | --- |
| `Test-WinPushTarget` | Tests PSRP session creation for direct `-ComputerName`, pipeline, or `-HostFile` targets sequentially using the current Windows identity or an optional `-Credential`. Returns one `WinPush.ExecutionResult` per resolved target. |
| `Invoke-WinPushCommand` | Runs non-empty command text on direct `-ComputerName`, pipeline, pipeline-by-property-name `ComputerName`, or `-HostFile` targets. PSRP is the default transport. `-Transport WinRM` runs current-identity commands through `winrs.exe`. `-Transport PsExec` runs current-identity commands through operator-supplied `PsExec.exe`. |
| `Invoke-WinPushScript` | Runs one existing local `.ps1` file on direct `-ComputerName`, pipeline, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP using `Invoke-Command -FilePath`. |
| `Copy-WinPushItem` | Uploads one existing local file to one target through `Copy-Item -ToSession`, or downloads one remote file through `Copy-Item -FromSession` when `-Direction Download` is supplied. |
| `Get-WinPushLog` | Copies immediate regular files from one explicit absolute remote Windows directory to the target's local `Logs` folder under a timestamped output run folder. |

## Parameters

| Command | Parameter | Required | Default | Purpose |
| --- | --- | --- | --- | --- |
| `Test-WinPushTarget` | `ComputerName` | Yes for direct or pipeline target input | None | Target names supplied directly, by pipeline string, or by pipeline property name. |
| `Test-WinPushTarget` | `HostFile` | Yes for host-file input | None | UTF-8 file containing target names. |
| `Test-WinPushTarget` | `Credential` | No | Current identity | Credential used for PSRP session creation. |
| `Invoke-WinPushCommand` | `ComputerName` | Yes for direct or pipeline target input | None | Target names supplied directly, by pipeline string, or by pipeline property name. |
| `Invoke-WinPushCommand` | `HostFile` | Yes for host-file input | None | UTF-8 file containing target names. |
| `Invoke-WinPushCommand` | `Command` | Yes | None | Command text to run remotely. PSRP treats it as PowerShell source; native transports use native command text. |
| `Invoke-WinPushCommand` | `Transport` | No | `Psrp` | Transport mode: `Psrp`, command-only current-identity `WinRM`/`winrs.exe`, or command-only current-identity `PsExec`/`PsExec.exe`. |
| `Invoke-WinPushCommand` | `PsExecPath` | No | PATH discovery | Explicit local path to `PsExec.exe`; only valid with `-Transport PsExec`. |
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

## Target Input

- Direct target arrays, pipeline strings, pipeline `ComputerName` properties, and host files are supported where documented per command.
- `Copy-WinPushItem` intentionally supports one target and one file per call.
- Host files must resolve to deterministic target names before remote work starts.
- Script execution accepts existing local `.ps1` files only.

Avoid:

- passing empty target names, command text, script paths, destination paths, output roots, or remote log directories
- using wildcard-expanded file transfer paths
- assuming WinPush configures WinRM or target firewall policy

## Transport Notes

PSRP command text is PowerShell source. Explicit command-shell invocations such as `cmd.exe /d /s /c "echo winpush"` are accepted as caller-supplied PowerShell command text; WinPush does not add automatic `cmd.exe` wrapping for PSRP.

WinRM transport launches `winrs.exe` once per resolved target. It keeps native standard output text in `Output`, native standard error text in `Errors`, and sets `ExitCode` to the native process exit code.

PsExec transport launches operator-supplied or PATH-discovered `PsExec.exe` once per resolved target. PsExec executes the supplied command text through remote `cmd.exe /d /s /c`. WinPush does not download, bundle, license, or redistribute PsExec.

`-Credential`, `-CaptureOutput`, and `-Logs` are rejected for WinRM and PsExec before launching a process.

## Logs

`Get-WinPushLog` copies immediate regular files only from an explicit remote directory. It does not read copied file contents into memory, traverse nested directories, create remote directories, write `summary.csv` or `result.txt`, or recurse.

`Invoke-WinPushCommand -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<command-name>\`, where `<command-name>` is derived from the first command name in the supplied PowerShell source and falls back to `Command`.

`Invoke-WinPushScript -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<script-name>\`, where `<script-name>` is the local script file base name.

Attached command and script logs reuse the same PSSession, run after the command or script attempt, populate `Logs` and `CopiedLogPaths`, and do not change the primary command or script success state.

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

## Side Effects

Importing the module loads functions from the module-local `Private` and `Public` folders. It does not open network connections, create remote sessions, write generated runtime output, or persist state.

Command and script behavior is determined by caller-supplied command text or script content. File upload and download operations write to caller-selected paths. Captured output and copied logs persist under the caller-selected local `OutputRoot`. Temporary PSRP sessions are created for the duration of each target operation.

## Known Limitations

- PowerShell 7.6 `Core` is the supported controller shell.
- Windows PowerShell 5.1 compatibility is not guaranteed.
- `Invoke-WinPushPackage` is planned but not implemented or exported.
- SSH transport, retries, parallel fan-out, persistent sessions, and transport fallback are not implemented.
- Automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration is not implemented.
- Recursive file transfer, recursive log enumeration, and multi-target file transfer are not implemented.
- Script arguments are not implemented for `Invoke-WinPushScript`.
- `Copy-WinPushItem` supports one target and one file per call.
