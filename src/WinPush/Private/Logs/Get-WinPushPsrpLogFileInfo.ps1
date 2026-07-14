function Get-WinPushPsrpLogFileInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $RemoteDirectory
    )

    $remoteScriptBlock = {
        param(
            [Parameter(Mandatory)]
            [string] $Path
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "RemoteDirectory was not found or is not a directory: $Path"
        }

        Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop |
            Where-Object { -not $_.PSIsContainer } |
            ForEach-Object {
                [pscustomobject] [ordered] @{
                    RemoteDirectory  = $Path
                    RemotePath       = $_.FullName
                    Name             = $_.Name
                    Length           = $_.Length
                    LastWriteTimeUtc = $_.LastWriteTimeUtc
                }
            }
    }

    Invoke-Command `
        -Session $Session `
        -ScriptBlock $remoteScriptBlock `
        -ArgumentList $RemoteDirectory `
        -ErrorAction Stop
}
