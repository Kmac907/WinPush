function Add-WinPushExecutionArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Result,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ArtifactIdentity,

        [AllowNull()]
        [string] $RunDirectory = $null
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Result.RunDirectory)) {
            $Result.RunDirectory = $RunDirectory
        }

        $artifact = Write-WinPushCommandOutputArtifact `
            -OutputRoot $OutputRoot `
            -ComputerName $Result.ComputerName `
            -Output $Result.Output `
            -Errors $Result.Errors `
            -RunDirectory $Result.RunDirectory `
            -Operation $Result.Operation `
            -Transport $Result.Transport `
            -ArtifactIdentity $ArtifactIdentity `
            -Succeeded $Result.Succeeded `
            -ExitCode $Result.ExitCode `
            -ErrorMessage $Result.ErrorMessage

        $Result.RunDirectory = $artifact.RunDirectory
        $Result.ComputerDirectory = $artifact.ComputerDirectory
        $Result.ResultPath = $artifact.ResultPath
        $Result.StdOutPath = $artifact.StdOutPath
        $Result.StdErrPath = $artifact.StdErrPath
    }
    catch {
        $Result.ArtifactError = if ([string]::IsNullOrWhiteSpace($Result.ArtifactError)) {
            $_.Exception.Message
        }
        else {
            '{0}; {1}' -f $Result.ArtifactError, $_.Exception.Message
        }
        $Result.ComputerDirectory = $null
        $Result.ResultPath = $null
        $Result.StdOutPath = $null
        $Result.StdErrPath = $null
    }

    $Result
}

function Add-WinPushExecutionLogArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Result,

        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $RemoteLogDirectory
    )

    try {
        $logCopy = Copy-WinPushPsrpLogDirectory `
            -Session $Session `
            -ComputerName $Result.ComputerName `
            -RemoteDirectory $RemoteLogDirectory `
            -OutputRoot $OutputRoot `
            -RunDirectory $Result.RunDirectory `
            -ComputerDirectory $Result.ComputerDirectory

        $Result.RunDirectory = $logCopy.RunDirectory
        $Result.ComputerDirectory = $logCopy.ComputerDirectory
        $Result.Logs = @($logCopy.Logs)
        $Result.CopiedLogPaths = @($logCopy.CopiedLogPaths)
    }
    catch {
        $Result.ArtifactError = if ([string]::IsNullOrWhiteSpace($Result.ArtifactError)) {
            $_.Exception.Message
        }
        else {
            '{0}; {1}' -f $Result.ArtifactError, $_.Exception.Message
        }
        $Result.Logs = @(
            New-WinPushLogResult `
                -ComputerName $Result.ComputerName `
                -RemotePath $RemoteLogDirectory `
                -Copied $false `
                -ErrorMessage $_.Exception.Message
        )
        $Result.CopiedLogPaths = @()
    }

    if ($null -ne $Result.PackageMetadata) {
        $Result.PackageMetadata.LogsCopied = $Result.CopiedLogPaths.Count -gt 0
        $Result.PackageMetadata.CopiedLogPaths = @($Result.CopiedLogPaths)
    }

    $Result
}
