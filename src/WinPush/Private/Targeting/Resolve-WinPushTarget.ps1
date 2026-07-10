function Resolve-WinPushTarget {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]] $ComputerName
    )

    $resolvedTargets = [System.Collections.Generic.List[string]]::new()

    foreach ($target in @($ComputerName)) {
        if ([string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        $trimmedTarget = $target.Trim()
        if ($trimmedTarget.Length -gt 0) {
            $resolvedTargets.Add($trimmedTarget)
        }
    }

    if ($resolvedTargets.Count -eq 0) {
        throw [System.ArgumentException]::new('At least one usable computer name is required.')
    }

    return $resolvedTargets.ToArray()
}
