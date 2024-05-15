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
        PS C:\> iwr https://... | iex
    .LINK
        https://github.com/prometheus-community/windows_exporter
  #>

[CmdletBinding()]
param(
	[Parameter(Mandatory=$false)]
	[string][ValidateNotNullOrEmpty()]
	$WebListenAddress = ":9182",

	[Parameter(Mandatory=$false)]
	[switch]
	$NoStart = $false
)

function Get-WindowsExporterExecutable
{
	$filename = "windows_exporter-0.25.1-amd64.exe"
	$sourceUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.25.1/$filename"
	$destinationPath = Join-Path $env:ProgramData "Prometheus"
	$destinationPathAndFilename = Join-Path $destinationPath $filename
	if (-not (Test-Path $destinationPathAndFilename))
	{
		if (-not (Test-Path $destinationPath))
		{
			Write-Information "Creating $destinationPath"
			New-Item -ItemType Directory -Path $destinationPath
		}
		Write-Information "Downloading $filename from $sourceUrl"
		Start-BitsTransfer -Source $sourceUrl -Destination $destinationPath
	}
	return $destinationPathAndFilename
}

function Get-WindowsExporterCollectors
{
	$collectors = @(
		'cpu',
		'cs',
		'logical_disk',
		'net',
		'os',
		'service',
		'system',
		'textfile'
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

function Get-WindowsExporterServices
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

$executable = Get-WindowsExporterExecutable
Write-Information "Executable to run: $executable"

$collectors = Get-WindowsExporterCollectors
Write-Information "Collectors to be enabled are: $collectors"

$services = Get-WindowsExporterServices
Write-Information "Services to be enabled are: $services"

if (-not $NoStart)
{
	Write-Information "Starting $executable"
	& $executable --collectors.enabled "$collectors"
}
