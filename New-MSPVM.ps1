#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    .SYNOPSIS
        Creates a new Hyper-V virtual machine
    .DESCRIPTION
        Check it out
    .EXAMPLE
        PS C:\> New-MSPVM.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/New-MSPVM.ps1 | iex
  #>

[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]
    [ValidateNotNullOrEmpty()]
    $Name,

    [Parameter(Mandatory=$true)]
    [string]
    [ValidateNotNullOrEmpty()]
    $HardDiskFolder = 'D:\Hyper-V\Virtual Hard Disks',

    [Parameter(Mandatory=$true)]
    [UInt64]
    [ValidateNotNullOrEmpty()]
    $HardDiskSize = 40GB,

    [Parameter(Mandatory=$true)]
    [UInt32]
    [ValidateNotNullOrEmpty()]
    $HardDiskBlockSize = 1MB,

    [Parameter(Mandatory=$true)]
    [UInt32]
    [ValidateNotNullOrEmpty()]
    $HardDiskPhysicalSectorSize = 512,

    [Parameter(Mandatory=$true)]
    [UInt32]
    [ValidateNotNullOrEmpty()]
    $HardDiskLogicalSectorSize = 512,

    [Parameter(Mandatory=$true)]
    [Int64]
    [ValidateNotNullOrEmpty()]
    $MemoryStartupBytes = 4GB,

    [Parameter(Mandatory=$true)]
    [string]
    [ValidateNotNullOrEmpty()]
    $SwitchName = 'External Virtual Switch'
)

$vhd = New-VHD `
    -Path (Join-Path $HardDiskFolder "$Name-OS.vhdx") `
    -SizeBytes $HardDiskSize `
    -BlockSizeBytes $HardDiskBlockSize `
    -LogicalSectorSizeBytes $HardDiskLogicalSectorSize `
    -PhysicalSectorSizeBytes $HardDiskPhysicalSectorSize `
    -Fixed

$vm = New-VM `
    -Name $Name `
    -MemoryStartupBytes $MemoryStartupBytes `
    -SwitchName $SwitchName `
    -VHDPath ($vhd.Path) `
    -Generation 2

$vm | Set-VM `
    -ProcessorCount 4 `
    -Notes '' `
    -AutomaticStartDelay 60 `
    -AutomaticStartAction 'Start' `
    -AutomaticStopAction 'Save' `
    -CheckpointType 'Disabled'

$vm | Add-VMDvdDrive `
    -ControllerNumber 0 `
    -Path 'C:\Users\Public\Documents\ISO\ubuntu-24.04-live-server-amd64.iso'

$vm | Get-VMNetworkAdapter | Connect-VMNetworkAdapter `
    -SwitchName $SwitchName

$vm | Set-VMNetworkAdapterVlan `
    -Access `
    -VlanId 68

$vm | Get-VMIntegrationService `
    -Name "Time Synchronization" | Disable-VMIntegrationService

$vm | Set-VMFirmware `
    -EnableSecureBoot 'On' `
    -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' `
    -BootOrder (($vm | Get-VMHardDiskDrive), ($vm | Get-VMDvdDrive))
