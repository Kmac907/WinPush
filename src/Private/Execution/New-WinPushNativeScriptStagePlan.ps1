function New-WinPushNativeScriptStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [AllowNull()]
        [string] $RemediateScriptPath
    )

    $stageId = [System.Guid]::NewGuid().ToString('N')
    $scriptName = Split-Path -Path $ScriptPath -Leaf
    $remoteDirectory = 'C:\Windows\Temp\WinPush\{0}' -f $stageId
    $remoteScriptPath = '{0}\{1}' -f $remoteDirectory, $scriptName

    $plan = [pscustomobject] [ordered] @{
        PSTypeName       = 'WinPush.NativeScriptStagePlan'
        ComputerName     = $ComputerName
        RemoteDirectory  = $remoteDirectory
        RemoteScriptPath = $remoteScriptPath
    }

    if (-not [string]::IsNullOrWhiteSpace($RemediateScriptPath)) {
        $remediateScriptName = Split-Path -Path $RemediateScriptPath -Leaf
        if ($remediateScriptName -eq $scriptName) {
            $remediateScriptName = 'Remediate-{0}' -f $remediateScriptName
        }

        $plan | Add-Member -NotePropertyName RemoteDetectionScriptPath -NotePropertyValue $remoteScriptPath
        $plan | Add-Member `
            -NotePropertyName RemoteRemediationScriptPath `
            -NotePropertyValue ('{0}\{1}' -f $remoteDirectory, $remediateScriptName)
    }

    $plan
}

function Copy-WinPushNativeScriptToStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter(Mandatory)]
        [object] $StagePlan,

        [Parameter(Mandatory)]
        [ValidateSet('WinRM', 'PsExec')]
        [string] $Transport,

        [AllowNull()]
        [string] $PsExecPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    $base64Path = '{0}.b64' -f $StagePlan.RemoteScriptPath
    $scriptBytes = [System.IO.File]::ReadAllBytes($ScriptPath)
    $scriptPayload = [System.Convert]::ToBase64String($scriptBytes)
    $encodedRemoteDirectory = ConvertTo-WinPushPowerShellSingleQuotedString -Value $StagePlan.RemoteDirectory
    $encodedRemoteScriptPath = ConvertTo-WinPushPowerShellSingleQuotedString -Value $StagePlan.RemoteScriptPath
    $encodedBase64Path = ConvertTo-WinPushPowerShellSingleQuotedString -Value $base64Path

    $initializeScript = @"
`$ErrorActionPreference = 'Stop'
[System.IO.Directory]::CreateDirectory($encodedRemoteDirectory) | Out-Null
if ([System.IO.File]::Exists($encodedRemoteScriptPath)) {
    [System.IO.File]::Delete($encodedRemoteScriptPath)
}
if ([System.IO.File]::Exists($encodedBase64Path)) {
    [System.IO.File]::Delete($encodedBase64Path)
}
"@
    Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $initializeScript -Transport $Transport -PsExecPath $PsExecPath -TimeoutSeconds $TimeoutSeconds

    $chunkSize = 1000
    for ($offset = 0; $offset -lt $scriptPayload.Length; $offset += $chunkSize) {
        $length = [System.Math]::Min($chunkSize, $scriptPayload.Length - $offset)
        $chunk = $scriptPayload.Substring($offset, $length)
        $encodedChunk = ConvertTo-WinPushPowerShellSingleQuotedString -Value $chunk
        $appendScript = "[System.IO.File]::AppendAllText($encodedBase64Path, $encodedChunk, [System.Text.Encoding]::ASCII)"
        Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $appendScript -Transport $Transport -PsExecPath $PsExecPath -TimeoutSeconds $TimeoutSeconds
    }

    $decodeScript = @"
`$ErrorActionPreference = 'Stop'
`$scriptBytes = [System.Convert]::FromBase64String([System.IO.File]::ReadAllText($encodedBase64Path))
[System.IO.File]::WriteAllBytes($encodedRemoteScriptPath, `$scriptBytes)
if ([System.IO.File]::Exists($encodedBase64Path)) {
    [System.IO.File]::Delete($encodedBase64Path)
}
"@
    Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $decodeScript -Transport $Transport -PsExecPath $PsExecPath -TimeoutSeconds $TimeoutSeconds
}

