#requires -Version 7.6

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'The live validation script passes job and remote script block values through param/ArgumentList.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ComputerName,

    [System.Management.Automation.PSCredential] $Credential,

    [string] $OutputRoot = (Join-Path -Path $PWD -ChildPath 'artifacts\validation\package-live-output'),

    [string] $ResultPath = (Join-Path -Path $PWD -ChildPath ('artifacts\validation\Invoke-WinPushPackageLiveValidation-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string] $PackageCacheRoot = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('WinPushPackageLiveCache-{0}' -f ([guid]::NewGuid().ToString('N')))),

    [string] $RemoteStageRoot = 'C:\ProgramData\WinPush\Staging',

    [int] $HttpPort = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Checks = [System.Collections.Generic.List[object]]::new()
$script:RemoteStageCleanupPaths = [System.Collections.Generic.List[string]]::new()
$script:RemoteLogCleanupPaths = [System.Collections.Generic.List[string]]::new()
$script:Validation = [ordered] @{
    RoadmapItem               = '11.12'
    Name                      = 'Invoke-WinPushPackage live validation'
    ComputerName              = $ComputerName
    Started                   = (Get-Date).ToString('o')
    Finished                  = $null
    Status                    = 'Running'
    Passed                    = $false
    Blocked                   = $false
    BlockReason               = $null
    PowerShellVersion         = $PSVersionTable.PSVersion.ToString()
    ModulePath                = $null
    OutputRoot                = $OutputRoot
    PackageCacheRoot          = $PackageCacheRoot
    RemoteStageRoot           = $RemoteStageRoot
    ResultPath                = $ResultPath
    BeforeLocalPSSessionCount = @(Get-PSSession).Count
    AfterLocalPSSessionCount  = $null
    Preflight                 = $null
    Scenarios                 = @()
    Checks                    = @()
    RuntimeBugs               = @()
    LocalScratchRemoved       = $false
    PackageCacheRemoved       = $false
    RemoteCleanup             = @()
}

function Add-WinPushLiveCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $Passed,

        [AllowNull()]
        [object] $Details = $null
    )

    $script:Checks.Add([pscustomobject] [ordered] @{
            Name    = $Name
            Passed  = $Passed
            Details = $Details
        }) | Out-Null
}

function Write-WinPushLiveResult {
    [CmdletBinding()]
    param()

    $script:Validation.Finished = (Get-Date).ToString('o')
    $script:Validation.AfterLocalPSSessionCount = @(Get-PSSession).Count
    $script:Validation.Checks = @($script:Checks)
    $failedChecks = @($script:Checks | Where-Object { -not $_.Passed })
    if ($script:Validation.Blocked) {
        $script:Validation.RuntimeBugs = [object[]] @()
    }
    else {
        $script:Validation.RuntimeBugs = @(
            $failedChecks |
                ForEach-Object {
                    [pscustomobject] [ordered] @{
                        Check   = $_.Name
                        Details = $_.Details
                    }
                }
        )
    }

    if (-not $script:Validation.Blocked) {
        $script:Validation.Passed = $failedChecks.Count -eq 0
        $script:Validation.Status = if ($script:Validation.Passed) { 'Passed' } else { 'Failed' }
    }

    $resultDirectory = Split-Path -Path $ResultPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
        New-Item -Path $resultDirectory -ItemType Directory -Force | Out-Null
    }

    $script:Validation |
        ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $ResultPath -Encoding utf8NoBOM
}

function New-WinPushLiveRemoteSession {
    [CmdletBinding()]
    param()

    $sessionParameters = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
    }

    if ($null -ne $Credential) {
        $sessionParameters['Credential'] = $Credential
    }

    New-PSSession @sessionParameters
}

function Invoke-WinPushLiveRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [object[]] $ArgumentList = @()
    )

    $session = $null
    try {
        $session = New-WinPushLiveRemoteSession
        Invoke-Command -Session $session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    }
    finally {
        if ($null -ne $session) {
            Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
        }
    }
}

function Test-WinPushLiveRemotePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [bool] (Invoke-WinPushLiveRemote -ScriptBlock {
            param([string] $LiteralPath)

            Test-Path -LiteralPath $LiteralPath
        } -ArgumentList $Path)
}

