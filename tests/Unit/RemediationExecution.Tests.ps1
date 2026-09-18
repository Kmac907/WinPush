$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

foreach ($relativePath in @(
        'src\Private\Results\New-WinPushExecutionResult.ps1'
        'src\Private\Results\New-WinPushLogResult.ps1'
        'src\Private\Execution\New-WinPushNativeScriptStagePlan.ps1'
        'src\Private\Execution\Invoke-WinPushRemediationStage.ps1'
        'src\Private\Execution\New-WinPushCaptureContext.ps1'
        'src\Private\Logs\Get-WinPushScriptLogDirectory.ps1'
        'src\Private\Logs\Copy-WinPushPsrpLogDirectory.ps1'
        'src\Public\Test-WinPushRemediation.ps1'
        'src\Public\Invoke-WinPushRemediation.ps1'
    )) {
    . (Join-Path -Path $script:ModuleRoot -ChildPath $relativePath)
}

function Resolve-WinPushTarget {}
function New-WinPushArtifactRunDirectory {}
function Add-WinPushExecutionArtifact {}
function Copy-WinPushPsrpItem {}
function Invoke-WinPushPsrpCommand {}
function Invoke-WinPushWinRsCommand {}
function Invoke-WinPushPsExecCommand {}
function Remove-WinPushNativeScriptStage {}
function New-WinPushNativePowerShellEncodedCommand {}

