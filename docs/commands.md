# WinPush Command Reference

## Command Behavior

| Command | Behavior |
| --- | --- |
| `Test-WinPushTarget` | Tests PSRP session creation for direct `-ComputerName`, pipeline, or `-HostFile` targets sequentially using the current Windows identity or an optional `-Credential`. Returns one `WinPush.ExecutionResult` per resolved target. |
| `Invoke-WinPushCommand` | Runs non-empty command text on direct `-ComputerName`, pipeline, pipeline-by-property-name `ComputerName`, or `-HostFile` targets. PSRP is the default transport. `-Transport WinRM` runs current-identity commands through `winrs.exe`. `-Transport PsExec` runs current-identity commands through operator-supplied `PsExec.exe`. |
| `Invoke-WinPushScript` | Runs one existing local `.ps1` file on direct `-ComputerName`, pipeline, pipeline-by-property-name `ComputerName`, or `-HostFile` targets. PSRP uses `Invoke-Command -FilePath`. WinRM and PsExec stage the script through the selected native transport and execute the staged file through remote Windows PowerShell. |
| `Copy-WinPushItem` | Uploads one existing local file to one target through `Copy-Item -ToSession`, or downloads one remote file through `Copy-Item -FromSession` when `-Direction Download` is supplied. |
| `Get-WinPushLog` | Copies immediate regular files from one explicit absolute remote Windows directory to the target's local `Logs` folder under a timestamped output run folder. |
| `Invoke-WinPushPackage` | Stages a local or cached URI package through PSRP, runs one package-relative `.ps1` entry point, and can capture output, copy logs, and clean remote staging. |
| `Get-WinPushRun` | Reads and types the rows in a captured run's `summary.csv`, preserving order and mapping safe target log paths. |
| `Test-WinPushRemediation` | Parses a detection/remediation script pair with Windows PowerShell 5.1 and reports errors and warnings without execution. |
| `Invoke-WinPushRemediation` | Validates, stages, and runs a detection/remediation pair through PSRP, WinRS, or PsExec. |
| `Export-WinPushHostFileFromEntraGroup` | Writes unique Entra device display names from direct or transitive group membership to a host file. |

## Default Output

Remote execution and transfer commands return structured `WinPush.ExecutionResult` objects. Run history and remediation validation have their own typed results; Entra export emits names only with `-PassThru`. The default terminal views are compact:

```text
Invoke-WinPushCommand
ComputerName Transport Status ExitCode OutputSummary ErrorSummary
------------ -------- ------ -------- ------------- ------------
PC01         Psrp     OK     0        PC01
PC02         WinRM    Failed 1                      Access denied

Invoke-WinPushScript
ComputerName Transport Status ExitCode Script        ErrorSummary
------------ -------- ------ -------- ------        ------------
PC01         Psrp     OK     0        inventory.ps1
PC02         WinRM    Failed 1        inventory.ps1 Script failed

Invoke-WinPushPackage
ComputerName Transport Status ExitCode Package    Cleanup  Logs ErrorSummary
------------ -------- ------ -------- -------    -------  ---- ------------
PC01         Psrp     OK     0        Agent.zip  Removed  Yes
PC02         Psrp     Failed 1603     Agent.zip  Retained No   Installer failed

Copy-WinPushItem
ComputerName Transport Status Source          Destination         ErrorSummary
------------ -------- ------ ------          -----------         ------------
PC01         Psrp     OK     C:\Temp\a.txt   C:\Temp\b.txt

Get-WinPushLog
ComputerName Transport Status LogPath                 Files Destination        ErrorSummary
------------ -------- ------ -------                 ----- -----------        ------------
PC01         Psrp     OK     C:\ProgramData\EA\Logs  4     C:\WinPush\...\Logs

Test-WinPushTarget
ComputerName Reachable Transport ErrorSummary
------------ --------- --------- ------------
PC01         True      Psrp

Get-WinPushRun
ComputerName Operation      Status ExitCode TargetLog
------------ ---------      ------ -------- ---------
PC01         RunCommand     OK     0        Available

Test-WinPushRemediation
Valid Errors Warnings DetectScript RemediateScript
----- ------ --------  ------------ -----------------
True  0      0         detect.ps1   remediate.ps1

Invoke-WinPushRemediation
ComputerName Transport Status     DetectExit RemediateExit ErrorSummary
------------ --------- ------     ---------- ------------- ------------
PC01         Psrp      Remediated 1          0
```