function Remove-WinPushLiveRemotePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('Stage', 'Log')]
        [string] $Kind
    )

    $cleanupResult = Invoke-WinPushLiveRemote -ScriptBlock {
        param(
            [string] $LiteralPath,
            [string] $CleanupKind,
            [string] $AllowedStageRoot
        )

        if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
            return [pscustomobject] @{ Path = $LiteralPath; Removed = $false; Reason = 'empty path' }
        }

        $canonicalPath = [System.IO.Path]::GetFullPath($LiteralPath)
        if ($CleanupKind -eq 'Stage') {
            $canonicalStageRoot = [System.IO.Path]::GetFullPath(('{0}\' -f $AllowedStageRoot.TrimEnd('\')))
            if (-not $canonicalPath.StartsWith($canonicalStageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove stage path outside RemoteStageRoot: $LiteralPath"
            }

            $leaf = Split-Path -Path $canonicalPath -Leaf
            if (-not $leaf.StartsWith('package-', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove non-WinPush stage path: $LiteralPath"
            }
        }
        else {
            $canonicalLogRoot = [System.IO.Path]::GetFullPath('C:\ProgramData\EA\Logs\')
            if (-not $canonicalPath.StartsWith($canonicalLogRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove log path outside EA log root: $LiteralPath"
            }

            $leaf = Split-Path -Path $canonicalPath -Leaf
            if (-not $leaf.StartsWith('WinPushLive', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove non-validation log path: $LiteralPath"
            }
        }

        if (Test-Path -LiteralPath $canonicalPath) {
            Remove-Item -LiteralPath $canonicalPath -Recurse -Force -ErrorAction Stop
            return [pscustomobject] @{ Path = $canonicalPath; Removed = $true; Reason = $null }
        }

        [pscustomobject] @{ Path = $canonicalPath; Removed = $false; Reason = 'not present' }
    } -ArgumentList $Path, $Kind, $RemoteStageRoot

    $script:Validation.RemoteCleanup += $cleanupResult
}

function Get-WinPushLiveRemoteStageDirectory {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $RemoteStagePath
    )

    if ([string]::IsNullOrWhiteSpace($RemoteStagePath)) {
        return $null
    }

    $trimmedPath = $RemoteStagePath.TrimEnd('\')
    $leaf = Split-Path -Path $trimmedPath -Leaf
    if ($leaf.StartsWith('package-', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $trimmedPath
    }

    Split-Path -Path $trimmedPath -Parent
}

function ConvertTo-WinPushLiveResultSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result
    )

    $metadata = $Result.PackageMetadata
    [pscustomobject] [ordered] @{
        ComputerName      = $Result.ComputerName
        Operation         = $Result.Operation
        Succeeded         = $Result.Succeeded
        ExitCode          = $Result.ExitCode
        ErrorMessage      = $Result.ErrorMessage
        Output            = @($Result.Output)
        Errors            = @($Result.Errors)
        RunDirectory      = $Result.RunDirectory
        ComputerDirectory = $Result.ComputerDirectory
        ResultPath        = $Result.ResultPath
        StdOutPath        = $Result.StdOutPath
        StdErrPath        = $Result.StdErrPath
        CopiedLogPaths    = @($Result.CopiedLogPaths)
        PackageMetadata   = if ($null -eq $metadata) {
            $null
        }
        else {
            [pscustomobject] [ordered] @{
                PackageSourceType = $metadata.PackageSourceType
                PackageSource     = $metadata.PackageSource
                LocalPackagePath  = $metadata.LocalPackagePath
                RemoteStagePath   = $metadata.RemoteStagePath
                EntryPoint        = $metadata.EntryPoint
                Extracted         = $metadata.Extracted
                CleanupPolicy     = $metadata.CleanupPolicy
                CleanupSucceeded  = $metadata.CleanupSucceeded
                LogsCopied        = $metadata.LogsCopied
                CopiedLogPaths    = @($metadata.CopiedLogPaths)
            }
        }
    }
}

function Test-WinPushLiveCaptureArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result,

        [Parameter(Mandatory)]
        [string] $ScenarioName,

        [Parameter(Mandatory)]
        [string] $ExpectedOutputText
    )

    $summaryPath = if ([string]::IsNullOrWhiteSpace($Result.RunDirectory)) { $null } else { Join-Path -Path $Result.RunDirectory -ChildPath 'summary.csv' }
    $runLogPath = $Result.ResultPath

    Add-WinPushLiveCheck -Name "$ScenarioName capture wrote summary.csv" -Passed (
        -not [string]::IsNullOrWhiteSpace($summaryPath) -and (Test-Path -LiteralPath $summaryPath -PathType Leaf)
    ) -Details $summaryPath

    Add-WinPushLiveCheck -Name "$ScenarioName capture wrote per-target run.log" -Passed (
        -not [string]::IsNullOrWhiteSpace($runLogPath) -and (Test-Path -LiteralPath $runLogPath -PathType Leaf)
    ) -Details $runLogPath

    $oldArtifactPaths = @{}
    foreach ($oldArtifactName in @('stdout.txt', 'stderr.txt', 'result.txt')) {
        $oldArtifactPaths[$oldArtifactName] = if ([string]::IsNullOrWhiteSpace($Result.ComputerDirectory)) {
            $null
        }
        else {
            Join-Path -Path $Result.ComputerDirectory -ChildPath $oldArtifactName
        }
    }

    Add-WinPushLiveCheck -Name "$ScenarioName capture did not write stdout.txt" -Passed (
        [string]::IsNullOrWhiteSpace($oldArtifactPaths['stdout.txt']) -or
        -not (Test-Path -LiteralPath $oldArtifactPaths['stdout.txt'] -PathType Leaf)
    ) -Details $oldArtifactPaths['stdout.txt']

    Add-WinPushLiveCheck -Name "$ScenarioName capture did not write stderr.txt" -Passed (
        [string]::IsNullOrWhiteSpace($oldArtifactPaths['stderr.txt']) -or
        -not (Test-Path -LiteralPath $oldArtifactPaths['stderr.txt'] -PathType Leaf)
    ) -Details $oldArtifactPaths['stderr.txt']

    Add-WinPushLiveCheck -Name "$ScenarioName capture did not write result.txt" -Passed (
        [string]::IsNullOrWhiteSpace($oldArtifactPaths['result.txt']) -or
        -not (Test-Path -LiteralPath $oldArtifactPaths['result.txt'] -PathType Leaf)
    ) -Details $oldArtifactPaths['result.txt']

    Add-WinPushLiveCheck -Name "$ScenarioName leaves split stream paths blank" -Passed (
        [string]::IsNullOrWhiteSpace($Result.StdOutPath) -and [string]::IsNullOrWhiteSpace($Result.StdErrPath)
    ) -Details @{ StdOutPath = $Result.StdOutPath; StdErrPath = $Result.StdErrPath }

    if (-not [string]::IsNullOrWhiteSpace($runLogPath) -and (Test-Path -LiteralPath $runLogPath -PathType Leaf)) {
        $runLogText = Get-Content -LiteralPath $runLogPath -Raw
        Add-WinPushLiveCheck -Name "$ScenarioName run.log includes expected package output" -Passed (
            $runLogText.Contains($ExpectedOutputText)
        ) -Details $ExpectedOutputText
    }
}

function Test-WinPushLiveLogArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result,

        [Parameter(Mandatory)]
        [string] $ScenarioName
    )

    $copiedNames = @($Result.CopiedLogPaths | ForEach-Object { Split-Path -Path $_ -Leaf })
    Add-WinPushLiveCheck -Name "$ScenarioName copied immediate package logs" -Passed (
        ($copiedNames -contains 'immediate.log') -and ($copiedNames -contains 'second.log')
    ) -Details $copiedNames

    Add-WinPushLiveCheck -Name "$ScenarioName did not copy nested package logs" -Passed (
        $copiedNames -notcontains 'nested.log'
    ) -Details $copiedNames

    Add-WinPushLiveCheck -Name "$ScenarioName metadata records copied logs" -Passed (
        $Result.PackageMetadata.LogsCopied -and @($Result.PackageMetadata.CopiedLogPaths).Count -ge 2
    ) -Details (ConvertTo-WinPushLiveResultSummary -Result $Result)
}

function New-WinPushLiveEntryPointContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ValidationId,

        [Parameter(Mandatory)]
        [string] $Scenario,

        [switch] $Fail
    )

    $template = @'
$ValidationId = '__VALIDATION_ID__'
$Scenario = '__SCENARIO__'
$EntryBase = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$LogDirectory = Join-Path -Path 'C:\ProgramData\EA\Logs' -ChildPath $EntryBase
New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
Set-Content -LiteralPath (Join-Path -Path $LogDirectory -ChildPath 'immediate.log') -Value ('scenario={0};validation={1}' -f $Scenario, $ValidationId)
Set-Content -LiteralPath (Join-Path -Path $LogDirectory -ChildPath 'second.log') -Value ('second={0};validation={1}' -f $Scenario, $ValidationId)
$NestedLogDirectory = Join-Path -Path $LogDirectory -ChildPath 'nested'
New-Item -Path $NestedLogDirectory -ItemType Directory -Force | Out-Null
Set-Content -LiteralPath (Join-Path -Path $NestedLogDirectory -ChildPath 'nested.log') -Value ('nested={0};validation={1}' -f $Scenario, $ValidationId)
$PayloadPath = Join-Path -Path $PSScriptRoot -ChildPath 'payload\data.txt'
if (Test-Path -LiteralPath $PayloadPath -PathType Leaf) {
    $Payload = Get-Content -LiteralPath $PayloadPath -Raw
}
else {
    $Payload = 'no-payload'
}
Write-Output ('WinPushPackageLive scenario={0} validation={1} payload={2}' -f $Scenario, $ValidationId, $Payload)
__FAILURE_LINE__
'@

    $failureLine = if ($Fail) {
        "Write-Error ('WinPushPackageLive expected failure validation={0}' -f `$ValidationId)"
    }
    else {
        ''
    }

    $template.
        Replace('__VALIDATION_ID__', $ValidationId).
        Replace('__SCENARIO__', $Scenario).
        Replace('__FAILURE_LINE__', $failureLine)
}

