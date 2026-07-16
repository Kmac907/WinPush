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

## Planned Package Workflow

`Invoke-WinPushPackage` is planned post-MVP work and is not currently exported or implemented.

The planned command is a higher-level workflow built on the primitive commands. It will stage a package, optionally extract it, run a PowerShell entry point from the staged package root, optionally capture output, optionally copy logs/results back, optionally clean up remote staged files, and return `WinPush.ExecutionResult` objects with `Operation = RunPackage`.

Planned local package source:

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
