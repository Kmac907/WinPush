function New-WinPushPackageStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemoteStageRoot,

        [Parameter(Mandatory)]
        [string] $PackagePath,

        [switch] $Directory
    )

    if ([string]::IsNullOrWhiteSpace($RemoteStageRoot)) {
        throw [System.ArgumentException]::new('RemoteStageRoot must not be empty.')
    }

    $fileName = Split-Path -Path $PackagePath -Leaf
    $stageId = 'package-{0}-{1}' -f ([datetime]::UtcNow.ToString('yyyyMMddHHmmssfff')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $trimmedStageRoot = $RemoteStageRoot.TrimEnd('\')
    $remoteDirectory = '{0}\{1}' -f $trimmedStageRoot, $stageId
    $remotePackagePath = if ($Directory) { $remoteDirectory } else { '{0}\{1}' -f $remoteDirectory, $fileName }

    [pscustomobject] [ordered] @{
        PSTypeName         = 'WinPush.PackageStagePlan'
        StageId            = $stageId
        RemoteDirectory    = $remoteDirectory
        RemotePackagePath  = $remotePackagePath
        PackageFileName    = $fileName
        IsDirectory        = [bool] $Directory
    }
}

function New-WinPushPackageCachePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri] $Uri,

        [Parameter(Mandatory)]
        [string] $PackageCacheRoot
    )

    if (-not $Uri.IsAbsoluteUri) {
        throw [System.ArgumentException]::new('Uri must be an absolute package URI.')
    }

    if ([string]::IsNullOrWhiteSpace($PackageCacheRoot)) {
        throw [System.ArgumentException]::new('PackageCacheRoot must not be empty.')
    }

    $fileName = [System.IO.Path]::GetFileName($Uri.AbsolutePath)
    $fileName = [System.Uri]::UnescapeDataString($fileName)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'package'
    }

    $invalidFileNamePattern = '[{0}]' -f ([regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars())))
    $safeFileName = [regex]::Replace($fileName, $invalidFileNamePattern, '_')
    $cacheId = '{0}-{1}' -f ([datetime]::UtcNow.ToString('yyyyMMddHHmmssfff')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $trimmedCacheRoot = $PackageCacheRoot.TrimEnd('\')
    $cacheDirectory = '{0}\{1}' -f $trimmedCacheRoot, $cacheId
    $localPackagePath = '{0}\{1}' -f $cacheDirectory, $safeFileName

    [pscustomobject] [ordered] @{
        PSTypeName        = 'WinPush.PackageCachePlan'
        CacheId           = $cacheId
        CacheDirectory    = $cacheDirectory
        LocalPackagePath  = $localPackagePath
        PackageFileName   = $safeFileName
        PackageSource     = $Uri.OriginalString
    }
}

function Save-WinPushPackageUriToCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri] $Uri,

        [Parameter(Mandatory)]
        [object] $CachePlan
    )

    [System.IO.Directory]::CreateDirectory([string] $CachePlan.CacheDirectory) | Out-Null
    Invoke-WebRequest `
        -Uri $Uri `
        -OutFile ([string] $CachePlan.LocalPackagePath) `
        -ErrorAction Stop | Out-Null

    [string] $CachePlan.LocalPackagePath
}

function Invoke-WinPushPsrpPackageStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $LocalPackagePath,

        [Parameter(Mandatory)]
        [object] $StagePlan
    )

    $null = Invoke-Command `
        -Session $Session `
        -ScriptBlock {
            [System.IO.Directory]::CreateDirectory([string] $args[0]) | Out-Null
        } `
        -ArgumentList $StagePlan.RemoteDirectory `
        -ErrorAction Stop

    if ($StagePlan.IsDirectory) {
        $localPackageRoot = (Get-Item -LiteralPath $LocalPackagePath -ErrorAction Stop).FullName
        $localDirectories = @(
            Get-ChildItem -LiteralPath $localPackageRoot -Directory -Recurse -Force |
                Sort-Object -Property FullName
        )

        foreach ($localDirectory in $localDirectories) {
            $relativePath = [System.IO.Path]::GetRelativePath($localPackageRoot, $localDirectory.FullName).Replace('/', '\')
            $remoteDirectory = '{0}\{1}' -f $StagePlan.RemoteDirectory, $relativePath
            $null = Invoke-Command `
                -Session $Session `
                -ScriptBlock {
                    [System.IO.Directory]::CreateDirectory([string] $args[0]) | Out-Null
                } `
                -ArgumentList $remoteDirectory `
                -ErrorAction Stop
        }

        $localFiles = @(
            Get-ChildItem -LiteralPath $localPackageRoot -File -Recurse -Force |
                Sort-Object -Property FullName
        )

        foreach ($localFile in $localFiles) {
            $relativePath = [System.IO.Path]::GetRelativePath($localPackageRoot, $localFile.FullName).Replace('/', '\')
            $remotePath = '{0}\{1}' -f $StagePlan.RemoteDirectory, $relativePath
            Copy-WinPushPsrpItem `
                -Session $Session `
                -Path $localFile.FullName `
                -Destination $remotePath `
                -Direction Upload
        }

        return
    }

    Copy-WinPushPsrpItem `
        -Session $Session `
        -Path $LocalPackagePath `
        -Destination $StagePlan.RemotePackagePath `
        -Direction Upload
}

function Invoke-WinPushPsrpPackageExtract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [object] $StagePlan
    )

    if ($StagePlan.IsDirectory -or [System.IO.Path]::GetExtension([string] $StagePlan.PackageFileName) -ne '.zip') {
        throw [System.ArgumentException]::new('Extract requires a staged .zip package file.')
    }

    $null = Invoke-Command `
        -Session $Session `
        -ScriptBlock {
            $archivePath = [string] $args[0]
            $destinationPath = [string] $args[1]

            if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
                throw [System.IO.FileNotFoundException]::new("Staged zip package was not found: $archivePath")
            }

            [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null
            Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force -ErrorAction Stop
        } `
        -ArgumentList $StagePlan.RemotePackagePath, $StagePlan.RemoteDirectory `
        -ErrorAction Stop
}
