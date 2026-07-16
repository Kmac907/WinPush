function New-WinPushNativeScriptStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $ScriptPath
    )

    $stageId = [System.Guid]::NewGuid().ToString('N')
    $scriptName = Split-Path -Path $ScriptPath -Leaf
    $remoteDirectory = 'C:\Windows\Temp\WinPush\{0}' -f $stageId
    $remoteScriptPath = '{0}\{1}' -f $remoteDirectory, $scriptName

    [pscustomobject] [ordered] @{
        PSTypeName       = 'WinPush.NativeScriptStagePlan'
        ComputerName     = $ComputerName
        RemoteDirectory  = $remoteDirectory
        RemoteScriptPath = $remoteScriptPath
    }
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
        [string] $PsExecPath
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
    Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $initializeScript -Transport $Transport -PsExecPath $PsExecPath

    $chunkSize = 1000
    for ($offset = 0; $offset -lt $scriptPayload.Length; $offset += $chunkSize) {
        $length = [System.Math]::Min($chunkSize, $scriptPayload.Length - $offset)
        $chunk = $scriptPayload.Substring($offset, $length)
        $encodedChunk = ConvertTo-WinPushPowerShellSingleQuotedString -Value $chunk
        $appendScript = "[System.IO.File]::AppendAllText($encodedBase64Path, $encodedChunk, [System.Text.Encoding]::ASCII)"
        Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $appendScript -Transport $Transport -PsExecPath $PsExecPath
    }

    $decodeScript = @"
`$ErrorActionPreference = 'Stop'
`$scriptBytes = [System.Convert]::FromBase64String([System.IO.File]::ReadAllText($encodedBase64Path))
[System.IO.File]::WriteAllBytes($encodedRemoteScriptPath, `$scriptBytes)
if ([System.IO.File]::Exists($encodedBase64Path)) {
    [System.IO.File]::Delete($encodedBase64Path)
}
"@
    Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $decodeScript -Transport $Transport -PsExecPath $PsExecPath
}

function New-WinPushNativeStagedScriptCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemoteScriptPath
    )

    $encodedRemoteScriptPath = ConvertTo-WinPushPowerShellSingleQuotedString -Value $RemoteScriptPath
    New-WinPushNativePowerShellEncodedCommand -Command ('$ProgressPreference = ''SilentlyContinue''; & {{ & {0} }}' -f $encodedRemoteScriptPath)
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
        [string] $PsExecPath
    )

    $encodedRemoteDirectory = ConvertTo-WinPushPowerShellSingleQuotedString -Value $StagePlan.RemoteDirectory
    $cleanupScript = @"
`$ErrorActionPreference = 'Stop'
if ([System.IO.Directory]::Exists($encodedRemoteDirectory)) {
    [System.IO.Directory]::Delete($encodedRemoteDirectory, `$true)
}
"@

    Invoke-WinPushNativeScriptStageCommand -ComputerName $ComputerName -Command $cleanupScript -Transport $Transport -PsExecPath $PsExecPath
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
        [string] $PsExecPath
    )

    $nativeCommand = New-WinPushNativePowerShellEncodedCommand -Command $Command
    $result = if ($Transport -eq 'WinRM') {
        Invoke-WinPushWinRsCommand -ComputerName $ComputerName -Command $nativeCommand
    }
    else {
        Invoke-WinPushPsExecCommand -ComputerName $ComputerName -Command $nativeCommand -PsExecPath $PsExecPath
    }

    if ($result.ExitCode -ne 0) {
        $firstError = @($result.Errors | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | Select-Object -First 1)
        if ($firstError.Count -gt 0) {
            throw ([string] $firstError[0]).Trim()
        }

        throw ('Native script staging command exited with code {0}.' -f $result.ExitCode)
    }
}

function New-WinPushNativePowerShellEncodedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Command
    )

    $encodedCommand = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))

    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encodedCommand
}

function ConvertTo-WinPushPowerShellSingleQuotedString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Value
    )

    "'{0}'" -f ($Value -replace "'", "''")
}
