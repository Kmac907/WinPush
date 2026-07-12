function Invoke-WinPushCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [string] $Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw [System.ArgumentException]::new('Command text must not be empty.')
    }

    $targets = @(Resolve-WinPushTarget -ComputerName $ComputerName)
    $target = $targets[0]
    $session = $null

    try {
        $session = New-PSSession -ComputerName $target -ErrorAction Stop
        $scriptBlock = [scriptblock]::Create($Command)
        $output = @(Invoke-WinPushPsrpCommand -Session $session -ScriptBlock $scriptBlock)

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'RunCommand' `
            -Succeeded $true `
            -ExitCode 0 `
            -Output $output
    }
    catch {
        $errorMessage = $_.Exception.Message

        New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'RunCommand' `
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
