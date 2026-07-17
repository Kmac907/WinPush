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

`Invoke-WinPushPackage` currently stages one existing local package file from the admin workstation to one direct target through PSRP. It creates a remote staging directory under `C:\ProgramData\WinPush\Staging\<run-id>\`, uploads the local package file into that directory, and returns a `WinPush.ExecutionResult` with `Operation = RunPackage`.

Later package workflow slices add directory packages, URI package download to the admin workstation cache, optional endpoint zip extraction, PowerShell entry-point execution, output capture, log/result copy, cleanup policy, multi-target target sources, and live package validation.

Package workflow results carry `PackageMetadata` on the returned `WinPush.ExecutionResult`. The metadata shape is:

| Field | Meaning |
| --- | --- |
| `PackageSourceType` | `Path` or `Uri`. |
| `PackageSource` | Original local path or URI supplied by the operator. |
| `LocalPackagePath` | Local package path used by the admin workstation. URI packages use the downloaded cache path. |
| `RemoteStagePath` | Endpoint staging path for the package or staged package root. |
| `EntryPoint` | Package-relative PowerShell entry point. |
| `Extracted` | Whether endpoint extraction was performed successfully. |
| `ExecutionStarted` | Package entry point start time when execution is implemented. |
| `ExecutionEnded` | Package entry point end time when execution is implemented. |
| `CleanupPolicy` | `Never`, `OnSuccess`, or `Always`. |
| `CleanupSucceeded` | Cleanup outcome when cleanup is attempted. |
| `LogsCopied` | Whether package logs/results were copied. |
| `CopiedLogPaths` | Local copied log/result paths. |

Current local file staging:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage.zip `
    -EntryPoint .\Install-EA.ps1
```

Planned local directory package:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage `
    -EntryPoint .\Install-EA.ps1
```

Planned local zip package with endpoint extraction:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Path .\EAInstallPackage.zip `
    -EntryPoint .\Install-EA.ps1 `
    -Extract
```

Planned remote package source downloaded by the admin workstation first:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
    -EntryPoint .\Install-EA.ps1 `
    -Extract
```

Planned package workflow with artifacts, logs, and cleanup:

```powershell
Invoke-WinPushPackage `
    -ComputerName PC01 `
    -Uri 'https://storage.blob.core.windows.net/packages/EA.zip' `
    -EntryPoint .\Install-EA.ps1 `
    -Extract `
    -CaptureOutput `
    -Logs `
    -Cleanup Always
```

Planned defaults:

- URI packages download to `C:\WinPush\PackageCache\<run-timestamp>\` on the admin workstation before endpoint staging.
- Endpoint staging uses `C:\ProgramData\WinPush\Staging\<run-id>\`.
- Cleanup defaults to `Never`.
- Initial entry points are PowerShell `.ps1` files only.
- Endpoints do not download package URIs directly.
- The first package workflow scope does not include package integrity switches, native `.exe` or `.cmd` entry points, package manifests, retries, parallel execution, or recursive log copy beyond the approved log behavior.

Current limitations:

- Only local file paths are staged.
- Directory packages and URI packages are rejected.
- `-Extract`, `-CaptureOutput`, `-Logs`, and cleanup policies other than `Never` are rejected.
- `-HostFile`, pipeline target input, and multi-target package workflows are rejected until the target-source package slice is implemented.
- The package entry point is recorded in metadata but not executed yet.
