function Resolve-WinPushTarget {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [string[]] $ComputerName
    )

    begin {
        $resolvedTargets = [System.Collections.Generic.List[string]]::new()
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