`OutputPreview`, raw multiline output, and artifact paths are not shown by default. Every execution summary includes `Transport`. `Invoke-WinPushCommand` includes `OutputSummary`, a short first-value command-output summary. Successful rows leave `ErrorSummary` blank; failed rows show a short normalized summary. Full output, full errors, logs, metadata, and artifact paths remain on the returned object and are visible with property access or `Format-List *`. `-CaptureOutput` writes detailed command, script, package, or remediation output to the root correlated `run.log` and each per-target `run.log`.

## Parameters

This section lists accepted parameters, whether they take an argument, and the valid argument shape. Switch parameters do not take an argument.

### `Test-WinPushTarget`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. |
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
| `-Shell` | `Auto`, `PowerShell`, `Cmd` | Command shell. `Auto` preserves the transport default; `PowerShell` forces PowerShell and `Cmd` forces `cmd.exe`. |
| `-TimeoutSeconds` | `int` | Native WinRS/PsExec timeout. Defaults to 1800; `0` disables the timeout. A timeout kills the process tree and returns exit code `124`. |
| `-PsExecPath` | `string` | Optional path to `PsExec.exe`; only valid with `-Transport PsExec`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Not supported with `WinRM` or `PsExec`. |
| `-CaptureOutput` | switch | Writes one run-level `summary.csv`, one root correlated `run.log`, and one per-target `run.log`. Supported with every transport. |
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
| `-TimeoutSeconds` | `int` | Native WinRS/PsExec staging and execution timeout. Defaults to 1800; `0` disables the timeout. |
| `-PsExecPath` | `string` | Optional path to `PsExec.exe`; only valid with `-Transport PsExec`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Not supported with `WinRM` or `PsExec`. |
| `-CaptureOutput` | switch | Writes one run-level `summary.csv`, one root correlated `run.log`, and one per-target `run.log`. Supported with every transport. |
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

Package support stages one existing local package file or directory to resolved direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP. Directory packages are staged recursively beneath each remote package root while preserving package-relative file layout. URI package sources are downloaded once to the local admin-workstation cache, then the cached package file is staged to each resolved target. When `-Extract` is supplied with a staged `.zip` package, each endpoint extracts the archive into its package staging directory and sets `PackageMetadata.Extracted = True`. The command sets the remote working directory to the staged or extracted package root, runs one package-relative PowerShell `.ps1` entry point, retains entry-point output and errors in each returned result, records execution timestamps in `PackageMetadata`, writes one shared package `summary.csv`, one root correlated `run.log`, and one per-target `run.log` when `-CaptureOutput` is supplied, copies convention-based package logs when `-Logs` is supplied, and applies the requested remote staged-package cleanup policy after optional logs.

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names. Also accepts pipeline strings and pipeline objects with a `ComputerName` property. |
| `-HostFile` | `string` | UTF-8 file containing target names. Blank lines and full-line `#` comments are ignored, and duplicate targets are removed case-insensitively. |
| `-Path` | `string` | Existing local admin-workstation package file or directory. Mutually exclusive with `-Uri`. |
| `-Uri` | `uri` | Absolute HTTPS package source downloaded to a temporary admin-workstation cache before endpoint staging. Mutually exclusive with `-Path`. |
| `-EntryPoint` | `string` | PowerShell `.ps1` package entry point relative to the staged package root. Required. |
| `-ArgumentList` | `object[]` | Positional values passed to the package entry point. Defaults to an empty array. |
| `-ExpectedSha256` | `string` | Optional 64-hex-character SHA-256 expected for a URI download. A mismatch stops before endpoint sessions are opened. |
| `-Extract` | switch | Extracts staged `.zip` package files on the endpoint into the package staging directory. Non-zip files and directory packages are rejected. |
| `-CaptureOutput` | switch | Writes one run-level `summary.csv`, one root correlated `run.log`, and one per-target `run.log` for package output and errors. |
| `-Logs` | switch | Copies immediate regular files from `C:\ProgramData\EA\Logs\<entry-point-name>\`, where `<entry-point-name>` is the package entry point base name. |
| `-Cleanup` | `Never`, `OnSuccess`, `Always` | Remote staged-package cleanup policy. Defaults to `Never`; `OnSuccess` removes staged files after successful package execution, and `Always` removes staged files after success or failure when a stage exists. |
| `-OutputRoot` | `string` | Local artifact root. Defaults to `C:\WinPush`. |
| `-PackageCacheRoot` | `string` | Parent for the temporary per-run URI cache. Defaults to `C:\WinPush\PackageCache`; the created cache directory is removed in `finally`. |
| `-RemoteStageRoot` | `string` | Absolute drive-rooted or UNC endpoint staging root. Defaults to `C:\ProgramData\WinPush\Staging`. |
| `-Credential` | `PSCredential` | Optional PSRP credential. Uses the current identity when omitted. |

Package staging, extraction, execution, artifact capture, and log copy support resolved direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, and `-HostFile` targets. `-Path` and `-Uri` are mutually exclusive. URI packages are downloaded once by the admin workstation before the cached file is uploaded to each endpoint through PSRP. `-EntryPoint` must be a package-relative `.ps1` path; rooted paths, parent traversal, empty path segments, and non-PowerShell entry points are rejected before execution. `-ArgumentList` is positional: values bind in the entry point's declared parameter order.

### `Get-WinPushRun`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-Path` | `string` | Existing captured run directory containing `summary.csv`. Required. |

