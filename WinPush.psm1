Set-StrictMode -Version Latest

$sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath 'src'
$privatePath = Join-Path -Path $sourceRoot -ChildPath 'Private'
$publicPath = Join-Path -Path $sourceRoot -ChildPath 'Public'

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

$publicFunctionsToExport = @(
    'Copy-WinPushItem',
    'Export-WinPushHostFileFromEntraGroup',
    'Get-WinPushLog',
    'Get-WinPushRun',
    'Invoke-WinPushCommand',
    'Invoke-WinPushPackage',
    'Invoke-WinPushRemediation',
    'Invoke-WinPushScript',
    'Test-WinPushRemediation',
    'Test-WinPushTarget'
)

Export-ModuleMember -Function $publicFunctionsToExport
