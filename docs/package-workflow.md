# WinPush package workflow

`Invoke-WinPushPackage` stages a local package or a controller-downloaded HTTPS package through PSRP, runs one package-relative PowerShell entry point, and returns one `WinPush.ExecutionResult` per resolved target.

## Workflow

```text
Local path ----------------------+
                                 |
HTTPS URI -> temporary cache ----+-> validate -> PSRP stage -> optional ZIP extract
                                                        |
                                                        v
                                              run .ps1 entry point
                                                        |
                                                        v
                                           optional capture and logs
                                                        |
                                                        v
                                              apply cleanup policy
```

Endpoints never download package URIs directly. URI content is downloaded once by the controller and then uploaded to each target.

## Sources and integrity

Use one source per invocation:

- `-Path` accepts an existing local file or directory.
- `-Uri` accepts an absolute HTTPS URI. HTTP and relative URIs are rejected.

Directory packages are uploaded recursively beneath the generated remote package root while preserving relative layout. A URI download is stored in a unique temporary directory under `PackageCacheRoot`, which defaults to `C:\WinPush\PackageCache`. That per-invocation cache directory is removed in `finally` after success or failure.

`-ExpectedSha256` accepts exactly 64 hexadecimal characters for a URI source. A mismatch stops before target sessions open. Verification is optional; callers remain responsible for package provenance and approval policy.

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Uri 'https://packages.example.test/EA.zip' `
    -ExpectedSha256 '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' `
    -EntryPoint .\Install-EA.ps1 `
    -Extract
```

## Staging and extraction

`RemoteStageRoot` defaults to `C:\ProgramData\WinPush\Staging` and must be an absolute drive-rooted or UNC Windows path. Relative paths and device namespaces are rejected before remote work.

Each target receives a generated stage beneath that root. Local files and cached URI files are uploaded into the stage. Local directory contents are uploaded beneath the package root.

`-Extract` is valid only for a staged `.zip` file. Extraction occurs on the target into the package staging directory and sets `PackageMetadata.Extracted` to `$true`. Non-ZIP files and directory packages are rejected when extraction is requested.

## Entry point and arguments

`EntryPoint` must identify one package-relative `.ps1` file. Rooted paths, parent traversal, empty path segments, and non-PowerShell files are rejected. The entry point runs with its staged or extracted package root as the working directory.

`ArgumentList` defaults to an empty array. Values bind positionally in the entry point's declared parameter order.

Local directory example:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1 `
    -ArgumentList @('Production', $true)
```

Local ZIP example:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage.zip `
    -EntryPoint .\Install-EA.ps1 `
    -Extract
```

A single script file can be both the package and its entry point:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\Install-EA.ps1 `
    -EntryPoint .\Install-EA.ps1
```

## Capture and logs

`-CaptureOutput` uses the standard artifact layout: one shared `summary.csv`, one correlated root `run.log`, and one per-target `run.log`. The returned result retains entry-point output and errors, sets `ResultPath` to the per-target log, and leaves `StdOutPath` and `StdErrPath` blank by default.

`-Logs` copies immediate regular files from `C:\ProgramData\EA\Logs\<entry-point-base-name>\` to the target's local `Logs` directory. Log copy runs after entry-point execution through the same PSSession. It is non-recursive.

Log-copy failures update `Logs`, `CopiedLogPaths`, `PackageMetadata.LogsCopied`, `PackageMetadata.CopiedLogPaths`, and artifact error detail without changing the primary package success or failure.

```powershell
Invoke-WinPushPackage `
    -HostFile .\hosts.txt `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1 `
    -CaptureOutput `
    -Logs `
    -Cleanup OnSuccess `
    -OutputRoot C:\WinPush
```

## Cleanup policy

Cleanup runs after optional log collection and removes only the generated stage beneath the configured root.

| Policy | Successful execution | Failed execution | Default |
| --- | --- | --- | --- |
| `Never` | Retain stage | Retain stage | Yes |
| `OnSuccess` | Remove stage | Retain stage | No |
| `Always` | Remove stage when created | Remove stage when created | No |

A cleanup failure sets `PackageMetadata.CleanupSucceeded` to `$false`. It does not replace primary output, errors, or log-copy results.

## Package metadata

Package results include `WinPush.PackageMetadata`:

| Property | Meaning |
| --- | --- |
| `PackageSourceType` | `Path` or `Uri`. |
| `PackageSource` | Original local path or URI. |
| `LocalPackagePath` | Controller path used for staging; a URI cache path is temporary. |
| `RemoteStagePath` | Generated target stage or package root. |
| `EntryPoint` | Package-relative PowerShell entry point. |
| `Extracted` | Whether target-side ZIP extraction succeeded. |
| `ExecutionStarted` / `ExecutionEnded` | Entry-point timestamps. |
| `CleanupPolicy` / `CleanupSucceeded` | Requested policy and attempted cleanup outcome. |
| `LogsCopied` / `CopiedLogPaths` | Package log-copy status and successful local paths. |

Default formatting shows `ComputerName`, `Transport`, `Status`, `ExitCode`, `Package`, `Cleanup`, `Logs`, and `ErrorSummary`. `Cleanup` displays `Retained`, `Removed`, or `Failed`. Full metadata remains available through `Format-List *`.

## Failure behavior

Validation failures that affect the invocation stop before remote work. Per-target staging or execution failures return failed results while other resolved targets continue. Package output and errors remain in memory even when local artifact capture fails.

Remote cleanup follows the selected policy when a stage exists. Temporary URI cache cleanup is automatic regardless of remote success. Cache-cleanup failures are surfaced rather than silently ignored.

## Live validation

Run the controlled PSRP integration harness from the repository root:

```powershell
.\tests\Integration\Invoke-WinPushPackageLiveValidation.ps1 `
    -ComputerName PC01
```

Use `-Credential` for explicit PSRP authentication:

```powershell
$Credential = Get-Credential

.\tests\Integration\Invoke-WinPushPackageLiveValidation.ps1 `
    -ComputerName PC01 `
    -Credential $Credential
```

The harness preflights PSRP, exercises disposable file, directory, and ZIP packages, validates capture, logs, cleanup policies, representative entry-point failure, stage cleanup, and PSSession stability, and writes JSON under `artifacts\validation` by default. A failed preflight records `Status = Blocked`, `Blocked = true`, exits with code `2`, and does not create remote package artifacts.

## Current limitations

- Package transport is PSRP only.
- Entry points are PowerShell `.ps1` files only.
- Package hashes are optional; signature enforcement is not implemented.
- Package manifests, dependency graphs, native `.exe` or `.cmd` entry points, retries, and parallel execution are not implemented.
- Package log copy is non-recursive.

For target resolution, results, safe artifact paths, and shared limitations, see the [command guide](commands.md). Release migration details are in the [changelog](../CHANGELOG.md).
