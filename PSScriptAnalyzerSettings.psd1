@{
    # New-WinPush* private helpers are object factories, not state-changing commands.
    # Unit tests intentionally use stable placeholder ComputerName values.
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingComputerNameHardcoded'
    )

    Severity = @(
        'Error'
        'Warning'
    )
}
