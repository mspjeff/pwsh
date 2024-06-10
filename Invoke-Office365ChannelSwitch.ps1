#Requires -Version 5.1

<#
    .SYNOPSIS
        Switches Office 365 update channel to Monthly Enterprise
    .DESCRIPTION

    .EXAMPLE
        PS C:\> Invoke-Office365ChannelSwitch.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Invoke-Office365ChannelSwitch.ps1 | iex
#>

$xml = @'
<Configuration>
     <Updates Channel="MonthlyEnterprise" />
</Configuration>
'@

$mec = 'http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6'

$cdn = Get-ItemProperty `
    -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" `
    -Name "CDNBaseUrl" | `
        Select-Object -ExpandProperty "CDNBaseUrl"

if ($cdn -eq $mec)
{
    Write-Host "Office is already on desired channel. Exiting."
    return
}

Write-Host 'Downloading office deployment tool'
Start-BitsTransfer `
    -Source 'https://exdosa.blob.core.windows.net/public/office/setup.exe' `
    -Destination "$env:temp\setup.exe"

Write-Host 'Creating configuration file'
$xml | Out-File -FilePath "$env:temp\switchtomec.xml"

Write-Host "Invoking setup.exe /configure $env:temp\switchtomec.xml"
& "$env:temp\setup.exe" /configure "$env:temp\switchtomec.xml"

if ($task = Get-ScheduledTask -TaskName "Office Automatic Updates 2.0" -TaskPath "\Microsoft\Office\" -ErrorAction SilentlyContinue)
{
    Write-Host "Starting office automatic update task"
    $task | Start-ScheduledTask
}
