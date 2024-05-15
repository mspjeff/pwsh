<#
    .SYNOPSIS
        Starts the Windows Exporter for surfacing metrics to Prometheus.
    .DESCRIPTION
        This script starts an instance of the Windows Exporter with the
        appropriate machine-specific collectors enabled without having to
        manually specify the enabled collector list.
    .EXAMPLE
        PS C:\> Start-WindowsExporter
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Start-WindowsExporter.ps1 | iex
    .LINK
        https://github.com/prometheus-community/windows_exporter
  #>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string][ValidateNotNullOrEmpty()]
    $WebListenAddress = ":9182",

    [Parameter(Mandatory=$false)]
    [string][ValidateNotNullOrEmpty()]
    $ExecutablePath = "$env:ProgramData\Prometheus\windows_exporter-0.25.1-amd64.exe",

    [Parameter(Mandatory=$false)]
    [switch]
    $NoStart = $false
)

function Get-Executable
{
    $filename = "windows_exporter-0.25.1-amd64.exe"
    $sourceUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.25.1/$filename"
    $destinationPath = Split-Path -Path $ExecutablePath
    if (-not (Test-Path $ExecutablePath))
    {
        if (-not (Test-Path $destinationPath))
        {
            Write-Information "Creating $destinationPath"
            New-Item -ItemType Directory -Path $destinationPath | Out-Null
        }
        Write-Information "Downloading $filename from $sourceUrl"
        Start-BitsTransfer -Source $sourceUrl -Destination $ExecutablePath
    }
}

function Get-Collectors
{
    $collectors = @(
        'cpu',
        'cs',
        'logical_disk',
        'net',
        'os',
        'system'
    )

    $serviceToCollectorHash = @{
        ntds = 'ad'
        dfsr = 'dfsr'
        dhcpserver = 'dhcp'
        dns = 'dns'
        vmms = 'hyperv'
        w3svc = 'iis'
        mssqlserver = 'mssql'
        termservice = 'terminal_services'
    }

    foreach ($key in $serviceToCollectorHash.Keys)
    {
        if ((Get-Service $key -ErrorAction SilentlyContinue).Status -eq 'Running')
        {
            $collectors += $serviceToCollectorHash[$key]
        }
    }

    return $collectors -join ','
}

function Get-Services
{
    $candidates = @{
        "NTDS" = @(
            "NTDS",    # Active Directory Domain Services
            "DNS",     # DNS Server
            "kdc",     # Kerberos Key Distribution Center
            "Netlogon",# Net Logon
            "IsmServ", # Intersite Messaging
            "NtFrs",   # File Replication Service
            "DFSR"     # Distributed File System Replication
        )
    }

    $services = @()

    foreach ($key in $candidates.Keys)
    {
        if ((Get-Service $key -ErrorAction SilentlyContinue).Status -eq 'Running')
        {
            $services += $candidates[$key]
        }
    }

    return ($services | ForEach-Object { "Name='$_'" }) -join " OR "
}

$InformationPreference = 'Continue'

Get-Executable
Write-Information "Executable to run: '$ExecutablePath'"

$collectors = Get-Collectors
Write-Information "Collectors to be enabled are: '$collectors'"

$services = Get-Services
Write-Information "Services to be enabled are: '$services'"

if (-not $NoStart)
{
    Write-Information "Starting '$ExecutablePath'"
    & $ExecutablePath --collectors.enabled "$collectors"
}
