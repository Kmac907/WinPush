function Test-WinPushRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DetectScript,

        [Parameter(Mandatory)]
        [string] $RemediateScript
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $resolvedPaths = [ordered] @{}
    $parserResults = @{}
    $windowsPowerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $parserSource = @'
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PATH__'))
$tokens = $null
$parseErrors = $null

try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $parseErrors)
}
catch {
    $parseErrors = @([pscustomobject] @{ ErrorId = 'FileReadError'; Message = $_.Exception.Message; Extent = $null })
}

$errors = @($parseErrors | ForEach-Object {
    [pscustomobject] @{
        ErrorId = $_.ErrorId
        Message = $_.Message
        Line = if ($null -eq $_.Extent) { 0 } else { $_.Extent.StartLineNumber }
        Column = if ($null -eq $_.Extent) { 0 } else { $_.Extent.StartColumnNumber }
    }
})
$exitCodes = @()
$rebootCommands = @()

if ($errors.Count -eq 0) {
    $exitCodes = @($ast.FindAll({
        param($node)

        $node -is [System.Management.Automation.Language.ExitStatementAst] -and
        $null -ne $node.Pipeline -and
        $node.Pipeline.PipelineElements.Count -eq 1 -and
        $node.Pipeline.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst] -and
        $node.Pipeline.PipelineElements[0].Expression.Extent.Text -match '^[01]$'
    }, $true) | ForEach-Object { [int] $_.Pipeline.PipelineElements[0].Expression.Extent.Text })

    $rebootCommands = @($ast.FindAll({
        param($node)

        if ($node -isnot [System.Management.Automation.Language.CommandAst]) {
            return $false
        }

        $commandName = $node.GetCommandName()
        ($commandName -match '(^|\\)Restart-Computer$') -or
        ($commandName -match '(^|\\)shutdown(?:\.exe)?$' -and $node.Extent.Text -match '(?i)(?:^|\s)[/-](?:r|g|sg)(?:\s|$)')
    }, $true) | ForEach-Object {
        [pscustomobject] @{ Line = $_.Extent.StartLineNumber; Text = $_.Extent.Text }
    })
}

[pscustomobject] @{ Errors = $errors; ExitCodes = $exitCodes; RebootCommands = $rebootCommands } |
    ConvertTo-Json -Compress -Depth 4
'@

    foreach ($scriptInput in @(
            [pscustomobject] @{ Name = 'DetectScript'; Path = $DetectScript }
            [pscustomobject] @{ Name = 'RemediateScript'; Path = $RemediateScript }
        )) {
        try {
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($scriptInput.Path)
        }
        catch {
            $errors.Add("$($scriptInput.Name) path is invalid: '$($scriptInput.Path)'.")
            $resolvedPaths[$scriptInput.Name] = $null
            continue
        }

        $resolvedPaths[$scriptInput.Name] = $resolvedPath

        if ([System.IO.Directory]::Exists($resolvedPath)) {
            $errors.Add("$($scriptInput.Name) must be a .ps1 file, but a directory was provided: '$resolvedPath'.")
            continue
        }

        if (-not [System.IO.File]::Exists($resolvedPath)) {
            $errors.Add("$($scriptInput.Name) was not found: '$resolvedPath'.")
            continue
        }

        if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.ps1') {
            $errors.Add("$($scriptInput.Name) must have a .ps1 extension: '$resolvedPath'.")
            continue
        }

        $encodedPath = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($resolvedPath))
        $encodedCommand = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($parserSource.Replace('__PATH__', $encodedPath))
        )
        $parserOutput = @(& $windowsPowerShell -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1)

        if ($LASTEXITCODE -ne 0) {
            $errors.Add("$($scriptInput.Name) could not be parsed by Windows PowerShell 5.1: '$resolvedPath'. $($parserOutput -join ' ')")
            continue
        }

        try {
            $parserResult = ($parserOutput -join "`n") | ConvertFrom-Json
        }
        catch {
            $errors.Add("$($scriptInput.Name) could not be parsed by Windows PowerShell 5.1: '$resolvedPath'. $($_.Exception.Message)")
            continue
        }

        $parseErrors = @($parserResult.Errors)
        $fileReadError = @($parseErrors | Where-Object { $_.ErrorId -eq 'FileReadError' } | Select-Object -First 1)
        if ($fileReadError.Count -gt 0) {
            $errors.Add("$($scriptInput.Name) could not be read: '$resolvedPath'. $($fileReadError[0].Message)")
            continue
        }

        foreach ($parseError in $parseErrors) {
            $errors.Add("$($scriptInput.Name) has a Windows PowerShell 5.1 parser error at line $($parseError.Line), column $($parseError.Column): $($parseError.Message)")
        }

        if ($parseErrors.Count -eq 0) {
            $parserResults[$scriptInput.Name] = $parserResult
        }
    }

    if ($parserResults.ContainsKey('DetectScript')) {
        foreach ($exitCode in @(0, 1)) {
            if (@($parserResults['DetectScript'].ExitCodes) -notcontains $exitCode) {
                $warnings.Add("DetectScript does not contain a literal 'exit $exitCode' path.")
            }
        }
    }

    foreach ($scriptName in @('DetectScript', 'RemediateScript')) {
        if (-not $parserResults.ContainsKey($scriptName)) {
            continue
        }

        foreach ($command in @($parserResults[$scriptName].RebootCommands)) {
            $warnings.Add("$scriptName contains a reboot command at line $($command.Line): $($command.Text)")
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName          = 'WinPush.RemediationValidationResult'
        IsValid             = $errors.Count -eq 0
        DetectScriptPath    = $resolvedPaths['DetectScript']
        RemediateScriptPath = $resolvedPaths['RemediateScript']
        Errors              = [string[]] $errors.ToArray()
        Warnings            = [string[]] $warnings.ToArray()
    }
}
