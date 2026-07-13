function Invoke-WinPushPsrpScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $FilePath
    )

    $invokeErrors = @()
    $output = @()

    try {
        $output = @(Invoke-Command `
                -Session $Session `
                -FilePath $FilePath `
                -ErrorVariable invokeErrors `
                -ErrorAction SilentlyContinue)
    }
    catch {
        $invokeErrors += $_
    }

    $errors = foreach ($errorRecord in @($invokeErrors)) {
        [string] $errorRecord
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsrpScriptResult'
        Output     = @($output)
        Errors     = @($errors)
    }
}
