function Test-WinPushAbsoluteWindowsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return ($Path -match '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\[^\\\/]+[\\\/][^\\\/]+([\\\/].*)?$')
}

function Get-WinPushLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $RemoteDirectory,

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

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'GetLogs' `
            -Succeeded $true `
            -ExitCode 0 `
            -Output $fileMetadata
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
