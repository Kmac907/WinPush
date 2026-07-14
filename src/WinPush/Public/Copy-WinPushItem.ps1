function Copy-WinPushItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [Parameter(Mandatory, Position = 2)]
        [string] $Destination,

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
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw [System.ArgumentException]::new('Path must not be empty.')
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            throw [System.IO.FileNotFoundException]::new("File was not found: $Path")
        }

        $pathItem = Get-Item -LiteralPath $Path
        if ($pathItem.PSProvider.Name -ne 'FileSystem') {
            throw [System.ArgumentException]::new("Path must refer to a local file: $Path")
        }

        if ($pathItem.PSIsContainer) {
            throw [System.ArgumentException]::new("Path must refer to a file: $Path")
        }

        if ([string]::IsNullOrWhiteSpace($Destination)) {
            throw [System.ArgumentException]::new('Destination must not be empty.')
        }

        if ($ComputerName -is [array]) {
            throw [System.ArgumentException]::new('Copy-WinPushItem requires exactly one target.')
        }

        $resolvedPath = $pathItem.FullName
        $targets = @(Resolve-WinPushTarget -ComputerName ([string] $ComputerName))
        if ($targets.Count -ne 1) {
            throw [System.ArgumentException]::new('Copy-WinPushItem requires exactly one target.')
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
        Copy-WinPushPsrpItem -Session $session -Path $resolvedPath -Destination $Destination

        $metadata = [pscustomobject] [ordered] @{
            Direction   = 'Upload'
            Source      = $resolvedPath
            Destination = $Destination
            FileName    = $pathItem.Name
            Length      = $pathItem.Length
        }

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'CopyFile' `
            -Succeeded $true `
            -ExitCode 0 `
            -Output $metadata
    }
    catch {
        $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $sessionCreationStarted -and $null -eq $session) {
            'PSRP file upload session creation failed for the target with the supplied credential.'
        }
        else {
            $_.Exception.Message
        }

        $resultComputerName = if ([string]::IsNullOrEmpty($target)) { [string] $ComputerName } else { $target }

        New-WinPushExecutionResult `
            -ComputerName $resultComputerName `
            -Transport 'Psrp' `
            -Operation 'CopyFile' `
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
