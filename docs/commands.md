# WinPush Command Reference

## Command Behavior

| Command | Behavior |
| --- | --- |
| `Test-WinPushTarget` | Tests PSRP session creation for direct `-ComputerName`, pipeline, or `-HostFile` targets sequentially using the current Windows identity or an optional `-Credential`. Returns one `WinPush.ExecutionResult` per resolved target. |
| `Invoke-WinPushCommand` | Runs non-empty command text on direct `-ComputerName`, pipeline, pipeline-by-property-name `ComputerName`, or `-HostFile` targets. PSRP is the default transport. `-Transport WinRM` runs current-identity commands through `winrs.exe`. `-Transport PsExec` runs current-identity commands through operator-supplied `PsExec.exe`. |
| `Invoke-WinPushScript` | Runs one existing local `.ps1` file on direct `-ComputerName`, pipeline, pipeline-by-property-name `ComputerName`, or `-HostFile` targets. PSRP uses `Invoke-Command -FilePath`. WinRM and PsExec stage the script through the selected native transport and execute the staged file through remote Windows PowerShell. |
| `Copy-WinPushItem` | Uploads one existing local file to one target through `Copy-Item -ToSession`, or downloads one remote file through `Copy-Item -FromSession` when `-Direction Download` is supplied. |
| `Get-WinPushLog` | Copies immediate regular files from one explicit absolute remote Windows directory to the target's local `Logs` folder under a timestamped output run folder. |
| `Invoke-WinPushPackage` | Stages one local package file or directory to one target through PSRP, or downloads one URI package to the local admin-workstation cache, stages the cached package to one target, optionally extracts staged `.zip` packages on the endpoint, runs one package-relative PowerShell `.ps1` entry point, optionally writes captured package output artifacts, optionally copies package logs, and returns `RunPackage` metadata. Later package slices add cleanup and multi-target workflows. |

## Parameters

This section lists accepted parameters, whether they take an argument, and the valid argument shape. Switch parameters do not take an argument.

### `Test-WinPushTarget`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. Current package workflows require exactly one resolved target; broader pipeline and multi-target package workflows are planned for item `11.11`. |
| `-HostFile` | `string` | UTF-8 file containing target names. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Uses the current identity when omitted. |

Target input is required from either `-ComputerName`, pipeline input, or `-HostFile`.

### `Invoke-WinPushCommand`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. Also accepts pipeline strings and pipeline objects with a `ComputerName` property. |
| `-HostFile` | `string` | UTF-8 file containing target names. |
| `-Command` | `string` | Command text. Required. PSRP treats this as PowerShell source; native transports use native command text. |
| `-Transport` | `Psrp`, `WinRM`, `PsExec` | Optional. Defaults to `Psrp`. |
| `-PsExecPath` | `string` | Optional path to `PsExec.exe`; only valid with `-Transport PsExec`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Not supported with `WinRM` or `PsExec`. |
| `-CaptureOutput` | switch | Writes one run-level `summary.csv` and one per-target `run.log`. Supported with every transport. |
| `-Logs` | switch | Copies convention-based command logs. Not supported with `WinRM` or `PsExec`. |
| `-OutputRoot` | `string` | Local artifact root. Defaults to `C:\WinPush`. |

Target input is required from either `-ComputerName`, pipeline input, or `-HostFile`.

### `Invoke-WinPushScript`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. Also accepts pipeline strings and pipeline objects with a `ComputerName` property. |
| `-HostFile` | `string` | UTF-8 file containing target names. |
| `-ScriptPath` | `string` | Existing local `.ps1` file. Required. |
| `-Transport` | `Psrp`, `WinRM`, `PsExec` | Optional. Defaults to `Psrp`. |
| `-PsExecPath` | `string` | Optional path to `PsExec.exe`; only valid with `-Transport PsExec`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Not supported with `WinRM` or `PsExec`. |
| `-CaptureOutput` | switch | Writes one run-level `summary.csv` and one per-target `run.log`. Supported with every transport. |
| `-Logs` | switch | Copies convention-based script logs. Not supported with `WinRM` or `PsExec`. |
| `-KeepStagedScript` | switch | Leaves the staged native-transport script folder on the target for troubleshooting. Native script staging is removed by default. |
| `-OutputRoot` | `string` | Local artifact root. Defaults to `C:\WinPush`. |

Target input is required from either `-ComputerName`, pipeline input, or `-HostFile`.

### `Copy-WinPushItem`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string` | Single target name. Required. |
| `-Path` | `string` | Upload source local file, or download source remote file. Required. |
| `-Destination` | `string` | Upload destination remote path, or download destination local path. Required. |
| `-Direction` | `Upload`, `Download` | Optional. Defaults to `Upload`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Uses the current identity when omitted. |

`Copy-WinPushItem` supports one target and one file per call.

### `Get-WinPushLog`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. Also accepts pipeline strings and pipeline objects with a `ComputerName` property. |
| `-HostFile` | `string` | UTF-8 file containing target names. |
| `-RemoteDirectory` | `string` | Absolute remote Windows directory containing immediate log files. Required. |
| `-OutputRoot` | `string` | Local artifact root. Defaults to `C:\WinPush`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Uses the current identity when omitted. |

Target input is required from either `-ComputerName`, pipeline input, or `-HostFile`.

