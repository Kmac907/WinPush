function New-WinPushPackageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Path', 'Uri')]
        [string] $PackageSourceType,

        [Parameter(Mandatory)]
        [string] $PackageSource,

        [AllowNull()]
        [string] $LocalPackagePath = $null,

        [AllowNull()]
        [string] $RemoteStagePath = $null,

        [Parameter(Mandatory)]
        [string] $EntryPoint,

        [bool] $Extracted = $false,

        [AllowNull()]
        [Nullable[datetime]] $ExecutionStarted = $null,

        [AllowNull()]
        [Nullable[datetime]] $ExecutionEnded = $null,

        [ValidateSet('Never', 'OnSuccess', 'Always')]
        [string] $CleanupPolicy = 'Never',

        [AllowNull()]
        [Nullable[bool]] $CleanupSucceeded = $null,

        [bool] $LogsCopied = $false,

        [AllowNull()]
        [object[]] $CopiedLogPaths = @()
    )

    [object[]] $normalizedCopiedLogPaths = @()
    if ($null -ne $CopiedLogPaths) {
        $normalizedCopiedLogPaths = @($CopiedLogPaths)
    }

    $normalizedLocalPackagePath = if ([string]::IsNullOrWhiteSpace($LocalPackagePath)) { $null } else { $LocalPackagePath }
    $normalizedRemoteStagePath = if ([string]::IsNullOrWhiteSpace($RemoteStagePath)) { $null } else { $RemoteStagePath }

    [pscustomobject] [ordered] @{
        PSTypeName        = 'WinPush.PackageMetadata'
        PackageSourceType = $PackageSourceType
        PackageSource     = $PackageSource
        LocalPackagePath  = $normalizedLocalPackagePath
        RemoteStagePath   = $normalizedRemoteStagePath
        EntryPoint        = $EntryPoint
        Extracted         = $Extracted
        ExecutionStarted  = $ExecutionStarted
        ExecutionEnded    = $ExecutionEnded
        CleanupPolicy     = $CleanupPolicy
        CleanupSucceeded  = $CleanupSucceeded
        LogsCopied        = $LogsCopied
        CopiedLogPaths    = $normalizedCopiedLogPaths
    }
}
