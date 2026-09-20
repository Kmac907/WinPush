@{
    RootModule           = 'WinPush.psm1'
    ModuleVersion        = '0.2.0'
    GUID                 = '4e7a6812-7b4f-4a4b-86dd-53f5b5c31d3f'
    Author               = 'Kyle Maclachlan'
    Copyright            = '(c) 2026 Kyle Maclachlan. Licensed under GPL-3.0-only.'
    Description          = 'PSRP-first Windows administration module for target testing, command execution, file transfer, and log retrieval.'
    PowerShellVersion    = '7.6'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
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
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    FormatsToProcess     = @('WinPush.format.ps1xml')

    PrivateData          = @{
        PSData = @{
            Tags       = @('Windows', 'PSRP', 'WinRM', 'Administration')
            ProjectUri = 'https://github.com/Kmac907/WinPush'
            LicenseUri = 'https://github.com/Kmac907/WinPush/blob/main/LICENSE'
        }
    }
}
