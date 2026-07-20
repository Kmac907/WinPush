# WinPush Packaging And Roadmap Notes

## Installation Scope

WinPush is installed with `-Scope AllUsers` only. Run installation and updates from an elevated PowerShell 7 session.

## Package Versions

Published package versions are immutable in Azure Artifacts. Installing with `-Reinstall` refreshes the same published version only; it does not make Azure Artifacts replace an existing package version with new contents.

The source `ModuleVersion` in `WinPush.psd1` tracks the human-managed release line as `major.minor.0`. CI replaces only the patch number with the Azure DevOps build ID in the staged package before publishing.

The source manifest version must stay in `major.minor.0` form. The CI package step keeps `major.minor` from the source manifest and writes the Azure DevOps build ID as the package patch version in the staged manifest only.

## Manifest Package Metadata

The module manifest includes package metadata required by PSResourceGet packaging:

- `Description`
- `FormatsToProcess`
- `PrivateData.PSData.Tags`
- `PrivateData.PSData.ProjectUri`

`ProjectUri` must not be empty. Empty package metadata can cause `Compress-PSResource` to fail during CI packaging. Files declared by manifest paths must be included in the staged package root before `Compress-PSResource` runs.

Verify the installed package includes manifest-declared format files:

```powershell
$Module = Get-Module -ListAvailable WinPush |
    Sort-Object Version -Descending |
    Select-Object -First 1

Import-PowerShellDataFile (Join-Path $Module.ModuleBase 'WinPush.psd1') |
    Select-Object -ExpandProperty FormatsToProcess

Test-Path (Join-Path $Module.ModuleBase 'WinPush.format.ps1xml')
```

## Repository Installation

For repository-based installation, use the shared installer tool from the `Tools` repository:

```powershell
Install-EndpointEngineeringModule -ModuleName WinPush -Force
```

`Install-EndpointEngineeringModule` must be available in the current PowerShell session before running this command. Follow the README under `Tools/Install-EndpointEngineeringModule` for that tool.

## Rollback Or Recovery

To remove a PSResourceGet installation:

```powershell
Uninstall-PSResource -Name WinPush -Scope AllUsers
```

For Windows PowerShell 5.1, also check:

```text
Documents\WindowsPowerShell\Modules\WinPush
```

Additional cleanup:

- remove local captured output or copied logs under `C:\WinPush` or the caller-supplied `OutputRoot` when no longer needed
- remove any remote files or changes created by caller-supplied command text, scripts, or file transfers

## Package Workflow

`Invoke-WinPushPackage` stages one existing local package file or directory from the admin workstation to resolved direct `-ComputerName`, pipeline string, pipeline-by-property-name `ComputerName`, or `-HostFile` targets through PSRP. It creates one remote staging directory per target under `C:\ProgramData\WinPush\Staging\<run-id>\`, uploads the local package file into that directory, or recursively uploads local directory contents beneath that remote package root while preserving relative file layout. It can also download one absolute URI package to the admin-workstation cache, then upload the cached package file to each resolved target through PSRP. When `-Extract` is supplied with a staged `.zip` package, each endpoint extracts the archive into its package staging directory and returns `PackageMetadata.Extracted = True`. The command sets the remote working directory to the staged or extracted package root and runs one package-relative PowerShell `.ps1` entry point per target. When `-CaptureOutput` is supplied, package entry-point output and errors are written to the same local artifact shape as command and script execution: one shared run-level `summary.csv` and one per-target `run.log`. When `-Logs` is supplied, immediate regular files are copied from `C:\ProgramData\EA\Logs\<entry-point-name>\` to the local target `Logs` folder. When `-Cleanup OnSuccess` or `-Cleanup Always` is supplied, the generated remote stage directory is removed after optional log collection. It returns one `WinPush.ExecutionResult` with `Operation = RunPackage` per resolved target.

Live package workflow validation is covered by the integration harness in `tests/Integration/Invoke-WinPushPackageLiveValidation.ps1`.

Package workflow results carry `PackageMetadata` on the returned `WinPush.ExecutionResult`. The metadata shape is:

| Field | Meaning |
| --- | --- |
| `PackageSourceType` | `Path` or `Uri`. |
| `PackageSource` | Original local path or URI supplied by the operator. |
| `LocalPackagePath` | Local package path used by the admin workstation. URI packages use the downloaded cache path. |
| `RemoteStagePath` | Endpoint staging path for the package or staged package root. |
| `EntryPoint` | Package-relative PowerShell entry point. |
| `Extracted` | Whether endpoint extraction was performed successfully. |
| `ExecutionStarted` | Package entry point start time. |
| `ExecutionEnded` | Package entry point end time. |
| `CleanupPolicy` | `Never`, `OnSuccess`, or `Always`. |
| `CleanupSucceeded` | Cleanup outcome when cleanup is attempted. |
| `LogsCopied` | Whether package logs/results were copied. |
| `CopiedLogPaths` | Local copied log/result paths. |

Local script-file package:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\Install-EA.ps1 `
    -EntryPoint .\Install-EA.ps1
```

Local directory package:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1
```

Local zip package with endpoint extraction:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage.zip `
    -EntryPoint .\Install-EA.ps1 `
    -Extract
