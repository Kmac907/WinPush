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
            '-h'
            'cmd.exe'
            '/d'
            '/s'
            '/c'
            $Command
        )

    $succeeded = $nativeResult.ExitCode -eq 0

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsExecCommandResult'
        PsExecPath = $resolvedPsExecPath
        ExitCode   = $nativeResult.ExitCode
        Output     = @(ConvertTo-WinPushPsExecTextArray -Text $nativeResult.StandardOutput)
        Errors     = @(ConvertTo-WinPushPsExecErrorArray -Text $nativeResult.StandardError -Succeeded $succeeded -ComputerName $ComputerName)
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

function ConvertTo-WinPushPsExecErrorArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Text,

        [bool] $Succeeded,

        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    $lines = @(ConvertTo-WinPushPsExecTextArray -Text $Text)

    $filteredLines = foreach ($line in $lines) {
        if ($Succeeded -and [string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if (-not (Test-WinPushPsExecInformationalLine -Line $line -ComputerName $ComputerName)) {
            $line
        }
    }

    return @($filteredLines)
}

function Test-WinPushPsExecInformationalLine {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Line,

        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $false
    }

    $trimmedLine = $Line.Trim()
    $escapedComputerName = [regex]::Escape($ComputerName)

    if ($trimmedLine -match '(?i)^PsExec v[\d.]+') {
        return $true
    }

    if ($trimmedLine -match '(?i)^Copyright \(C\)') {
        return $true
    }

    if ($trimmedLine -match '(?i)^Sysinternals - www\.sysinternals\.com$') {
        return $true
    }

    foreach ($pattern in @(
            '(?i)^Connecting to {0}\.\.\.$',
            '(?i)^Starting PSEXESVC service on {0}\.\.\.$',
            '(?i)^Connecting with PsExec service on {0}\.\.\.$',
            '(?i)^Starting .+ on {0}\.\.\.$',
            '(?i)^.+ exited on {0} with error code 0\.$'
        )) {
        if ($trimmedLine -match ($pattern -f $escapedComputerName)) {
            return $true
        }
    }

    return $false
}