function New-WinPushLivePackageSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [string] $ValidationId
    )

    New-Item -Path $Root -ItemType Directory -Force | Out-Null

    $fileEntry = 'WinPushLiveFile-{0}.ps1' -f $ValidationId
    $filePackage = Join-Path -Path $Root -ChildPath $fileEntry
    New-WinPushLiveEntryPointContent -ValidationId $ValidationId -Scenario 'file' |
        Set-Content -LiteralPath $filePackage -Encoding utf8NoBOM

    $directoryEntry = 'WinPushLiveDirectory-{0}.ps1' -f $ValidationId
    $directoryPackage = Join-Path -Path $Root -ChildPath 'DirectoryPackage'
    New-Item -Path (Join-Path -Path $directoryPackage -ChildPath 'payload') -ItemType Directory -Force | Out-Null
    New-WinPushLiveEntryPointContent -ValidationId $ValidationId -Scenario 'directory' |
        Set-Content -LiteralPath (Join-Path -Path $directoryPackage -ChildPath $directoryEntry) -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path -Path $directoryPackage -ChildPath 'payload\data.txt') -Value 'directory-payload' -Encoding utf8NoBOM

    $zipEntry = 'WinPushLiveZip-{0}.ps1' -f $ValidationId
    $zipRoot = Join-Path -Path $Root -ChildPath 'ZipRoot'
    New-Item -Path (Join-Path -Path $zipRoot -ChildPath 'payload') -ItemType Directory -Force | Out-Null
    New-WinPushLiveEntryPointContent -ValidationId $ValidationId -Scenario 'zip' |
        Set-Content -LiteralPath (Join-Path -Path $zipRoot -ChildPath $zipEntry) -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path -Path $zipRoot -ChildPath 'payload\data.txt') -Value 'zip-payload' -Encoding utf8NoBOM
    $zipPackage = Join-Path -Path $Root -ChildPath 'WinPushLiveZipPackage.zip'
    Compress-Archive -Path (Join-Path -Path $zipRoot -ChildPath '*') -DestinationPath $zipPackage -Force

    $uriEntry = 'WinPushLiveUri-{0}.ps1' -f $ValidationId
    $uriRoot = Join-Path -Path $Root -ChildPath 'UriRoot'
    New-Item -Path (Join-Path -Path $uriRoot -ChildPath 'payload') -ItemType Directory -Force | Out-Null
    New-WinPushLiveEntryPointContent -ValidationId $ValidationId -Scenario 'uri' |
        Set-Content -LiteralPath (Join-Path -Path $uriRoot -ChildPath $uriEntry) -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path -Path $uriRoot -ChildPath 'payload\data.txt') -Value 'uri-payload' -Encoding utf8NoBOM
    $uriPackage = Join-Path -Path $Root -ChildPath 'WinPushLiveUriPackage.zip'
    Compress-Archive -Path (Join-Path -Path $uriRoot -ChildPath '*') -DestinationPath $uriPackage -Force

    $failureEntry = 'WinPushLiveFailure-{0}.ps1' -f $ValidationId
    $failurePackage = Join-Path -Path $Root -ChildPath $failureEntry
    New-WinPushLiveEntryPointContent -ValidationId $ValidationId -Scenario 'failure' -Fail |
        Set-Content -LiteralPath $failurePackage -Encoding utf8NoBOM

    foreach ($entryName in @($fileEntry, $directoryEntry, $zipEntry, $uriEntry, $failureEntry)) {
        $script:RemoteLogCleanupPaths.Add((Join-Path -Path 'C:\ProgramData\EA\Logs' -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($entryName)))) | Out-Null
    }

    [pscustomobject] [ordered] @{
        FilePackage      = $filePackage
        FileEntry        = ".\$fileEntry"
        DirectoryPackage = $directoryPackage
        DirectoryEntry   = ".\$directoryEntry"
        ZipPackage       = $zipPackage
        ZipEntry         = ".\$zipEntry"
        UriPackage       = $uriPackage
        UriEntry         = ".\$uriEntry"
        FailurePackage   = $failurePackage
        FailureEntry     = ".\$failureEntry"
    }
}

