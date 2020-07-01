Param(
    #An object for which we return the metrics
    [parameter(Mandatory=$true, Position=0)][String]$Object,
    #Additional parameters that will be used to return metrics for the object
    [parameter(Mandatory=$false, Position=1)]$Param1,
    [parameter(Mandatory=$false, Position=2)]$Param2
)

Set-Variable DFSNamespace -Option ReadOnly -Value "root\MicrosoftDfs" -ErrorAction Ignore

Set-Variable RoleNotInstalledText -Option ReadOnly -Value "DFS Replication role not installed" -ErrorAction Ignore

#Localization parameters (so that the decimal separator is a dot, because Zabbix will not understand the comma)
$USCulture = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
[System.Threading.Thread]::CurrentThread.CurrentCulture = $USCulture

<#
	#Timeout to get the value (must be less than the timeout in the Zabbix agent settings)
	Using this parameter, we limit the time of the partner queries:
	Considering that it usually takes up to 20 seconds to query an unavailable partner,
	and the timeout for the Zabbix agent is usually less (3s by default),
	we limit the polling time in the script itself so that the Zabbix agent doesn't get NoData due to a timeout
	This allows you to return the value or error text instead of NoData
#>
Set-Variable RequestTimeout -Option ReadOnly -Value 2 -ErrorAction Ignore

If ($PSVersionTable.PSVersion.Major -lt 3) {
    "The script requires PowerShell version 3.0 or above"
    Break
}

$DFSRRoleInstalled = (Get-WindowsFeature FS-DFS-Replication).Installed

$ErrorActionPreference = "Continue"

