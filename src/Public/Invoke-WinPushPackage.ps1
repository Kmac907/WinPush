function Add-WinPushPackageCaptureOutputArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Result,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ArtifactIdentity
    )

    $artifact = Write-WinPushCommandOutputArtifact `
        -OutputRoot $OutputRoot `
        -ComputerName $Result.ComputerName `
        -Output $Result.Output `
        -Errors $Result.Errors `
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

    $Result
}

function Invoke-WinPushPackage {
    [CmdletBinding(DefaultParameterSetName = 'PathComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'PathComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'UriComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'PathHostFile')]
        [Parameter(Mandatory, ParameterSetName = 'UriHostFile')]
        [string] $HostFile,

        [Parameter(Mandatory, ParameterSetName = 'PathComputerName', Position = 1)]
        [Parameter(Mandatory, ParameterSetName = 'PathHostFile', Position = 1)]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'UriComputerName', Position = 1)]
        [Parameter(Mandatory, ParameterSetName = 'UriHostFile', Position = 1)]
        [uri] $Uri,

        [Parameter(Mandatory, Position = 2)]
        [string] $EntryPoint,

        [switch] $Extract,

        [switch] $CaptureOutput,

        [switch] $Logs,

        [ValidateSet('Never', 'OnSuccess', 'Always')]
        [string] $Cleanup = 'Never',

        [string] $OutputRoot = 'C:\WinPush',

        [string] $PackageCacheRoot = 'C:\WinPush\PackageCache',

        [string] $RemoteStageRoot = 'C:\ProgramData\WinPush\Staging',

        [System.Management.Automation.PSCredential] $Credential
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($EntryPoint)) {
            throw [System.ArgumentException]::new('EntryPoint must not be empty.')
        }

        Resolve-WinPushPackageEntryPoint -PackageRoot 'C:\WinPushPackageRoot' -EntryPoint $EntryPoint | Out-Null

        if (($CaptureOutput -or $Logs) -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
            throw [System.ArgumentException]::new('OutputRoot must not be empty.')
        }

        if ($PSBoundParameters.ContainsKey('PackageCacheRoot') -and [string]::IsNullOrWhiteSpace($PackageCacheRoot)) {
            throw [System.ArgumentException]::new('PackageCacheRoot must not be empty.')
        }

        if ($PSBoundParameters.ContainsKey('RemoteStageRoot') -and [string]::IsNullOrWhiteSpace($RemoteStageRoot)) {
            throw [System.ArgumentException]::new('RemoteStageRoot must not be empty.')
        }

        $computerNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'PathComputerName' -or $PSCmdlet.ParameterSetName -eq 'UriComputerName') {
            foreach ($target in @($ComputerName)) {
                $computerNames.Add($target)
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'PathHostFile' -or $PSCmdlet.ParameterSetName -eq 'UriHostFile') {
            throw [System.NotSupportedException]::new('HostFile package target input is not supported until roadmap item 11.11.')
        }

        if ($Logs) {
            throw [System.NotSupportedException]::new('Logs is not supported until roadmap item 11.9.')
        }

        if ($Cleanup -ne 'Never') {
            throw [System.NotSupportedException]::new('Cleanup policies other than Never are not supported until roadmap item 11.10.')
        }

        if ($PSCmdlet.ParameterSetName -eq 'UriComputerName') {
            $target = if ($computerNames.Count -eq 1) { $computerNames[0] } else { $null }
            $session = $null
            $cachePlan = $null
            $stagePlan = $null
            $localPackagePath = $null
            $remoteStagePath = $null
            $extracted = $false
            $executionStarted = $null
            $executionEnded = $null
            $sessionCreationStarted = $false

            try {
                $targets = @(Resolve-WinPushTarget -ComputerName $computerNames.ToArray())
                if ($targets.Count -ne 1) {
                    throw [System.ArgumentException]::new('Invoke-WinPushPackage currently supports exactly one target until roadmap item 11.11.')
                }

                $target = $targets[0]
                $cachePlan = New-WinPushPackageCachePlan -Uri $Uri -PackageCacheRoot $PackageCacheRoot
                if ($Extract -and [System.IO.Path]::GetExtension([string] $cachePlan.PackageFileName) -ne '.zip') {
                    throw [System.ArgumentException]::new('Extract requires a staged .zip package file.')
                }

                $localPackagePath = Save-WinPushPackageUriToCache -Uri $Uri -CachePlan $cachePlan
                $sessionParameters = @{
                    ComputerName = $target
                    ErrorAction  = 'Stop'
                }

                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $sessionParameters['Credential'] = $Credential
                }

                $sessionCreationStarted = $true
                $session = New-PSSession @sessionParameters
                $stagePlan = New-WinPushPackageStagePlan -RemoteStageRoot $RemoteStageRoot -PackagePath $localPackagePath
                Invoke-WinPushPsrpPackageStage -Session $session -LocalPackagePath $localPackagePath -StagePlan $stagePlan
                $remoteStagePath = $stagePlan.RemotePackagePath
                $packageRoot = $stagePlan.RemoteDirectory
                if ($Extract) {
                    Invoke-WinPushPsrpPackageExtract -Session $session -StagePlan $stagePlan
                    $remoteStagePath = $stagePlan.RemoteDirectory
                    $packageRoot = $stagePlan.RemoteDirectory
                    $extracted = $true
                }

                $executionStarted = [datetime]::UtcNow
                $packageExecution = Invoke-WinPushPsrpPackageEntryPoint -Session $session -PackageRoot $packageRoot -EntryPoint $EntryPoint
                $executionEnded = [datetime]::UtcNow
                $output = @($packageExecution.Output)
                $errors = @($packageExecution.Errors)
                $succeeded = $errors.Count -eq 0
                $exitCode = if ($succeeded) { 0 } else { 1 }
                $errorMessage = if ($errors.Count -gt 0) { [string] $errors[0] } else { $null }
                $metadata = New-WinPushPackageInfo `
                    -PackageSourceType Uri `
                    -PackageSource $Uri.OriginalString `
                    -LocalPackagePath $localPackagePath `
                    -RemoteStagePath $remoteStagePath `
                    -EntryPoint $EntryPoint `
                    -Extracted $extracted `
                    -ExecutionStarted $executionStarted `
                    -ExecutionEnded $executionEnded `
                    -CleanupPolicy $Cleanup

                $result = New-WinPushExecutionResult `
                    -ComputerName $target `
                    -Transport 'Psrp' `
                    -Operation 'RunPackage' `
                    -Succeeded $succeeded `
                    -ExitCode $exitCode `
                    -ErrorMessage $errorMessage `
                    -Output $output `
                    -Errors $errors `
                    -PackageMetadata $metadata

                if ($CaptureOutput) {
                    $result = Add-WinPushPackageCaptureOutputArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity ('Uri: {0}; EntryPoint: {1}' -f $Uri.OriginalString, $EntryPoint)
                }

                $result
            }
            catch {
                if ($null -ne $executionStarted -and $null -eq $executionEnded) {
                    $executionEnded = [datetime]::UtcNow
                }

                $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $sessionCreationStarted -and $null -eq $session) {
                    'PSRP package staging session creation failed for the target with the supplied credential.'
                }
                else {
                    $_.Exception.Message
                }

                $metadata = $null
                if ($null -ne $cachePlan) {
                    $metadataLocalPackagePath = if ([string]::IsNullOrWhiteSpace($localPackagePath)) { $cachePlan.LocalPackagePath } else { $localPackagePath }
                    $metadataRemoteStagePath = if ([string]::IsNullOrWhiteSpace($remoteStagePath)) {
                        if ($null -eq $stagePlan) { $null } else { $stagePlan.RemotePackagePath }
                    }
                    else {
                        $remoteStagePath
                    }
                    $metadata = New-WinPushPackageInfo `
                        -PackageSourceType Uri `
                        -PackageSource $Uri.OriginalString `
                        -LocalPackagePath $metadataLocalPackagePath `
                        -RemoteStagePath $metadataRemoteStagePath `
                        -EntryPoint $EntryPoint `
                        -Extracted $extracted `
                        -ExecutionStarted $executionStarted `
                        -ExecutionEnded $executionEnded `
                        -CleanupPolicy $Cleanup
                }

                $resultComputerName = if ([string]::IsNullOrWhiteSpace($target)) { [string] $ComputerName } else { $target }
                $result = New-WinPushExecutionResult `
                    -ComputerName $resultComputerName `
                    -Transport 'Psrp' `
                    -Operation 'RunPackage' `
                    -Succeeded $false `
                    -ExitCode 1 `
                    -ErrorMessage $errorMessage `
                    -Errors $errorMessage `
                    -PackageMetadata $metadata

                if ($CaptureOutput -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                    $result = Add-WinPushPackageCaptureOutputArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity ('Uri: {0}; EntryPoint: {1}' -f $Uri.OriginalString, $EntryPoint)
                }

                $result
            }
            finally {
                if ($null -ne $session) {
                    Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
                }
            }

            return
        }

        $target = if ($computerNames.Count -eq 1) { $computerNames[0] } else { $null }
        $session = $null
        $stagePlan = $null
        $resolvedPackagePath = $Path
        $packageIsDirectory = $false
        $remoteStagePath = $null
        $extracted = $false
        $executionStarted = $null
        $executionEnded = $null
        $sessionCreationStarted = $false

        try {
            if ([string]::IsNullOrWhiteSpace($Path)) {
                throw [System.ArgumentException]::new('Path must not be empty.')
            }

            if (-not (Test-Path -LiteralPath $Path)) {
                throw [System.IO.FileNotFoundException]::new("Package file was not found: $Path")
            }

            $packageItem = Get-Item -LiteralPath $Path
            if ($packageItem.PSProvider.Name -ne 'FileSystem') {
                throw [System.ArgumentException]::new("Path must refer to a local package file or directory: $Path")
            }

            $resolvedPackagePath = $packageItem.FullName
            $packageIsDirectory = [bool] $packageItem.PSIsContainer
            if ($Extract -and ($packageIsDirectory -or [System.IO.Path]::GetExtension($resolvedPackagePath) -ne '.zip')) {
                throw [System.ArgumentException]::new('Extract requires a staged .zip package file.')
            }

            $targets = @(Resolve-WinPushTarget -ComputerName $computerNames.ToArray())
            if ($targets.Count -ne 1) {
                throw [System.ArgumentException]::new('Invoke-WinPushPackage currently supports exactly one target until roadmap item 11.11.')
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
            $stagePlan = New-WinPushPackageStagePlan -RemoteStageRoot $RemoteStageRoot -PackagePath $resolvedPackagePath -Directory:$packageIsDirectory
            Invoke-WinPushPsrpPackageStage -Session $session -LocalPackagePath $resolvedPackagePath -StagePlan $stagePlan
            $remoteStagePath = $stagePlan.RemotePackagePath
            $packageRoot = $stagePlan.RemoteDirectory
            if ($Extract) {
                Invoke-WinPushPsrpPackageExtract -Session $session -StagePlan $stagePlan
                $remoteStagePath = $stagePlan.RemoteDirectory
                $packageRoot = $stagePlan.RemoteDirectory
                $extracted = $true
            }

            $executionStarted = [datetime]::UtcNow
            $packageExecution = Invoke-WinPushPsrpPackageEntryPoint -Session $session -PackageRoot $packageRoot -EntryPoint $EntryPoint
            $executionEnded = [datetime]::UtcNow
            $output = @($packageExecution.Output)
            $errors = @($packageExecution.Errors)
            $succeeded = $errors.Count -eq 0
            $exitCode = if ($succeeded) { 0 } else { 1 }
            $errorMessage = if ($errors.Count -gt 0) { [string] $errors[0] } else { $null }
            $metadata = New-WinPushPackageInfo `
                -PackageSourceType Path `
                -PackageSource $resolvedPackagePath `
                -LocalPackagePath $resolvedPackagePath `
                -RemoteStagePath $remoteStagePath `
                -EntryPoint $EntryPoint `
                -Extracted $extracted `
                -ExecutionStarted $executionStarted `
                -ExecutionEnded $executionEnded `
                -CleanupPolicy $Cleanup

            $result = New-WinPushExecutionResult `
                -ComputerName $target `
                -Transport 'Psrp' `
                -Operation 'RunPackage' `
                -Succeeded $succeeded `
                -ExitCode $exitCode `
                -ErrorMessage $errorMessage `
                -Output $output `
                -Errors $errors `
                -PackageMetadata $metadata

            if ($CaptureOutput) {
                $result = Add-WinPushPackageCaptureOutputArtifact `
                    -Result $result `
                    -OutputRoot $OutputRoot `
                    -ArtifactIdentity ('Path: {0}; EntryPoint: {1}' -f $resolvedPackagePath, $EntryPoint)
            }

            $result
        }
        catch {
            if ($null -ne $executionStarted -and $null -eq $executionEnded) {
                $executionEnded = [datetime]::UtcNow
            }

            $errorMessage = if ($PSBoundParameters.ContainsKey('Credential') -and $sessionCreationStarted -and $null -eq $session) {
                'PSRP package staging session creation failed for the target with the supplied credential.'
            }
            else {
                $_.Exception.Message
            }

            $metadata = $null
            if ($null -ne $stagePlan) {
                $metadataRemoteStagePath = if ([string]::IsNullOrWhiteSpace($remoteStagePath)) { $stagePlan.RemotePackagePath } else { $remoteStagePath }
                $metadata = New-WinPushPackageInfo `
                    -PackageSourceType Path `
                    -PackageSource $resolvedPackagePath `
                    -LocalPackagePath $resolvedPackagePath `
                    -RemoteStagePath $metadataRemoteStagePath `
                    -EntryPoint $EntryPoint `
                    -Extracted $extracted `
                    -ExecutionStarted $executionStarted `
                    -ExecutionEnded $executionEnded `
                    -CleanupPolicy $Cleanup
            }

            $resultComputerName = if ([string]::IsNullOrWhiteSpace($target)) { [string] $ComputerName } else { $target }
            $result = New-WinPushExecutionResult `
                -ComputerName $resultComputerName `
                -Transport 'Psrp' `
                -Operation 'RunPackage' `
                -Succeeded $false `
                -ExitCode 1 `
                -ErrorMessage $errorMessage `
                -Errors $errorMessage `
                -PackageMetadata $metadata

            if ($CaptureOutput -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                $result = Add-WinPushPackageCaptureOutputArtifact `
                    -Result $result `
                    -OutputRoot $OutputRoot `
                    -ArtifactIdentity ('Path: {0}; EntryPoint: {1}' -f $resolvedPackagePath, $EntryPoint)
            }

            $result
        }
        finally {
            if ($null -ne $session) {
                Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
            }
        }
    }
}