function Get-WinPushLiveFreeTcpPort {
    [CmdletBinding()]
    param()

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        [int] $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Start-WinPushLiveFileServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [int] $Port = 0
    )

    $effectivePort = if ($Port -gt 0) { $Port } else { Get-WinPushLiveFreeTcpPort }
    $job = Start-Job -Name ('WinPushPackageLiveUri-{0}' -f $effectivePort) -ScriptBlock {
        param(
            [string] $ServerRoot,
            [int] $ServerPort
        )

        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $ServerPort)
        $listener.Start()
        try {
            while ($true) {
                $client = $listener.AcceptTcpClient()
                try {
                    $stream = $client.GetStream()
                    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                    $requestLine = $reader.ReadLine()
                    do {
                        $headerLine = $reader.ReadLine()
                    } while ($null -ne $headerLine -and $headerLine.Length -gt 0)

                    $statusLine = 'HTTP/1.1 404 Not Found'
                    $contentType = 'text/plain'
                    $body = [System.Text.Encoding]::UTF8.GetBytes('not found')
                    if (-not [string]::IsNullOrWhiteSpace($requestLine)) {
                        $requestParts = @($requestLine -split ' ')
                        if ($requestParts.Count -ge 2 -and $requestParts[0] -eq 'GET') {
                            $relative = [System.Uri]::UnescapeDataString($requestParts[1].TrimStart('/')).Replace('/', '\')
                            if (-not [string]::IsNullOrWhiteSpace($relative) -and -not $relative.Contains('..')) {
                                $candidate = Join-Path -Path $ServerRoot -ChildPath $relative
                                $canonicalRoot = [System.IO.Path]::GetFullPath(('{0}\' -f $ServerRoot.TrimEnd('\')))
                                $canonicalCandidate = [System.IO.Path]::GetFullPath($candidate)
                                if (
                                    $canonicalCandidate.StartsWith($canonicalRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
                                    (Test-Path -LiteralPath $canonicalCandidate -PathType Leaf)
                                ) {
                                    $statusLine = 'HTTP/1.1 200 OK'
                                    $contentType = 'application/octet-stream'
                                    $body = [System.IO.File]::ReadAllBytes($canonicalCandidate)
                                }
                            }
                        }
                    }

                    $header = "{0}`r`nContent-Type: {1}`r`nContent-Length: {2}`r`nConnection: close`r`n`r`n" -f $statusLine, $contentType, $body.Length
                    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                    $stream.Write($headerBytes, 0, $headerBytes.Length)
                    $stream.Write($body, 0, $body.Length)
                    $stream.Flush()
                }
                finally {
                    $client.Close()
                }
            }
        }
        finally {
            $listener.Stop()
        }
    } -ArgumentList $Root, $effectivePort

    [pscustomobject] [ordered] @{
        Job     = $job
        Port    = $effectivePort
        BaseUri = 'http://127.0.0.1:{0}/' -f $effectivePort
    }
}

function Stop-WinPushLiveFileServer {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Server
    )

    if ($null -eq $Server -or $null -eq $Server.Job) {
        return
    }

    Stop-Job -Job $Server.Job -ErrorAction SilentlyContinue
    Remove-Job -Job $Server.Job -Force -ErrorAction SilentlyContinue
}

function Invoke-WinPushLivePackageScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [hashtable] $Parameters
    )

    $result = Invoke-WinPushPackage @Parameters
    $summary = ConvertTo-WinPushLiveResultSummary -Result $result
    $script:Validation.Scenarios += [pscustomobject] [ordered] @{
        Name   = $Name
        Result = $summary
    }

    $stageDirectory = Get-WinPushLiveRemoteStageDirectory -RemoteStagePath $result.PackageMetadata.RemoteStagePath
    if (-not [string]::IsNullOrWhiteSpace($stageDirectory)) {
        $script:RemoteStageCleanupPaths.Add($stageDirectory) | Out-Null
    }

    $result
}

