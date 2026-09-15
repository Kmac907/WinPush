function Test-WinPushPackageAbsoluteWindowsPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Path
    )

    -not [string]::IsNullOrWhiteSpace($Path) -and
        -not $Path.Contains('/') -and
        $Path -notmatch '^\\\\[.?]\\' -and
        ($Path -match '^[A-Za-z]:\\' -or $Path -match '^\\\\[^\\]+\\[^\\]+(?:\\|$)')
}

function New-WinPushPackageStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemoteStageRoot,

        [Parameter(Mandatory)]
        [string] $PackagePath,

        [switch] $Directory
    )

    if (-not (Test-WinPushPackageAbsoluteWindowsPath -Path $RemoteStageRoot)) {
        throw [System.ArgumentException]::new('RemoteStageRoot must be an absolute drive-rooted or UNC Windows path.')
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
        StageDirectoryCreated = $false
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

    if ($Uri.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw [System.ArgumentException]::new('Uri must use HTTPS.')
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

function Resolve-WinPushPackageEntryPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageRoot,

        [Parameter(Mandatory)]
        [string] $EntryPoint
    )

    if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
        throw [System.ArgumentException]::new('PackageRoot must not be empty.')
    }

    if ([string]::IsNullOrWhiteSpace($EntryPoint)) {
        throw [System.ArgumentException]::new('EntryPoint must not be empty.')
    }

    $trimmedEntryPoint = $EntryPoint.Trim()
    if ([System.IO.Path]::IsPathRooted($trimmedEntryPoint)) {
        throw [System.ArgumentException]::new('EntryPoint must be relative to the staged package root.')
    }

    $segments = @($trimmedEntryPoint -split '[\\/]')
    $safeSegments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            throw [System.ArgumentException]::new('EntryPoint must not contain empty path segments.')
        }

        if ($segment -eq '..') {
            throw [System.ArgumentException]::new('EntryPoint must not contain parent traversal.')
        }

        if ($segment -eq '.') {
            continue
        }

        $safeSegments.Add($segment)
    }

    if ($safeSegments.Count -eq 0) {
        throw [System.ArgumentException]::new('EntryPoint must include a .ps1 file name.')
    }

    if ([System.IO.Path]::GetExtension($safeSegments[$safeSegments.Count - 1]) -ne '.ps1') {
        throw [System.ArgumentException]::new('EntryPoint must refer to a .ps1 file.')
    }

    $relativePath = $safeSegments.ToArray() -join '\'
    $normalizedPackageRoot = $PackageRoot.TrimEnd([char[]] @('\', '/'))
    $remotePath = '{0}\{1}' -f $normalizedPackageRoot, $relativePath

    [pscustomobject] [ordered] @{
        PSTypeName   = 'WinPush.PackageEntryPointPlan'
        PackageRoot  = $normalizedPackageRoot
        RelativePath = $relativePath
        RemotePath   = $remotePath
    }
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
    $StagePlan.StageDirectoryCreated = $true

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

function Invoke-WinPushPsrpPackageEntryPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $PackageRoot,

        [Parameter(Mandatory)]
        [string] $EntryPoint,

        [object[]] $ArgumentList = @()
    )

    $entryPointPlan = Resolve-WinPushPackageEntryPoint -PackageRoot $PackageRoot -EntryPoint $EntryPoint
    $remoteScriptBlock = {
        param(
            [Parameter(Mandatory)]
            [string] $WorkingDirectory,

            [Parameter(Mandatory)]
            [string] $EntryPointRelativePath,

            [object[]] $EntryPointArgumentList = @()
        )

        try {
            if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
                throw [System.IO.DirectoryNotFoundException]::new("Package root was not found: $WorkingDirectory")
            }

            Set-Location -LiteralPath $WorkingDirectory -ErrorAction Stop
            $entryPointPath = Join-Path -Path $WorkingDirectory -ChildPath $EntryPointRelativePath
            if (-not (Test-Path -LiteralPath $entryPointPath -PathType Leaf)) {
                throw [System.IO.FileNotFoundException]::new("Package entry point was not found: $entryPointPath")
            }

            & $entryPointPath @EntryPointArgumentList 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    [pscustomobject] [ordered] @{
                        Stream = 'Error'
                        Value  = [string] $_
                    }
                }
                else {
                    [pscustomobject] [ordered] @{
                        Stream = 'Output'
                        Value  = $_
                    }
                }
            }
        }
        catch {
            [pscustomobject] [ordered] @{
                Stream = 'Error'
                Value  = [string] $_
            }
        }
    }

    [object[]] $invokeArguments = $entryPointPlan.PackageRoot, $entryPointPlan.RelativePath, $null
    $invokeArguments[2] = $ArgumentList
    $streamItems = @(Invoke-Command `
            -Session $Session `
            -ScriptBlock $remoteScriptBlock `
            -ArgumentList $invokeArguments `
            -ErrorAction Stop)

    $output = foreach ($item in $streamItems) {
        if ($item.Stream -eq 'Output') {
            $item.Value
        }
    }

    $errors = foreach ($item in $streamItems) {
        if ($item.Stream -eq 'Error') {
            $item.Value
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsrpPackageEntryPointResult'
        Output     = @($output)
        Errors     = @($errors)
    }
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

function Remove-WinPushPsrpPackageStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [object] $StagePlan,

        [Parameter(Mandatory)]
        [string] $RemoteStageRoot
    )

    if (-not (Test-WinPushPackageAbsoluteWindowsPath -Path $RemoteStageRoot)) {
        throw [System.ArgumentException]::new('RemoteStageRoot must be an absolute drive-rooted or UNC Windows path.')
    }

    $remoteDirectory = [string] $StagePlan.RemoteDirectory
    if ([string]::IsNullOrWhiteSpace($remoteDirectory)) {
        throw [System.ArgumentException]::new('Package cleanup path must not be empty.')
    }

    $canonicalStageRoot = [System.IO.Path]::GetFullPath(('{0}\' -f $RemoteStageRoot.TrimEnd('\')))
    $canonicalRemoteDirectory = [System.IO.Path]::GetFullPath($remoteDirectory)
    if (-not $canonicalRemoteDirectory.StartsWith($canonicalStageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.InvalidOperationException]::new('Package cleanup path must stay under RemoteStageRoot.')
    }

    $stageLeaf = Split-Path -Path $canonicalRemoteDirectory -Leaf
    if (-not $stageLeaf.StartsWith('package-', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.InvalidOperationException]::new('Package cleanup path must reference a WinPush package stage directory.')
    }

    $null = Invoke-Command `
        -Session $Session `
        -ScriptBlock {
            $cleanupDirectory = [string] $args[0]
            $canonicalAllowedRoot = [System.IO.Path]::GetFullPath(('{0}\' -f ([string] $args[1]).TrimEnd('\')))
            $canonicalCleanupDirectory = [System.IO.Path]::GetFullPath($cleanupDirectory)
            if (-not $canonicalCleanupDirectory.StartsWith($canonicalAllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw [System.InvalidOperationException]::new('Package cleanup path must stay under RemoteStageRoot.')
            }

            Set-Location -LiteralPath ([System.IO.Path]::GetTempPath()) -ErrorAction Stop
            Remove-Item -LiteralPath $canonicalCleanupDirectory -Recurse -Force -ErrorAction Stop
        } `
        -ArgumentList $canonicalRemoteDirectory, $canonicalStageRoot `
        -ErrorAction Stop
}
