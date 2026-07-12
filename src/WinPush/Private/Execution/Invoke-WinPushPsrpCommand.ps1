function Invoke-WinPushPsrpCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ErrorAction Stop
}
