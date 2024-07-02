#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    .SYNOPSIS
        Updates nsclient.ini on the local system based on the current system
        attributes and configuration
    .DESCRIPTION
        This script will dynamically determine which monitors need to be active
        on a system and configure the nsclient.ini on the local system thusly.
    .EXAMPLE
        PS C:\> Update-NSClientIni.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Update-NSClientIni.ps1 | iex
    .PARAMETER NSClientIni
        The path to write to and/or the path of the existing nsclient.ini file.
        Defaults to C:\Program Files\NSClient\nsclient.ini if omitted.
    .PARAMETER Hostname
        The hostname of the local system to be used in the nsclient.ini file.
        Does not necessarily need to correspond to the actual hostname of the
        system. If omitted it will default to the hostname in the existing
        nsclient.ini at the location specified by the NSClientIni parameter.
    .PARAMETER Address
        The network address (name or IP) of the Icinga server. If omitted it
        will default to the address in the existing nsclient.ini at the location
        specified by the NSClientIni parameter.
    .PARAMETER Password
        The password to use when AES encrypting data to be sent to the server
        specified by the Address parameter. If omitted it will default to the
        password in the existing nsclient.ini at the location specified by the
        NSClientIni parameter.
#>

[CmdletBinding()]
param(

    [Parameter(Mandatory=$false)]
    [string]
    $NSClientIni = "C:\Program Files\NSClient++\nsclient.ini",

    [Parameter(Mandatory=$false)]
    [string]
    $Hostname,

    [Parameter(Mandatory=$false)]
    [securestring]
    $Password,

    [Parameter(Mandatory=$false)]
    [string]
    $Address
)

#
# services to be ignored (like)
#
# GoogleUpdaterService
# GoogleUpdaterInternalService
# cbdhsvc_
# CDPUserSvc_
# clr_optimization_v
# OneSyncSvc_
# WpnUserService_
# 
# (exact)
#'BITS','CDPSvc','dbupdate','DoSvc','edgeupdate','GISvc','gpsvc','gupdate','IaasVmProvider','iDRAC Service Module','IntelAudioService','Intel(R) TPM Provisioning Service','MapsBroker','MMCSS','Net Driver HPZ12','Pml Driver HPZ12','RemoteRegistry','ShellHWDetection','sppsvc','StateRepository','SysmonLog','TabletInputService','tiledatamodelsvc','TrustedInstaller','VSS','WbioSrvc','wuauserv'
