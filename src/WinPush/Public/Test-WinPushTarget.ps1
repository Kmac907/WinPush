function Test-WinPushTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateCount(1, 1)]
        [string[]] $ComputerName
    )

    $target = @(Resolve-WinPushTarget -ComputerName $ComputerName)[0]
    $session = $null

    try {
        $session = New-PSSession -ComputerName $target -ErrorAction Stop

        return New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'TestTarget' `
            -Succeeded $true `
            -ExitCode $null
    }
    catch {
        $errorMessage = $_.Exception.Message

        return New-WinPushExecutionResult `
            -ComputerName $target `
            -Transport 'Psrp' `
            -Operation 'TestTarget' `
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
