<#
.SYNOPSIS
Exports Entra group device names to a WinPush host file.

.DESCRIPTION
Uses an existing authenticated Microsoft Graph context to resolve a group by ID or exact display name, filters its device members, removes duplicate display names case-insensitively, and writes the resulting host file as UTF-8.

.PARAMETER GroupId
The Entra group ID. This parameter is mutually exclusive with GroupName.

.PARAMETER GroupName
The exact Entra group display name. The command fails when the name is missing or ambiguous. This parameter is mutually exclusive with GroupId.

.PARAMETER OutputPath
The host file to create or update.

.PARAMETER IncludeDisabled
Includes disabled device objects. Disabled devices are excluded by default.

.PARAMETER Append
Appends only names not already present in the output file, compared case-insensitively. Without this switch, the file is replaced.

.PARAMETER PassThru
Returns only the device names written by this invocation.

.PARAMETER Transitive
Uses flattened transitive group membership instead of direct membership.

.EXAMPLE
Export-WinPushHostFileFromEntraGroup -GroupName 'Windows Pilot Devices' -OutputPath .\hosts.txt

Writes enabled direct device members of the named group to hosts.txt.

.EXAMPLE
Export-WinPushHostFileFromEntraGroup -GroupId $GroupId -OutputPath .\hosts.txt -Transitive -Append -PassThru

Appends unique enabled transitive device members and returns the newly written names.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String when PassThru is used. Otherwise the command produces no pipeline output.

.NOTES
Microsoft Graph is optional and is not loaded when WinPush imports. Get-MgContext and the applicable group commands must already be available.

.LINK
docs/examples.md#export-entra-devices
#>
function Export-WinPushHostFileFromEntraGroup {
    [CmdletBinding(DefaultParameterSetName = 'GroupId')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'GroupId', Position = 0)]
        [string] $GroupId,

        [Parameter(Mandatory, ParameterSetName = 'GroupName', Position = 0)]
        [string] $GroupName,

        [Parameter(Mandatory, Position = 1)]
        [string] $OutputPath,

        [switch] $IncludeDisabled,

        [switch] $Append,

        [switch] $PassThru,

        [switch] $Transitive
    )

    $groupValue = if ($PSCmdlet.ParameterSetName -eq 'GroupName') { $GroupName } else { $GroupId }
    if ([string]::IsNullOrWhiteSpace($groupValue)) {
        throw "$($PSCmdlet.ParameterSetName) must not be empty."
    }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        throw 'OutputPath must not be empty.'
    }

    $memberCommand = if ($Transitive) { 'Get-MgGroupTransitiveMember' } else { 'Get-MgGroupMember' }
    $requiredCommands = @('Get-MgContext', $memberCommand)
    if ($PSCmdlet.ParameterSetName -eq 'GroupName') {
        $requiredCommands += 'Get-MgGroup'
    }

    foreach ($requiredCommand in $requiredCommands) {
        if ($null -eq (Get-Command -Name $requiredCommand -ErrorAction SilentlyContinue)) {
            throw "Required Microsoft Graph command '$requiredCommand' is not available."
        }
    }

    if ($null -eq (Get-MgContext -ErrorAction Stop)) {
        throw 'No authenticated Microsoft Graph context is available. Connect with Connect-MgGraph first.'
    }

    $resolvedGroupId = $GroupId
    if ($PSCmdlet.ParameterSetName -eq 'GroupName') {
        $escapedGroupName = $GroupName.Replace("'", "''")
        $groups = @(Get-MgGroup -Filter "displayName eq '$escapedGroupName'" -All -ErrorAction Stop)
        if ($groups.Count -eq 0) {
            throw "No Entra group named '$GroupName' was found."
        }
        if ($groups.Count -gt 1) {
            throw "More than one Entra group named '$GroupName' was found; use GroupId."
        }
        $resolvedGroupId = $groups[0].Id
    }

    $members = if ($Transitive) {
        @(Get-MgGroupTransitiveMember -GroupId $resolvedGroupId -All -ErrorAction Stop)
    }
    else {
        @(Get-MgGroupMember -GroupId $resolvedGroupId -All -ErrorAction Stop)
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $members) {
        $additionalPropertiesProperty = $member.PSObject.Properties['AdditionalProperties']
        if ($null -eq $additionalPropertiesProperty) {
            continue
        }

        $additionalProperties = $additionalPropertiesProperty.Value
        if ($null -eq $additionalProperties) {
            continue
        }
        if ($additionalProperties['@odata.type'] -ne '#microsoft.graph.device') {
            continue
        }
        if ($null -eq $additionalProperties['displayName'] -or $null -eq $additionalProperties['accountEnabled']) {
            throw 'Microsoft Graph returned incomplete device properties. Reconnect with Device.Read.All permission.'
        }

        $displayName = [string] $additionalProperties['displayName']
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            continue
        }
        if (-not $IncludeDisabled -and $additionalProperties['accountEnabled'] -eq $false) {
            continue
        }

        $displayName = $displayName.Trim()
        if ($seenNames.Add($displayName)) {
            [void] $names.Add($displayName)
        }
    }

    $writtenNames = [System.Collections.Generic.List[string]]::new()
    if ($Append -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        $existingNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($existingName in @(Get-Content -LiteralPath $OutputPath)) {
            [void] $existingNames.Add($existingName)
        }

        foreach ($name in $names) {
            if ($existingNames.Add($name)) {
                [void] $writtenNames.Add($name)
            }
        }

        if ($writtenNames.Count -gt 0) {
            Add-Content -LiteralPath $OutputPath -Value $writtenNames.ToArray() -Encoding utf8
        }
    }
    else {
        Set-Content -LiteralPath $OutputPath -Value $names.ToArray() -Encoding utf8
        foreach ($name in $names) {
            [void] $writtenNames.Add($name)
        }
    }

    if ($PassThru) {
        $writtenNames.ToArray()
    }
}
