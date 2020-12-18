<#


$XMLDocument = [XML](Get-Content .\export.xml)
PS C:\Users\sleadm\Desktop> foreach($role in $roles.childnodes){write-host $role.name; foreach($permission in $role.perm
ission){write-host "permission: " $permission}}











 .Synopsis
 Provision a given number of VM(s) in one or more MCS catalog(s) and assign the VM(s) to a delivery group.

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
    [Parameter(Mandatory=$false)] [string]$DeliveryController,
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\Export-CitrixSite.log"
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

#Check if export file already exists
Write-Host "Creating XML file... " -NoNewline
#Fixing path to save XML if $ExportFile is not set
$XMLPath = (Get-Location).Path
$ExportFile = "$XMLPath\export.xml"

if(Test-Path -Path $ExportFile){
    Write-Host "File already exists" -ForegroundColor Yellow
    $overwrite = $null
    while ($overwrite -notlike "y" -and $overwrite -notlike "n") {
        $overwrite = Read-Host "Do you want to overwrite existing file? Y/N"
    }
    if($overwrite -like "y"){
        try {
            Remove-Item -Path $ExportFile -Force | Out-Null
            [xml]$Doc = New-Object System.Xml.XmlDocument
            $Doc.CreateXmlDeclaration("1.0","UTF-8",$null) | Out-Null
            $oXMLRoot=$Doc.CreateElement("site")
            $Doc.AppendChild($oXMLRoot) | Out-Null
            Write-Host "OK" -ForegroundColor Green
        }
        catch {
            Write-Host "An error occured while deleting existing file" -ForegroundColor Red
            Stop-Transcript
            break
        }
    } else {
        Write-Host "Chose another file name to export the configuration" -ForegroundColor Yellow
        Stop-Transcript
        break
    }
} else {
    [xml]$Doc = New-Object System.Xml.XmlDocument
    $Doc.CreateXmlDeclaration("1.0","UTF-8",$null) | Out-Null
    $oXMLRoot=$Doc.CreateElement("site")
    $Doc.AppendChild($oXMLRoot) | Out-Null
    Write-Host "OK" -ForegroundColor Green
}

################################################################################################
#Enumerating Site's Tags
################################################################################################

Write-Host "Enumerating Site's Tags... " -NoNewline
try {
    $oXMLTags = $oXMLRoot.appendChild($Doc.CreateElement("Tags"))
    $tags = Get-BrokerTag
    foreach ($Tag in $Tags) {
        $oxmlTag = $oXMLTags.appendChild($Doc.CreateElement("Tag"))
        $oxmltagName = $oXMLTag.appendChild($Doc.CreateElement("Name"))
        $oxmltagName.InnerText = $Tag.Name
    }
}
catch {
    Write-Host "An error occured while enumerating Site's tags" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green

################################################################################################
#Enumerating Site's Administrators
################################################################################################

Write-Host "Enumerating Roles config... " -NoNewline
try {
    $oXMLRoles = $oXMLRoot.appendChild($Doc.CreateElement("Roles"))
    $Roles = get-adminRole
    foreach ($Role in $Roles) {
        $oxmlRole = $oXMLRoles.appendChild($Doc.CreateElement("Role"))
        $oxmlrolename = $oxmlRole.appendChild($Doc.CreateElement("Name"))
        $oxmlrolename.InnerText = $Role.Name
        $permissions = $Role.Permissions
        foreach ($permission in $permissions){
            $oxmlrolepermission = $oxmlrole.appendChild($Doc.CreateElement("Permission"))
            $oxmlrolepermission.InnerText = $permission
        }
    }
}
catch {
    Write-Host "An error occured while enumerating Roles config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green

Write-Host "Enumerating Scopes config... " -NoNewline
try {
    $oXMLScopes = $oXMLRoot.appendChild($Doc.CreateElement("Scopes"))
    $scopes = get-adminscope
    foreach ($scope in $scopes) {
        $oxmlscope = $oXMLscopes.appendChild($Doc.CreateElement("Scope"))
        $oxmlscopename = $oxmlscope.appendChild($Doc.CreateElement("Name"))
        $oxmlscopename.InnerText = $scope.Name
    }
}
catch {
    Write-Host "An error occured while enumerating Scopes config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green

Write-Host "Enumerating Administrators config... " -NoNewline
try {
    $oXMLadmins = $oXMLRoot.appendChild($Doc.CreateElement("Administrators"))
    $admins = get-adminadministrator
    foreach ($admin in $admins) {
        $oxmladmin = $oXMLadmins.appendChild($Doc.CreateElement("Administrator"))
        $oxmladminname = $oxmladmin.appendChild($Doc.CreateElement("Name"))
        $oxmladminname.InnerText = $admin.Name
        $oxmladminEnabled = $oxmladmin.appendChild($Doc.CreateElement("Enabled"))
        $oxmladminEnabled.InnerText = $admin.Enabled
        $oxmladminrolename = $oxmladmin.appendChild($Doc.CreateElement("RoleName"))
        $oxmladminrolename.InnerText = $admin.Rights.RoleName
        $oxmladminScopeName = $oxmladmin.appendChild($Doc.CreateElement("ScopeName"))
        $oxmladminScopeName.InnerText = $admin.Rights.ScopeName
    }
}
catch {
    Write-Host "An error occured while enumerating Administrators config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green

################################################################################################
#Enumerating Catalogs
################################################################################################

Write-Host "Enumerating Catalogs config... " -NoNewline
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
            $oxmlCatalogscope.InnerText = $permission
        }
    }
}
catch {
    Write-Host "An error occured while enumerating Catalogs config" -ForegroundColor Red
    Stop-Transcript
    break
} 
Write-Host "OK" -ForegroundColor Green






$doc.save("$ExportFile")
Stop-Transcript
break
