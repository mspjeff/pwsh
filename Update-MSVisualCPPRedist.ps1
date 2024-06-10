#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    .SYNOPSIS
        Updates to latest version of redist
    .DESCRIPTION
        This script exists because some RMM systems have a hard time with
        patching this particular component. Run 
    .EXAMPLE
        PS C:\> Update-MSVisualCPPRedist.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Update-MSVisualCPPRedist.ps1 | iex
    .LINK
        https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist
  #>

[CmdletBinding()]
param(

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $BaseUri = "https://aka.ms/vs/17/release"
)

Push-Location "$env:temp"
@('vc_redist.x64.exe', 'vc_redist.x86.exe') | ForEach-Object {
    Write-Host "Silently installing $_"
    $source = "$BaseUri/$_"
    Start-BitsTransfer -Source $source -Destination ".\$_"
    & ".\$_" --% /q /norestart
}
Pop-Location
Write-Host "Done"
