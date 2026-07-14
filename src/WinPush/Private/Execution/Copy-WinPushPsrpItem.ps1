function Copy-WinPushPsrpItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    Copy-Item `
        -LiteralPath $Path `
        -Destination $Destination `
        -ToSession $Session `
        -ErrorAction Stop
}
