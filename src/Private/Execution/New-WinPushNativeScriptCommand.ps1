function New-WinPushNativeScriptCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath
    )

    $scriptText = [System.IO.File]::ReadAllText($ScriptPath)
    $scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($scriptText)
    $scriptPayload = [System.Convert]::ToBase64String($scriptBytes)
    $wrapper = @"
`$ErrorActionPreference = 'Continue'
`$scriptText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$scriptPayload'))
`$scriptBlock = [scriptblock]::Create(`$scriptText)
try {
    & `$scriptBlock
    if (`$global:Error.Count -gt 0) {
        exit 1
    }
    if (`$global:LASTEXITCODE -is [int] -and `$global:LASTEXITCODE -ne 0) {
        exit `$global:LASTEXITCODE
    }
    exit 0
}
catch {
    Write-Error `$_.Exception.Message
    exit 1
}
"@
    $encodedWrapper = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wrapper))

    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encodedWrapper
}
