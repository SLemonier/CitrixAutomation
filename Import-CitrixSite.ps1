<#


$XMLDocument = [XML](Get-Content .\export.xml)
PS C:\Users\sleadm\Desktop> foreach($role in $roles.childnodes){write-host $role.name; foreach($permission in $role.perm
ission){write-host "permission: " $permission}}











 .Synopsis
 Provision a given number of VM(s) in one or more MCS DeliveryGroup(s) and assign the VM(s) to a delivery group.

 .Description
 Provision a given number of VM(s).
 This script supports to provision in several MCS catalogs.
 It also supports to attach the newly created VM(s) to a delivery group (only one is supported).
 Finally, you can specify to split equally the VM(s) to provision into different MCS catalogs (optionnal).

 .Parameter DeliveryController
 Specifiy the Delivery Controller to use for the provision
 This parameter is optionnal, by default it will use with the local machine.

 .Parameter VDICount
 Specify how much VM(s) to provision (integer).
 This parameter is mandatory.

 .Parameter Catalog
 Specify a list of MCS catalogs to provision the VM(s) to.
 This parameter is mandatory.

 .Parameter Split
 Split equally the number of VM(s) to provision into the MCS catalogs provided with -Catalog parameter.
 This paramater is optionnal.

 .Parameter DeliveryGroup
 Specifiy the DesktopGroup to attach to the newly created VM(s).
 This parameter is mandatory.

 .Parameter Log
 Specifiy the output file for the logs.
 This parameter is optionnal, by default, it will create a file in the current directory.

 .Example
 # Provision 10 VMs to the "Windows 10" catalog and assign them to the "Desktop" delivery group.
 VDI_Provisionning.ps1 -VDICount 10 -Catalog "Windows10" -DeliveryGroup "Desktop"

 .Example
 # Connect to "CTXDDC01" to provision 10 VMs to the "Windows 10" catalog and assign them to the "Desktop" delivery group.
 VDI_Provisionning.ps1 -DeliveryController "CTXDDC01" -VDICount 10 -Catalog "Windows10" -DeliveryGroup "Desktop"

.Example
 # Provision 10 VMs to the "DTC1" and "DTC2" catalogs    and assign them to the "Desktop" delivery group.
 VDI_Provisionning.ps1 -VDICount 10 -Catalog "DTC1","DTC2" -DeliveryGroup "Desktop"

 .Example
 # Provision 5 (10 split equally between two catalogs) VMs to the "DTC1" and "DTC2" catalogs, assign them 
 to the "Desktop" delivery group and log the output in C:\Temp
 VDI_Provisionning.ps1 -VDICount 10 -Catalog "DTC1","DTC2" -Split -DeliveryGroup "Desktop" -Log "C:\temp\test.log"
#>

[CmdletBinding()]
Param(
    # Declaring input variables for the script
    [Parameter(Mandatory=$false)] [string]$XMLFile,
    [Parameter(Mandatory=$false)] [string]$ResourcesFolder,
    [Parameter(Mandatory=$false)] [string]$DeliveryController,
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\Import-CitrixSite.log"
)

#Start logging
Start-Transcript -Path $LogFile

#Setting variables prior to their usage is not mandatory
Set-StrictMode -Version 2

#Check Snapin can be loaded
#Could be improved by only loading the necessary modules but it would not be compatible with version older than 1912
Write-Host "Loading Citrix Snapin... " -NoNewline
if(!(Add-PSSnapin Citrix* -ErrorAction SilentlyContinue -PassThru )){
    Write-Host "Failed" -ForegroundColor Red
    Write-Host "Citrix Snapin cannot be loaded. Please, check the component is installed on the computer." -ForegroundColor Red
    #Stop logging
    Stop-Transcript 
    break
}
Write-Host "OK" -ForegroundColor Green

################################################################################################
#Checking the parameters
################################################################################################