```

Remote package source downloaded by the admin workstation first, then staged to the endpoint:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
    -EntryPoint .\Install-EA.ps1 `
    -Extract
```

Package workflow with captured output artifacts:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
    -EntryPoint .\Install-EA.ps1 `
    -Extract `
    -CaptureOutput
```

Package workflow with artifacts and logs:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
    -EntryPoint .\Install-EA.ps1 `
    -Extract `
    -CaptureOutput `
    -Logs `
    -Cleanup OnSuccess
```

Package `-CaptureOutput` uses the same local artifact shape as command and script execution: one run-level `summary.csv` and one per-target `run.log`. The returned result keeps package output and errors in memory, populates `ResultPath` with `run.log`, and leaves `StdOutPath` and `StdErrPath` blank by default.

Package `-Logs` uses the package entry point base name to copy immediate regular files from `C:\ProgramData\EA\Logs\<entry-point-name>\` into the local target `Logs` folder. Log copy runs after package entry-point execution using the same PSSession. Log-copy failures are reflected in `Logs`, `CopiedLogPaths`, `PackageMetadata.LogsCopied`, and `PackageMetadata.CopiedLogPaths` without changing the primary package success or failure state.

Package `-Cleanup` controls remote staged-package retention. The default `Never` preserves staged files. `OnSuccess` removes the generated stage directory after successful package execution, and `Always` removes it after success or failure when a remote stage was created. Cleanup runs after optional log collection. Cleanup failures set `PackageMetadata.CleanupSucceeded = False` without changing the primary package output, errors, or log-copy outcome.

## Live Package Workflow Validation

Run the package live-validation harness from the repository root when a controlled PSRP target is available:

```powershell
.\tests\Integration\Invoke-WinPushPackageLiveValidation.ps1 `
    -ComputerName PC01
```

Use `-Credential` when the target requires explicit PSRP credentials:

```powershell
$Credential = Get-Credential

.\tests\Integration\Invoke-WinPushPackageLiveValidation.ps1 `
    -ComputerName PC01 `
    -Credential $Credential
```

The harness imports the source module, preflights PSRP session creation, and writes a JSON result under `artifacts\validation` by default. If PSRP session creation fails, it records `Status = Blocked`, `Blocked = true`, the preflight error, and exits with code `2` before creating remote package artifacts.

Parameters:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `ComputerName` | Required | Target used for live PSRP package validation. |
| `Credential` | Current identity | Optional `PSCredential` passed to preflight and package workflow sessions. |
| `OutputRoot` | `.\artifacts\validation\package-live-output` | Local root used for `-CaptureOutput` and `-Logs` artifacts. |
| `ResultPath` | Timestamped JSON under `.\artifacts\validation` | Machine-readable validation result. |
| `PackageCacheRoot` | Temporary folder | URI package download cache used by `Invoke-WinPushPackage`; removed by the harness. |
| `RemoteStageRoot` | `C:\ProgramData\WinPush\Staging` | Remote package staging root to validate and clean. |
| `HttpPort` | Auto-selected loopback port | Local ephemeral HTTP server port for the disposable URI package source. |

When PSRP authentication works, the harness creates disposable local file, directory, zip, and loopback URI package sources, runs `Invoke-WinPushPackage` through PSRP, validates package output capture, immediate-file log copy from `C:\ProgramData\EA\Logs\<entry-point-name>`, `Cleanup Never`, `Cleanup OnSuccess`, `Cleanup Always`, representative entry-point failure, remote stage cleanup, and local PSSession count stability. It removes local scratch package sources, the temporary URI cache, retained remote package stages, and validation log directories it creates. Generated JSON and captured validation artifacts live under ignored `artifacts/`.

Defaults:

- URI packages download to `C:\WinPush\PackageCache\<run-timestamp>\` on the admin workstation before endpoint staging.
- Endpoint staging uses `C:\ProgramData\WinPush\Staging\<run-id>\`.
- Cleanup defaults to `Never`.
- Initial entry points are PowerShell `.ps1` files only.
- Endpoints do not download package URIs directly.
- Package workflow does not include package integrity switches, native `.exe` or `.cmd` entry points, package manifests, retries, parallel execution, or recursive log copy beyond the approved log behavior.

Package rules:

- Local files, local directories, and cached URI package files are staged to endpoints.
- Staged `.zip` package files can be extracted on the endpoint with `-Extract`; non-zip files and directory packages are rejected for extraction.
- One package-relative PowerShell `.ps1` entry point is executed from the staged or extracted package root.
- Rooted entry-point paths, parent traversal, empty path segments, and non-`.ps1` entry points are rejected before execution.
- Package entry-point output and errors are retained in the returned `WinPush.ExecutionResult`.
- `-CaptureOutput` writes one shared run-level `summary.csv` and one per-target `run.log` for returned package results.
- `-Logs` copies convention-based package logs from `C:\ProgramData\EA\Logs\<entry-point-name>\` to the local target `Logs` folder.
- URI packages are downloaded only by the admin workstation, then uploaded to endpoints through PSRP.
- `-Cleanup OnSuccess` and `-Cleanup Always` remove only generated stage directories under the configured remote staging root.
- Direct `-ComputerName` arrays, pipeline strings, pipeline objects with a `ComputerName` property, and `-HostFile` targets are supported for package workflows.
