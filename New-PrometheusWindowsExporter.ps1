#Requires -Version 5.1
#Requires -RunAsAdministrator

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
    $TargetFolder = "C:\ProgramData\Prometheus",

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $TaskName = "Start Prometheus Windows Exporter",

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $FirewallRuleName = "Allow TCP/9182 Inbound (Windows Exporter)"
)

if (-not (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue))
{
    Write-Output "[+] Creating firewall rule '$FirewallRuleName'"
    New-NetFirewallRule `
        -DisplayName $FirewallRuleName `
        -Description 'Allows access to http://<thismachine>:9182/metrics' `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 9182 `
        -Action Allow `
        -Profile Any | Out-Null
}

if (-not (Test-Path $TargetFolder))
{
    Write-Output "[+] Creating $TargetFolder"
    New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null
}

#
# use github api to determine the latest stable release for windows exporter
# and get the appropriate download url and filename
#
$downloadUrl = Invoke-RestMethod `
    https://api.github.com/repos/prometheus-community/windows_exporter/releases/latest `
| Select-Object -ExpandProperty assets `
| Where-Object { $_.name.EndsWith("-amd64.exe")} `
| Select-Object -ExpandProperty browser_download_url

$filename = Split-Path $downloadUrl -Leaf

$filenameFull = (Join-Path $TargetFolder $filename)

if (-not (Test-Path $filenameFull))
{
    Write-Output "[+] Downloading latest windows exporter"
    Start-BitsTransfer -Source $downloadUrl -Destination $filenameFull
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
    'scheduled_task',
    'system',
    'time'
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

$arguments = @(
    "--collectors.enabled ""$($collectors -join ',')""",
    "--collector.scheduled_task.exclude=""/Microsoft/.+"""
)

$action = New-ScheduledTaskAction `
    -Execute $filenameFull `
    -Argument ($arguments -join ' ') `
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
if (-not ((Invoke-RestMethod http://localhost:9182/health).status -eq 'ok'))
{
    Write-Warning "Windows Exporter does not appear to be providing health info"
    return
}

Write-Output "[*] Listening at http://localhost:9182/metrics"
