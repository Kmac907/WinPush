function Copy-WinPushPsrpLogDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemoteDirectory,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [AllowNull()]
        [string] $RunDirectory = $null,

        [AllowNull()]
        [string] $ComputerDirectory = $null
    )

    $fileMetadata = @(Get-WinPushPsrpLogFileInfo -Session $Session -RemoteDirectory $RemoteDirectory)
    $artifactDirectory = New-WinPushLogArtifactDirectory `
        -OutputRoot $OutputRoot `
        -ComputerName $ComputerName `
        -RunDirectory $RunDirectory `
        -ComputerDirectory $ComputerDirectory
    $logResults = @()
    $activeCaptureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
        Get-WinPushActiveCaptureContext
    }

    foreach ($file in $fileMetadata) {
        $localPath = Join-Path -Path $artifactDirectory.LogDirectory -ChildPath $file.Name

        try {
            Copy-WinPushPsrpItem `
                -Session $Session `
                -Path $file.RemotePath `
                -Destination $localPath `
                -Direction Download

            $logResults += New-WinPushLogResult `
                -ComputerName $ComputerName `
                -RemotePath $file.RemotePath `
                -LocalPath $localPath `
                -Copied $true

            if ($null -ne $activeCaptureContext) {
                Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Log -Value $localPath
            }
        }
        catch {
            $logResults += New-WinPushLogResult `
                -ComputerName $ComputerName `
                -RemotePath $file.RemotePath `
                -Copied $false `
                -ErrorMessage $_.Exception.Message
        }
    }

    $copyErrors = @(
        $logResults |
            Where-Object { -not $_.Copied } |
            ForEach-Object { $_.Error }
    )
    $copiedLogPaths = @(
        $logResults |
            Where-Object { $_.Copied } |
            ForEach-Object { $_.LocalPath }
    )

    [pscustomobject] [ordered] @{
        FileMetadata      = $fileMetadata
        Logs              = $logResults
        Errors            = $copyErrors
        CopiedLogPaths    = $copiedLogPaths
        RunDirectory      = $artifactDirectory.RunDirectory
        ComputerDirectory = $artifactDirectory.ComputerDirectory
        LogDirectory      = $artifactDirectory.LogDirectory
    }
}
