function Invoke-WinPushPsrpScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [Parameter(Mandatory)]
        [string] $FilePath
    )

    $output = @()
    $errors = [System.Collections.Generic.List[string]]::new()
    $activeCaptureContext = if (Get-Command -Name Get-WinPushActiveCaptureContext -ErrorAction SilentlyContinue) {
        Get-WinPushActiveCaptureContext
    }

    try {
        Invoke-Command `
            -Session $Session `
            -FilePath $FilePath `
            -OutVariable output `
            -ErrorAction Continue 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $errors.Add([string] $_)
                if ($null -ne $activeCaptureContext) {
                    Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Error -Value $_
                }
            }
            else {
                if ($null -ne $activeCaptureContext) {
                    Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Output -Value $_
                }
            }
        }
    }
    catch {
        $errors.Add([string] $_)
        if ($null -ne $activeCaptureContext) {
            Write-WinPushCaptureRecord -Context $activeCaptureContext -Type Error -Value $_
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'WinPush.PsrpScriptResult'
        Output     = @($output)
        Errors     = $errors.ToArray()
    }
}
