function Invoke-WinPushPsExecCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $Command,

        [AllowNull()]
        [string] $PsExecPath
    )

    $resolvedPsExecPath = Resolve-WinPushPsExecPath -PsExecPath $PsExecPath

    $nativeResult = Invoke-WinPushNativeProcess `
        -FilePath $resolvedPsExecPath `
        -ArgumentList @(
            ('\\{0}' -f $ComputerName)
            $Command
        )

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsExecCommandResult'
        PsExecPath = $resolvedPsExecPath
        ExitCode   = $nativeResult.ExitCode
        Output     = @(ConvertTo-WinPushPsExecTextArray -Text $nativeResult.StandardOutput)
        Errors     = @(ConvertTo-WinPushPsExecTextArray -Text $nativeResult.StandardError)
    }
}

function Resolve-WinPushPsExecPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $PsExecPath
    )

    if (-not [string]::IsNullOrWhiteSpace($PsExecPath)) {
        $resolvedItem = Get-Item -LiteralPath $PsExecPath -ErrorAction SilentlyContinue

        if ($null -eq $resolvedItem) {
            throw [System.IO.FileNotFoundException]::new(('PsExec executable was not found: {0}' -f $PsExecPath))
        }

        if ($resolvedItem.PSIsContainer) {
            throw [System.ArgumentException]::new(('PsExec path must be a file: {0}' -f $resolvedItem.FullName))
        }

        if (-not $resolvedItem.Name.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw [System.ArgumentException]::new(('PsExec path must reference an .exe file: {0}' -f $resolvedItem.FullName))
        }

        return $resolvedItem.FullName
    }

    $discoveredCommand = Get-Command -Name 'PsExec.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $discoveredCommand -or [string]::IsNullOrWhiteSpace($discoveredCommand.Source)) {
        throw [System.IO.FileNotFoundException]::new('PsExec.exe was not found. Supply -PsExecPath or add PsExec.exe to PATH.')
    }

    return $discoveredCommand.Source
}

function ConvertTo-WinPushPsExecTextArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = @($normalized -split "`n")

    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = @($lines[0..($lines.Count - 2)])
    }

    return $lines
}
