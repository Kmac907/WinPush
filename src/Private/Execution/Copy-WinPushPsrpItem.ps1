function Copy-WinPushPsrpItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Destination,

        [ValidateSet('Upload', 'Download')]
        [string] $Direction = 'Upload'
    )

    if ($Direction -eq 'Download') {
        Copy-Item `
            -LiteralPath $Path `
            -Destination $Destination `
            -FromSession $Session `
            -ErrorAction Stop
    }
    else {
        Copy-Item `
            -LiteralPath $Path `
            -Destination $Destination `
            -ToSession $Session `
            -ErrorAction Stop
    }
}