function Copy-WinPushRemediationScriptsToStage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $DetectScriptPath,

        [Parameter(Mandatory)]
        [string] $RemediateScriptPath,

        [Parameter(Mandatory)]
        [object] $StagePlan,

        [Parameter(Mandatory)]
        [ValidateSet('Psrp', 'WinRM', 'PsExec')]
        [string] $Transport,

        [AllowNull()]
        [string] $PsExecPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    if ($Transport -eq 'Psrp') {
        $null = Invoke-WinPushPsrpJob `
            -Session $Session `
            -ScriptBlock {
                [System.IO.Directory]::CreateDirectory([string] $args[0]) | Out-Null
                [System.IO.File]::WriteAllBytes([string] $args[1], [byte[]] @())
                [System.IO.File]::WriteAllBytes([string] $args[2], [byte[]] @())
            } `
            -ArgumentList $StagePlan.RemoteDirectory, $StagePlan.RemoteDetectionScriptPath, $StagePlan.RemoteRemediationScriptPath `
            -TimeoutSeconds $TimeoutSeconds `
            -Operation 'PSRP staging'
        foreach ($script in @(
                [pscustomobject] @{ LocalPath = $DetectScriptPath; RemotePath = $StagePlan.RemoteDetectionScriptPath }
                [pscustomobject] @{ LocalPath = $RemediateScriptPath; RemotePath = $StagePlan.RemoteRemediationScriptPath }
            )) {
            $bytes = [System.IO.File]::ReadAllBytes($script.LocalPath)
            for ($offset = 0; $offset -lt $bytes.Length; $offset += 32768) {
                $length = [System.Math]::Min(32768, $bytes.Length - $offset)
                $chunk = [byte[]] $bytes[$offset..($offset + $length - 1)]
                $null = Invoke-WinPushPsrpJob `
                    -Session $Session `
                    -ScriptBlock {
                        $stream = [System.IO.File]::Open([string] $args[0], [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                        try { $stream.Write([byte[]] $args[1], 0, ([byte[]] $args[1]).Length) }
                        finally { $stream.Dispose() }
                    } `
                    -ArgumentList $script.RemotePath, $chunk `
                    -TimeoutSeconds $TimeoutSeconds `
                    -Operation 'PSRP upload'
            }
        }
        return
    }

    Copy-WinPushNativeScriptToStage `
        -ComputerName $ComputerName `
        -ScriptPath $DetectScriptPath `
        -StagePlan $StagePlan `
        -Transport $Transport `
        -PsExecPath $PsExecPath `
        -TimeoutSeconds $TimeoutSeconds

    $remediationPlan = [pscustomobject] @{
        RemoteDirectory  = $StagePlan.RemoteDirectory
        RemoteScriptPath = $StagePlan.RemoteRemediationScriptPath
    }
    Copy-WinPushNativeScriptToStage `
        -ComputerName $ComputerName `
        -ScriptPath $RemediateScriptPath `
        -StagePlan $remediationPlan `
        -Transport $Transport `
        -PsExecPath $PsExecPath `
        -TimeoutSeconds $TimeoutSeconds
}

function Remove-WinPushRemediationScriptStage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [object] $StagePlan,

        [Parameter(Mandatory)]
        [ValidateSet('Psrp', 'WinRM', 'PsExec')]
        [string] $Transport,

        [AllowNull()]
        [string] $PsExecPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    if ($Transport -eq 'Psrp') {
        $null = Invoke-WinPushPsrpJob `
            -Session $Session `
            -ScriptBlock {
                if ([System.IO.Directory]::Exists([string] $args[0])) {
                    [System.IO.Directory]::Delete([string] $args[0], $true)
                }
            } `
            -ArgumentList $StagePlan.RemoteDirectory `
            -TimeoutSeconds $TimeoutSeconds `
            -Operation 'PSRP cleanup'
        return
    }

    Remove-WinPushNativeScriptStage `
        -ComputerName $ComputerName `
        -StagePlan $StagePlan `
        -Transport $Transport `
        -PsExecPath $PsExecPath `
        -TimeoutSeconds $TimeoutSeconds
}

function New-WinPushNativeStagedScriptCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemoteScriptPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) {
        $encodedRemoteScriptPath = ConvertTo-WinPushPowerShellSingleQuotedString -Value $RemoteScriptPath
        return New-WinPushNativePowerShellEncodedCommand -Command ('$ProgressPreference = ''SilentlyContinue''; & {{ & {0} }}' -f $encodedRemoteScriptPath)
    }

    $scriptArguments = ConvertTo-WinPushPowerShellSingleQuotedString `
        -Value ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $RemoteScriptPath)
    $command = @"
`$ErrorActionPreference = 'Stop'
`$startInfo = [System.Diagnostics.ProcessStartInfo]::new('powershell.exe', $scriptArguments)
`$startInfo.UseShellExecute = `$false
`$process = [System.Diagnostics.Process]::Start(`$startInfo)
if ($TimeoutSeconds -eq 0) {
    `$process.WaitForExit()
    `$exited = `$true
}
else {
    `$remainingMilliseconds = [long] $TimeoutSeconds * 1000
    do {
        `$waitMilliseconds = [int] [System.Math]::Min([int]::MaxValue, `$remainingMilliseconds)
        `$exited = `$process.WaitForExit(`$waitMilliseconds)
        `$remainingMilliseconds -= `$waitMilliseconds
    } while (-not `$exited -and `$remainingMilliseconds -gt 0)
}
if (-not `$exited) {
    `$process.Kill()
    `$process.WaitForExit()
    [Console]::Error.WriteLine('Process timed out after $TimeoutSeconds seconds.')
    exit 124
}
exit `$process.ExitCode
"@
    New-WinPushNativePowerShellEncodedCommand -Command $command
}

function Invoke-WinPushPsrpJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [object[]] $ArgumentList = @(),

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800,

        [string] $Operation = 'PSRP operation'
    )

    $job = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -AsJob -ErrorAction Stop
    try {
        $completedJob = if ($TimeoutSeconds -eq 0) {
            Wait-Job -Job $job
        }
        else {
            Wait-Job -Job $job -Timeout $TimeoutSeconds
        }
        if ($null -eq $completedJob) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            throw "$Operation timed out after $TimeoutSeconds seconds."
        }

        Receive-Job -Job $job -ErrorAction Stop
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Remove-WinPushNativeScriptStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [object] $StagePlan,

        [Parameter(Mandatory)]
        [ValidateSet('WinRM', 'PsExec')]
        [string] $Transport,

        [AllowNull()]
        [string] $PsExecPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    $encodedRemoteDirectory = ConvertTo-WinPushPowerShellSingleQuotedString -Value $StagePlan.RemoteDirectory
    $cleanupScript = @"
`$ErrorActionPreference = 'Stop'
if ([System.IO.Directory]::Exists($encodedRemoteDirectory)) {
    [System.IO.Directory]::Delete($encodedRemoteDirectory, `$true)
}
"@

    Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $cleanupScript -Transport $Transport -PsExecPath $PsExecPath -TimeoutSeconds $TimeoutSeconds
}

function Invoke-WinPushNativeScriptStageCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $Command,

        [Parameter(Mandatory)]
        [ValidateSet('WinRM', 'PsExec')]
        [string] $Transport,

        [AllowNull()]
        [string] $PsExecPath,

        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSeconds = 1800
    )

    $nativeCommand = New-WinPushNativePowerShellEncodedCommand -Command $Command
    $result = if ($Transport -eq 'WinRM') {
        Invoke-WinPushWinRsCommand -ComputerName $ComputerName -Command $nativeCommand -TimeoutSeconds $TimeoutSeconds
    }
    else {
        Invoke-WinPushPsExecCommand -ComputerName $ComputerName -Command $nativeCommand -PsExecPath $PsExecPath -TimeoutSeconds $TimeoutSeconds
    }

    if ($result.ExitCode -ne 0) {
        $firstError = @($result.Errors | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | Select-Object -First 1)
        if ($firstError.Count -gt 0) {
            throw ([string] $firstError[0]).Trim()
        }

        throw ('Native script staging command exited with code {0}.' -f $result.ExitCode)
    }
}

function ConvertTo-WinPushPowerShellSingleQuotedString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Value
    )

    "'{0}'" -f ($Value -replace "'", "''")
}
