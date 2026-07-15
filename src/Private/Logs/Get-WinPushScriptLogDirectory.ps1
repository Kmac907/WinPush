function Get-WinPushScriptLogDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath
    )

    $leafName = Split-Path -Path $ScriptPath -Leaf
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($leafName)
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = 'Script'
    }

    $invalidPattern = '[\\/:*?"<>|\p{Cc}]'
    $safeName = ([regex]::Replace($baseName, $invalidPattern, '-')).Trim('. ')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'Script'
    }

    Join-Path -Path 'C:\ProgramData\EA\Logs' -ChildPath $safeName
}
