function Resolve-WinPushTarget {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(ParameterSetName = 'ComputerName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [Parameter(ParameterSetName = 'HostFile')]
        [string] $HostFile
    )

    begin {
        $resolvedTargets = [System.Collections.Generic.List[string]]::new()
        $seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        function Add-ResolvedTarget {
            param(
                [AllowNull()]
                [string] $Target
            )

            if ([string]::IsNullOrWhiteSpace($Target)) {
                return
            }

            $trimmedTarget = $Target.Trim()
            if ($trimmedTarget.Length -gt 0 -and $seenTargets.Add($trimmedTarget)) {
                $resolvedTargets.Add($trimmedTarget)
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($HostFile)) {
            if (-not (Test-Path -LiteralPath $HostFile)) {
                throw [System.IO.FileNotFoundException]::new("Host file was not found: $HostFile")
            }

            $hostFileItem = Get-Item -LiteralPath $HostFile
            if ($hostFileItem.PSIsContainer) {
                throw [System.ArgumentException]::new("Host file path must reference a file: $HostFile")
            }

            foreach ($line in @(Get-Content -LiteralPath $hostFileItem.FullName -Encoding UTF8)) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                $trimmedLine = $line.Trim()
                if ($trimmedLine.StartsWith('#')) {
                    continue
                }

                Add-ResolvedTarget -Target $trimmedLine
            }
        }
    }

    process {
        foreach ($target in @($ComputerName)) {
            Add-ResolvedTarget -Target $target
        }
    }

    end {
        if ($resolvedTargets.Count -eq 0) {
            throw [System.ArgumentException]::new('At least one usable computer name is required.')
        }

        return $resolvedTargets.ToArray()
    }
}
