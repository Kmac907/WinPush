@{
    RootModule           = 'WinPush.psm1'
    ModuleVersion        = '0.2.0'
    GUID                 = '4e7a6812-7b4f-4a4b-86dd-53f5b5c31d3f'
    Author               = 'Endpoint Engineering'
    CompanyName          = 'Endpoint Engineering'
    Copyright            = '(c) Endpoint Engineering. All rights reserved.'
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
            ProjectUri = 'https://dev.azure.com/scfitops/Endpoint%20Engineering/_git/Modules'
        }
    }
}
