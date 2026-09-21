# WinPush development guide

## Prerequisites

- Windows with PowerShell 7.6 Core or newer.
- Pester 3.4.0 exactly for the offline suite.
- PSScriptAnalyzer providing `Invoke-ScriptAnalyzer`.
- A controlled Windows target only for optional live validation.
- An explicit PsExec executable path only for optional PsExec smoke validation.

Install the retained test dependency when needed:

```powershell
Install-Module Pester -RequiredVersion 3.4.0 -Scope CurrentUser
```

## Repository layout

```text
WinPush/
|-- README.md
|-- CHANGELOG.md
|-- LICENSE
|-- SECURITY.md
|-- install.ps1
|-- WinPush.psd1
|-- WinPush.psm1
|-- WinPush.format.ps1xml
|-- src/
|   |-- Public/
|   `-- Private/
|-- docs/
|-- tests/
|   |-- Fixtures/
|   |-- Integration/
|   `-- Unit/
`-- build/
    |-- build.ps1
    `-- package.ps1
```

`WinPush.psd1` and `WinPush.psm1` are the normal module entry points. Runtime code stays inside this module folder, normally under `src` and an optional module-local `lib`; it must not import helper code from sibling modules. Human documentation belongs under `docs`, tests under `tests`, and build logic under `build`.

Generated build, test, validation, package, log, and report output belongs under the ignored `artifacts` directory, not committed source folders.

## Local development

Clone the repository for development:

```text
git clone https://github.com/Kmac907/WinPush.git
cd WinPush
```

Then import directly from the working tree:

```powershell
Test-ModuleManifest .\WinPush.psd1
Import-Module .\WinPush.psd1 -Force
Get-Command -Module WinPush
```

The manifest explicitly exports ten functions and loads `WinPush.format.ps1xml`. Import does not create remote sessions, write generated output, or load Microsoft Graph.

## Offline quality gate

Run the full offline gate from the repository root:

```powershell
.\build\build.ps1
```

The build:

1. Requires PowerShell 7.6 Core or newer.
2. Validates and imports `WinPush.psd1`.
3. Runs PSScriptAnalyzer over `src`, `tests`, and `build` using `PSScriptAnalyzerSettings.psd1`.
4. Runs the offline unit suite with Pester 3.4.0.
5. Enforces the command-coverage threshold stored in build configuration.
6. Writes `pester-results.xml` and `coverage-summary.txt` beneath `artifacts\build` by default.

The offline gate does not require live targets.

After it passes, create the same release ZIP used by GitHub Releases:

```powershell
.\build\build.ps1
.\build\package.ps1
```

The package script reads `ModuleVersion` from the manifest, stages the complete module under `artifacts\release\WinPush`, validates and imports that staged module, and writes `artifacts\release\WinPush-<version>.zip`.

## Optional live checks

Transport smoke checks are explicit build parameters:

```powershell
.\build\build.ps1 -PsrpTarget PC01
.\build\build.ps1 -WinRsTarget PC01
.\build\build.ps1 `
    -PsExecTarget PC01 `
    -PsExecPath C:\Tools\PsExec.exe
```

Manual checks should use a controlled target and harmless operations:

- Test PSRP with `Test-WinPushTarget`.
- Run a harmless command with `Invoke-WinPushCommand`.
- Confirm root and per-target logs with `-CaptureOutput`.
- Confirm copied files with `-Logs`.
- Run `tests\Integration\Invoke-WinPushPackageLiveValidation.ps1` for the package workflow described in [package workflow](package-workflow.md#live-validation).

## Future Gallery package metadata

The current GitHub Release ZIP is created by `build/package.ps1` with `Compress-Archive`. The manifest already supplies metadata needed for a future PowerShell Gallery transition:

- `Description`
- `FormatsToProcess`
- `PrivateData.PSData.Tags`
- `PrivateData.PSData.ProjectUri`
- `PrivateData.PSData.LicenseUri`

`ProjectUri` must remain populated. If Gallery publishing is added, every manifest-declared file must exist in the staged package root before `Compress-PSResource` runs.

Verify an installed package contains its format data:

```powershell
$Module = Get-Module -ListAvailable WinPush |
    Sort-Object Version -Descending |
    Select-Object -First 1

Import-PowerShellDataFile (Join-Path $Module.ModuleBase 'WinPush.psd1') |
    Select-Object -ExpandProperty FormatsToProcess

Test-Path (Join-Path $Module.ModuleBase 'WinPush.format.ps1xml')
```

## Versioning and releases

The manual `Release WinPush` GitHub Actions workflow accepts a `patch`, `minor`, or `major` version bump. It updates `ModuleVersion` in `WinPush.psd1`, runs `build/package.ps1`, commits the version change, creates an annotated `v<version>` tag, pushes the commit and tag atomically to `main`, and creates a GitHub release containing `artifacts/release/WinPush-<version>.zip`.

Run the offline quality gate before dispatching a release. The workflow packages the selected `main` revision; it does not run the repository's Windows-only quality gate.

Release installation is documented in the [README](../README.md#install). The manifest's project and license URIs must continue to point to this repository and its GPL-3.0-only license.

## Recovery

Unload the module from the current session with:

```powershell
Remove-Module WinPush
```

Delete a development clone when it is no longer needed. Remove an installed release version from the corresponding user or system PowerShell module path.

Remove caller-controlled captures and copied logs under `C:\WinPush` or the selected `OutputRoot` when they are no longer required. Remote files or changes created by caller-supplied commands, scripts, transfers, or retained package stages require separate operator cleanup.

## Maintenance rules

- Keep the manifest, explicit export list, native help, format definitions, tests, and Markdown documentation aligned.
- Add behavior only after tests define the public contract.
- Do not commit credentials, tokens, private keys, certificates, credential-bearing connection strings, internal host inventories, runtime logs, exports, receipts, state files, or packages.
- Preserve clear validation and safe defaults at trust boundaries.
- Record user-visible changes in [CHANGELOG.md](../CHANGELOG.md).
- Follow [SECURITY.md](../SECURITY.md) for vulnerability handling.
