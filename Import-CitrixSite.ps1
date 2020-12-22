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


Write-Host "Setting AcctIdentityPool config... "
if($xdoc.site.AcctIdentityPools){
    $AcctIdentityPools = $xdoc.site.AcctIdentityPools.AcctIdentityPool
    foreach($AcctIdentityPool in $AcctIdentityPools){
        if(!(get-AcctIdentityPool -IdentityPoolName $AcctIdentityPool.IdentityPoolName -errorAction SilentlyContinue)){
            Write-host "Adding new AcctIdentityPool" $AcctIdentityPool.IdentityPoolName"... " -NoNewline
            #try {
                $Command = "New-AcctIdentityPool -IdentityPoolName $AcctIdentityPool.IdentityPoolName "
                $command += "-NamingScheme $AcctIdentityPool.NamingScheme "
                $command += "-NamingSchemeType $AcctIdentityPool.NamingSchemeType "
                $command += "-OU $AcctIdentityPool.OU "
                $command += "-Domain $AcctIdentityPool.Domain "
                try {
                    $count = $AcctIdentityPool.scope.count | Out-Null
                    $i=0
                    if($count -eq 1){
                        $command += "-Scope $AcctIdentityPool.scope"
                    } else {
                        $command += "Scope "
                        while ($i -lt $count) {
                            $i++
                            $command += $AcctIdentityPool.scope[$i]
                            if($i -ne ($count - 1)){
                                $command += ","
                            }
                        }
                    }
                }
                catch {
                    #No Scope to assign
                }
                write-host $command
                Pause
                Invoke-Expression $command
                Write-Host "OK" -ForegroundColor Green
            <#}
            catch {
                Write-Host "An error occured while adding a new ProvScheme" -ForegroundColor Red
                Stop-Transcript
                break
            }#>
        } else {
            Write-Host $AcctIdentityPool.IdentityPoolName "already exists. IdentityPoolName won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually IdentityPoolName's properties." -ForegroundColor Yellow
        }
        Pause
    }
} else {
    Write-Host "No AcctIdentityPool to import" -ForegroundColor Yellow
}



Stop-Transcript
break

################################################################################################
#Enumerating ProvSchemes
################################################################################################


Write-Host "Setting ProvSchemes config... "
if($xdoc.site.provschemes){
    $provschemes = $xdoc.site.provschemes.provscheme
    foreach($provscheme in $provschemes){
        if(!(get-ProvScheme -ProvisioningSchemeName $provscheme.ProvisioningSchemeName -errorAction SilentlyContinue)){
            Write-host "Adding new ProvScheme" $provscheme.ProvisioningSchemeName"... " -NoNewline
            #try {
                New-ProvScheme -ProvisioningSchemeName $provscheme.ProvisioningSchemeName `
                    -HostingUnitName $provscheme.HostingUnitName `
                    -IdentityPoolName $provscheme.IdentityPoolName `
                    -CleanOnBoot $provscheme.CleanOnBoot `
                    -MasterImageVM $provscheme.MasterImageVM `
                    -VMCpuCount  $provscheme.CpuCount `
                    -VMMemoryMB $provscheme.MemoryMB `
                    -UsePersonalVDiskStorage $provscheme.UsePersonalVDiskStorage `
                    -UseWriteBackCache $ProvScheme.UseWriteBackCache `
                    -WriteBackCacheDiskSize $provscheme.WriteBackCacheDiskSize `
                    -WriteBackCacheMemorySize $provscheme.WriteBackCacheMemorySize
                try {
                    $count = $provscheme.scope.count | Out-Null
                    $i=0
                    if($count -eq 1){
                        #No index to referer to when ProvScheme has only one scope assigned
                        Get-ProvScheme -ProvisioningSchemeName $provscheme.ProvisioningSchemeName | Add-ProvSchemeScope -scope $provscheme.scope
                    } else {
                        while ($i -lt $count) {
                            $i++
                            Get-ProvScheme -ProvisioningSchemeName $provscheme.ProvisioningSchemeName | Add-ProvSchemeScope -scope $provscheme.scope[$i]
                        }
                    }
                }
                catch {
                    #No Scope to assign
                }
                Write-Host "OK" -ForegroundColor Green

            <#}
            catch {
                Write-Host "An error occured while adding a new ProvScheme" -ForegroundColor Red
                Stop-Transcript
                break
            }#>
        } else {
            Write-Host $provscheme.ProvisioningSchemeName "already exists. ProvScheme won't be modified by this script." -ForegroundColor Yellow
            Write-Host "Check manually ProvScheme's properties." -ForegroundColor Yellow
        }
        Pause
    }
} else {
    Write-Host "No ProvSchemes to import" -ForegroundColor Yellow
}



################################################################################################
#Enumerating Catalogs
################################################################################################