#Check if the DeliveryController parameter is set or if it has to use the local machine
if($DeliveryController){
    #Check if the parameter is a FQDN or not
    Write-Host "Trying to contact the Delivery Controller $DeliveryController... " -NoNewline
    if($DeliveryController -contains "."){
        $DDC = Get-BrokerController -DNSName "$DeliveryController"
    } else {
        $DDC = Get-BrokerController -DNSName "$DeliveryController.$env:USERDNSDOMAIN"
    }
} else {
    Write-Host "Trying to contact the Delivery Controller $env:COMPUTERNAME... " -NoNewline
    $DDC = Get-BrokerController -DNSName "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
}
if(($DDC)){
    Write-Host "OK" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    Write-Host "Cannot contact the Delivery Controller. Please, check the role is installed on the target computer and your account is allowed to communicate with it." -ForegroundColor Red
}

#TODO Check if current DDC = DDC in the XML
#WARN about lauching the script on the same DDC as the one in export file!

#Check if export file exists
Write-Host "Checking XML file... " -NoNewline
Try{
    #TODO improve check (google to check XML)
    $xdoc = New-Object System.Xml.XmlDocument
    $file = Resolve-Path($XMLFile)
    $xdoc.load($file)
}
catch{
    Write-Host "An error occured while importing XML file" -ForegroundColor Red
    Stop-Transcript
    break
}
Write-Host "OK" -ForegroundColor Green


#Check if resources folder exists (to import icon)
Write-Host "Checking resources folder... " -NoNewline
#TODO improve check (uid.txt as childitem)
if(Test-Path -path $ResourcesFolder){
    Write-Host "OK" -ForegroundColor Green
} else {
    Write-Host "An error occured while checking resources folder. Ensure the path is correct." -ForegroundColor Red
    Stop-Transcript
    break
}

################################################################################################
#Setting Site's Properties
################################################################################################
if($xdoc.site.Properties.TrustXML.InnerText){
    Write-Host "Setting Site's TrustXML Property... " -NoNewline
    try {
        $value = [bool]$xdoc.site.Properties.TrustXML.InnerText
        Set-BrokerSite -TrustRequestsSentToTheXmlServicePort $value
    }
    catch {
        Write-Host "An error occured while setting Site's TrustXML Property" -ForegroundColor Red
        Stop-Transcript
        break
    }
    Write-Host "OK" -ForegroundColor Green
}

################################################################################################
#Setting Site's Tags
################################################################################################

