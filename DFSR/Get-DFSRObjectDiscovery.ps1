Param(
    #What type of objects are we collecting
    [parameter(Mandatory=$true, Position=0)][String]$ObjectType
)


If ($PSVersionTable.PSVersion.Major -lt 3) {
    "The script requires PowerShell version 3.0 or above"
    Break
}
If (!(Get-WindowsFeature FS-DFS-Replication).Installed) {
   $Data = @{ "{#MSG}"= "DFS Replication role not installed"}
   @{
    "data" = $Data
} | ConvertTo-Json
    Break
}

$ErrorActionPreference = "Continue"

Set-Variable DFSNamespace -Option ReadOnly -Value "root\MicrosoftDfs" -ErrorAction Ignore

$Data = @()

#Depending on the object type, we collect and return the corresponding data in JSON
Switch($ObjectType) {
    #Performance counters for replicated folders
    "RFPerfCounter" {
        #Find the first counter number in the registry that belongs to the "Replicated DFS folders" object" (DFS Replicated Folders)
        #(Numbers are generated by the system and are individual for each server)
        # Zabbix will operate with these numbers
        $PerfObjectRegKey = "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\_V2Providers\{d7b456d4-ca82-4080-a5d0-27fe1a27a851}\{bfe2736b-c79f-4f36-bd15-2897a1a91d4a}"
        $PerfObjectID = (Get-ItemProperty -Path $PerfObjectRegKey -Name "First Counter")."First Counter"
        #Getting a list of instances for the RF object (i.e. a list of DFSR folders that have counters for them)
        Get-WmiObject -Class Win32_PerfFormattedData_Dfsr_DFSReplicatedFolders | ForEach-Object {
            #The instance (in our case, RF) that counter data is collected from has the form Refname - {REFID}
            #Extracting the RF ID and name from it
            $RFName = $_.Name.Substring(0, $_.Name.IndexOf('-{'))
            $RFID = $_.Name.Substring($_.Name.IndexOf('-{') + 2, $_.Name.Length -$_.Name.IndexOf('-{') - 3)
            #Finding the replication group that the RF belongs to
            $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderGuid = '$RFID'"
            $RGName = (Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).ReplicationGroupName

            $Entry = [PSCustomObject] @{
                "{#RGNAME}" = $RGName
                "{#RFNAME}" = $_.Name.Substring(0, $_.Name.IndexOf('-{'))
                "{#RFPERFOBJECTID}" = $PerfObjectID
                "{#RFPERFINSTANCEID}" = $_.Name
                #We get the counter numbers by incrementing by 2 the number found above
                "{#RFPERFCOUNTER1ID}" = $PerfObjectID + 2 # Staging Files Generated
                "{#RFPERFCOUNTER2ID}" = $PerfObjectID + 4 # Staging Bytes Generated
                "{#RFPERFCOUNTER3ID}" = $PerfObjectID + 6 # Staging Files Cleaned up
                "{#RFPERFCOUNTER4ID}" = $PerfObjectID + 8 # Staging Bytes Cleaned up
                "{#RFPERFCOUNTER5ID}" = $PerfObjectID + 10 # Staging Space In Use
                "{#RFPERFCOUNTER6ID}" = $PerfObjectID + 12 # Conflict Files Generated
                "{#RFPERFCOUNTER7ID}" = $PerfObjectID + 14 # Conflict Bytes Generated
                "{#RFPERFCOUNTER8ID}" = $PerfObjectID + 16 # Conflict Files Cleaned up
                "{#RFPERFCOUNTER9ID}" = $PerfObjectID + 18 # Conflict Bytes Cleaned up
                "{#RFPERFCOUNTER10ID}" = $PerfObjectID + 20 # Conflict Space In Use
                "{#RFPERFCOUNTER11ID}" = $PerfObjectID + 22 # Conflict Folder Cleanups Completed
                "{#RFPERFCOUNTER12ID}" = $PerfObjectID + 24 # File Installs Succeeded
                "{#RFPERFCOUNTER13ID}" = $PerfObjectID + 26 # File Installs Retried
                "{#RFPERFCOUNTER14ID}" = $PerfObjectID + 28 # Updates Dropped
                "{#RFPERFCOUNTER15ID}" = $PerfObjectID + 30 # Deleted Files Generated
                "{#RFPERFCOUNTER16ID}" = $PerfObjectID + 32 # Deleted Bytes Generated
                "{#RFPERFCOUNTER17ID}" = $PerfObjectID + 34 # Deleted Files Cleaned up
                "{#RFPERFCOUNTER18ID}" = $PerfObjectID + 36 # Deleted Bytes Cleaned up
                "{#RFPERFCOUNTER19ID}" = $PerfObjectID + 38 # Deleted Space In Use
                "{#RFPERFCOUNTER20ID}" = $PerfObjectID + 40 # Total Files Received
                "{#RFPERFCOUNTER21ID}" = $PerfObjectID + 42 # Size of Files Received
                "{#RFPERFCOUNTER22ID}" = $PerfObjectID + 44 # Compressed Size of Files Received
                "{#RFPERFCOUNTER23ID}" = $PerfObjectID + 46 # RDC Number of Files Received
                "{#RFPERFCOUNTER24ID}" = $PerfObjectID + 48 # RDC Size of Files Received
                "{#RFPERFCOUNTER25ID}" = $PerfObjectID + 50 # RDC Compressed Size of Files Received
                "{#RFPERFCOUNTER26ID}" = $PerfObjectID + 52 # RDC Bytes Received
                "{#RFPERFCOUNTER27ID}" = $PerfObjectID + 54 # Bandwidth Savings Using DFS Replication
            }
            $Data += $Entry
        }
    }

    #Performance counters for DFSR connections
    "ConPerfCounter" {
        #Find the first counter number in the registry that is related to the "DFS replication Connections" object" (DFS Replication Connections)
        #(Numbers are generated by the system and are individual for each server)
        # Zabbix will operate with these numbers
        $PerfObjectRegKey = "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\_V2Providers\{d7b456d4-ca82-4080-a5d0-27fe1a27a851}\{a689f9be-38ad-4c17-9d62-ad60492084a7}"
        $PerfObjectID = (Get-ItemProperty -Path $PerfObjectRegKey -Name "First Counter")."First Counter"
        Get-WmiObject -Class Win32_PerfFormattedData_Dfsr_DFSReplicationConnections | ForEach-Object {
            #Getting a list of instances for the RC object (i.e. a list of DFSR connections that have counters)
            #The instance (in our case, this is a connection) that counter data is collected from has the form SendingParnerFQDN-{RCID}
            #We extract the name of the sending partner server and the connection ID from it
            $SendingPartner = $_.Name.Substring(0, $_.Name.IndexOf('-{'))
            $RCID = $_.Name.Substring($_.Name.IndexOf('-{') + 2, $_.Name.Length -$_.Name.IndexOf('-{') - 3)
            #Finding the replication group that RC belongs to
            $WMIQuery = "SELECT * FROM DfsrConnectionInfo WHERE ConnectionGuid = '$RCID'"
            $RGName = (Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).ReplicationGroupName

            $Entry = [PSCustomObject] @{
                "{#RGNAME}" = $RGName
                "{#RCPARTNER}" = $SendingPartner
                "{#RCPERFOBJECTID}" = $PerfObjectID
                "{#RCPERFINSTANCEID}" = $_.Name
                #We get the counter numbers by incrementing by 2 the number found above
                "{#RCPERFCOUNTER1ID}" = $PerfObjectID + 2 # Total Bytes Received
                "{#RCPERFCOUNTER2ID}" = $PerfObjectID + 4 # Total Files Received
                "{#RCPERFCOUNTER3ID}" = $PerfObjectID + 6 # Size of Files Received
                "{#RCPERFCOUNTER4ID}" = $PerfObjectID + 8 # Compressed Size of Files Received
                "{#RCPERFCOUNTER5ID}" = $PerfObjectID + 10 # Bytes Received Per Second
                "{#RCPERFCOUNTER6ID}" = $PerfObjectID + 12 # RDC Number of Files Received
                "{#RCPERFCOUNTER7ID}" = $PerfObjectID + 14 # RDC Size of Files Received
                "{#RCPERFCOUNTER8ID}" = $PerfObjectID + 16 # RDC Compressed Size of Files Received
                "{#RCPERFCOUNTER9ID}" = $PerfObjectID + 18 # RDC Bytes Received
                "{#RCPERFCOUNTER10ID}" = $PerfObjectID + 20 # Bandwidth Savings Using DFS Replication
            }
            $Data += $Entry
        }
    }

    #Performance counters for DFSR volumes
    "VolPerfCounter" {
        #Find the first counter number in the registry that is related to the DFS replication service Volume object" (DFS Replication Service Volumes)
        #(Numbers are generated by the system and are individual for each server)
        # Zabbix will operate with these numbers
        $PerfObjectRegKey = "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\_V2Providers\{d7b456d4-ca82-4080-a5d0-27fe1a27a851}\{3f1707df-6381-4287-affc-a60e109a4d30}"
        $PerfObjectID = (Get-ItemProperty -Path $PerfObjectRegKey -Name "First Counter")."First Counter"
        #Getting the list of DFS Replication Service Volumes
        Get-WmiObject -Class Win32_PerfFormattedData_Dfsr_DFSReplicationServiceVolumes |
            ForEach-Object {
                $RV = [PSCustomObject] @{
                    "{#RVNAME}" = $_.Name
                    "{#RVPERFOBJECTID}" = $PerfObjectID
                    "{#RVPERFCOUNTER1ID}" = $PerfObjectID + 2 # USN Journal Records Read
                    "{#RVPERFCOUNTER2ID}" = $PerfObjectID + 4 # USN Journal Records Accepted
                    "{#RVPERFCOUNTER3ID}" = $PerfObjectID + 6 # USN Journal Unread Percentage
                    "{#RVPERFCOUNTER4ID}" = $PerfObjectID + 8 # Database Commits
                    "{#RVPERFCOUNTER5ID}" = $PerfObjectID + 10 # Database Lookups
                }
                $Data += $RV
        }
    }

    #Replicated folders located on the server
    "RF" {
        (Get-WmiObject -Namespace $DFSNamespace -Class DfsrReplicatedFolderConfig) |
            ForEach-Object {
                #Определяем имя группы репликации по ее ID
                $RGID = $_.ReplicationGroupGuid
                $WMIQuery = "SELECT * FROM DfsrReplicationGroupConfig WHERE ReplicationGroupGuid='$RGID'"
                $RGName = (Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).ReplicationGroupName
                $RF = [PSCustomObject] @{
                    "{#RFID}" = $_.ReplicatedFolderGuid
                    "{#RFNAME}" = $_.ReplicatedFolderName
                    "{#RGNAME}" = $RGName
                }
                $Data += $RF
        }
    }

    #Outgoing file backlog for each replicated folder
    "RFBacklog" {
        #reference text to use for parsing the subscription's DN
        $ReferenceText = ",CN=DFSR-LocalSettings,CN="
        $RFMembers = @()
        #Find all enabled DFSR subscriptions in the AD database, except our own
        (New-Object DirectoryServices.DirectorySearcher "ObjectClass=msDFSR-Subscription").FindAll() |
            Where-Object {($_.Properties.distinguishedname -notlike "*$ReferenceText$env:COMPUTERNAME,*") -and
                ($_.Properties."msdfsr-enabled" -eq $true)} |
                    ForEach-Object {
                    $SubscriptionDN = $_.Properties.distinguishedname
                    #the signed server name is enclosed in a DN string between the reference text
                    $TempText = $SubscriptionDN.Substring($SubscriptionDN.LastIndexOf($ReferenceText) + $ReferenceText.Length)
                    #and comma
                    $ComputerName = $TempText.Substring(0, $TempText.IndexOf(","))
                    $RFMember = [PSCustomObject]@{
                        ComputerName = $ComputerName
                        RFID = [String]$_.Properties.name
                    }
                    $RFMembers += $RFMember
                }
        #Finding groups that include the local server
        $RGs = Get-WmiObject -Namespace $DFSNamespace -Class DfsrReplicationGroupConfig
        ForEach ($RG in $RGs) {
            $RGID = $RG.ReplicationGroupGuid
            $RGName = $RG.ReplicationGroupName
            #Finding outgoing connections related to the group
            $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGuid='$RGID' AND Inbound='False'"
            $OutConnections = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
            #Finding folders (RF) on this server that belong to the group,
            # except for both disabled and readonly folders, because they don't have a backlog of outgoing files
            $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig "+
                "WHERE ReplicationGroupGuid='$RGID' AND Enabled='True' AND ReadOnly='False'"
            $RFs = Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery
            #We check the presence of these folders on each of the group's host partners
            ForEach ($Connection in $OutConnections) {
                ForEach ($RF in $RFs) {
                    $RFID = $RF.ReplicatedFolderGuid
                    $RFName = $RF.ReplicatedFolderName
                    #If the receiving partner contains a folder, we will create a metric for the corresponding backlog
                    ForEach ($RFMember in $RFMembers) {
                        If (($RFMember.RFID -eq $RFID) -and ($RFMember.ComputerName -eq $Connection.PartnerName)) {
                            $Entry = [PSCustomObject] @{
                                "{#RGNAME}" = $RGName
                                "{#RFNAME}" = $RFName
                                "{#RFID}" = $RFID
                                "{#SSERVERNAME}" = $env:COMPUTERNAME
                                "{#RSERVERID}" = $Connection.PartnerGuid
                                "{#RSERVERNAME}" = $Connection.PartnerName
                            }
                            $Data += $Entry
                        }
                    }
                }
            }
        }
    }
    #Connections for replication groups
    "Connection" {
        Get-WmiObject -Namespace $DFSNamespace -Class DfsrConnectionConfig |
            ForEach-Object {
                #Defining the name of the replication group by its ID
                $RGID = $_.ReplicationGroupGuid
                $WMIQuery = "SELECT * FROM DfsrReplicationGroupConfig WHERE ReplicationGroupGuid='$RGID'"
                $RGName = (Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery).ReplicationGroupName
                If ($_.Inbound) {
                    $SendingServer = $_.PartnerName
                    $ReceivingServer = $env:COMPUTERNAME
                }
                Else {
                    $SendingServer = $env:COMPUTERNAME
                    $ReceivingServer = $_.PartnerName
                }
                $Connection = [PSCustomObject] @{
                    "{#CONNECTIONID}" = $_.ConnectionGuid
                    "{#RGNAME}" = $RGName
                    "{#SSERVERNAME}" = $SendingServer
                    "{#RSERVERNAME}" = $ReceivingServer
                }
                $Data += $Connection
        }
    }

    #Группы репликации
    "RG" {
        Get-WmiObject -Namespace $DFSNamespace -Class DfsrReplicationGroupConfig |
            ForEach-Object {
                $RG = [PSCustomObject] @{
                    "{#RGID}" = $_.ReplicationGroupGuid
                    "{#RGNAME}" = $_.ReplicationGroupName
                }
                $Data += $RG
        }
    }

    #Volumes where replicated folders are stored
    "Volume" {
        Get-WmiObject -Namespace $DFSNamespace -Class DfsrVolumeConfig |
            ForEach-Object {
                $Volume = [PSCustomObject] @{
                    "{#VOLUMEID}" = $_.VolumeGuid
                    #The path is initially returned in UNC format, so we trim the initial characters
                    "{#VOLUMENAME}" = $_.VolumePath.TrimStart("\\.\")
                }
                $Data += $Volume
        }
    }

    #Partners for replication groups
    "Partner" {
        #Finding replication groups
        Get-WmiObject -Namespace $DFSNamespace -Class DfsrReplicationGroupConfig |
            ForEach-Object {
                $RGID = $_.ReplicationGroupGuid
                $RGName = $_.ReplicationGroupName
                #and we find partners in each group
                $WMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGuid='$RGID'"
                Get-WmiObject -Namespace $DFSNamespace -Query $WMIQuery |
                    Select-Object PartnerGuid, PartnerName -Unique | ForEach-Object {
                        $Partner = [PSCustomObject] @{
                            "{#PARTNERID}" = $_.PartnerGuid
                            "{#PARTNERNAME}" = $_.PartnerName
                            "{#RGNAME}" = $RGName
                            #The account that the Zabbix Agent service runs on behalf of
                            "{#NTACCOUNT}" = "$env:USERDOMAIN\$env:USERNAME"
                        }
                        $Data += $Partner
                }
        }
    }
}

@{
    "data" = $Data
} | ConvertTo-Json