Write-Host "Enumerating Catalogs config... "
try {
    $oXMLCatalogs = $oXMLRoot.appendChild($Doc.CreateElement("Catalogs"))
    $Catalogs = Get-BrokerCatalog
    foreach ($Catalog in $Catalogs) {
        $oxmlCatalog = $oXMLCatalogs.appendChild($Doc.CreateElement("Catalog"))
        $oxmlCatalogname = $oxmlCatalog.appendChild($Doc.CreateElement("Name"))
        $oxmlCatalogname.InnerText = $Catalog.Name
        $oxmlCatalogDescription = $oxmlCatalog.appendChild($Doc.CreateElement("Description"))
        $oxmlCatalogDescription.InnerText = $Catalog.Description
        $oxmlCatalogAllocationType = $oxmlCatalog.appendChild($Doc.CreateElement("AllocationType"))
        $oxmlCatalogAllocationType.InnerText = $Catalog.AllocationType
        $oxmlCatalogProvisioningType = $oxmlCatalog.appendChild($Doc.CreateElement("ProvisioningType"))
        $oxmlCatalogProvisioningType.InnerText = $Catalog.ProvisioningType
        $oxmlCatalogSessionSupport = $oxmlCatalog.appendChild($Doc.CreateElement("SessionSupport"))
        $oxmlCatalogSessionSupport.InnerText = $Catalog.SessionSupport
        $oxmlCatalogPersistUserChanges = $oxmlCatalog.appendChild($Doc.CreateElement("PersistUserChanges"))
        $oxmlCatalogPersistUserChanges.InnerText = $Catalog.PersistUserChanges
        $oxmlCatalogIsRemotePC = $oxmlCatalog.appendChild($Doc.CreateElement("IsRemotePC"))
        $oxmlCatalogIsRemotePC.InnerText = $Catalog.IsRemotePC
        $oxmlCatalogMachinesArePhysical = $oxmlCatalog.appendChild($Doc.CreateElement("MachinesArePhysical"))
        $oxmlCatalogMachinesArePhysical.InnerText = $Catalog.MachinesArePhysical
        $oxmlCatalogProvisioningSchemeId = $oxmlCatalog.appendChild($Doc.CreateElement("ProvisioningSchemeId"))
        $oxmlCatalogProvisioningSchemeId.InnerText = $Catalog.ProvisioningSchemeId
        $oxmlCatalogHypervisorConnectionUid = $oxmlCatalog.appendChild($Doc.CreateElement("HypervisorConnectionUid"))
        $oxmlCatalogHypervisorConnectionUid.InnerText = $Catalog.HypervisorConnectionUid
        $scopes = $Catalog.Scopes
        foreach ($scope in $scopes){
            $oxmlCatalogscope = $oxmlCatalog.appendChild($Doc.CreateElement("scope"))
            $oxmlCatalogscope.InnerText = $scope
        }
    }
}
catch {
    Write-Host "An error occured while enumerating Catalogs config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green



################################################################################################
#Enumerating DeliveryGroups
################################################################################################

Write-Host "Enumerating Delivery Groups config... " -NoNewline
try {
    $oXMLDeliveryGroups = $oXMLRoot.appendChild($Doc.CreateElement("DeliveryGroups"))
    $DeliveryGroups = Get-BrokerDesktopGroup
    foreach ($DeliveryGroup in $DeliveryGroups) {
        $oxmlDeliveryGroup = $oXMLDeliveryGroups.appendChild($Doc.CreateElement("DeliveryGroup"))
        $oxmlDeliveryGroupname = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("Name"))
        $oxmlDeliveryGroupname.InnerText = $DeliveryGroup.Name
        $oxmlDeliveryGroupPublishedName = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PublishedName"))
        $oxmlDeliveryGroupPublishedName.InnerText = $DeliveryGroup.PublishedName
        $oxmlDeliveryGroupDescription = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("Description"))
        $oxmlDeliveryGroupDescription.InnerText = $DeliveryGroup.Description
        $oxmlDeliveryGroupDeliveryType = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("DeliveryType"))
        $oxmlDeliveryGroupDeliveryType.InnerText = $DeliveryGroup.DeliveryType
        $oxmlDeliveryGroupIconUid = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("IconUid"))
        $oxmlDeliveryGroupIconUid.InnerText = $DeliveryGroup.IconUid
        $iconUid = $DeliveryGroup.IconUid
        if(!(test-path -Path "./resources/$iconuid.txt")){
            (Get-BrokerIcon -Uid $iconUid).EncodedIconData | Out-File "./resources/$iconuid.txt"
        }
        $oxmlDeliveryGroupDesktopKind = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("DesktopKind"))
        $oxmlDeliveryGroupDesktopKind.InnerText = $DeliveryGroup.DesktopKind
        $oxmlDeliveryGroupEnabled = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("Enabled"))
        $oxmlDeliveryGroupEnabled.InnerText = $DeliveryGroup.Enabled
        $oxmlDeliveryGroupAutomaticPowerOnForAssigned = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("AutomaticPowerOnForAssigned"))
        $oxmlDeliveryGroupAutomaticPowerOnForAssigned.InnerText = $DeliveryGroup.AutomaticPowerOnForAssigned
        $oxmlDeliveryGroupAutomaticPowerOnForAssignedDuringPeak = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("AutomaticPowerOnForAssignedDuringPeak"))
        $oxmlDeliveryGroupAutomaticPowerOnForAssignedDuringPeak.InnerText = $DeliveryGroup.AutomaticPowerOnForAssignedDuringPeak
        $oxmlDeliveryGroupIsRemotePC = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("IsRemotePC"))
        $oxmlDeliveryGroupIsRemotePC.InnerText = $DeliveryGroup.IsRemotePC
        $oxmlDeliveryGroupOffPeakBufferSizePercent = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakBufferSizePercent"))
        $oxmlDeliveryGroupOffPeakBufferSizePercent.InnerText = $DeliveryGroup.OffPeakBufferSizePercent
        $oxmlDeliveryGroupOffPeakDisconnectAction = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakDisconnectAction"))
        $oxmlDeliveryGroupOffPeakDisconnectAction.InnerText = $DeliveryGroup.OffPeakDisconnectAction
        $oxmlDeliveryGroupOffPeakDisconnectTimeout = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakDisconnectTimeout"))
        $oxmlDeliveryGroupOffPeakDisconnectTimeout.InnerText = $DeliveryGroup.OffPeakDisconnectTimeout
        $oxmlDeliveryGroupOffPeakExtendedDisconnectAction = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakExtendedDisconnectAction"))
        $oxmlDeliveryGroupOffPeakExtendedDisconnectAction.InnerText = $DeliveryGroup.OffPeakExtendedDisconnectAction
        $oxmlDeliveryGroupOffPeakExtendedDisconnectTimeout = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakExtendedDisconnectTimeout"))
        $oxmlDeliveryGroupOffPeakExtendedDisconnectTimeout.InnerText = $DeliveryGroup.OffPeakExtendedDisconnectTimeout
        $oxmlDeliveryGroupOffPeakLogOffAction = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakLogOffAction"))
        $oxmlDeliveryGroupOffPeakLogOffAction.InnerText = $DeliveryGroup.OffPeakLogOffAction
        $oxmlDeliveryGroupOffPeakLogOffTimeout = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("OffPeakLogOffTimeout"))
        $oxmlDeliveryGroupOffPeakLogOffTimeout.InnerText = $DeliveryGroup.OffPeakLogOffTimeout
        $oxmlDeliveryGroupPeakBufferSizePercent = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakBufferSizePercent"))
        $oxmlDeliveryGroupPeakBufferSizePercent.InnerText = $DeliveryGroup.PeakBufferSizePercent
        $oxmlDeliveryGroupPeakDisconnectAction = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakDisconnectAction"))
        $oxmlDeliveryGroupPeakDisconnectAction.InnerText = $DeliveryGroup.PeakDisconnectAction
        $oxmlDeliveryGroupPeakDisconnectTimeout = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakDisconnectTimeout"))
        $oxmlDeliveryGroupPeakDisconnectTimeout.InnerText = $DeliveryGroup.PeakDisconnectTimeout
        $oxmlDeliveryGroupPeakExtendedDisconnectAction = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakExtendedDisconnectAction"))
        $oxmlDeliveryGroupPeakExtendedDisconnectAction.InnerText = $DeliveryGroup.PeakExtendedDisconnectAction
        $oxmlDeliveryGroupPeakExtendedDisconnectTimeout = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakExtendedDisconnectTimeout"))
        $oxmlDeliveryGroupPeakExtendedDisconnectTimeout.InnerText = $DeliveryGroup.PeakExtendedDisconnectTimeout
        $oxmlDeliveryGroupPeakLogOffAction = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakLogOffAction"))
        $oxmlDeliveryGroupPeakLogOffAction.InnerText = $DeliveryGroup.PeakLogOffAction
        $oxmlDeliveryGroupPeakLogOffTimeout = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("PeakLogOffTimeout"))
        $oxmlDeliveryGroupPeakLogOffTimeout.InnerText = $DeliveryGroup.PeakLogOffTimeout
        $scopes = $DeliveryGroup.Scopes
        foreach ($scope in $scopes){
            $oxmlDeliveryGroupscope = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("scope"))
            $oxmlDeliveryGroupscope.InnerText = $scope
        }
        $oxmlDeliveryGroupSessionSupport = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("SessionSupport"))
        $oxmlDeliveryGroupSessionSupport.InnerText = $DeliveryGroup.SessionSupport
        $oxmlDeliveryGroupShutdownDesktopsAfterUse = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("ShutdownDesktopsAfterUse"))
        $oxmlDeliveryGroupShutdownDesktopsAfterUse.InnerText = $DeliveryGroup.ShutdownDesktopsAfterUse
        $Tags = $DeliveryGroup.Tags
        foreach ($Tag in $Tags){
            $oxmlDeliveryGroupTag = $oxmlDeliveryGroup.appendChild($Doc.CreateElement("Tag"))
            $oxmlDeliveryGroupTag.InnerText = $tag
        }
    }
}
catch {
    Write-Host "An error occured while enumerating Delivery Groups config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green

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