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
        $captureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
            Get-WinPushActiveCaptureContext
        }
        if ($null -ne $captureContext) {
            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Started'
        }
        Remove-WinPushPsrpPackageStage `
            -Session $Session `
            -StagePlan $StagePlan `
            -RemoteStageRoot $RemoteStageRoot

        $Result.PackageMetadata.CleanupSucceeded = $true
        if ($null -ne $captureContext) {
            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Completed'
        }
    }
    catch {
        $Result.PackageMetadata.CleanupSucceeded = $false
        if ($null -ne $captureContext) {
            Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $_
        }
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

        [object[]] $ArgumentList = @(),

        [Parameter(ParameterSetName = 'UriComputerName')]
        [Parameter(ParameterSetName = 'UriHostFile')]
        [ValidatePattern('^[0-9A-Fa-f]{64}\z')]
        [string] $ExpectedSha256,

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

        if (-not (Test-WinPushPackageAbsoluteWindowsPath -Path $RemoteStageRoot)) {
            throw [System.ArgumentException]::new('RemoteStageRoot must be an absolute drive-rooted or UNC Windows path.')
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
        $cachePlan = $null
        $captureContext = $null

        try {
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

            $targets = @()
            $packageSourceType = if ($isUriPackageSet) { 'Uri' } else { 'Path' }
            $packageSource = if ($isUriPackageSet) { $Uri.OriginalString } else { $Path }
            $localPackagePath = if ($isUriPackageSet) { $null } else { $Path }
            $packageIsDirectory = $false
            $artifactIdentity = '{0}: {1}; EntryPoint: {2}' -f $packageSourceType, $packageSource, $EntryPoint
            $captureContext = if ($captureOutputEnabled -and $null -ne $sharedRunDirectory -and
                (Get-Command -Name New-WinPushCaptureContext -ErrorAction SilentlyContinue)) {
                New-WinPushCaptureContext `
                    -RunDirectory $sharedRunDirectory `
                    -Operation 'RunPackage' `
                    -Transport 'Psrp' `
                    -ArtifactIdentity $artifactIdentity
            }
            if ($null -ne $captureContext -and -not [string]::IsNullOrWhiteSpace($captureContext.ArtifactError)) {
                $artifactError = $captureContext.ArtifactError
            }

            try {
                if ($isUriPackageSet) {
                    $targets = @(
                        if ($isHostFileTargetSet) {
                            Resolve-WinPushTarget -HostFile $HostFile
                        }
                        else {
                            Resolve-WinPushTarget -ComputerName $computerNames.ToArray()
                        }
                    )

                    $cachePlan = New-WinPushPackageCachePlan -Uri $Uri -PackageCacheRoot $PackageCacheRoot
                    $localPackagePath = $cachePlan.LocalPackagePath
                    if ($Extract -and [System.IO.Path]::GetExtension([string] $cachePlan.PackageFileName) -ne '.zip') {
                        throw [System.ArgumentException]::new('Extract requires a staged .zip package file.')
                    }

                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Download Started' -RootOnly
                    }
                    $localPackagePath = Save-WinPushPackageUriToCache -Uri $Uri -CachePlan $cachePlan
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Download Completed' -RootOnly
                    }
                    if ($PSBoundParameters.ContainsKey('ExpectedSha256')) {
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Validation Started' -RootOnly
                        }
                        $actualSha256 = (Get-FileHash -LiteralPath $localPackagePath -Algorithm SHA256 -ErrorAction Stop).Hash
                        if (-not $actualSha256.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                            throw [System.IO.InvalidDataException]::new('Downloaded package SHA256 does not match ExpectedSha256.')
                        }
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Validation Completed' -RootOnly
                        }
                    }
                }
                else {
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

                    $localPackagePath = $packageItem.FullName
                    $packageSource = $localPackagePath
                    $packageIsDirectory = [bool] $packageItem.PSIsContainer
                    $artifactIdentity = 'Path: {0}; EntryPoint: {1}' -f $packageSource, $EntryPoint
                    if ($Extract -and ($packageIsDirectory -or [System.IO.Path]::GetExtension($localPackagePath) -ne '.zip')) {
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
            }
            catch {
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $_ -RootOnly
                }
                $failureTargets = if ($isUriPackageSet -and $targets.Count -gt 0) {
                    @($targets)
                }
                elseif ($isHostFileTargetSet -and -not [string]::IsNullOrWhiteSpace($HostFile)) {
                    @($HostFile)
                }
                elseif ($computerNames.Count -gt 0) {
                    @([string] $computerNames[0])
                }
                else {
                    @('Unknown')
                }

                foreach ($failureTarget in $failureTargets) {
                    if ($null -ne $captureContext) {
                        $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName $failureTarget -Transport 'Psrp'
                    }
                    $metadata = $null
                    if ($isUriPackageSet -and $null -ne $cachePlan) {
                        $metadata = New-WinPushPackageInfo `
                            -PackageSourceType $packageSourceType `
                            -PackageSource $packageSource `
                            -LocalPackagePath $localPackagePath `
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
                            -ArtifactIdentity $artifactIdentity `
                            -RunDirectory $sharedRunDirectory
                        if ($null -ne $captureContext) {
                            $result.ArtifactError = $captureContext.ArtifactError
                        }
                        elseif ($result.ArtifactError -ne $previousArtifactError) {
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

            $sourcePreparation = [pscustomobject] [ordered] @{
                PSTypeName        = 'WinPush.PackageSourcePreparation'
                PackageSourceType = $packageSourceType
                PackageSource     = $packageSource
                LocalPackagePath  = $localPackagePath
                IsDirectory       = $packageIsDirectory
                ArtifactIdentity  = $artifactIdentity
            }

            foreach ($target in $targets) {
                $session = $null
                $stagePlan = $null
                $remoteStagePath = $null
                $extracted = $false
                $executionStarted = $null
                $executionEnded = $null
                $sessionCreationStarted = $false

                if ($null -ne $captureContext) {
                    $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName $target -Transport 'Psrp'
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Started'
                    $artifactError = $captureContext.ArtifactError
                }

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
                    $stagePlan = New-WinPushPackageStagePlan `
                        -RemoteStageRoot $RemoteStageRoot `
                        -PackagePath $sourcePreparation.LocalPackagePath `
                        -Directory:$sourcePreparation.IsDirectory
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Upload Started'
                    }
                    Invoke-WinPushPsrpPackageStage `
                        -Session $session `
                        -LocalPackagePath $sourcePreparation.LocalPackagePath `
                        -StagePlan $stagePlan
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Upload Completed'
                    }
                    $remoteStagePath = $stagePlan.RemotePackagePath
                    $packageRoot = $stagePlan.RemoteDirectory
                    if ($Extract) {
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Extraction Started'
                        }
                        Invoke-WinPushPsrpPackageExtract -Session $session -StagePlan $stagePlan
                        $remoteStagePath = $stagePlan.RemoteDirectory
                        $packageRoot = $stagePlan.RemoteDirectory
                        $extracted = $true
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Extraction Completed'
                        }
                    }

                    $executionStarted = [datetime]::UtcNow
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Execution Started'
                    }
                    $packageExecution = Invoke-WinPushPsrpPackageEntryPoint `
                        -Session $session `
                        -PackageRoot $packageRoot `
                        -EntryPoint $EntryPoint `
                        -ArgumentList $ArgumentList
                    $executionEnded = [datetime]::UtcNow
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Execution Completed'
                    }
                    $output = @($packageExecution.Output)
                    $errors = @($packageExecution.Errors)
                    $succeeded = $errors.Count -eq 0
                    $exitCode = if ($succeeded) { 0 } else { 1 }
                    $errorMessage = if ($errors.Count -gt 0) { [string] $errors[0] } else { $null }
                    $metadata = New-WinPushPackageInfo `
                        -PackageSourceType $sourcePreparation.PackageSourceType `
                        -PackageSource $sourcePreparation.PackageSource `
                        -LocalPackagePath $sourcePreparation.LocalPackagePath `
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

                    if ($logsEnabled) {
                        if ([string]::IsNullOrWhiteSpace($result.RunDirectory) -and -not [string]::IsNullOrWhiteSpace($sharedRunDirectory)) {
                            $result.RunDirectory = $sharedRunDirectory
                        }
                        if ($null -ne $captureContext) {
                            $result.ComputerDirectory = $captureContext.ComputerDirectory
                            $result.ResultPath = $captureContext.ResultPath
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Started'
                        }

                        $result = Add-WinPushExecutionLogArtifact `
                            -Result $result `
                            -Session $session `
                            -OutputRoot $OutputRoot `
                            -RemoteLogDirectory $remoteLogDirectory
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Completed'
                        }
                        $sharedRunDirectory = $result.RunDirectory
                    }

                    $result = Set-WinPushPackageCleanupResult `
                        -Result $result `
                        -Session $session `
                        -StagePlan $stagePlan `
                        -RemoteStageRoot $RemoteStageRoot `
                        -Cleanup $Cleanup

                    if ($captureOutputEnabled) {
                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionArtifact `
                            -Result $result `
                            -OutputRoot $OutputRoot `
                            -ArtifactIdentity $sourcePreparation.ArtifactIdentity `
                            -RunDirectory $sharedRunDirectory
                        $sharedRunDirectory = $result.RunDirectory
                        if ($null -ne $captureContext -and [string]::IsNullOrWhiteSpace($result.ArtifactError)) {
                            $result.ArtifactError = $captureContext.ArtifactError
                        }
                        elseif ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $captureOutputEnabled = $false
                        }
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
                    if ($null -ne $captureContext) {
                        Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value $errorMessage
                    }

                    $metadata = $null
                    if ($isUriPackageSet -or $null -ne $stagePlan) {
                        $metadataRemoteStagePath = if ([string]::IsNullOrWhiteSpace($remoteStagePath)) {
                            if ($null -eq $stagePlan) { $null } else { $stagePlan.RemotePackagePath }
                        }
                        else {
                            $remoteStagePath
                        }
                        $metadata = New-WinPushPackageInfo `
                            -PackageSourceType $sourcePreparation.PackageSourceType `
                            -PackageSource $sourcePreparation.PackageSource `
                            -LocalPackagePath $sourcePreparation.LocalPackagePath `
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

                    if ($logsEnabled -and $null -ne $session -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                        if ([string]::IsNullOrWhiteSpace($result.RunDirectory) -and -not [string]::IsNullOrWhiteSpace($sharedRunDirectory)) {
                            $result.RunDirectory = $sharedRunDirectory
                        }
                        if ($null -ne $captureContext) {
                            $result.ComputerDirectory = $captureContext.ComputerDirectory
                            $result.ResultPath = $captureContext.ResultPath
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Started'
                        }

                        $result = Add-WinPushExecutionLogArtifact `
                            -Result $result `
                            -Session $session `
                            -OutputRoot $OutputRoot `
                            -RemoteLogDirectory $remoteLogDirectory
                        if ($null -ne $captureContext) {
                            Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'LogCopy Completed'
                        }
                        $sharedRunDirectory = $result.RunDirectory
                    }

                    $result = Set-WinPushPackageCleanupResult `
                        -Result $result `
                        -Session $session `
                        -StagePlan $stagePlan `
                        -RemoteStageRoot $RemoteStageRoot `
                        -Cleanup $Cleanup

                    if ($captureOutputEnabled -and -not [string]::IsNullOrWhiteSpace($result.ComputerName)) {
                        $previousArtifactError = $result.ArtifactError
                        $result = Add-WinPushExecutionArtifact `
                            -Result $result `
                            -OutputRoot $OutputRoot `
                            -ArtifactIdentity $sourcePreparation.ArtifactIdentity `
                            -RunDirectory $sharedRunDirectory
                        $sharedRunDirectory = $result.RunDirectory
                        if ($null -ne $captureContext -and [string]::IsNullOrWhiteSpace($result.ArtifactError)) {
                            $result.ArtifactError = $captureContext.ArtifactError
                        }
                        elseif ($result.ArtifactError -ne $previousArtifactError) {
                            $artifactError = $result.ArtifactError
                            $captureOutputEnabled = $false
                        }
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
        finally {
            if ($null -ne $cachePlan -and (Test-Path -LiteralPath $cachePlan.CacheDirectory)) {
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Started' -RootOnly
                }
                Remove-Item -LiteralPath $cachePlan.CacheDirectory -Recurse -Force -ErrorAction SilentlyContinue
                if ($null -ne $captureContext) {
                    Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Cleanup Completed' -RootOnly
                }
            }
        }
    }
}
