$script:ModuleRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Logs\New-WinPushLogArtifactDirectory.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\New-WinPushCaptureContext.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Write-WinPushCommandOutputArtifact.ps1')
. (Join-Path -Path $script:ModuleRoot -ChildPath 'src\Private\Execution\Invoke-WinPushNativeProcess.ps1')

Describe 'Capture logging' {
    It 'creates root and target logs before work and appends timestamped records' {
        $runDirectory = New-WinPushArtifactRunDirectory -OutputRoot $TestDrive
        $captureContext = New-WinPushCaptureContext `
            -RunDirectory $runDirectory `
            -Operation 'RunCommand' `
            -Transport 'Psrp' `
            -ArtifactIdentity 'hostname'

        Test-Path -LiteralPath $captureContext.RootLogPath -PathType Leaf | Should Be $true
        $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName 'PC-001'
        Test-Path -LiteralPath $captureContext.ResultPath -PathType Leaf | Should Be $true

        Write-WinPushCaptureRecord -Context $captureContext -Type Stage -Value 'Execution Started'
        Write-WinPushCaptureRecord -Context $captureContext -Type Output -Value 'first output'
        Write-WinPushCaptureRecord -Context $captureContext -Type Error -Value 'first error'

        $text = Get-Content -LiteralPath $captureContext.ResultPath -Raw
        $text | Should Match '\d{4}-\d{2}-\d{2}T.+ \[Operation\] RunCommand'
        $text | Should Match '\[Target\] PC-001'
        $text | Should Match '\[Stage\] Execution Started'
        $text | Should Match '\[Output\] first output'
        $text | Should Match '\[Error\] first error'
    }

    It 'adds a summary row only when a target is completed' {
        $runDirectory = New-WinPushArtifactRunDirectory -OutputRoot $TestDrive
        $captureContext = New-WinPushCaptureContext -RunDirectory $runDirectory -Operation 'RunCommand' -Transport 'Psrp'
        $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName 'PC-001'
        $summaryPath = Join-Path -Path $runDirectory -ChildPath 'summary.csv'

        Test-Path -LiteralPath $summaryPath | Should Be $false
        $null = Write-WinPushCommandOutputArtifact `
            -OutputRoot $TestDrive `
            -RunDirectory $runDirectory `
            -ComputerName 'PC-001' `
            -Operation 'RunCommand' `
            -Transport 'Psrp' `
            -Succeeded $true `
            -ExitCode 0 `
            -Output 'done'

        @(Import-Csv -LiteralPath $summaryPath).Count | Should Be 1
    }

    It 'suppresses later writes only to an artifact that fails mid-stream' {
        $runDirectory = New-WinPushArtifactRunDirectory -OutputRoot $TestDrive
        $captureContext = New-WinPushCaptureContext -RunDirectory $runDirectory -Operation 'RunCommand' -Transport 'Psrp'
        $null = Start-WinPushCaptureTarget -Context $captureContext -ComputerName 'PC-001'
        Remove-Item -LiteralPath $captureContext.ResultPath -Force
        $null = New-Item -Path $captureContext.ResultPath -ItemType Directory

        Write-WinPushCaptureRecord -Context $captureContext -Type Output -Value 'fails locally'
        $firstError = $captureContext.ArtifactError
        Write-WinPushCaptureRecord -Context $captureContext -Type Output -Value 'still reaches root'

        $captureContext.ArtifactError | Should Be $firstError
        $captureContext.FailedArtifacts.ContainsKey($captureContext.ResultPath) | Should Be $true
        (Get-Content -LiteralPath $captureContext.RootLogPath -Raw) | Should Match 'still reaches root'
    }

    It 'streams native callbacks while retaining identical output arrays' {
        $callbackOutput = [System.Collections.Generic.List[string]]::new()
        $callbackErrors = [System.Collections.Generic.List[string]]::new()
        $executable = (Get-Process -Id $PID).Path
        $result = Invoke-WinPushNativeProcess `
            -FilePath $executable `
            -ArgumentList @('-NoProfile', '-Command', 'Write-Output native-output; [Console]::Error.WriteLine("native-error")') `
            -TimeoutSeconds 30 `
            -OutputCallback { param($line) $callbackOutput.Add($line) } `
            -ErrorCallback { param($line) $callbackErrors.Add($line) }

        ($callbackOutput.ToArray() -join ',') | Should Be ($result.StandardOutput -join ',')
        ($callbackErrors.ToArray() -join ',') | Should Be ($result.StandardError -join ',')
    }
}
