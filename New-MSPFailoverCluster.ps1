param (
	[Parameter(Required=$true)]
	[string]
	$ClusterName,

	[Parameter(Required=$true)]
	[string]
	$NASAddress
)
if (-not (Get-WindowsFeature Failover-Clustering).State -eq 'Installed')
{
	Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools
	Write-Warning "Restarting after installing clustering feature"
	Restart-Computer -Force
}

if (Get-Service -Name MSiSCSI)
{
	Write-Warning "MSiSCSI service is missing"
	return
}

if ((Get-Service -Name MSiSCSI).StartType -ne 'Automatic')
{
	Set-Service -Name MSiSCSI -StartupType Automatic
}

if ((Get-Service -Name MSiSCSI).Status -ne 'Running')
{
	Start-Service -Name MSiSCSI
}

if (-not (Test-NetConnection $NASAddress))
{
	Write-Warning "Unable to ping NAS address at $NASAddress"
	return
}

if (-not (Get-IscsiTargetPortal -TargetPortalAddress $NASAddress))
{
	New-IscsiTargetPortal -TargetPortalAddress $NASAddress
}

if ($target = Get-IscsiTargetPortal -TargetPortalAddress $NASAddress | Get-IscsiTarget | Where-Object {$_.IsConnected -eq $false})
{
	$target | Connect-IscsiTarget -IsPersistent $true
}

if ($disk = Get-Disk | Where-Object {$_.OperationalStatus -eq 'Offline' -and $_.PartitionStyle -eq 'Raw'})
{
	Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru `
	| Set-Disk -IsOffline $false `
	| New-Partition -UseMaximumSize -AssignDriveLetter:$false `
	| Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Clustered'
}

New-Cluster -Name $ClusterName
