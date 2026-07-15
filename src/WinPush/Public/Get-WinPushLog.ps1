function Test-WinPushAbsoluteWindowsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return ($Path -match '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\[^\\\/]+[\\\/][^\\\/]+([\\\/].*)?$')
}

function New-WinPushLogArtifactDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        throw [System.ArgumentException]::new('OutputRoot must not be empty.')
    }

    $runName = Get-Date -Format 'dd-MM-yyyy-HHmmss'
    $runDirectory = Join-Path -Path $OutputRoot -ChildPath $runName
    $suffix = 1

    while (Test-Path -LiteralPath $runDirectory) {
        $runDirectory = Join-Path -Path $OutputRoot -ChildPath ('{0}-{1}' -f $runName, $suffix)
        $suffix++
    }

    $computerDirectory = Join-Path -Path $runDirectory -ChildPath $ComputerName
    $logDirectory = Join-Path -Path $computerDirectory -ChildPath 'Logs'
    $null = New-Item -Path $logDirectory -ItemType Directory -Force

    [pscustomobject] [ordered] @{
        RunDirectory      = $runDirectory
        ComputerDirectory = $computerDirectory
        LogDirectory      = $logDirectory
    }
}

function Get-WinPushLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $RemoteDirectory,

        [string] $OutputRoot = 'C:\WinPush',

        [System.Management.Automation.PSCredential] $Credential
    )

    $target = if ($ComputerName -is [array]) {
        [string]::Join(',', @($ComputerName))
    }
    elseif ([string]::IsNullOrWhiteSpace([string] $ComputerName)) {
        [string] $ComputerName
    }
    else {
        ([string] $ComputerName).Trim()
    }
    $session = $null
    $sessionCreationStarted = $false

    try {
        if ([string]::IsNullOrWhiteSpace($RemoteDirectory)) {
            throw [System.ArgumentException]::new('RemoteDirectory must not be empty.')
        }

        if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
            throw [System.ArgumentException]::new('OutputRoot must not be empty.')
        }

        if (-not (Test-WinPushAbsoluteWindowsPath -Path $RemoteDirectory)) {
            throw [System.ArgumentException]::new('RemoteDirectory must be an absolute Windows path.')
        }

        if ($ComputerName -is [array]) {
            throw [System.ArgumentException]::new('Get-WinPushLog requires exactly one target.')
        }

        $targets = @(Resolve-WinPushTarget -ComputerName ([string] $ComputerName))
        if ($targets.Count -ne 1) {
            throw [System.ArgumentException]::new('Get-WinPushLog requires exactly one target.')
        }

        $target = $targets[0]
        $sessionParameters = @{
            ComputerName = $target
            ErrorAction  = 'Stop'
        }

        if ($PSBoundParameters.ContainsKey('Credential')) {
            $sessionParameters['Credential'] = $Credential
        }

        $sessionCreationStarted = $true
        $session = New-PSSession @sessionParameters
        $fileMetadata = @(Get-WinPushPsrpLogFileInfo -Session $session -RemoteDirectory $RemoteDirectory)
        $artifactDirectory = New-WinPushLogArtifactDirectory -OutputRoot $OutputRoot -ComputerName $target
        $logResults = @()

        foreach ($file in $fileMetadata) {
            $localPath = Join-Path -Path $artifactDirectory.LogDirectory -ChildPath $file.Name

            try {
                Copy-WinPushPsrpItem `
                    -Session $session `
                    -Path $file.RemotePath `
                    -Destination $localPath `
                    -Direction Download

                $logResults += New-WinPushLogResult `
                    -ComputerName $target `
                    -RemotePath $file.RemotePath `
                    -LocalPath $localPath `
                    -Copied $true
            }
            catch {
                $logResults += New-WinPushLogResult `
                    -ComputerName $target `
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
        $succeeded = ($copyErrors.Count -eq 0)
        $errorMessage = if ($succeeded) { $null } else { 'One or more log files failed to copy.' }
        $exitCode = if ($succeeded) { 0 } else { 1 }

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'GetLogs' `
            -Succeeded $succeeded `
            -ExitCode $exitCode `
            -ErrorMessage $errorMessage `
            -Output $fileMetadata `
            -Errors $copyErrors `
            -Logs $logResults `
            -RunDirectory $artifactDirectory.RunDirectory `
            -ComputerDirectory $artifactDirectory.ComputerDirectory `
            -CopiedLogPaths $copiedLogPaths
    }
    catch {
        $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $sessionCreationStarted -and $null -eq $session) {
            'PSRP log retrieval session creation failed for the target with the supplied credential.'
        }
        else {
            $_.Exception.Message
        }

        $resultComputerName = if ([string]::IsNullOrEmpty($target)) { [string] $ComputerName } else { $target }

        New-WinPushExecutionResult `
            -ComputerName $resultComputerName `
            -Transport 'Psrp' `
            -Operation 'GetLogs' `
            -Succeeded $false `
            -ExitCode 1 `
            -ErrorMessage $errorMessage `
            -Errors $errorMessage
    }
    finally {
        if ($null -ne $session) {
            Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
        }
    }
}