Each CSV row becomes a `WinPush.RunResult`. `Succeeded` is restored to `bool`, `ExitCode` to `int` or `$null`, and the original row fields are retained. `RunDirectory`, `TargetLogPath`, and `TargetLogExists` are added. The target log path uses the same safe target-directory mapping as capture, not the raw target name.

### `Test-WinPushRemediation`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-DetectScript` | `string` | Existing local `.ps1` detection script. Required. |
| `-RemediateScript` | `string` | Existing local `.ps1` remediation script. Required. |

The command returns `WinPush.RemediationValidationResult` with `IsValid`, resolved paths, `Errors`, and `Warnings`. Both scripts are parsed by Windows PowerShell 5.1 without execution. Missing literal `exit 0`/`exit 1` detection paths and reboot commands are warnings; file and parser failures are errors.

### `Invoke-WinPushRemediation`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-ComputerName` | `string[]` | Target names; accepts pipeline strings and `ComputerName` properties. |
| `-HostFile` | `string` | UTF-8 file containing target names. |
| `-DetectScript` | `string` | Local detection `.ps1`; exit `0` means compliant and `1` requests remediation. |
| `-RemediateScript` | `string` | Local remediation `.ps1`; exit `0` means remediated. |
| `-Transport` | `Psrp`, `WinRM`, `PsExec` | Defaults to `Psrp`. |
| `-TimeoutSeconds` | `int` | Native stage/phase timeout. Defaults to 1800; `0` disables it. |
| `-PsExecPath` | `string` | Optional `PsExec.exe` path, valid only for PsExec. |
| `-Credential` | `PSCredential` | Optional for PSRP; unsupported for native transports. |
| `-CaptureOutput` | switch | Writes gradual root/per-target logs and `summary.csv`. |
| `-Logs` | switch | Copies detect/remediate convention logs through PSRP; unsupported for native transports. |
| `-OutputRoot` | `string` | Local artifact root. Defaults to `C:\WinPush`. |

Results have `Operation = RunRemediation` and `RemediationMetadata` with `Status` (`Compliant`, `Remediated`, or `Failed`), separate exit codes, output, and errors for both phases. Scripts are always validated first and staged files are removed after execution.

### `Export-WinPushHostFileFromEntraGroup`

| Parameter | Argument | Notes |
| --- | --- | --- |
| `-GroupId` | `string` | Entra group ID; mutually exclusive with `-GroupName`. |
| `-GroupName` | `string` | Exact group display name; fails when missing or ambiguous. |
| `-OutputPath` | `string` | Host file to write. Required. |
| `-IncludeDisabled` | switch | Includes disabled devices; omitted by default. |
| `-Append` | switch | Appends only device names not already present, case-insensitively. |
| `-PassThru` | switch | Returns only names written by this invocation. |
| `-Transitive` | switch | Uses flattened transitive membership instead of direct membership. |

This command uses an existing authenticated Microsoft Graph context and the installed `Get-MgContext`, `Get-MgGroupMember`/`Get-MgGroupTransitiveMember`, and, for names, `Get-MgGroup` commands. Microsoft Graph is optional and is not declared as a WinPush manifest dependency.

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

