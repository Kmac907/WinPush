function Get-WinPushCommandLogDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Command
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref] $tokens, [ref] $parseErrors)
    $commandAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    $commandName = if ($null -ne $commandAst) { $commandAst.GetCommandName() } else { $null }

    if ([string]::IsNullOrWhiteSpace($commandName)) {
        $commandName = 'Command'
    }

    $leafName = Split-Path -Path $commandName -Leaf
    if ([string]::IsNullOrWhiteSpace($leafName)) {
        $leafName = $commandName
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($leafName)
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = 'Command'
    }

    $invalidPattern = '[\\/:*?"<>|\p{Cc}]'
    $safeName = ([regex]::Replace($baseName, $invalidPattern, '-')).Trim('. ')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'Command'
    }

    Join-Path -Path 'C:\ProgramData\EA\Logs' -ChildPath $safeName
}
