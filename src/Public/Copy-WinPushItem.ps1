<#
.SYNOPSIS
Copies one file to or from one Windows target through PSRP.

.DESCRIPTION
Creates a temporary PSSession and uploads one existing local file or downloads one remote file. Upload is the default direction. The command returns a structured result and always removes the temporary session.

.PARAMETER ComputerName
The single target computer. Arrays and target lists are not supported by this command.

.PARAMETER Path
For uploads, the existing local source file. For downloads, the remote source file.

.PARAMETER Destination
For uploads, the remote destination path. For downloads, a local filesystem destination whose parent directory already exists.

.PARAMETER Direction
The transfer direction. Valid values are Upload and Download. The default is Upload.

.PARAMETER Credential
An optional credential for PSRP session creation. The current Windows identity is used when omitted.

.EXAMPLE
Copy-WinPushItem -ComputerName PC01 -Path .\payload.txt -Destination C:\Windows\Temp\payload.txt

Uploads one local file to PC01.

.EXAMPLE
Copy-WinPushItem -ComputerName PC01 -Path C:\Windows\Temp\result.txt -Destination .\result.txt -Direction Download

Downloads one remote file from PC01.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
WinPush.ExecutionResult

.NOTES
Only PSRP, one target, and one file are supported. The command does not recurse or expand wildcard paths.

.LINK
docs/commands.md
#>
function Copy-WinPushItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [Parameter(Mandatory, Position = 2)]
        [string] $Destination,

        [ValidateSet('Upload', 'Download')]
        [string] $Direction = 'Upload',

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

        if ([string]::IsNullOrWhiteSpace($Destination)) {
            throw [System.ArgumentException]::new('Destination must not be empty.')
        }

        $metadataSource = $Path
        $metadataDestination = $Destination
        $metadataFileName = $null
        $metadataLength = $null

        if ($Direction -eq 'Upload') {
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

            $metadataSource = $pathItem.FullName
            $metadataFileName = $pathItem.Name
            $metadataLength = $pathItem.Length
        }
        else {
            if (Test-Path -LiteralPath $Destination) {
                $destinationItem = Get-Item -LiteralPath $Destination
                if ($destinationItem.PSProvider.Name -ne 'FileSystem') {
                    throw [System.ArgumentException]::new("Destination must refer to a local filesystem path: $Destination")
                }
            }
            else {
                $destinationParent = Split-Path -Path $Destination -Parent
                if ([string]::IsNullOrWhiteSpace($destinationParent)) {
                    $destinationParent = (Get-Location -PSProvider FileSystem).ProviderPath
                }

                if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                    throw [System.IO.DirectoryNotFoundException]::new("Destination parent directory was not found: $destinationParent")
                }

                $destinationParentItem = Get-Item -LiteralPath $destinationParent
                if ($destinationParentItem.PSProvider.Name -ne 'FileSystem') {
                    throw [System.ArgumentException]::new("Destination must refer to a local filesystem path: $Destination")
                }
            }
        }

        if ($ComputerName -is [array]) {
            throw [System.ArgumentException]::new('Copy-WinPushItem requires exactly one target.')
        }

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
        Copy-WinPushPsrpItem -Session $session -Path $metadataSource -Destination $Destination -Direction $Direction

        $metadata = [pscustomobject] [ordered] @{
            Direction   = $Direction
            Source      = $metadataSource
            Destination = $metadataDestination
            FileName    = $metadataFileName
            Length      = $metadataLength
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
        $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $sessionCreationStarted -and $null -eq $session -and $Direction -eq 'Upload') {
            'PSRP file upload session creation failed for the target with the supplied credential.'
        }
        elseif ($PSBoundParameters.ContainsKey('Credential') -and $sessionCreationStarted -and $null -eq $session -and $Direction -eq 'Download') {
            'PSRP file download session creation failed for the target with the supplied credential.'
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