Switch($Object) {
    "RoleInstalled" {
        $DFSRRoleInstalled
    }
    "ServiceState" {
        $DFSRService = Get-Service DFSR -ErrorAction Ignore
        If ($DFSRService) {
            If ($DFSRService.Status -eq "Running") {
                (Get-WmiObject -Namespace $DFSNamespace -Class DfsrInfo).State
            }
            Else {
                #If the service is stopped
                [int]100
            }
        }
        Else {
            #If the service is not found
            [int]101
        }
    }

    #DFS Replication service version
    "ServiceVer" {
        $DFSRConfig = Get-WmiObject -Namespace $DFSNamespace -Class DfsrConfig -ErrorAction Ignore
        If ($DFSRConfig) {
            $DFSRConfig.ServiceVersion
        }
        Else {
            "n/a"
        }
    }

    #DFS Replication provider version
    "ProvVer" {
        $DFSRConfig = Get-WmiObject -Namespace $DFSNamespace -Class DfsrConfig -ErrorAction Ignore
        If ($DFSRConfig) {
            $DFSRConfig.ProviderVersion
        }
        Else {
            "n/a"
        }
    }

    #DFS Replication monitoring provider version
    "MonProvVer" {
        $DFSRInfo = Get-WmiObject -Namespace $DFSNamespace -Class DfsrInfo -ErrorAction Ignore
        If ($DFSRInfo) {
            $DFSRInfo.ProviderVersion
        }
        Else {
            "n/a"
        }
    }

    "ServiceUptime" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $DFSRInfo = Get-WmiObject -Namespace $DFSNamespace -Class DfsrInfo -ErrorAction Ignore
        If ($DFSRInfo) {
            #Get the start time of the service in WMA format
            $WMIStartTime = $DFSRInfo.ServiceStartTime
            #and convert it to DateTime format
            $StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($WMIStartTime)
            (New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds
        }
        Else {
            "n/a"
        }
    }

    #Replicated folder
    "RF" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $RFID = $Param1
        $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicatedFolderGuid='$RFID'"
        $RFConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$RFConfig) {
            "RF '$RFID' not found"
            Break
        }
        $RFName = $RFConfig.ReplicatedFolderName
        $RGID = $RFConfig.ReplicationGroupGuid
        #Statistics can only be collected from Enabled folders
        If ($RFConfig.Enabled) {
            $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderGuid='$RFID'"
            $RFInfo = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        }
        $ErrorText = "Couldn't retrieve info for disabled RF"
        
        Switch($Param2) {
            "Enabled" {
            #Whether replication is enabled for the folder
                $RFConfig.Enabled
            }
            #Delete files instead of moving to the conflict folder
            "RemoveDeleted" {
                $RFConfig.DisableSaveDeletes
            }
            "ReadOnly" {
            #The folder is in read-only mode"
                $RFConfig.ReadOnly
            }
            #Maximum size set for the intermediate folder, bytes
            "StageQuota" {
                $RFConfig.StagingSizeInMb*1024*1024
            }
            #Maximum size set for the ConflictAndDeleted folder, bytes
            "ConflictQuota" {
                $RFConfig.ConflictSizeInMb*1024*1024
            }
            "State" {
                If ($RFInfo) {
                    # 0 - Uninitialized, 1 - Initialized, 2 - Initial Sync,
                    # 3 - Auto Recovery, 4 - Normal, 5 - In Error
                    $RFInfo.State
                }
                Else {
                    "Couldn't retrieve info for disabled RF"
                }
            }
            #Current size of the intermediate folder, bytes
            "StageSize" {
                If ($RFInfo) {
                    $RFInfo.CurrentStageSizeInMb*1024*1024
                }
                Else {
                    "Couldn't retrieve info for disabled RF"
                }
            }
            #% free space in the intermediate folder
            "StagePFree" {
                If ($RFInfo) {
                    ($RFConfig.StagingSizeInMb - $RFInfo.CurrentStageSizeInMb)/ `
                        $RFConfig.StagingSizeInMb*100
                }
                Else {
                    $ErrorText
                }
            }
            #Current size of the ConflictAndDeleted folder, bytes
            "ConflictSize" {
                If ($RFInfo) {
                    $RFInfo.CurrentConflictSizeInMb*1024*1024
                }
                Else {
                    $ErrorText
                }
            }
            #% free space in the ConflictAndDeleted folder
            "ConflictPFree" {
                If ($RFInfo) {
                    ($RFConfig.ConflictSizeInMb - $RFInfo.CurrentConflictSizeInMb)/ `
                        $RFConfig.ConflictSizeInMb*100
                }
                Else {
                    $ErrorText
                }
            }
            #How many partners have a copy of the folder in working order
            "Redundancy" {
                #Finding partners for the replication group
                $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGuid='$RGID'"
                $PartnersByGroup = (Get-WmiObject `
                    -Namespace $DFSNamespace `
                    -Query $WMIQuery).PartnerName | Select-Object -Unique
                $n = 0
                #Check for a folder with the 'Normal' (4) state on each of the partners
                ForEach ($Partner in $PartnersByGroup) {
                    $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo " +
                        "WHERE ReplicatedFolderGuid='$RFID' AND State=4"
                    #and counting the total number of such folders
                    $j = Get-WmiObject -ComputerName $Partner `
                                       -Namespace $DFSNamespace `
                                       -Query $WMIQuery `
                                       -ErrorAction Ignore -AsJob
                    [void](Wait-Job $j -Timeout $RequestTimeout)
                    If ($j.State -eq "Completed") {
                        $n += @(Receive-Job $j).Count
                    }
                    #If we can't interview at least one node, we stop the queries and return an error
                    Else {
                        $n = -1
                        "Couldn't retrieve info from partner '$Partner'"
                        Break
                    }
                }
                #If everything is fine, we return the number of partners who store a copy of the folder
                If ($n -ge 0) {
                    $n
                }
            }
        }
    }

    "RFBacklog" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $RFID = $Param1
        $RServerID = $Param2 #ID принимающего партнера
        $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicatedFolderGuid='$RFID'"
        $RFConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$RFConfig) {
            "RF '$RFID' not found"
            Break
        }
        #Finding the name of the receiving partner by ID
        $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE PartnerGuid='$RServerID' AND Inbound='False'"
        $ConnectionConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$ConnectionConfig) {
            "Outbound connection to partner '$RServerID' not found"
            Break
        }
        $RServerName = $ConnectionConfig.PartnerName
        #Knowing the folder ID, we find its name and the name of the group that it belongs to
        $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderGuid='$RFID'"
        #Requesting information about the folder from the receiving partner
        $j = Get-WmiObject -ComputerName $RServerName `
                           -Namespace $DFSNamespace `
                           -Query $WMIQuery `
                           -ErrorAction Ignore -AsJob
        [void](Wait-Job $j -Timeout $RequestTimeout)
        If ($j.State -eq "Completed") {
            Try {
                #and trying to retrieve with this partner vector version
                $VersionVector = (Receive-Job $j).GetVersionVector().VersionVector
                #On the sending partner (i.e. on the local server), we determine the size of the backlog for the found vector
                (Get-WmiObject `
                    -Namespace $DFSNamespace `
                    -Query $WMIQuery).GetOutboundBacklogFileCount($VersionVector).BacklogFileCount
                }
            Catch {
                If ($VersionVector) {
                    "Couldn't retrieve backlog info for vector '$VersionVector'"
                }
                Else {
                    "Version vector not found"
                }
            }
        }
        Else {
            "Couldn't retrieve info from partner '$RServerName'"
        }
    }

    "Connection" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $ConnectionID = $Param1
        $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ConnectionGuid='$ConnectionID'"
        $ConnectionConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$ConnectionConfig) {
            "Connection '$ConnectionID' not found"
            Break
        }
        Switch($Param2) {
            "Enabled" {
                $ConnectionConfig.Enabled
            }
            "State" {
                #Statistics can only be obtained from enabled connections
                If ($ConnectionConfig.Enabled) {
                    $WMIQuery = "SELECT * FROM DfsrConnectionInfo WHERE ConnectionGuid='$ConnectionID'"
                    $ConnectionInfo = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
                    If ($ConnectionInfo) {
                        #0 - Connecting, 1 - Online, 2 - Offline, 3 - In Error
                        $ConnectionInfo.State
                    }
                    Else {
                        "Coundn't retrieve connection info. Check availability of partner '$($ConnectionConfig.PartnerName)'"
                    }
                }
                Else {
                    "Coundn't retrieve info for disabled connection"
                }
            }
            #If replication is completely disabled on a schedule
            "BlankSchedule" {
                [Int]$s = 0
                $ConnectionConfig.Schedule | ForEach-Object {
                    $s += $_
                }
                #If replication is disabled for every hour of every day, return True
                [Boolean]($s -eq 0)
            }
        }
    }

    "RG"
    {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $RGID = $Param1
        $WMIQuery = "SELECT * FROM DfsrReplicationGroupConfig WHERE ReplicationGroupGuid='$RGID'"
        $RGConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$RGConfig) {
            "RG '$RGID' not found"
            Break
        }
        Switch($Param2) {
            #number of folders in the group
            "RFCount" {
                $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGuid='$RGID'"
                @(Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).Count
            }
            #number of incoming connections (including disabled) from the group's partners
            "InConCount" {
                $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGuid='$RGID' AND Inbound='True'"
                @(Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).Count
            }
            #number of outgoing connections (including disabled) from the group's partners
            "OutConCount" {
                $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGuid='$RGID' AND Inbound='False'"
                @(Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).Count
            }
            #If replication is completely disabled for a group in the default schedule
            "BlankSchedule" {
                $WMIQuery = "SELECT * FROM DfsrReplicationGroupConfig WHERE ReplicationGroupGuid='$RGID'"
                $RGConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
                If ($RGConfig) {
                    [Int]$s = 0
                    $RGConfig.DefaultSchedule | ForEach-Object {
                        $s += $_
                    }
                    #Если репликация отключена для каждого часа каждого дня, возвращаем True
                    [Boolean]($s -eq 0)
                }
            }
        }
    }

    #Number of replication groups that the server belongs to
    "RGCount" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        @(Get-WmiObject -Namespace $DFSNamespace -Class DfsrReplicationGroupConfig).Count
    }
    
    "Partner" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $PartnerID = $Param1
        $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE PartnerGuid='$PartnerID'"
        $ConnectionConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$ConnectionConfig) {
            "Partner '$PartnerID' not found"
            Break
        }
        $PartnerName = (Get-WmiObject `
            -Namespace $DFSNamespace `
            -Query $WMIQuery).PartnerName | Select-Object -Unique
        Switch($Param2) {
            "PingCheckOK" {
                $CheckResult = Test-Connection -ComputerName $PartnerName `
                    -Count 1 -Delay 1 -ErrorAction Ignore
                [Boolean]($CheckResult -ne $Null)
            }
            "WMICheckOK" {
                $WMIQuery = "SELECT * FROM DfsrConfig"
                $j = Get-WmiObject -ComputerName $PartnerName `
                                   -Namespace $DFSNamespace `
                                   -Query $WMIQuery `
                                   -ErrorAction Ignore -AsJob
                [void](Wait-Job $j -Timeout $RequestTimeout)
                [Boolean]($j.State -eq "Completed")
            }
        }
    }

    "Volume" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $VolumeID = $Param1
        $WMIQuery = "SELECT * FROM DfsrVolumeConfig WHERE VolumeGuid='$VolumeID'"
        $VolumeConfig = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
        If (!$VolumeConfig) {
            "Volume '$VolumeID' not found"
            Break
        }
        Switch ($Param2) {
            "State" {
                $WMIQuery = "SELECT * FROM DfsrVolumeInfo WHERE VolumeGuid='$VolumeID'"
                #0 - Initialized, 1 - Shutting Down, 2 - In Error, 3 - Auto Recovery
                (Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).State
            }
        }
    }

    "Log" {
        If (!$DFSRRoleInstalled) {
            $RoleNotInstalledText
            Break
        }
        $ErrorActionPreference = "Stop"
        Try {
            [String]$TimeSpanAsString = $Param2
            $EndTime = Get-Date
            #Factor to convert from original units of measure in seconds
            $Multiplier = 1
            #Defining units of measurement (look at the last character in the resulting string)
            $TimeUnits = $TimeSpanAsString[$TimeSpanAsString.Length-1]
            #If units are not specified (at the end of the number),
            If ($TimeUnits -match "\d") {
                #we think we got the value in seconds
                $TimeValue = ($TimeSpanAsString -as [Int])
            }
            Else {
                #We get the numeric value by dropping the last character of the string
                $TimeValue = ($TimeSpanAsString.Substring(0, $TimeSpanAsString.Length - 1) -as [Int])
                #Converting from the original units of measurement to seconds
                Switch ($TimeUnits) {
                    "m" {$Multiplier = 60} #минуты
                    "h" {$Multiplier = 3600} #часы
                    "d" {$Multiplier = 86400} #дни
                    "w" {$Multiplier = 604800} #недели
                }
            }
            $StartTime = $EndTime.AddSeconds(-$TimeValue*$Multiplier)

            $Filter = @{
                LogName="DFS Replication"
                StartTime=$StartTime
                EndTime=$EndTime
            }
            Switch ($Param1) {
                "WarnCount" {$Filter += @{Level=3}}
                "ErrCount" {$Filter += @{Level=2}}
                "CritCount" {$Filter += @{Level=1}}
            }
            @(Get-WinEvent -FilterHashtable $Filter -ErrorAction Ignore).Count
        }
        Catch {
            $Error[0].Exception.Message
        }
    }
}