Write-Host "Setting Site's Tags... " -NoNewline
if($xdoc.site.tags){
    $tags = $xdoc.site.tags.tag
    foreach($tag in $tags){
        if(!(Get-BrokerTag -Name $tag.Name -errorAction SilentlyContinue)){
            Write-host "Adding new tag" $tag.Name"... " -NoNewline
            try {
                New-BrokerTag -Name $scope.Name  | out-null
                Write-Host "OK" -ForegroundColor Green
            }
            catch {
                Write-Host "An error occured while adding a new tag" -ForegroundColor Red
                Stop-Transcript
                break
            }
        } else {
            Write-Host $tag.Name "already exists. tag won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually tag's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No tags to import" -ForegroundColor Yellow
}

################################################################################################
#Setting Site's Administrators
################################################################################################

Write-Host "Setting Roles config... "
if($xdoc.site.Roles){
    $roles = $xdoc.site.roles.role
    foreach($role in $roles){
        if(!(Get-AdminRole -Name $role.Name -errorAction SilentlyContinue)){
            Write-host "Adding new role" $role.Name"... " -NoNewline
            try {
                New-AdminRole -Name $role.Name -description $role.description | out-null
                Write-Host "OK" -ForegroundColor Green
                Write-host "Adding permissions to" $role.name"... " -NoNewline
                try {
                    Add-AdminPermission -Role $role.name -Permission $role.permission
                    Write-host "OK" -ForegroundColor Green
                }
                catch {
                    Write-Host "An error occured while setting permissions for" $role.name -ForegroundColor Red                        
                    Stop-Transcript
                    break
                }
            }
            catch {
                Write-Host "An error occured while adding a new role" -ForegroundColor Red
                Stop-Transcript
                break
            }
        } else {
            Write-Host $role.name "already exists. Role won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually role's properties." -ForegroundColor Yellow
        }
    }
}else {
    Write-Host "No roles to import" -ForegroundColor Yellow
}

Write-Host "Setting Scopes config... "
if($xdoc.site.scopes){
    $scopes = $xdoc.site.scopes.scope
    foreach($scope in $scopes){
        if(!(Get-AdminScope -Name $scope.Name -errorAction SilentlyContinue)){
            Write-host "Adding new scope" $scope.Name"... " -NoNewline
            try {
                New-AdminScope -Name $scope.Name -description $scope.description | out-null
                Write-Host "OK" -ForegroundColor Green
            }
            catch {
                Write-Host "An error occured while adding a new scope" -ForegroundColor Red
                Stop-Transcript
                break
            }
        } else {
            Write-Host $scope.Name "already exists. Scope won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually scope's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No scopes to import" -ForegroundColor Yellow
}

Write-Host "Setting Administrators config... "
if($xdoc.site.administrators){
    $administrators = $xdoc.site.administrators.administrator
    foreach($administrator in $administrators){
        if(!(get-adminadministrator -Name $administrator.name -errorAction SilentlyContinue)){
            Write-host "Adding new admin" $administrator.Name"... " -NoNewline
            try {
                New-AdminAdministrator -Name $administrator.Name | Out-Null
                Write-Host "OK" -ForegroundColor Green
                Write-host "Setting permissions to" $administrator.name"... " -NoNewline
                try {
                    Add-AdminRight -Role $administrator.rolename -Scope $administrator.scopeName -Administrator $administrator.name
                    Write-host "OK" -ForegroundColor Green
                }
                catch {
                    Write-Host "An error occured while setting permissions for" $administrator.name -ForegroundColor Red                        
                    Stop-Transcript
                    break
                }
            }
            catch {
                Write-Host "An error occured while adding a new administrator" -ForegroundColor Red
                Stop-Transcript
                break
            }
        } else {
            Write-Host $administrator.Name "already exists. Administrator won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually administrator's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No administrators to import" -ForegroundColor Yellow
}

################################################################################################
#Setting AcctIdentityPool
################################################################################################
<#
Write-Host "Setting AcctIdentityPool config... "
if($xdoc.site.AcctIdentityPools){
    $AcctIdentityPools = $xdoc.site.AcctIdentityPools.AcctIdentityPool
    foreach($AcctIdentityPool in $AcctIdentityPools){
        if(!(get-AcctIdentityPool -IdentityPoolName $AcctIdentityPool.IdentityPoolName -errorAction SilentlyContinue)){
            Write-host "Adding new AcctIdentityPool" $AcctIdentityPool.IdentityPoolName"... " -NoNewline
            $Command = "New-AcctIdentityPool -IdentityPoolName """ + $AcctIdentityPool.IdentityPoolName + """"
            $command += " -NamingScheme """ + $AcctIdentityPool.NamingScheme  + """"
            $command += " -NamingSchemeType """ + $AcctIdentityPool.NamingSchemeType + """"
            $command += " -OU """+ $AcctIdentityPool.OU + """"
            $command += " -Domain """+ $AcctIdentityPool.Domain + """"
            try {
                $count = $AcctIdentityPool.scope.count
                $i=0
                $command += " -Scope """
                while ($i -lt $count) {
                    $command += $AcctIdentityPool.scope[$i]
                    if($i -ne ($count - 1)){
                        $command += ""","""
                    } else {
                        $command += """"
                    }
                    $i++
                }
            }
            catch {
                try { #Only one scope is declared
                    $command += " -Scope """ + $provscheme.scope + """"
                }
                catch {
                    #No Scope to assign
                }
            }
            #write-host $command
            #Pause
            try {
                Invoke-Expression $command | Out-Null
            }
            catch {
                Write-Host "An error occured while adding a new IdentityPoolName" -ForegroundColor Red
                Stop-Transcript
                break
            }
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host $AcctIdentityPool.IdentityPoolName "already exists. IdentityPoolName won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually IdentityPoolName's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No AcctIdentityPools to import" -ForegroundColor Yellow
}
#>
################################################################################################
#Setting ProvSchemes
################################################################################################

<#
Write-Host "Setting ProvSchemes config... "
if($xdoc.site.provschemes){
    $provschemes = $xdoc.site.provschemes.provscheme
    foreach($provscheme in $provschemes){
        if(!(get-ProvScheme -ProvisioningSchemeName $provscheme.ProvisioningSchemeName -errorAction SilentlyContinue)){
            Write-host "Adding new ProvScheme" $provscheme.ProvisioningSchemeName"... " -NoNewline
            $command = "New-ProvScheme -ProvisioningSchemeName """ + $provscheme.ProvisioningSchemeName + """"
            $command += " -HostingUnitName """ + $provscheme.HostingUnitName + """"
            $command += " -IdentityPoolName """ + $provscheme.IdentityPoolName + """"
            if($provscheme.CleanOnBoot){
                $command += " -CleanOnBoot"
            }
            $command += " -MasterImageVM """ + $provscheme.MasterImageVM + """"
            $command += " -VMCpuCount """ +  $provscheme.CpuCount + """"
            $command += " -VMMemoryMB """ + $provscheme.MemoryMB + """"
            if($provscheme.UsePersonalVDiskStorage -match "True"){ #it is not a boolean but a string
                $command += " -UsePersonalVDiskStorage"
                #Require PersonalVDiskDriveLetter parameter
            }
            if($ProvScheme.UseWriteBackCache -match "True"){ #it is not a boolean but a string
                $command += " -UseWriteBackCache"
                $command += " -WriteBackCacheDiskSize """ + $provscheme.WriteBackCacheDiskSize + """"
                $command += " -WriteBackCacheMemorySize """ + $provscheme.WriteBackCacheMemorySize + """"
            }
            try {
                $count = $provscheme.scope.count
                $i=0
                $command += " -Scope """
                while ($i -lt $count) {
                    $command += $provscheme.scope[$i]
                    if($i -ne ($count - 1)){
                        $command += ""","""
                    } else {
                        $command += """"
                    }
                    $i++
                }
            }
            catch {
                try { #Only one scope is declared
                    $command += " -Scope """ + $provscheme.scope + """"
                }
                catch {
                    #No Scope to assign
                }
            }
            #write-host $command
            #Pause
            try {
                Invoke-Expression $command | Out-Null
            }
            catch {
                Write-Host "An error occured while adding a new ProvSchemes" -ForegroundColor Red
                Stop-Transcript
                break
            }
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host $provscheme.ProvisioningSchemeName "already exists. ProvScheme won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually ProvScheme's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No ProvSchemes to import" -ForegroundColor Yellow
}
#>
################################################################################################
#Setting Catalogs
################################################################################################

Write-Host "Setting Catalogs config... "
if($xdoc.site.Catalogs){
    $Catalogs = $xdoc.site.Catalogs.Catalog
    foreach($Catalog in $Catalogs){
        if(!(Get-BrokerCatalog -Name $Catalog.Name -errorAction SilentlyContinue)){
            Write-host "Adding new Catalog" $Catalog.Name"... " -NoNewline
            $command = "New-BrokerCatalog -Name """ + $Catalog.Name + """"
            $command += " -AllocationType """ + $Catalog.AllocationType + """"
            $command += " -Description """ + $Catalog.Description + """"
            $command += " -ProvisioningType """ + $Catalog.ProvisioningType + """"
            $command += " -SessionSupport """ + $Catalog.SessionSupport + """"
            $command += " -PersistUserChanges """ + $Catalog.PersistUserChanges + """"
            if($Catalog.IsRemotePC -match "True"){
                $command += " -IsRemotePC `$True"
            }
            if($Catalog.IsRemotePC -match "False"){
                $command += " -IsRemotePC `$False"
            }
            if($Catalog.MachinesArePhysical -match "True"){
                $command += " -MachinesArePhysical `$True"
            }
            if($Catalog.MachinesArePhysical -match "False"){
                $command += " -MachinesArePhysical `$False"
            }
            if($Catalog.ProvisioningSchemeName){
                $ProvisioningSchemeUid = (Get-ProvScheme -ProvisioningSchemeName $Catalog.ProvisioningSchemeName).ProvisioningSchemeUid
                $command += " -ProvisioningSchemeId """ + $ProvisioningSchemeUid + """"
            }
            try {
                $count = $Catalog.scope.count
                $i=0
                $command += " -Scope """
                while ($i -lt $count) {
                    $command += $Catalog.scope[$i]
                    if($i -ne ($count - 1)){
                        $command += ""","""
                    } else {
                        $command += """"
                    }
                    $i++
                }
            }
            catch {
                try { #Only one scope is declared
                    $command += " -Scope """ + $Catalog.scope + """"
                }
                catch {
                    #No Scope to assign
                }
            }
            #write-host $command
            #Pause
            try {
                Invoke-Expression $command | Out-Null
            }
            catch {
                Write-Host "An error occured while adding a new Catalog" -ForegroundColor Red
                Stop-Transcript
                break
            }
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host $Catalog.Name "already exists. Catalog won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually Catalog's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No Catalogs to import" -ForegroundColor Yellow
}

################################################################################################
#Setting DesktopGroups
################################################################################################

Write-Host "Setting DesktopGroups config... "
if($xdoc.site.DesktopGroups){
    $DesktopGroups = $xdoc.site.DesktopGroups.DesktopGroup
    foreach($DesktopGroup in $DesktopGroups){
        if(!(Get-BrokerDesktopGroup -Name $DesktopGroup.Name -errorAction SilentlyContinue)){
            Write-host "Adding new DesktopGroup" $DesktopGroup.Name"... " -NoNewline
            $command = "New-BrokerDesktopGroup -Name """ + $DesktopGroup.Name + """"
            $command += " -PublishedName """ + $DesktopGroup.PublishedName + """"
            $command += " -DesktopKind """ + $DesktopGroup.DesktopKind + """"
            $command += " -SessionSupport """ + $DesktopGroup.SessionSupport + """"
            $command += " -ShutdownDesktopsAfterUse """ + $DesktopGroup.ShutdownDesktopsAfterUse + """"
            if($DesktopGroup.AutomaticPowerOnForAssigned -match "True"){
                $command += " -AutomaticPowerOnForAssigned `$True"
            }
            if($DesktopGroup.AutomaticPowerOnForAssigned -match "False"){
                $command += " -AutomaticPowerOnForAssigned `$False"
            }
            if($DesktopGroup.AutomaticPowerOnForAssignedDuringPeak -match "True"){
                $command += " -AutomaticPowerOnForAssignedDuringPeak `$True"
            }
            if($DesktopGroup.AutomaticPowerOnForAssignedDuringPeak -match "False"){
                $command += " -AutomaticPowerOnForAssignedDuringPeak `$False"
            }
            $command += " -DeliveryType """ + $DesktopGroup.DeliveryType + """"
            $command += " -Description """ + $DesktopGroup.Description + """"
            if($DesktopGroup.Enabled -match "True"){
                $command += " -Enabled `$True"
            }
            if($DesktopGroup.Enabled -match "False"){
                $command += " -Enabled `$False"
            }
            $iconUid = $DesktopGroup.IconUid
            if(test-path -Path "./resources/$iconuid.txt"){
                $encodedData = Get-Content -Path "./resources/$iconuid.txt"
                $brokericon = New-BrokerIcon -EncodedData $encodedData
                $command += " -IconUid """ + $brokericon.Uid + """"
            }
            if($DesktopGroup.IsRemotePC -match "True"){
                $command += " -IsRemotePC `$True"
            }
            if($DesktopGroup.IsRemotePC -match "False"){
                $command += " -IsRemotePC `$False"
            }
            $command += " -OffPeakBufferSizePercent """ + $DesktopGroup.OffPeakBufferSizePercent + """"
            $command += " -OffPeakDisconnectAction """ + $DesktopGroup.OffPeakDisconnectAction + """"
            $command += " -OffPeakDisconnectTimeout """ + $DesktopGroup.OffPeakDisconnectTimeout + """"
            $command += " -OffPeakExtendedDisconnectAction	 """ + $DesktopGroup.OffPeakExtendedDisconnectAction	 + """"
            $command += " -OffPeakExtendedDisconnectTimeout	 """ + $DesktopGroup.OffPeakExtendedDisconnectTimeout	 + """"
            $command += " -OffPeakLogOffAction	 """ + $DesktopGroup.OffPeakLogOffAction	 + """"
            $command += " -OffPeakLogOffTimeout	 """ + $DesktopGroup.OffPeakLogOffTimeout	 + """"
            $command += " -PeakBufferSizePercent	 """ + $DesktopGroup.PeakBufferSizePercent	 + """"
            $command += " -PeakDisconnectAction	 """ + $DesktopGroup.PeakDisconnectAction	 + """"
            $command += " -PeakDisconnectTimeout	 """ + $DesktopGroup.PeakDisconnectTimeout	 + """"
            $command += " -PeakExtendedDisconnectAction	 """ + $DesktopGroup.PeakExtendedDisconnectAction	 + """"
            $command += " -PeakExtendedDisconnectTimeout	 """ + $DesktopGroup.PeakExtendedDisconnectTimeout	 + """"
            $command += " -PeakLogOffAction	 """ + $DesktopGroup.PeakLogOffAction	 + """"
            $command += " -PeakLogOffTimeout	 """ + $DesktopGroup.PeakLogOffTimeout	 + """"
            try {
                $count = $DesktopGroup.scope.count
                $i=0
                $command += " -Scope """
                while ($i -lt $count) {
                    $command += $DesktopGroup.scope[$i]
                    if($i -ne ($count - 1)){
                        $command += ""","""
                    } else {
                        $command += """"
                    }
                    $i++
                }
            }
            catch {
                try { #Only one scope is declared
                    $command += " -Scope """ + $DesktopGroup.scope + """"
                }
                catch {
                    #No Scope to assign
                }
            }
            write-host $command
            Pause
            try {
                Invoke-Expression $command #| Out-Null
            }
            catch {
                Write-Host "An error occured while adding a new DesktopGroup" -ForegroundColor Red
                Stop-Transcript
                break
            }
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host $DesktopGroup.Name "already exists. DesktopGroup won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually DesktopGroup's properties." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No DesktopGroups to import" -ForegroundColor Yellow
}

Stop-Transcript
break


################################################################################################
#Enumerating PublishedApps
################################################################################################

Write-Host "Enumerating Published Apps config... " -NoNewline
try {
    $oXMLPublishedApps = $oXMLRoot.appendChild($Doc.CreateElement("PublishedApps"))
    $PublishedApps = Get-BrokerApplication
    foreach ($PublishedApp in $PublishedApps) {
        $oxmlPublishedApp = $oXMLPublishedApps.appendChild($Doc.CreateElement("PublishedApp"))
        $oxmlPublishedAppname = $oxmlPublishedApp.appendChild($Doc.CreateElement("Name"))
        $oxmlPublishedAppname.InnerText = $PublishedApp.Name
        $oxmlPublishedAppDescription = $oxmlPublishedApp.appendChild($Doc.CreateElement("Description"))
        $oxmlPublishedAppDescription.InnerText = $PublishedApp.Description
        $oxmlPublishedAppCommandLineExecutable = $oxmlPublishedApp.appendChild($Doc.CreateElement("CommandLineExecutable"))
        $oxmlPublishedAppCommandLineExecutable.InnerText = $PublishedApp.CommandLineExecutable
        $oxmlPublishedAppCommandLineArguments = $oxmlPublishedApp.appendChild($Doc.CreateElement("CommandLineArguments"))
        $oxmlPublishedAppCommandLineArguments.InnerText = $PublishedApp.CommandLineArguments
        $oxmlPublishedAppWorkingDirectory = $oxmlPublishedApp.appendChild($Doc.CreateElement("WorkingDirectory"))
        $oxmlPublishedAppWorkingDirectory.InnerText = $PublishedApp.WorkingDirectory
        $oxmlPublishedAppPublishedName = $oxmlPublishedApp.appendChild($Doc.CreateElement("PublishedName"))
        $oxmlPublishedAppPublishedName.InnerText = $PublishedApp.PublishedName
        $oxmlPublishedAppIconUid = $oxmlPublishedApp.appendChild($Doc.CreateElement("IconUid"))
        $oxmlPublishedAppIconUid.InnerText = $PublishedApp.IconUid
        $iconUid = $PublishedApp.IconUid
        if(!(test-path -Path "./resources/$iconuid.txt")){
            (Get-BrokerIcon -Uid $iconUid).EncodedIconData | Out-File "./resources/$iconuid.txt"
        }
        $oxmlPublishedAppAdminFolderName = $oxmlPublishedApp.appendChild($Doc.CreateElement("AdminFolderName"))
        $oxmlPublishedAppAdminFolderName.InnerText = $PublishedApp.AdminFolderName
        $oxmlPublishedAppApplicationName = $oxmlPublishedApp.appendChild($Doc.CreateElement("ApplicationName"))
        $oxmlPublishedAppApplicationName.InnerText = $PublishedApp.ApplicationName
        $oxmlPublishedAppApplicationType = $oxmlPublishedApp.appendChild($Doc.CreateElement("ApplicationType"))
        $oxmlPublishedAppApplicationType.InnerText = $PublishedApp.ApplicationType
        $AssociatedDesktopGroupUids = $PublishedApp.AssociatedDesktopGroupUids
        foreach ($AssociatedDesktopGroupUid in $AssociatedDesktopGroupUids){
            $oxmlPublishedAppAssociatedDesktopGroupUid = $oxmlPublishedApp.appendChild($Doc.CreateElement("AssociatedDesktopGroupUid"))
            $oxmlPublishedAppAssociatedDesktopGroupUid.InnerText = $AssociatedDesktopGroupUid
        }
        $AssociatedUserFullNames = $PublishedApp.AssociatedUserFullNames
        foreach ($AssociatedUserFullName in $AssociatedUserFullNames){
            $oxmlPublishedAppAssociatedUserFullName = $oxmlPublishedApp.appendChild($Doc.CreateElement("AssociatedUserFullName"))
            $oxmlPublishedAppAssociatedUserFullName.InnerText = $AssociatedUserFullName
        }
        $oxmlPublishedAppEnabled = $oxmlPublishedApp.appendChild($Doc.CreateElement("Enabled"))
        $oxmlPublishedAppEnabled.InnerText = $PublishedApp.Enabled
        $oxmlPublishedAppMaxPerUserInstances = $oxmlPublishedApp.appendChild($Doc.CreateElement("MaxPerUserInstances"))
        $oxmlPublishedAppMaxPerUserInstances.InnerText = $PublishedApp.MaxPerUserInstances
        $oxmlPublishedAppMaxTotalInstances = $oxmlPublishedApp.appendChild($Doc.CreateElement("MaxTotalInstances"))
        $oxmlPublishedAppMaxTotalInstances.InnerText = $PublishedApp.MaxTotalInstances
        $oxmlPublishedAppShortcutAddedToDesktop = $oxmlPublishedApp.appendChild($Doc.CreateElement("ShortcutAddedToDesktop"))
        $oxmlPublishedAppShortcutAddedToDesktop.InnerText = $PublishedApp.ShortcutAddedToDesktop
        $oxmlPublishedAppShortcutAddedToStartMenu = $oxmlPublishedApp.appendChild($Doc.CreateElement("ShortcutAddedToStartMenu"))
        $oxmlPublishedAppShortcutAddedToStartMenu.InnerText = $PublishedApp.ShortcutAddedToStartMenu
        $oxmlPublishedAppStartMenuFolder = $oxmlPublishedApp.appendChild($Doc.CreateElement("StartMenuFolder"))
        $oxmlPublishedAppStartMenuFolder.InnerText = $PublishedApp.StartMenuFolder
        $oxmlPublishedAppUserFilterEnabled = $oxmlPublishedApp.appendChild($Doc.CreateElement("UserFilterEnabled"))
        $oxmlPublishedAppUserFilterEnabled.InnerText = $PublishedApp.UserFilterEnabled
        $oxmlPublishedAppVisible = $oxmlPublishedApp.appendChild($Doc.CreateElement("Visible"))
        $oxmlPublishedAppVisible.InnerText = $PublishedApp.Visible
    }
}
catch {
    Write-Host "An error occured while enumerating Published Apps config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green


$doc.save("$ExportFile")
Stop-Transcript
break