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
