function Resolve-WinPushTarget {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName,

        [string] $HostFile
    )

    begin {
        $resolvedTargets = [System.Collections.Generic.List[string]]::new()

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

                $resolvedTargets.Add($trimmedLine)
            }
        }
    }

    process {
        foreach ($target in @($ComputerName)) {
            if ([string]::IsNullOrWhiteSpace($target)) {
                continue
            }

            $trimmedTarget = $target.Trim()
            if ($trimmedTarget.Length -gt 0) {
                $resolvedTargets.Add($trimmedTarget)
            }
        }
    }

    end {
        if ($resolvedTargets.Count -eq 0) {
            throw [System.ArgumentException]::new('At least one usable computer name is required.')
        }

        return $resolvedTargets.ToArray()
    }
}
