# Relay Backlog

<!-- relay: backlog campaign=20260918-003046-713765 repository=17279ff94680 -->

Resolve the following verified backlog defects. Plan only work still missing from the repository.

## BUG-0004 — The dot alternative is combined with an optional extension, causing valid compon

- Severity: P2
- Source: TASK-0003
- Source finding: TASK-0003-003
- Location: src/Private/Execution/New-WinPushPackageStagePlan.ps1:30
- Observable failure: The dot alternative is combined with an optional extension, causing valid components beginning with two dots, such as `..foo`, to be rejected rather than rejecting only exact `.` and `..`.
- Reproduction: `Test-WinPushPackageAbsoluteWindowsPath 'C:\..foo' returns False, while [IO.Path]::GetFullPath('C:\..foo') succeeds unchanged.`
- Requirement: Valid Windows component forms should remain usable as RemoteStageRoot values.
- Evidence: The pattern `(?:\.|\.\.|...)(?:\..*)?` matches `..foo`; no regression test covers valid double-dot-prefixed names.
- Deferral reason: Candidate-introduced P2 compatibility issue; valid double-dot-prefixed components are rejected, but it does not block the stated required root-path validation.
- Allowed paths:
  - `src/Private/Execution/New-WinPushPackageStagePlan.ps1`
