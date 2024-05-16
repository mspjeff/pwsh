<#
    .SYNOPSIS
        Downloads and starts the Windows Exporter
    .DESCRIPTION
        This script downloads the Windows Exporter that surfaces Prometheus
        metrics at http://<hostname>:9182/metrics. A scheduled task is created
        that starts the exporter at system startup. The task is automatically
        started at the end of this script. The collector list is dynamically
        created at script runtime based on the Windows services that exist and
        are running at the time the script is run.
    .EXAMPLE
        PS C:\> New-PrometheusWindowsExporter.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/New-PrometheusWindowsExporter.ps1 | iex
    .LINK
        https://prometheus.io
    .LINK
        https://github.com/prometheus-community/windows_exporter
  #>

[CmdletBinding()]
param(

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $WindowsExporterSource = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.25.1/windows_exporter-0.25.1-amd64.exe",

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $TargetFolder = "C:\ProgramData\Prometheus",

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $TargetExecutable = "windows_exporter-amd64.exe",
 
    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $TaskName = "Start Prometheus Windows Exporter"
)

if (-not (Test-Path $TargetFolder))
{
    Write-Output "[+] Creating $TargetFolder"
    New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null
}

if (-not (Test-Path (Join-Path $TargetFolder $TargetExecutable)))
{
    Write-Output "[+] Downloading $($WindowsExporterSource.Substring(0, 60))..."

    #
    # workaround for older powershell versions that do not default to using
    # TLS 1.2 or later causing requests to some sites (including github) to
    # fail
    #
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Invoke-WebRequest `
        -Uri $WindowsExporterSource `
        -OutFile (Join-Path $TargetFolder $TargetExecutable)
}

#
# list of collectors that we enable by default
#
$collectors = @(
    'cpu',
    'cs',
    'logical_disk',
    'net',
    'os',
    'system'
)

#
# list of collectors that we optionally enable depeneding on whether the
# specified Windows service is installed; for example, if the ntds service
# is installed and running then we enable the active directory collector
#
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

#
# check to see if we already have a scheduled task and stop it
#
if ($existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
{
    Write-Output "[!] Stopping existing scheduled task"
    $existingTask | Stop-ScheduledTask
}

$action = New-ScheduledTaskAction `
    -Execute (Join-Path $TargetFolder $TargetExecutable) `
    -Argument "--collectors.enabled $($collectors -join ',')" `
    -WorkingDirectory $TargetFolder

$trigger = New-ScheduledTaskTrigger `
    -AtStartup

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit '00:00:00' `
    -RestartCount 3 `
    -RestartInterval '00:05:00'

$task = New-ScheduledTask `
    -Action $action `
    -Principal $principal `
    -Trigger $trigger `
    -Settings $settings

Register-ScheduledTask `
    -TaskName "$TaskName" `
    -InputObject $task `
    -Force | Out-Null 

Start-ScheduledTask `
    -TaskName "$TaskName"

#
# if everything worked as expected then the exporter should be running
# and providing health information at http://localhost:9182/health
#
if (-not ((Invoke-WebRequest http://localhost:9182/health).StatusCode -eq 200))
{
    Write-Warning "Windows Exporter does not appear to be providing health info"
    return
}

Write-Output "[*] Listening at http://localhost:9182/metrics"