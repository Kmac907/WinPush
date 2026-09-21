# Security

Kyle Maclachlan owns WinPush, matching the module manifest.

## Report a vulnerability

Contact Kyle Maclachlan privately through an appropriate non-public channel. Do not place suspected vulnerabilities, credentials, tokens, package URLs containing secrets, host inventories, or other sensitive data in public issues.

Include the following when it is safe to do so:

- the affected WinPush version and command
- controller PowerShell and Windows versions
- transport and relevant parameter values with secrets removed
- expected and observed behavior
- minimal reproduction steps
- sanitized error text, logs, and artifact layout
- the security impact and any known mitigations

Remove credentials, PATs, access tokens, private keys, certificates, connection strings, target names, usernames, internal URLs, and proprietary package contents before sharing evidence.

## Package integrity

`Invoke-WinPushPackage -ExpectedSha256` can verify an HTTPS download against a caller-supplied SHA-256 value. The parameter is optional. Callers remain responsible for package provenance, content approval, and any organizational signing or mandatory checksum policy.
