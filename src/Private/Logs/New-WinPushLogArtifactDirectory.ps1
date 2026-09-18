function New-WinPushArtifactRunDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot
    )

    $runName = '{0}-{1}' -f (Get-Date -Format 'dd-MM-yyyy-HHmmss'), ([guid]::NewGuid().ToString('N'))
    $runDirectory = Join-Path -Path $OutputRoot -ChildPath $runName
    [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
    $runDirectory
}

function ConvertTo-WinPushArtifactTargetName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    $invalidNamePattern = '[\x00-\x1f<>:"/\\|?*]'
    $reservedNamePattern = '^(?i:con|prn|aux|nul|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3])(?:\.|$)'
    $isUnsafe = $ComputerName -match $invalidNamePattern -or
        $ComputerName -match '[ .]$' -or
        $ComputerName -eq '.' -or
        $ComputerName -eq '..' -or
        $ComputerName -match $reservedNamePattern

    if (-not $isUnsafe -and $ComputerName.Length -le 255) {
        return $ComputerName
    }

    $stem = ([regex]::Replace($ComputerName, $invalidNamePattern, '_')).TrimEnd([char[]] @(' ', '.'))
    if ($ComputerName -match $reservedNamePattern) {
        $stem = $stem.Replace('.', '_')
    }
    if ([string]::IsNullOrWhiteSpace($stem) -or $stem -eq '.' -or $stem -eq '..') {
        $stem = 'target'
    }
    elseif ($stem.Length -gt 246) {
        $stem = $stem.Substring(0, 246)
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [System.BitConverter]::ToString(
            $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ComputerName))
        ).Replace('-', '').Substring(0, 8).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }

    '{0}-{1}' -f $stem, $hash
}

function New-WinPushLogArtifactDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [AllowNull()]
        [string] $RunDirectory = $null,

        [AllowNull()]
        [string] $ComputerDirectory = $null
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        throw [System.ArgumentException]::new('OutputRoot must not be empty.')
    }

    $runDirectory = $RunDirectory
    $computerDirectory = $ComputerDirectory

    if ([string]::IsNullOrWhiteSpace($computerDirectory)) {
        if ([string]::IsNullOrWhiteSpace($runDirectory)) {
            $runDirectory = New-WinPushArtifactRunDirectory -OutputRoot $OutputRoot
        }

        $targetName = ConvertTo-WinPushArtifactTargetName -ComputerName $ComputerName
        $computerDirectory = Join-Path -Path $runDirectory -ChildPath $targetName
    }
    elseif ([string]::IsNullOrWhiteSpace($runDirectory)) {
        $runDirectory = Split-Path -Path $computerDirectory -Parent
    }

    $logDirectory = Join-Path -Path $computerDirectory -ChildPath 'Logs'
    $null = New-Item -Path $logDirectory -ItemType Directory -Force

    [pscustomobject] [ordered] @{
        RunDirectory      = $runDirectory
        ComputerDirectory = $computerDirectory
        LogDirectory      = $logDirectory
    }
}
