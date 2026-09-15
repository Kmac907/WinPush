function Set-WinPushPackageCleanupResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Result,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Session,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $StagePlan,

        [Parameter(Mandatory)]
        [string] $RemoteStageRoot,

        [Parameter(Mandatory)]
        [ValidateSet('Never', 'OnSuccess', 'Always')]
        [string] $Cleanup
    )

    if ($null -eq $Result.PackageMetadata) {
        return $Result
    }

    $Result.PackageMetadata.CleanupPolicy = $Cleanup
    if ($Cleanup -eq 'Never') {
        return $Result
    }

    $shouldCleanup = $Cleanup -eq 'Always' -or ($Cleanup -eq 'OnSuccess' -and $Result.Succeeded)
    if (-not $shouldCleanup -or $null -eq $Session -or $null -eq $StagePlan) {
        return $Result
    }

    if (-not [bool] $StagePlan.StageDirectoryCreated) {
        return $Result
    }

    try {
        Remove-WinPushPsrpPackageStage `
            -Session $Session `
            -StagePlan $StagePlan `
            -RemoteStageRoot $RemoteStageRoot

        $Result.PackageMetadata.CleanupSucceeded = $true
    }
    catch {
        $Result.PackageMetadata.CleanupSucceeded = $false
    }

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

        $remoteLogDirectory = if ($Logs) { Get-WinPushScriptLogDirectory -ScriptPath $EntryPoint } else { $null }
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
        $isHostFileTargetSet = $PSCmdlet.ParameterSetName.EndsWith('HostFile', [System.StringComparison]::Ordinal)
        $isUriPackageSet = $PSCmdlet.ParameterSetName.StartsWith('Uri', [System.StringComparison]::Ordinal)
        $sharedRunDirectory = $null
        $artifactError = $null
        $captureOutputEnabled = [bool] $CaptureOutput
        $logsEnabled = [bool] $Logs
        if ($CaptureOutput -or $Logs) {
            try {
                $sharedRunDirectory = New-WinPushArtifactRunDirectory -OutputRoot $OutputRoot
            }
            catch {
                $artifactError = $_.Exception.Message
                $captureOutputEnabled = $false
                $logsEnabled = $false
            }
        }

        if ($isUriPackageSet) {
            $targets = @()
            $cachePlan = $null
            $localPackagePath = $null

            try {
                $targets = @(
                    if ($isHostFileTargetSet) {
                        Resolve-WinPushTarget -HostFile $HostFile
                    }
                    else {
                        Resolve-WinPushTarget -ComputerName $computerNames.ToArray()
                    }
                )
                $cachePlan = New-WinPushPackageCachePlan -Uri $Uri -PackageCacheRoot $PackageCacheRoot
                if ($Extract -and [System.IO.Path]::GetExtension([string] $cachePlan.PackageFileName) -ne '.zip') {
                    throw [System.ArgumentException]::new('Extract requires a staged .zip package file.')
                }

                $localPackagePath = Save-WinPushPackageUriToCache -Uri $Uri -CachePlan $cachePlan
            }
            catch {
                $failureTargets = if ($targets.Count -gt 0) {
                    @($targets)
                }
                elseif ($computerNames.Count -gt 0) {
                    @([string] $computerNames[0])
                }
                elseif ($isHostFileTargetSet -and -not [string]::IsNullOrWhiteSpace($HostFile)) {
                    @($HostFile)
                }
                else {
                    @('Unknown')
                }
                foreach ($failureTarget in $failureTargets) {
                    $metadata = $null
                    if ($null -ne $cachePlan) {
                        $metadata = New-WinPushPackageInfo `
                            -PackageSourceType Uri `
                            -PackageSource $Uri.OriginalString `
                            -LocalPackagePath $cachePlan.LocalPackagePath `
                            -EntryPoint $EntryPoint `
                            -CleanupPolicy $Cleanup
                    }

                    $result = New-WinPushExecutionResult `
                        -ComputerName $failureTarget `
                        -Transport 'Psrp' `
                        -Operation 'RunPackage' `
                        -Succeeded $false `
                        -ExitCode 1 `
                        -ErrorMessage $_.Exception.Message `
                        -ArtifactError $artifactError `
                        -Errors $_.Exception.Message `
                        -RunDirectory $sharedRunDirectory `
                        -PackageMetadata $metadata

                    if ($captureOutputEnabled -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionArtifact `
                            -Result $result `
                            -OutputRoot $OutputRoot `
                            -ArtifactIdentity ('Uri: {0}; EntryPoint: {1}' -f $Uri.OriginalString, $EntryPoint) `
                            -RunDirectory $sharedRunDirectory
                        if ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $captureOutputEnabled = $false
                        }
                    }

                    if (-not [string]::IsNullOrWhiteSpace($result.RunDirectory)) {
                        $sharedRunDirectory = $result.RunDirectory
                    }

                    $result
                }

                return
            }

            foreach ($target in $targets) {
                $session = $null
                $stagePlan = $null
                $remoteStagePath = $null
                $extracted = $false
                $executionStarted = $null
                $executionEnded = $null
                $sessionCreationStarted = $false

                try {
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
                        -ArtifactError $artifactError `
                        -Output $output `
                        -Errors $errors `
                        -RunDirectory $sharedRunDirectory `
                        -PackageMetadata $metadata

                    if ($captureOutputEnabled) {
                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionArtifact `
                            -Result $result `
                            -OutputRoot $OutputRoot `
                            -ArtifactIdentity ('Uri: {0}; EntryPoint: {1}' -f $Uri.OriginalString, $EntryPoint) `
                            -RunDirectory $sharedRunDirectory
                        $sharedRunDirectory = $result.RunDirectory
                        if ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $captureOutputEnabled = $false
                        }
                    }

                    if ($logsEnabled) {
                        if ([string]::IsNullOrWhiteSpace($result.RunDirectory) -and -not [string]::IsNullOrWhiteSpace($sharedRunDirectory)) {
                            $result.RunDirectory = $sharedRunDirectory
                        }

                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionLogArtifact `
                            -Result $result `
                            -Session $session `
                            -OutputRoot $OutputRoot `
                            -RemoteLogDirectory $remoteLogDirectory
                        $sharedRunDirectory = $result.RunDirectory
                        if ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $logsEnabled = $false
                        }
                    }

                    $result = Set-WinPushPackageCleanupResult `
                        -Result $result `
                        -Session $session `
                        -StagePlan $stagePlan `
                        -RemoteStageRoot $RemoteStageRoot `
                        -Cleanup $Cleanup

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
                        -ArtifactError $artifactError `
                        -Errors $errorMessage `
                        -RunDirectory $sharedRunDirectory `
                        -PackageMetadata $metadata

                    if ($captureOutputEnabled -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionArtifact `
                            -Result $result `
                            -OutputRoot $OutputRoot `
                            -ArtifactIdentity ('Uri: {0}; EntryPoint: {1}' -f $Uri.OriginalString, $EntryPoint) `
                            -RunDirectory $sharedRunDirectory
                        $sharedRunDirectory = $result.RunDirectory
                        if ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $captureOutputEnabled = $false
                        }
                    }

                    if ($logsEnabled -and $null -ne $session -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                        if ([string]::IsNullOrWhiteSpace($result.RunDirectory) -and -not [string]::IsNullOrWhiteSpace($sharedRunDirectory)) {
                            $result.RunDirectory = $sharedRunDirectory
                        }

                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionLogArtifact `
                            -Result $result `
                            -Session $session `
                            -OutputRoot $OutputRoot `
                            -RemoteLogDirectory $remoteLogDirectory
                        $sharedRunDirectory = $result.RunDirectory
                        if ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $logsEnabled = $false
                        }
                    }

                    $result = Set-WinPushPackageCleanupResult `
                        -Result $result `
                        -Session $session `
                        -StagePlan $stagePlan `
                        -RemoteStageRoot $RemoteStageRoot `
                        -Cleanup $Cleanup

                    $result
                }
                finally {
                    if ($null -ne $session) {
                        Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
                    }
                }
            }

            return
        }

        $resolvedPackagePath = $Path
        $packageIsDirectory = $false
        $targets = @()

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

            $targets = @(
                if ($isHostFileTargetSet) {
                    Resolve-WinPushTarget -HostFile $HostFile
                }
                else {
                    Resolve-WinPushTarget -ComputerName $computerNames.ToArray()
                }
            )
        }
        catch {
            $resultComputerName = if ($isHostFileTargetSet -and -not [string]::IsNullOrWhiteSpace($HostFile)) {
                $HostFile
            }
            elseif ($computerNames.Count -eq 1) {
                [string] $computerNames[0]
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string] $ComputerName)) {
                [string] $ComputerName
            }
            else {
                'Unknown'
            }
            $result = New-WinPushExecutionResult `
                -ComputerName $resultComputerName `
                -Transport 'Psrp' `
                -Operation 'RunPackage' `
                -Succeeded $false `
                -ExitCode 1 `
                -ErrorMessage $_.Exception.Message `
                -ArtifactError $artifactError `
                -Errors $_.Exception.Message `
                -RunDirectory $sharedRunDirectory

            if ($captureOutputEnabled -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                $result = Add-WinPushExecutionArtifact `
                    -Result $result `
                    -OutputRoot $OutputRoot `
                    -ArtifactIdentity ('Path: {0}; EntryPoint: {1}' -f $resolvedPackagePath, $EntryPoint) `
                    -RunDirectory $sharedRunDirectory
            }

            $result
            return
        }

        foreach ($target in $targets) {
            $session = $null
            $stagePlan = $null
            $remoteStagePath = $null
            $extracted = $false
            $executionStarted = $null
            $executionEnded = $null
            $sessionCreationStarted = $false

            try {
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
                    -ArtifactError $artifactError `
                    -Output $output `
                    -Errors $errors `
                    -RunDirectory $sharedRunDirectory `
                    -PackageMetadata $metadata

                if ($captureOutputEnabled) {
                    $previousArtifactError = $result.ArtifactError
                    $result = Add-WinPushExecutionArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity ('Path: {0}; EntryPoint: {1}' -f $resolvedPackagePath, $EntryPoint) `
                        -RunDirectory $sharedRunDirectory
                    $sharedRunDirectory = $result.RunDirectory
                    if ($result.ArtifactError -ne $previousArtifactError) {
                        $artifactError = $result.ArtifactError
                        $captureOutputEnabled = $false
                    }
                }

                if ($logsEnabled) {
                    if ([string]::IsNullOrWhiteSpace($result.RunDirectory) -and -not [string]::IsNullOrWhiteSpace($sharedRunDirectory)) {
                        $result.RunDirectory = $sharedRunDirectory
                    }

                    $previousArtifactError = $result.ArtifactError
                    $result = Add-WinPushExecutionLogArtifact `
                        -Result $result `
                        -Session $session `
                        -OutputRoot $OutputRoot `
                        -RemoteLogDirectory $remoteLogDirectory
                    $sharedRunDirectory = $result.RunDirectory
                    if ($result.ArtifactError -ne $previousArtifactError) {
                        $artifactError = $result.ArtifactError
                        $logsEnabled = $false
                    }
                }

                $result = Set-WinPushPackageCleanupResult `
                    -Result $result `
                    -Session $session `
                    -StagePlan $stagePlan `
                    -RemoteStageRoot $RemoteStageRoot `
                    -Cleanup $Cleanup

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
                    -ArtifactError $artifactError `
                    -Errors $errorMessage `
                    -RunDirectory $sharedRunDirectory `
                    -PackageMetadata $metadata

                if ($captureOutputEnabled -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                    $previousArtifactError = $result.ArtifactError
                    $result = Add-WinPushExecutionArtifact `
                        -Result $result `
                        -OutputRoot $OutputRoot `
                        -ArtifactIdentity ('Path: {0}; EntryPoint: {1}' -f $resolvedPackagePath, $EntryPoint) `
                        -RunDirectory $sharedRunDirectory
                    $sharedRunDirectory = $result.RunDirectory
                    if ($result.ArtifactError -ne $previousArtifactError) {
                        $artifactError = $result.ArtifactError
                        $captureOutputEnabled = $false
                    }
                }

                if ($logsEnabled -and $null -ne $session -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                    if ([string]::IsNullOrWhiteSpace($result.RunDirectory) -and -not [string]::IsNullOrWhiteSpace($sharedRunDirectory)) {
                        $result.RunDirectory = $sharedRunDirectory
                    }

                    $previousArtifactError = $result.ArtifactError
                    $result = Add-WinPushExecutionLogArtifact `
                        -Result $result `
                        -Session $session `
                        -OutputRoot $OutputRoot `
                        -RemoteLogDirectory $remoteLogDirectory
                    $sharedRunDirectory = $result.RunDirectory
                    if ($result.ArtifactError -ne $previousArtifactError) {
                        $artifactError = $result.ArtifactError
                        $logsEnabled = $false
                    }
                }

                $result = Set-WinPushPackageCleanupResult `
                    -Result $result `
                    -Session $session `
                    -StagePlan $stagePlan `
                    -RemoteStageRoot $RemoteStageRoot `
                    -Cleanup $Cleanup

                $result
            }
            finally {
                if ($null -ne $session) {
                    Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
