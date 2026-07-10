@{
    RootModule           = 'WinPush.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '4e7a6812-7b4f-4a4b-86dd-53f5b5c31d3f'
    Author               = 'Endpoint Engineering'
    CompanyName          = 'Endpoint Engineering'
    Copyright            = '(c) Endpoint Engineering. All rights reserved.'
    Description          = 'PSRP-first Windows administration module for target testing, command execution, file transfer, and log retrieval.'
    PowerShellVersion    = '7.6'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Test-WinPushTarget'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Windows', 'PSRP', 'WinRM', 'Administration')
            ProjectUri = ''
        }
    }
}