$exitCode = 0
$scratchRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('WinPushPackageLiveValidation-{0}' -f ([guid]::NewGuid().ToString('N')))
$server = $null

try {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'WinPush.psd1'
    $script:Validation.ModulePath = $modulePath
    Import-Module $modulePath -Force

    $preflightSession = $null
    try {
        $preflightSession = New-WinPushLiveRemoteSession
        $preflightOutput = Invoke-Command -Session $preflightSession -ScriptBlock {
            [pscustomobject] [ordered] @{
                ComputerName = $env:COMPUTERNAME
                UserName     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                PowerShell   = $PSVersionTable.PSVersion.ToString()
            }
        } -ErrorAction Stop

        $script:Validation.Preflight = $preflightOutput
        Add-WinPushLiveCheck -Name 'PSRP preflight session creation succeeded' -Passed $true -Details $preflightOutput
    }
    catch {
        $script:Validation.Blocked = $true
        $script:Validation.Status = 'Blocked'
        $script:Validation.BlockReason = 'PSRP session creation failed during target preflight.'
        $script:Validation.Preflight = [pscustomobject] [ordered] @{
            Succeeded = $false
            Error     = $_.Exception.Message
        }
        Add-WinPushLiveCheck -Name 'PSRP preflight session creation succeeded' -Passed $false -Details $_.Exception.Message
        $exitCode = 2
    }
    finally {
        if ($null -ne $preflightSession) {
            Remove-PSSession -Id $preflightSession.Id -ErrorAction SilentlyContinue
        }
    }

    if (-not $script:Validation.Blocked) {
        $validationId = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $sources = New-WinPushLivePackageSource -Root $scratchRoot -ValidationId $validationId
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $PackageCacheRoot -ItemType Directory -Force | Out-Null
        $server = Start-WinPushLiveFileServer -Root $scratchRoot -Port $HttpPort
        Start-Sleep -Milliseconds 400
        $uriPackageName = Split-Path -Path $sources.UriPackage -Leaf
        $uriPackageSource = [uri] ('{0}{1}' -f $server.BaseUri, $uriPackageName)
        $probePath = Join-Path -Path $scratchRoot -ChildPath 'uri-probe.zip'
        Invoke-WebRequest -Uri $uriPackageSource -OutFile $probePath -ErrorAction Stop

        $basePackageParameters = @{
            ComputerName     = $ComputerName
            OutputRoot       = $OutputRoot
            PackageCacheRoot = $PackageCacheRoot
            RemoteStageRoot  = $RemoteStageRoot
            CaptureOutput    = $true
        }
        if ($null -ne $Credential) {
            $basePackageParameters['Credential'] = $Credential
        }

        $fileParameters = $basePackageParameters.Clone()
        $fileParameters['Path'] = $sources.FilePackage
        $fileParameters['EntryPoint'] = $sources.FileEntry
        $fileParameters['Cleanup'] = 'Never'
        $fileResult = Invoke-WinPushLivePackageScenario -Name 'local file package cleanup Never' -Parameters $fileParameters
        $fileStageDirectory = Get-WinPushLiveRemoteStageDirectory -RemoteStagePath $fileResult.PackageMetadata.RemoteStagePath
        Add-WinPushLiveCheck -Name 'local file package succeeded' -Passed $fileResult.Succeeded -Details (ConvertTo-WinPushLiveResultSummary -Result $fileResult)
        Add-WinPushLiveCheck -Name 'Cleanup Never leaves remote package stage present until harness cleanup' -Passed (
            -not [string]::IsNullOrWhiteSpace($fileStageDirectory) -and (Test-WinPushLiveRemotePath -Path $fileStageDirectory)
        ) -Details $fileStageDirectory
        Test-WinPushLiveCaptureArtifact -Result $fileResult -ScenarioName 'local file package' -ExpectedOutputText 'scenario=file'

        $directoryParameters = $basePackageParameters.Clone()
        $directoryParameters['Path'] = $sources.DirectoryPackage
        $directoryParameters['EntryPoint'] = $sources.DirectoryEntry
        $directoryParameters['Logs'] = $true
        $directoryParameters['Cleanup'] = 'OnSuccess'
        $directoryResult = Invoke-WinPushLivePackageScenario -Name 'local directory package logs cleanup OnSuccess' -Parameters $directoryParameters
        $directoryStageDirectory = Get-WinPushLiveRemoteStageDirectory -RemoteStagePath $directoryResult.PackageMetadata.RemoteStagePath
        Add-WinPushLiveCheck -Name 'local directory package succeeded' -Passed $directoryResult.Succeeded -Details (ConvertTo-WinPushLiveResultSummary -Result $directoryResult)
        Add-WinPushLiveCheck -Name 'local directory package used preserved relative payload' -Passed (
            (@($directoryResult.Output) -join "`n").Contains('directory-payload')
        ) -Details @($directoryResult.Output)
        Add-WinPushLiveCheck -Name 'Cleanup OnSuccess removed remote package stage' -Passed (
            -not [string]::IsNullOrWhiteSpace($directoryStageDirectory) -and -not (Test-WinPushLiveRemotePath -Path $directoryStageDirectory)
        ) -Details $directoryStageDirectory
        Test-WinPushLiveCaptureArtifact -Result $directoryResult -ScenarioName 'local directory package' -ExpectedOutputText 'scenario=directory'
        Test-WinPushLiveLogArtifact -Result $directoryResult -ScenarioName 'local directory package'

        $zipParameters = $basePackageParameters.Clone()
        $zipParameters['Path'] = $sources.ZipPackage
        $zipParameters['EntryPoint'] = $sources.ZipEntry
        $zipParameters['Extract'] = $true
        $zipParameters['Cleanup'] = 'Always'
        $zipResult = Invoke-WinPushLivePackageScenario -Name 'local zip package extract cleanup Always' -Parameters $zipParameters
        $zipStageDirectory = Get-WinPushLiveRemoteStageDirectory -RemoteStagePath $zipResult.PackageMetadata.RemoteStagePath
        Add-WinPushLiveCheck -Name 'local zip package succeeded' -Passed $zipResult.Succeeded -Details (ConvertTo-WinPushLiveResultSummary -Result $zipResult)
        Add-WinPushLiveCheck -Name 'local zip package extracted remotely' -Passed $zipResult.PackageMetadata.Extracted -Details (ConvertTo-WinPushLiveResultSummary -Result $zipResult)
        Add-WinPushLiveCheck -Name 'Cleanup Always removed successful zip remote package stage' -Passed (
            -not [string]::IsNullOrWhiteSpace($zipStageDirectory) -and -not (Test-WinPushLiveRemotePath -Path $zipStageDirectory)
        ) -Details $zipStageDirectory
        Test-WinPushLiveCaptureArtifact -Result $zipResult -ScenarioName 'local zip package' -ExpectedOutputText 'scenario=zip'

        $uriParameters = $basePackageParameters.Clone()
        $uriParameters.Remove('Path')
        $uriParameters['Uri'] = $uriPackageSource
        $uriParameters['EntryPoint'] = $sources.UriEntry
        $uriParameters['Extract'] = $true
        $uriParameters['Cleanup'] = 'Always'
        $uriResult = Invoke-WinPushLivePackageScenario -Name 'URI package extract cleanup Always' -Parameters $uriParameters
        $uriStageDirectory = Get-WinPushLiveRemoteStageDirectory -RemoteStagePath $uriResult.PackageMetadata.RemoteStagePath
        Add-WinPushLiveCheck -Name 'URI package succeeded' -Passed $uriResult.Succeeded -Details (ConvertTo-WinPushLiveResultSummary -Result $uriResult)
        Add-WinPushLiveCheck -Name 'URI package recorded source and admin cache path' -Passed (
            $uriResult.PackageMetadata.PackageSourceType -eq 'Uri' -and
            $uriResult.PackageMetadata.PackageSource -eq $uriPackageSource.OriginalString -and
            -not [string]::IsNullOrWhiteSpace($uriResult.PackageMetadata.LocalPackagePath) -and
            $uriResult.PackageMetadata.LocalPackagePath.StartsWith($PackageCacheRoot, [System.StringComparison]::OrdinalIgnoreCase)
        ) -Details (ConvertTo-WinPushLiveResultSummary -Result $uriResult)
        Add-WinPushLiveCheck -Name 'Cleanup Always removed successful URI remote package stage' -Passed (
            -not [string]::IsNullOrWhiteSpace($uriStageDirectory) -and -not (Test-WinPushLiveRemotePath -Path $uriStageDirectory)
        ) -Details $uriStageDirectory
        Test-WinPushLiveCaptureArtifact -Result $uriResult -ScenarioName 'URI package' -ExpectedOutputText 'scenario=uri'

        $failureParameters = $basePackageParameters.Clone()
        $failureParameters['Path'] = $sources.FailurePackage
        $failureParameters['EntryPoint'] = $sources.FailureEntry
        $failureParameters['Logs'] = $true
        $failureParameters['Cleanup'] = 'Always'
        $failureResult = Invoke-WinPushLivePackageScenario -Name 'entry point failure cleanup Always' -Parameters $failureParameters
        $failureStageDirectory = Get-WinPushLiveRemoteStageDirectory -RemoteStagePath $failureResult.PackageMetadata.RemoteStagePath
        Add-WinPushLiveCheck -Name 'representative package entry point failure failed the package result' -Passed (
            -not $failureResult.Succeeded -and ((@($failureResult.Errors) -join "`n").Contains('expected failure'))
        ) -Details (ConvertTo-WinPushLiveResultSummary -Result $failureResult)
        Add-WinPushLiveCheck -Name 'Cleanup Always removed failed package remote stage' -Passed (
            -not [string]::IsNullOrWhiteSpace($failureStageDirectory) -and -not (Test-WinPushLiveRemotePath -Path $failureStageDirectory)
        ) -Details $failureStageDirectory
        Test-WinPushLiveCaptureArtifact -Result $failureResult -ScenarioName 'entry point failure package' -ExpectedOutputText 'scenario=failure'
        Test-WinPushLiveLogArtifact -Result $failureResult -ScenarioName 'entry point failure package'
    }
}
catch {
    $script:Validation.Status = 'Failed'
    $script:Validation.Blocked = $false
    Add-WinPushLiveCheck -Name 'harness completed without unhandled exception' -Passed $false -Details $_.Exception.Message
    $exitCode = 1
}
finally {
    Stop-WinPushLiveFileServer -Server $server

    if (Test-Path -LiteralPath $scratchRoot) {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:Validation.LocalScratchRemoved = -not (Test-Path -LiteralPath $scratchRoot)

    if (Test-Path -LiteralPath $PackageCacheRoot) {
        Remove-Item -LiteralPath $PackageCacheRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:Validation.PackageCacheRemoved = -not (Test-Path -LiteralPath $PackageCacheRoot)

    if (-not $script:Validation.Blocked) {
        foreach ($remoteStagePath in @($script:RemoteStageCleanupPaths | Select-Object -Unique)) {
            if (-not [string]::IsNullOrWhiteSpace($remoteStagePath)) {
                try {
                    Remove-WinPushLiveRemotePath -Path $remoteStagePath -Kind Stage
                }
                catch {
                    Add-WinPushLiveCheck -Name 'remote stage cleanup completed' -Passed $false -Details $_.Exception.Message
                }
            }
        }

        foreach ($remoteLogPath in @($script:RemoteLogCleanupPaths | Select-Object -Unique)) {
            if (-not [string]::IsNullOrWhiteSpace($remoteLogPath)) {
                try {
                    Remove-WinPushLiveRemotePath -Path $remoteLogPath -Kind Log
                }
                catch {
                    Add-WinPushLiveCheck -Name 'remote package log cleanup completed' -Passed $false -Details $_.Exception.Message
                }
            }
        }
    }

    Add-WinPushLiveCheck -Name 'local scratch package sources were removed' -Passed $script:Validation.LocalScratchRemoved -Details $scratchRoot
    Add-WinPushLiveCheck -Name 'local URI package cache was removed' -Passed $script:Validation.PackageCacheRemoved -Details $PackageCacheRoot
    Add-WinPushLiveCheck -Name 'local PSSession count did not increase' -Passed (
        @(Get-PSSession).Count -eq $script:Validation.BeforeLocalPSSessionCount
    ) -Details @{
        Before = $script:Validation.BeforeLocalPSSessionCount
        After  = @(Get-PSSession).Count
    }

    Write-WinPushLiveResult
}

Write-Output ('WinPush package live validation result: {0}' -f $ResultPath)
exit $exitCode
