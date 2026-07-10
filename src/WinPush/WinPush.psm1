Set-StrictMode -Version Latest

$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

foreach ($sourcePath in @($privatePath, $publicPath)) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        continue
    }

    $functions = Get-ChildItem -LiteralPath $sourcePath -Filter '*.ps1' -File -Recurse |
        Sort-Object -Property FullName

    foreach ($function in $functions) {
        . $function.FullName
    }
}

Export-ModuleMember -Function @()
