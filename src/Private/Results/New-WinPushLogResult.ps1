function New-WinPushLogResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemotePath,

        [AllowNull()]
        [string] $LocalPath = $null,

        [Parameter(Mandatory)]
        [bool] $Copied,

        [AllowNull()]
        [Alias('Error')]
        [string] $ErrorMessage = $null
    )

    $normalizedLocalPath = if ([string]::IsNullOrWhiteSpace($LocalPath)) { $null } else { $LocalPath }
    $normalizedError = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { $null } else { $ErrorMessage }

    if ($Copied) {
        if ($null -eq $normalizedLocalPath) {
            throw [System.ArgumentException]::new('A successfully copied log result requires LocalPath.')
        }

        if ($null -ne $normalizedError) {
            throw [System.ArgumentException]::new('A successfully copied log result cannot include Error.')
        }
    }
    else {
        if ($null -ne $normalizedLocalPath) {
            throw [System.ArgumentException]::new('A failed log copy result cannot include LocalPath.')
        }

        if ($null -eq $normalizedError) {
            throw [System.ArgumentException]::new('A failed log copy result requires Error.')
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName   = 'WinPush.LogResult'
        ComputerName = $ComputerName
        RemotePath   = $RemotePath
        LocalPath    = $normalizedLocalPath
        Copied       = $Copied
        Error        = $normalizedError
    }
}
