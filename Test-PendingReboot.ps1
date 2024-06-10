#Requires -Version 5.1

<#
    .SYNOPSIS
        Checks if local machine is pending reboot
    .DESCRIPTION
        Intended to be run following the installation of patches, this script
        will check known registry locations that indicate when a reboot is
        pending and will return true if any of the conditions exist.
    .EXAMPLE
        PS C:\> Test-PendingReboot.ps1 -Verbose
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Test-PendingReboot.ps1 | iex
#>

[CmdletBinding()]
param(
)

function Test-RegistryKey
{
    [OutputType('bool')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Key
    )

    $ErrorActionPreference = 'Stop'

    if (Get-Item -Path $Key -ErrorAction Ignore)
    {
        $true
    }
}

function Test-RegistryValueNotNull
{
    [OutputType('bool')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Key,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Value
    )

    $ErrorActionPreference = 'Stop'

    if (($val = Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) -and $val.($Value))
    {
        $true
    }
}

$tests = @(
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
    { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' }
    { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending' }
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting' }
)

foreach ($test in $tests)
{
    if (& $test)
    {
        Write-Verbose "Pending reboot because of $test"
        $true
        break
    }
}
