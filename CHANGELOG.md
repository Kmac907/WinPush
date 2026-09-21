# Changelog

## Unreleased

## 0.3.0 - 2026-09-21

### Added

- Added native help for every exported command and refreshed the task, command, package, development, security, and release documentation.
- Added a manual GitHub release workflow and versioned release ZIP packaging with staged manifest validation.
- Added an interactive, scope-aware installer that verifies GitHub's SHA-256 asset digest and installs module versions side by side.
- Added GPL-3.0 licensing and public GitHub project metadata.

### Changed

- Made release installation the primary setup path and moved clone-based setup into development documentation.

### Fixed

- Preserved native command exit codes and structured output during PSRP command execution.
- Applied timeouts to PSRP remediation staging, execution, and cleanup, including process-tree termination with exit code `124`.
- Hardened remote stage-root and local artifact-path validation for invalid, reserved, and overlong Windows path components.
- Isolated attached-log failures by target and surfaced URI package-cache cleanup failures without replacing the primary remote result.
- Preserved Unicode data in captured CSV summaries.
- Rejected incomplete Microsoft Graph device results before changing an Entra host file.

## 0.2.0

### Added

- Added `Get-WinPushRun`, `Test-WinPushRemediation`, `Invoke-WinPushRemediation`, and `Export-WinPushHostFileFromEntraGroup`.
- Added `-Shell` selection for command execution and native-process timeouts, with exit code `124` on timeout.
- Added gradual root and per-target artifact capture with `ArtifactError` separated from the primary remote outcome.
- Added optional SHA-256 verification for HTTPS package downloads.
- Added remediation phase metadata with separate detection and remediation exit codes, output, and errors.

### Changed

- Changed captured run directory names from timestamp-only values to timestamp/GUID values.
- Mapped unsafe target names to safe, bounded directory components with stable hash suffixes.
- Required package URIs to use HTTPS and removed each temporary per-run package cache after success or failure.
- Required `RemoteStageRoot` to be an absolute drive-rooted or UNC Windows path.
- Added positional package entry-point arguments through `-ArgumentList`.

### Migration from 0.1.0

- Update tooling that assumes timestamp-only run directories or raw target directory names; consume returned artifact paths or use `Get-WinPushRun` instead.
- Replace HTTP package URIs with HTTPS. Supply `-ExpectedSha256` when organizational policy requires content pinning.
- Pass package entry-point values positionally with `-ArgumentList` and use an absolute `-RemoteStageRoot`.
- Read package, remediation, and artifact details from the added metadata without removing existing execution-result fields.
