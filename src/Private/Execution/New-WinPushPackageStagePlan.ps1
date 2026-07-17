function New-WinPushPackageStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemoteStageRoot,

        [Parameter(Mandatory)]
        [string] $PackagePath
    )

    if ([string]::IsNullOrWhiteSpace($RemoteStageRoot)) {
        throw [System.ArgumentException]::new('RemoteStageRoot must not be empty.')
    }

    $fileName = Split-Path -Path $PackagePath -Leaf
    $stageId = 'package-{0}-{1}' -f ([datetime]::UtcNow.ToString('yyyyMMddHHmmssfff')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $trimmedStageRoot = $RemoteStageRoot.TrimEnd('\')
    $remoteDirectory = '{0}\{1}' -f $trimmedStageRoot, $stageId
    $remotePackagePath = '{0}\{1}' -f $remoteDirectory, $fileName

    [pscustomobject] [ordered] @{
        PSTypeName         = 'WinPush.PackageStagePlan'
        StageId            = $stageId
        RemoteDirectory    = $remoteDirectory
        RemotePackagePath  = $remotePackagePath
        PackageFileName    = $fileName
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

    Copy-WinPushPsrpItem `
        -Session $Session `
        -Path $LocalPackagePath `
        -Destination $StagePlan.RemotePackagePath `
        -Direction Upload
}
