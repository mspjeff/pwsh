#Requires -Version 7.4
#Requires -RunAsAdministrator
#Requires -Modules Microsoft.WinGet.Client

<#
    .SYNOPSIS
        Performs an update
    .DESCRIPTION
        Check it out
    .EXAMPLE
        PS C:\> Invoke-3PPUpdate.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/3pp/Invoke-3PPUpdate.ps1 | iex
#>

[CmdletBinding()]
param(

    [Parameter()]
    [string]
    $DefinitionUrl = $env:3PP_DEFINITIONURI,

    [Parameter()]
    [string]
    $ApiBaseUrl = 'https://operation-slept.pockethost.io',

    [Parameter()]
    [switch]
    $Remediate
)

function Send-Results
{
    param (
        [Parameter(Mandatory)]
        [string]
        $Payload
    )

    $response = Invoke-RestMethod `
        -Uri "$ApiBaseUrl/api/collections/3ppaudits/records" `
        -ContentType 'application/json' `
        -Method Post `
        -Body $Payload
}

function Get-ComputerId
{
    $machineGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid").MachineGuid
    $byteArray = [System.Text.Encoding]::UTF8.GetBytes($machineGuid)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($byteArray)
    $chars = '0123456789abcdefghijklmnopqrstuvwxyz'
    $bigInteger = [System.Numerics.BigInteger]::Parse("0" + ([BitConverter]::ToString($hashBytes) -replace '-'), 'AllowHexSpecifier')
    $result = ""
    while ($bigInteger -gt 0)
    {
        $remainder = [int]($bigInteger % 36)
        $bigInteger = [System.Numerics.BigInteger]::Divide($bigInteger, 36)
        $result = $chars[$remainder] + $result
    }
    $result.Substring(0,15)
}

if ($DefinitionUrl.Length -eq 0)
{
    Write-Warning "You're missing the 3PP_DEFINITIONURI environment variable!"
    return
}

Write-Host "Loading application definitions from $DefinitionUrl"
$defs = (Invoke-RestMethod -Uri $DefinitionUrl) -split "`n"
if ($defs.Length -le 0)
{
    Write-Warning "No definitions found"
    return
}

#
# we assume that the client is compliant and will mark the client as not
# compliant if any of the package definitions are missing from the client
# or if any are not up to date
#
$compliant = $true

$packages = @()
foreach ($def in $defs)
{
    #
    # check against an empty or blank definition which will end up pulling
    # the list of all installed applications on the client which is not at
    # all what we want - if we find a blank then we skip it
    if ($def.Length -le 0)
    {
        continue
    }

    #
    # this gets the installed package information and will return null if
    # the package is not installed on the client - this is not a search for
    # available packages but a search for a specific package that is installed
    # on this computer
    #
    $package = Get-WinGetPackage -Id $def -Source 'winget' -MatchOption Equals

    if (-not $package)
    {
        #
        # the package is not installed on the local computer so we're going to
        # try to find if such a package is available for installation so that
        # we can report the name and version info or attempt to install it if
        # we are remediating
        #
        $package = Find-WinGetPackage -Id $def -Source 'winget' -MatchOption Equals

        if (-not $package)
        {
            #
            # not only is no such package installed but the package isn't even
            # a real package identifier so we're going to bail out on this
            # package at this point
            continue
        }
    }

    if ($package)
    {
        #
        # we know 
        if ($package.IsUpdateAvailable)
        {
            $compliant = $false
        }

        $status = $package.IsUpdateAvailable `
            ? 'update needed' `
            : 'current'

        $color = $package.IsUpdateAvailable `
            ? [System.ConsoleColor]::Gray `
            : [System.ConsoleColor]::Green

        $icon = $package.IsUpdateAvailable `
            ? [char]0x26A0 `
            : [char]0x2713

        Write-Host ($icon + " $($package.Name) ($status)") -ForegroundColor $color

        $packages += @{
            PackageId = $package.Id
            Name = $package.Name
            Source = $package.Source
            Version = $package.InstalledVersion
            Latest = $package.AvailableVersions | Select-Object -First 1
            IsUpdateAvailable = $package.IsUpdateAvailable
        }
    } else
    {
        $compliant = $false
        $package = Find-WinGetPackage -Id $def -Source 'winget' -MatchOption Equals
        if ($package)
        {
            $packages += @{
                PackageId = $package.Id
                Name = $package.Name
                Source = $package.Source
                Version = ''
                Latest = $package.AvailableVersions | Select-Object -First 1
                IsUpdateAvailable = $true
            }
            Write-Host ([char]0x26A0 + " $($package.Name) (missing)") -ForegroundColor Yellow
        }
    }
}

$generated = (Get-Date).ToUniversalTime()
$computerId = Get-ComputerId
$computerInfo = Get-ComputerInfo
$payload = @{
    computerid = $computerId
    generated = $generated.ToString("yyyy-MM-dd HH:mm:ss.fff") + "Z"
    name = $computerInfo.CsName
    type = $computerInfo.CsPCSystemType.ToString()
    domain = $computerInfo.CsDomain
    mfg = $computerInfo.CsManufacturer
    model = $computerInfo.CsModel
    serial = $computerInfo.BiosSerialNumber
    asset = ''
    osname = $computerInfo.OsName
    osarch = $computerInfo.OsArchitecture
    compliant = $compliant
    packages = $packages
}

#Write-Host ($payload | ConvertTo-Json)

Send-Results -Payload ($payload | ConvertTo-Json)

Write-Host 'Done'
