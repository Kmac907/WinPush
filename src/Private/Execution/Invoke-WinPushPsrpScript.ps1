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
        $null = Invoke-Command `
                -Session $Session `
                -FilePath $FilePath `
                -OutVariable output `
                -ErrorVariable invokeErrors `
                -ErrorAction SilentlyContinue
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