`Invoke-WinPushCommand -Shell Auto` preserves each transport's default: PowerShell for PSRP, raw WinRS command text, and `cmd.exe` for PsExec. `-Shell PowerShell` forces encoded PowerShell, while `-Shell Cmd` explicitly runs `cmd.exe /d /s /c`. Native processes are terminated with their process tree when `-TimeoutSeconds` expires and return exit code `124`.

WinRM transport launches `winrs.exe` once per resolved target. It keeps native standard output text in `Output`, native standard error text in `Errors`, and sets `ExitCode` to the native process exit code.

PsExec transport launches operator-supplied or PATH-discovered `PsExec.exe` once per resolved target. WinPush passes `-h` so PsExec requests the elevated remote token when available, then executes the supplied command text through remote `cmd.exe /d /s /c`. WinPush does not download, bundle, license, or redistribute PsExec.

Native script transports copy the local `.ps1` file to `C:\Windows\Temp\WinPush\<stage-id>\` through small native PowerShell staging commands, then invoke the staged script path through remote Windows PowerShell. The staged folder is removed after execution unless `-KeepStagedScript` is supplied.

`-Credential` and `-Logs` are rejected for WinRM and PsExec before launching a process. `-CaptureOutput` is supported for command and script execution on every transport.

## Logs

`Get-WinPushLog` copies immediate regular files only from an explicit remote directory. It does not read copied file contents into memory, traverse nested directories, create remote directories, write `summary.csv` or `run.log`, or recurse.

`Invoke-WinPushCommand -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<command-name>\`, where `<command-name>` is derived from the first command name in the supplied PowerShell source and falls back to `Command`.

`Invoke-WinPushScript -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<script-name>\`, where `<script-name>` is the local script file base name.

`Invoke-WinPushPackage -Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<entry-point-name>\`, where `<entry-point-name>` is the package entry point base name.

Attached command, script, package, and remediation logs reuse the same PSSession, run after the primary execution attempt, populate `Logs` and `CopiedLogPaths`, and do not change the primary execution state.

## Capture And Artifact Safety

Captured runs use `<OutputRoot>\<dd-MM-yyyy-HHmmss>-<GUID>\`, preventing same-second controller runs from sharing files. Root and per-target `run.log` files are created before execution and receive stage, output, and error records gradually rather than only at completion.

Target names that are unsafe as a Windows directory component are sanitized and receive an eight-character SHA-256 suffix. This prevents traversal, reserved-name, separator, and IPv6 filename problems while preserving the original `ComputerName` in results and CSV rows. `Get-WinPushRun` applies the same mapping.

Local artifact failures populate `ArtifactError`; they do not overwrite the primary remote `Succeeded`, `ExitCode`, `Output`, or `Errors`. Full in-memory results remain available when capture cannot continue.

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
- remediation validation or execution fails
- URI packages use a non-HTTPS URI or fail an optional expected SHA-256 check
- file transfer or log copy fails

Recoverable conditions:

- multi-target command, script, package, connectivity, and log operations continue after one target fails
- log copy attempts continue after an individual file copy fails
- failed target results preserve error detail in the returned object

## Side Effects

Importing the module loads functions from the module-local `Private` and `Public` folders. It does not open network connections, create remote sessions, write generated runtime output, or persist state.

Command and script behavior is determined by caller-supplied command text or script content. File upload and download operations write to caller-selected paths. Captured output and copied logs persist under the caller-selected local `OutputRoot`. Temporary PSRP sessions are created for the duration of each target operation.

## Known Limitations

- PowerShell 7.6 `Core` is the supported controller shell.
- Windows PowerShell 5.1 compatibility is not guaranteed.
- `Invoke-WinPushPackage` supports direct `-ComputerName` arrays, pipeline strings, pipeline objects with a `ComputerName` property, and `-HostFile` targets.
- SSH transport, retries, parallel fan-out, persistent sessions, and transport fallback are not implemented.
- Automatic WinRM, firewall, TrustedHosts, certificate, endpoint, or policy configuration is not implemented.
- Recursive file transfer, recursive log enumeration, and multi-target file transfer are not implemented.
- Script arguments are not implemented for `Invoke-WinPushScript`.
- Package signature enforcement and mandatory checksums are not implemented; `ExpectedSha256` is optional.
- Native script transports stage script content through the selected native transport and do not support `-Credential` or `-Logs`.
- `Copy-WinPushItem` supports one target and one file per call.
