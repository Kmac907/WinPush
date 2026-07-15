function Invoke-WinPushPsrpCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    $remoteScriptBlock = {
        param(
            [Parameter(Mandatory)]
            [string] $CommandText
        )

        $scriptBlock = [scriptblock]::Create($CommandText)

        try {
            & $scriptBlock 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    [pscustomobject] [ordered] @{
                        Stream = 'Error'
                        Value  = [string] $_
                    }
                }
                else {
                    [pscustomobject] [ordered] @{
                        Stream = 'Output'
                        Value  = $_
                    }
                }
            }
        }
        catch {
            [pscustomobject] [ordered] @{
                Stream = 'Error'
                Value  = [string] $_
            }
        }
    }

    $streamItems = @(Invoke-Command `
            -Session $Session `
            -ScriptBlock $remoteScriptBlock `
            -ArgumentList $ScriptBlock.ToString() `
            -ErrorAction Stop)

    $output = foreach ($item in $streamItems) {
        if ($item.Stream -eq 'Output') {
            $item.Value
        }
    }

    $errors = foreach ($item in $streamItems) {
        if ($item.Stream -eq 'Error') {
            $item.Value
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsrpCommandResult'
        Output     = @($output)
        Errors     = @($errors)
    }
}
