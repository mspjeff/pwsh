#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    .SYNOPSIS
        Downloads and starts Prometheus
    .DESCRIPTION
        Check it out
    .EXAMPLE
        PS C:\> Install-Prometheus.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Install-Prometheus.ps1 | iex
    .LINK
        https://prometheus.io
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
    $TaskName = "Start Prometheus",

    [Parameter(Mandatory=$false)]
    [string]
    [ValidateNotNullOrEmpty()]
    $FirewallRuleName = "Allow TCP/9090 Inbound (Prometheus)"
)

function Get-Prometheus
{

    if (-not (Test-Path $TargetFolder))
    {
        New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null
    }

    #
    # https://github.com/prometheus/.../prometheus-2.52.0.windows-amd64.zip
    #
    $downloadUrl = Invoke-RestMethod `
        https://api.github.com/repos/prometheus/prometheus/releases/latest`
    | Select-Object -ExpandProperty assets `
    | Where-Object { $_.name.EndsWith("windows-amd64.zip")} `
    | Select-Object -ExpandProperty browser_download_url

    Write-Verbose "Url: $downloadUrl"

    #
    # %temp%\prometheus-2.52.0.windows-amd64.zip
    #
    $downloadZip = Join-Path `
        -Path $env:TEMP `
        -ChildPath (Split-Path $downloadUrl -Leaf)

    Write-Verbose "Download zip is $downloadZip"

    #
    # download to temporary folder
    #
    Start-BitsTransfer -Source $downloadUrl -Destination $downloadZip

    #
    # save a list of files that we'll use later
    #
    $extractedFiles = Expand-Archive `
        -Path $downloadZip `
        -DestinationPath $TargetFolder `
        -Force `
        -PassThru

    #
    # cleanup after ourselves
    #
    Remove-Item $downloadZip

    #
    # return the fully qualified path to the prometheus executable so
    # that the caller can use this to create a service or scheduled
    # task that runs the executable 'prometheus.exe' at startup
    #
    $extractedFiles | Where-Object { $_.FullName -like '*\prometheus.exe' }
}

function New-PrometheusConfig
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $Program
    )

    $configfile = (Join-Path (Split-Path $Program) "prometheus.yml")

    Write-Verbose "Generating config at $configfile"

    $config = @()
    $config += 'global:'
    $config += '  scrape_interval: 15s'
    $config += '  evaluation_interval: 15s'
    $config += 'scrape_configs:'
    $config += '  - job_name: "prometheus"'
    $config += '    static_configs:'
    $config += '      - targets: ["localhost:9090"]'

    $config | Out-File $configfile -Encoding utf8
}

function Remove-PrometheusTask
{
    if ($task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
    {
        Write-Verbose "Stopping and deleting existing scheduled task"
        $task | Stop-ScheduledTask
        $task | Unregister-ScheduledTask -Confirm:$false
    }
}

function New-PrometheusTask
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $Program
    )

    Write-Verbose "Scheduling startup task for $Program"

    $action = New-ScheduledTaskAction `
        -Execute $Program `
        -Argument '--web.enable-lifecycle'
    -WorkingDirectory (Split-Path $Program)

    $trigger = New-ScheduledTaskTrigger `
        -AtStartup

    $principal = New-ScheduledTaskPrincipal `
        -UserId "NT AUTHORITY\LocalService" `
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
}

function New-AllowPrometheusFirewallRule
{
    if (-not (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue))
    {
        Write-Verbose "Creating firewall rule '$FirewallRuleName'"

        New-NetFirewallRule `
            -DisplayName $FirewallRuleName `
            -Description 'Allows access to http://<thismachine>:9090' `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 9090 `
            -Action Allow `
            -Profile Any | Out-Null
    }
}

Remove-PrometheusTask

$target = Get-Prometheus
$target | New-PrometheusConfig
$target | New-PrometheusTask

Write-Output "Done"
