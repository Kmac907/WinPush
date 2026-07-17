function Invoke-WinPushPackage {
    [CmdletBinding(DefaultParameterSetName = 'PathComputerName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'PathComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'UriComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'PathHostFile')]
        [Parameter(Mandatory, ParameterSetName = 'UriHostFile')]
        [string] $HostFile,

        [Parameter(Mandatory, ParameterSetName = 'PathComputerName', Position = 1)]
        [Parameter(Mandatory, ParameterSetName = 'PathHostFile', Position = 1)]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'UriComputerName', Position = 1)]
        [Parameter(Mandatory, ParameterSetName = 'UriHostFile', Position = 1)]
        [uri] $Uri,

        [Parameter(Mandatory, Position = 2)]
        [string] $EntryPoint,

        [switch] $Extract,

        [switch] $CaptureOutput,

        [switch] $Logs,

        [ValidateSet('Never', 'OnSuccess', 'Always')]
        [string] $Cleanup = 'Never',

        [string] $OutputRoot = 'C:\WinPush',

        [string] $PackageCacheRoot = 'C:\WinPush\PackageCache',

        [string] $RemoteStageRoot = 'C:\ProgramData\WinPush\Staging',

        [System.Management.Automation.PSCredential] $Credential
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($EntryPoint)) {
            throw [System.ArgumentException]::new('EntryPoint must not be empty.')
        }

        if (($CaptureOutput -or $Logs) -and [string]::IsNullOrWhiteSpace($OutputRoot)) {
            throw [System.ArgumentException]::new('OutputRoot must not be empty.')
        }

        if ($PSBoundParameters.ContainsKey('PackageCacheRoot') -and [string]::IsNullOrWhiteSpace($PackageCacheRoot)) {
            throw [System.ArgumentException]::new('PackageCacheRoot must not be empty.')
        }

        if ($PSBoundParameters.ContainsKey('RemoteStageRoot') -and [string]::IsNullOrWhiteSpace($RemoteStageRoot)) {
            throw [System.ArgumentException]::new('RemoteStageRoot must not be empty.')
        }
    }

    process {
    }

    end {
        throw [System.NotSupportedException]::new('Invoke-WinPushPackage is not exported or executable until package staging is implemented in roadmap item 11.2.')
    }
}