### `Invoke-WinPushPackage`

Current package support stages one existing local package file or directory to one resolved target through PSRP. Directory packages are staged recursively beneath one remote package root while preserving package-relative file layout. URI package sources are downloaded to the local admin-workstation cache, then the cached package file is staged to the same kind of remote package path as a local file package. When `-Extract` is supplied with a staged `.zip` package, the endpoint extracts the archive into the package staging directory and sets `PackageMetadata.Extracted = True`. The command sets the remote working directory to the staged or extracted package root, runs one package-relative PowerShell `.ps1` entry point, retains entry-point output and errors in the returned result, records execution timestamps in `PackageMetadata`, writes package `summary.csv` plus per-target `run.log` artifacts when `-CaptureOutput` is supplied, and copies convention-based package logs when `-Logs` is supplied. Later package workflow slices add cleanup, host-file targets, and multi-target target sources.

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. Also accepts pipeline strings and pipeline objects with a `ComputerName` property. |
| `-HostFile` | `string` | UTF-8 file containing target names. Planned for later package workflows; currently rejected. |
| `-Path` | `string` | Existing local admin-workstation package file or directory. Mutually exclusive with `-Uri`. |
| `-Uri` | `uri` | Absolute remote package source downloaded to the admin-workstation cache before endpoint staging. Mutually exclusive with `-Path`. |
| `-EntryPoint` | `string` | PowerShell `.ps1` package entry point relative to the staged package root. Required. |
| `-Extract` | switch | Extracts staged `.zip` package files on the endpoint into the package staging directory. Non-zip files and directory packages are rejected. |
| `-CaptureOutput` | switch | Writes one run-level `summary.csv` and one per-target `run.log` for package output and errors. |
| `-Logs` | switch | Copies immediate regular files from `C:\ProgramData\EA\Logs\<entry-point-name>\`, where `<entry-point-name>` is the package entry point base name. |
| `-Cleanup` | `Never`, `OnSuccess`, `Always` | Planned remote staging cleanup policy. Defaults to `Never`; values other than `Never` are currently rejected. |
| `-OutputRoot` | `string` | Local artifact root. Defaults to `C:\WinPush`. |
| `-PackageCacheRoot` | `string` | Local admin-workstation URI package cache root. Defaults to `C:\WinPush\PackageCache`. |
| `-RemoteStageRoot` | `string` | Remote endpoint staging root. Defaults to `C:\ProgramData\WinPush\Staging`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Uses the current identity when omitted. |

Current package staging, extraction, execution, artifact capture, and log copy support one resolved direct `-ComputerName` target. `-Path` and `-Uri` are mutually exclusive. URI packages are downloaded by the admin workstation before the cached file is uploaded to the endpoint through PSRP. `-EntryPoint` must be a package-relative `.ps1` path; rooted paths, parent traversal, empty path segments, and non-PowerShell entry points are rejected before execution.

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

PsExec transport launches operator-supplied or PATH-discovered `PsExec.exe` once per resolved target. WinPush passes `-h` so PsExec requests the elevated remote token when available, then executes the supplied command text through remote `cmd.exe /d /s /c`. WinPush does not download, bundle, license, or redistribute PsExec.

Native script transports copy the local `.ps1` file to `C:\Windows\Temp\WinPush\<stage-id>\` through small native PowerShell staging commands, then invoke the staged script path through remote Windows PowerShell. The staged folder is removed after execution unless `-KeepStagedScript` is supplied.

`-Credential` and `-Logs` are rejected for WinRM and PsExec before launching a process. `-CaptureOutput` is supported for command and script execution on every transport.

## Logs

`Get-WinPushLog` copies immediate regular files only from an explicit remote directory. It does not read copied file contents into memory, traverse nested directories, create remote directories, write `summary.csv` or `run.log`, or recurse.

`Invoke-WinPushCommand -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<command-name>\`, where `<command-name>` is derived from the first command name in the supplied PowerShell source and falls back to `Command`.

`Invoke-WinPushScript -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<script-name>\`, where `<script-name>` is the local script file base name.

`Invoke-WinPushPackage -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<entry-point-name>\`, where `<entry-point-name>` is the package entry point base name.

Attached command, script, and package logs reuse the same PSSession, run after the primary execution attempt, populate `Logs` and `CopiedLogPaths`, and do not change the primary command, script, or package success state.

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
- `Invoke-WinPushPackage` currently stages one local file or directory package to one resolved target, or downloads one absolute URI package to the local cache before staging the cached file to one resolved target. It can extract staged `.zip` package files on the endpoint with `-Extract`, runs one package-relative PowerShell `.ps1` entry point from the staged or extracted package root, writes package output artifacts when `-CaptureOutput` is supplied, and copies package logs when `-Logs` is supplied. Cleanup policies other than `Never`, host-file targets, and multi-target package workflows are not implemented yet.
- SSH transport, retries, parallel fan-out, persistent sessions, and transport fallback are not implemented.
- Automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration is not implemented.
- Recursive file transfer, recursive log enumeration, and multi-target file transfer are not implemented.
- Script arguments are not implemented for `Invoke-WinPushScript`.
- Native script transports stage script content through the selected native transport and do not support `-Credential` or `-Logs`.
- `Copy-WinPushItem` supports one target and one file per call.
