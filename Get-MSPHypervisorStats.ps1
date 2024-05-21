#Requires -Version 5.1
#Requires -Modules Hyper-V

<#
    .SYNOPSIS
        Gets usage information for a Hyper-V server
    .DESCRIPTION
        This script is intended to be run on a Windows Hyper-V server to assess
        the assigned resources vs the available resources on the server. We
        take into account CPU cores, memory, and any storage volumes that have
        a drive letter (other volumes are ignored).

        Example output:

        PS C:\> .\Get-MSPHypervisorStats.ps1
        ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇ Memory: 19.62 GB free of 32 GB (39% used)
        ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇ Cores: 6 assigned out of 8 available
        ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇ Storage: 144 GB used of 232 GB (62%) on volume 'C'

    .EXAMPLE
        PS C:\> Get-MSPHypervisorStats.ps1
    .EXAMPLE
        PS C:\> irm https://raw.githubusercontent.com/mspjeff/pwsh/main/Get-MSPHypervisorStats.ps1 | iex
  #>

function Write-Block
{
    param(
        [int] $Color
    )
    #$block = '▇'
    $block = '|'
    Write-Host ('{2}[38;5;{0}m{1}{2}[0m' -f $Color, $block, [char] 0x1b) -NoNewline
}

function Write-Bar
{
    param(
        [int] $Percent,
        [int] $Length = 20,
        [int] $BaseColor = 8, # DarkGray
        [int] $FillColor = 10 # Green
    )
    1..$Length | ForEach-Object {
        $current = $_ / $Length * 100
        $color = if ($current -le $Percent)
        { $FillColor
        } else
        { $BaseColor
        }
        Write-Block -Color $color
    }
}

function Write-Info
{
    param (
        [Parameter(Mandatory = $true)]
        [int] $Percent,
        [Parameter(Mandatory = $true)]
        [string] $Message
    )
    Write-Bar $Percent
    Write-Host (' {0}' -f $Message)
}

$info = Get-ComputerInfo

Write-Host
Write-Host ("Name............... {0}" -f $info.CsName)
Write-Host ("Manufacturer....... {0}" -f $info.CsManufacturer)
Write-Host ("Model.............. {0}" -f $info.CsModel)
Write-Host ("Serial number...... {0}" -f $info.BiosSeralNumber)
Write-Host ("Operating system... {0}" -f $info.OsName)
Write-Host ("Installed.......... {0}" -f $info.WindowsInstallDateFromRegistry)
Write-Host

#
# memory
#
# deal with inconsistency in the naming between different
# versions of powershell
#
$installed = if ($info.CsPhyicallyInstalledMemory)
{$info.CsPhyicallyInstalledMemory
} else
{$info.CsPhysicallyInstalledMemory
}
$percent = (100 - ($info.OsFreePhysicalMemory / $installed * 100))
$freeGB = $info.OsFreePhysicalMemory / 1MB
$sizeGB = $installed / 1MB
Write-Info `
    -Percent $percent `
    -Message ( `
        "Memory: {0:N2} GB free of {1:N0} GB ({2:N0}% used)" -f `
        $freeGB, `
        $sizeGB, `
        $percent)

#
# cpu cores
# 
$coresTotal = $info.CsNumberOfLogicalProcessors
$coresAssigned = (Get-VM | Measure-Object -Property ProcessorCount -Sum).Sum 
$coresFree = $coresTotal - $coresAssigned
$percent = $coresAssigned / $coresTotal * 100
Write-Info `
    -Percent $percent `
    -Message ( `
        "Cores: {0} out of {1} available ({2:N0}% used)" -f `
        $coresFree, `
        $coresTotal, `
        $percent)

#
# storage
#
Get-Volume `
| Where-Object {$_.DriveLetter.Length -gt 0 -and $_.DriveType -eq 'Fixed'} `
| Select-Object DriveLetter, FileSystemLabel, Size, SizeRemaining `
| ForEach-Object {
    $used = $_.Size - $_.SizeRemaining
    $percent = ($used / $_.Size * 100)
    $sizeGB = $_.Size / 1GB
    $freeGB = $_.SizeRemaining / 1GB
    Write-Info `
        -Percent $percent `
        -Message ( `
            "Storage: {1:N0} GB free of {2:N0} GB ({3:N0}% used) on volume '{0}'" -f `
            $_.DriveLetter, `
            $freeGB, `
            $sizeGB, `
            $percent)
}

#
# individual VM stats
#
$vmList = @(Get-VM)

Write-Host
Write-Host ("Percentages for {0} virtual machine(s) are relative to other VMs:" -f $vmList.Length)

$vmListMem = ($vmList | Measure-Object -Property MemoryAssigned -Sum).Sum
$vmListCores = ($vmList | Measure-Object -Property ProcessorCount -Sum).Sum
$vmListDisk = ($vmList | Get-VMHardDiskDrive | Get-VHD | Measure-Object -Property Size -Sum).Sum
 
Get-VM | ForEach-Object {
    Write-Host
    Write-Host ("{0} ({1}):" -f $_.Name, $_.Notes)
    $vmCorePercent = $_.ProcessorCount / $vmListCores * 100
    Write-Info `
        -Percent $vmCorePercent `
        -Message ("{0} core(s)" -f $_.ProcessorCount)
    $vmMemPercent = $_.MemoryAssigned / $vmListMem * 100
    Write-Info `
        -Percent $vmMemPercent `
        -Message ("{0:N0} GB memory" -f ($_.MemoryAssigned / 1GB))
    $vmDisk = ($_ | Get-VMHardDiskDrive | Get-VHD | Measure-Object -Property Size -Sum).Sum
    Write-Info `
        -Percent ($vmDisk / $vmListDisk * 100) `
        -Message ("{0:N0} GB storage" -f ($vmDisk / 1GB))
}
