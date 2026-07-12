function Invoke-WinPushCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $Command,

        [switch] $CaptureOutput,

        [string] $OutputRoot = 'C:\WinPush'
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw [System.ArgumentException]::new('Command text must not be empty.')
    }

    if ($CaptureOutput -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
        throw [System.ArgumentException]::new('OutputRoot must not be empty.')
    }

    $targets = @(Resolve-WinPushTarget -ComputerName $ComputerName)
    $target = $targets[0]
    $session = $null
    $runDirectory = $null
    $computerDirectory = $null
    $stdOutPath = $null
    $stdErrPath = $null

    try {
        $session = New-PSSession -ComputerName $target -ErrorAction Stop
        $scriptBlock = [scriptblock]::Create($Command)
        $output = @(Invoke-WinPushPsrpCommand -Session $session -ScriptBlock $scriptBlock)

        if ($CaptureOutput) {
            $artifact = Write-WinPushCommandOutputArtifact -OutputRoot $OutputRoot -ComputerName $target -Output $output
            $runDirectory = $artifact.RunDirectory
            $computerDirectory = $artifact.ComputerDirectory
            $stdOutPath = $artifact.StdOutPath
            $stdErrPath = $artifact.StdErrPath
        }

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'RunCommand' `
            -Succeeded $true `
            -ExitCode 0 `
            -Output $output `
            -RunDirectory $runDirectory `
            -ComputerDirectory $computerDirectory `
            -StdOutPath $stdOutPath `
            -StdErrPath $stdErrPath
    }
    catch {
        $errorMessage = $_.Exception.Message

        if ($CaptureOutput) {
            $artifact = Write-WinPushCommandOutputArtifact -OutputRoot $OutputRoot -ComputerName $target -Errors $errorMessage
            $runDirectory = $artifact.RunDirectory
            $computerDirectory = $artifact.ComputerDirectory
            $stdOutPath = $artifact.StdOutPath
            $stdErrPath = $artifact.StdErrPath
        }

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'RunCommand' `
            -Succeeded $false `
            -ExitCode 1 `
            -ErrorMessage $errorMessage `
            -Errors $errorMessage `
            -RunDirectory $runDirectory `
            -ComputerDirectory $computerDirectory `
            -StdOutPath $stdOutPath `
            -StdErrPath $stdErrPath
    }
    finally {
        if ($null -ne $session) {
            Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue
        }
    }
}