Describe 'Invoke-WinPushRemediation' {
    BeforeEach {
        $script:DetectScript = Join-Path -Path $TestDrive -ChildPath 'detect.ps1'
        $script:RemediateScript = Join-Path -Path $TestDrive -ChildPath 'remediate.ps1'
        Set-Content -LiteralPath $script:DetectScript -Value 'exit 0'
        Set-Content -LiteralPath $script:RemediateScript -Value 'exit 0'

        $script:Targets = @('PC-001')
        $script:StageResults = @{}
        $script:CleanupFailures = @{}
        $script:Stages = @()
        $script:StageCalls = @()
        $script:CapturedResult = $null
        $script:LogCopyCalls = @()

        Mock Test-WinPushRemediation {
            [pscustomobject] @{
                IsValid             = $true
                DetectScriptPath    = $script:DetectScript
                RemediateScriptPath = $script:RemediateScript
                Errors              = @()
            }
        }
        Mock Resolve-WinPushTarget { @($script:Targets) }
        Mock New-PSSession { [pscustomobject] @{ Id = 7 } }
        Mock Remove-PSSession {}
        Mock New-WinPushNativeScriptStagePlan {
            param($ComputerName)

            [pscustomobject] @{
                RemoteDirectory             = "C:\Windows\Temp\WinPush\$ComputerName"
                RemoteDetectionScriptPath   = "C:\Windows\Temp\WinPush\$ComputerName\detect.ps1"
                RemoteRemediationScriptPath = "C:\Windows\Temp\WinPush\$ComputerName\remediate.ps1"
            }
        }
        Mock Copy-WinPushRemediationScriptsToStage {}
        Mock Invoke-WinPushRemediationStage {
            param($ComputerName, $RemoteScriptPath, $Transport)

            $phase = if ($RemoteScriptPath -like '*\detect.ps1') { 'Detection' } else { 'Remediation' }
            $script:StageCalls += "$Transport|$ComputerName|$phase"
            $configured = $script:StageResults[$ComputerName]
            if ($null -eq $configured) {
                $configured = $script:StageResults['*']
            }
            $configured[$phase]
        }
        Mock Remove-WinPushRemediationScriptStage {
            param($ComputerName)

            if ($script:CleanupFailures.ContainsKey($ComputerName)) {
                throw $script:CleanupFailures[$ComputerName]
            }
        }
        Mock New-WinPushArtifactRunDirectory { Join-Path -Path $TestDrive -ChildPath 'run' }
        Mock New-WinPushCaptureContext {
            $context = [pscustomobject] @{
                PSTypeName         = 'WinPush.CaptureContext'
                ArtifactError      = $null
                ComputerDirectory  = $null
                ComputerName       = $null
                Transport          = $null
            }
            $context
        }
        Mock Start-WinPushCaptureTarget {
            param($Context, $ComputerName, $Transport)

            $Context.ComputerName = $ComputerName
            $Context.Transport = $Transport
            $Context.ComputerDirectory = Join-Path -Path $TestDrive -ChildPath $ComputerName
            $Context
        }
        Mock Write-WinPushCaptureRecord {
            param($Type, $Value)

            if ($Type -eq 'Stage') {
                $script:Stages += [string] $Value
            }
        }
        Mock Add-WinPushExecutionArtifact {
            param($Result)

            $script:CapturedResult = $Result
            $Result.ResultPath = Join-Path -Path $TestDrive -ChildPath 'run.log'
            $Result
        }
        Mock Get-WinPushScriptLogDirectory {
            param($ScriptPath)

            'C:\ProgramData\EA\Logs\{0}' -f [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
        }
        Mock Copy-WinPushPsrpLogDirectory {
            param($RemoteDirectory, $ComputerName)

            $script:LogCopyCalls += $RemoteDirectory
            $localPath = Join-Path -Path $TestDrive -ChildPath ("$ComputerName-$([System.IO.Path]::GetFileName($RemoteDirectory)).log")
            [pscustomobject] @{
                Logs           = @([pscustomobject] @{ Copied = $true; LocalPath = $localPath })
                CopiedLogPaths = @($localPath)
            }
        }
    }

    $transportCases = @(
        @{ Transport = 'Psrp' }
        @{ Transport = 'WinRM' }
        @{ Transport = 'PsExec' }
    )

    It 'returns Compliant and skips remediation over <Transport>' -TestCases $transportCases {
        param($Transport)

        $script:StageResults['*'] = @{
            Detection = [pscustomobject] @{ ExitCode = 0; Output = @('detected'); Errors = @() }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -Transport $Transport

        $result.PSTypeNames[0] | Should Be 'WinPush.ExecutionResult'
        $result.PSTypeNames[1] | Should Be 'WinPush.ExecutionResult.RunRemediation'
        $result.Operation | Should Be 'RunRemediation'
        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
        $result.RemediationMetadata.Status | Should Be 'Compliant'
        $result.RemediationMetadata.DetectionExitCode | Should Be 0
        $null -eq $result.RemediationMetadata.RemediationExitCode | Should Be $true
        ($result.Output -join ',') | Should Be 'detected'
        @($script:StageCalls).Count | Should Be 1
    }

    It 'returns Remediated after separate detection and remediation processes over <Transport>' -TestCases $transportCases {
        param($Transport)

        $script:StageResults['*'] = @{
            Detection   = [pscustomobject] @{ ExitCode = 1; Output = @('not compliant'); Errors = @() }
            Remediation = [pscustomobject] @{ ExitCode = 0; Output = @('fixed'); Errors = @() }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -Transport $Transport

        $result.Succeeded | Should Be $true
        $result.RemediationMetadata.Status | Should Be 'Remediated'
        $result.RemediationMetadata.DetectionExitCode | Should Be 1
        $result.RemediationMetadata.RemediationExitCode | Should Be 0
        ($result.Output -join ',') | Should Be 'not compliant,fixed'
        ($result.RemediationMetadata.DetectionOutput -join ',') | Should Be 'not compliant'
        ($result.RemediationMetadata.RemediationOutput -join ',') | Should Be 'fixed'
        @($script:StageCalls).Count | Should Be 2
    }

    It 'fails without remediation for an unexpected detection exit over <Transport>' -TestCases $transportCases {
        param($Transport)

        $script:StageResults['*'] = @{
            Detection = [pscustomobject] @{ ExitCode = 7; Output = @('partial'); Errors = @('detect error') }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -Transport $Transport

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 7
        $result.ErrorMessage | Should Be 'detect error'
        $result.RemediationMetadata.Status | Should Be 'Failed'
        $result.RemediationMetadata.RemediationOutput.Count | Should Be 0
        @($script:StageCalls).Count | Should Be 1
    }

    It 'fails with separate phase errors for a failed remediation over <Transport>' -TestCases $transportCases {
        param($Transport)

        $script:StageResults['*'] = @{
            Detection   = [pscustomobject] @{ ExitCode = 1; Output = @('detect output'); Errors = @('detect warning') }
            Remediation = [pscustomobject] @{ ExitCode = 9; Output = @('remediate output'); Errors = @('remediate error') }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -Transport $Transport

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 9
        $result.ErrorMessage | Should Be 'remediate error'
        ($result.RemediationMetadata.DetectionErrors -join ',') | Should Be 'detect warning'
        ($result.RemediationMetadata.RemediationErrors -join ',') | Should Be 'remediate error'
    }

    It 'treats a timeout exit as a detection failure' {
        $script:StageResults['*'] = @{
            Detection = [pscustomobject] @{ ExitCode = 124; Output = @(); Errors = @('timed out') }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -TimeoutSeconds 3

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be 124
        $result.RemediationMetadata.DetectionExitCode | Should Be 124
        Assert-MockCalled Invoke-WinPushRemediationStage -Times 1 -ParameterFilter { $TimeoutSeconds -eq 3 }
    }

    It 'fails on cleanup without discarding metadata and continues to later targets' {
        $script:Targets = @('PC-001', 'PC-002')
        $script:StageResults['*'] = @{
            Detection = [pscustomobject] @{ ExitCode = 0; Output = @('compliant'); Errors = @() }
        }
        $script:CleanupFailures['PC-001'] = 'cleanup failed'

        $results = @(Invoke-WinPushRemediation `
                -ComputerName $script:Targets `
                -DetectScript $script:DetectScript `
                -RemediateScript $script:RemediateScript)

        $results.Count | Should Be 2
        $results[0].Succeeded | Should Be $false
        $results[0].ErrorMessage | Should Be 'cleanup failed'
        $results[0].RemediationMetadata.Status | Should Be 'Failed'
        $results[0].RemediationMetadata.DetectionExitCode | Should Be 0
        ($results[0].RemediationMetadata.DetectionOutput -join ',') | Should Be 'compliant'
        $results[1].Succeeded | Should Be $true
        $results[1].RemediationMetadata.Status | Should Be 'Compliant'
        Assert-MockCalled Remove-WinPushRemediationScriptStage -Times 2
    }

    It 'captures remediation stages once while preserving combined output' {
        $script:StageResults['*'] = @{
            Detection   = [pscustomobject] @{ ExitCode = 1; Output = @('detect'); Errors = @() }
            Remediation = [pscustomobject] @{ ExitCode = 0; Output = @('remediate'); Errors = @() }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -CaptureOutput `
            -OutputRoot $TestDrive

        ($script:Stages -join ',') | Should Be 'Started,Upload Started,Upload Completed,Detection Started,Detection Completed,Remediation Started,Remediation Completed,Cleanup Started,Cleanup Completed'
        ($result.Output -join ',') | Should Be 'detect,remediate'
        ($script:CapturedResult.Output -join ',') | Should Be 'detect,remediate'
        $result.ResultPath | Should Not BeNullOrEmpty
    }

    It 'attaches logs from both scripts when requested over Psrp' {
        $script:StageResults['*'] = @{
            Detection = [pscustomobject] @{ ExitCode = 0; Output = @(); Errors = @() }
        }

        $result = Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -Logs `
            -OutputRoot $TestDrive

        @($script:LogCopyCalls).Count | Should Be 2
        @($result.Logs).Count | Should Be 2
        @($result.CopiedLogPaths).Count | Should Be 2
    }

    It 'passes PsExecPath only through the PsExec workflow and stages both files once' {
        $script:StageResults['*'] = @{
            Detection = [pscustomobject] @{ ExitCode = 0; Output = @(); Errors = @() }
        }
        $psExecPath = Join-Path -Path $TestDrive -ChildPath 'PsExec.exe'

        Invoke-WinPushRemediation `
            -ComputerName 'PC-001' `
            -DetectScript $script:DetectScript `
            -RemediateScript $script:RemediateScript `
            -Transport PsExec `
            -PsExecPath $psExecPath | Out-Null

        Assert-MockCalled Copy-WinPushRemediationScriptsToStage -Times 1 -ParameterFilter {
            $PsExecPath -eq $psExecPath -and $DetectScriptPath -eq $script:DetectScript -and
                $RemediateScriptPath -eq $script:RemediateScript
        }
    }
}

Describe 'Invoke-WinPushRemediationStage' {
    BeforeEach {
        $script:WindowsPowerShellCommand = $null
        Mock New-WinPushNativeStagedScriptCommand { 'powershell.exe -NoLogo -NoProfile -File staged.ps1' }
        Mock Invoke-WinPushPsrpCommand {
            param($Command)

            $script:WindowsPowerShellCommand = $Command
            [pscustomobject] @{ ExitCode = 3; Output = @('psrp'); Errors = @() }
        }
        Mock Invoke-WinPushWinRsCommand {
            param($Command)

            $script:WindowsPowerShellCommand = $Command
            [pscustomobject] @{ ExitCode = 3; Output = @('winrs'); Errors = @() }
        }
        Mock Invoke-WinPushPsExecCommand {
            param($Command)

            $script:WindowsPowerShellCommand = $Command
            [pscustomobject] @{ ExitCode = 3; Output = @('psexec'); Errors = @() }
        }
    }

    It 'launches a staged script through Windows PowerShell over <Transport>' -TestCases @(
        @{ Transport = 'Psrp'; CommandName = 'Invoke-WinPushPsrpCommand' }
        @{ Transport = 'WinRM'; CommandName = 'Invoke-WinPushWinRsCommand' }
        @{ Transport = 'PsExec'; CommandName = 'Invoke-WinPushPsExecCommand' }
    ) {
        param($Transport, $CommandName)

        $result = Invoke-WinPushRemediationStage `
            -Session ([pscustomobject] @{ Id = 7 }) `
            -ComputerName 'PC-001' `
            -RemoteScriptPath 'C:\Windows\Temp\WinPush\one\detect.ps1' `
            -Transport $Transport `
            -PsExecPath 'C:\Tools\PsExec.exe' `
            -TimeoutSeconds 12

        $result.ExitCode | Should Be 3
        $script:WindowsPowerShellCommand | Should BeLike 'powershell.exe *'
        Assert-MockCalled New-WinPushNativeStagedScriptCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 12 }
        switch ($CommandName) {
            'Invoke-WinPushPsrpCommand' {
                Assert-MockCalled Invoke-WinPushPsrpCommand -Times 1
            }
            'Invoke-WinPushWinRsCommand' {
                Assert-MockCalled Invoke-WinPushWinRsCommand -Times 1
            }
            'Invoke-WinPushPsExecCommand' {
                Assert-MockCalled Invoke-WinPushPsExecCommand -Times 1
            }
        }
    }

    It 'places detection and remediation scripts in one stage directory' {
        $plan = New-WinPushNativeScriptStagePlan `
            -ComputerName 'PC-001' `
            -ScriptPath 'C:\Source\detect.ps1' `
            -RemediateScriptPath 'C:\Other\remediate.ps1'

        Split-Path -Path $plan.RemoteDetectionScriptPath -Parent | Should Be $plan.RemoteDirectory
        Split-Path -Path $plan.RemoteRemediationScriptPath -Parent | Should Be $plan.RemoteDirectory
        $plan.RemoteDetectionScriptPath | Should Not Be $plan.RemoteRemediationScriptPath
    }
}

Describe 'PSRP remediation timeouts' {
    It 'stops a PSRP operation when its timeout expires' {
        Mock Invoke-Command { Start-Job -ScriptBlock { Start-Sleep -Seconds 30 } }
        $session = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
            [System.Management.Automation.Runspaces.PSSession]
        )

        $message = $null
        try {
            Invoke-WinPushPsrpJob `
                -Session $session `
                -ScriptBlock { 'work' } `
                -TimeoutSeconds 1 `
                -Operation 'PSRP upload'
        }
        catch {
            $message = $_.Exception.Message
        }

        $message | Should Be 'PSRP upload timed out after 1 seconds.'
        Assert-MockCalled Invoke-Command -Times 1 -ParameterFilter { $AsJob }
    }

    It 'binds the timeout to PSRP upload and cleanup operations' {
        $detect = Join-Path -Path $TestDrive -ChildPath 'detect.ps1'
        $remediate = Join-Path -Path $TestDrive -ChildPath 'remediate.ps1'
        Set-Content -LiteralPath $detect -Value 'exit 0'
        Set-Content -LiteralPath $remediate -Value 'exit 0'
        $plan = [pscustomobject] @{
            RemoteDirectory             = 'C:\Windows\Temp\WinPush\one'
            RemoteDetectionScriptPath   = 'C:\Windows\Temp\WinPush\one\detect.ps1'
            RemoteRemediationScriptPath = 'C:\Windows\Temp\WinPush\one\remediate.ps1'
        }
        Mock Invoke-WinPushPsrpJob {}

        Copy-WinPushRemediationScriptsToStage `
            -Session ([pscustomobject] @{ Id = 7 }) `
            -ComputerName 'PC-001' `
            -DetectScriptPath $detect `
            -RemediateScriptPath $remediate `
            -StagePlan $plan `
            -Transport Psrp `
            -TimeoutSeconds 6
        Remove-WinPushRemediationScriptStage `
            -Session ([pscustomobject] @{ Id = 7 }) `
            -ComputerName 'PC-001' `
            -StagePlan $plan `
            -Transport Psrp `
            -TimeoutSeconds 6

        Assert-MockCalled Invoke-WinPushPsrpJob -Times 3 -ParameterFilter { $TimeoutSeconds -eq 6 -and $Operation -ne 'PSRP cleanup' }
        Assert-MockCalled Invoke-WinPushPsrpJob -Times 1 -ParameterFilter { $TimeoutSeconds -eq 6 -and $Operation -eq 'PSRP cleanup' }
    }

    It 'generates a timed process wrapper that preserves the script exit code' {
        $script:WrapperCommand = $null
        Mock New-WinPushNativePowerShellEncodedCommand {
            param($Command)

            $script:WrapperCommand = $Command
            'powershell.exe encoded'
        }

        New-WinPushNativeStagedScriptCommand `
            -RemoteScriptPath 'C:\Windows\Temp\WinPush\one\detect.ps1' `
            -TimeoutSeconds 12 | Out-Null

        $script:WrapperCommand | Should Match '\[long\] 12 \* 1000'
        $script:WrapperCommand | Should Match 'taskkill\.exe /PID \$process\.Id /T /F'
        $script:WrapperCommand | Should Match 'exit 124'
        $script:WrapperCommand | Should Match 'exit \$process\.ExitCode'
    }
}
