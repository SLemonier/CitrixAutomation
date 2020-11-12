<#
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
 VDI_Provisionning.ps1 -VDICount 10 -Catalog "DTC1","DTC2" -Split -DeliveryGroup "Desktop" -Log "C:\temp"
#>

[CmdletBinding()]
Param(
    # Declaring input variables for the script
    [Parameter(Mandatory=$false)] [string]$DeliveryController,
    [Parameter(Mandatory=$true)] [int]$VDICount,
    [Parameter(Mandatory=$true)] [string[]]$Catalog,
    [Parameter(Mandatory=$false)] [switch]$Split,
    [Parameter(Mandatory=$true)] [string]$DeliveryGroup,
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\VDI_Provisionning.log"
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

#Check if the catalog(s) exist(s)
$errorcount = 0
$catalogcount = 0
foreach($cat in $Catalog){
    $catalogcount++
    Write-Host "Checking the catalog $cat..." -NoNewline
    if(Get-BrokerCatalog -AdminAddress $DeliveryController -Name $cat -ErrorAction Ignore){
        Write-Host "OK" -ForegroundColor Green
    } else {
        Write-Host "Failed." -ForegroundColor Red
        Write-Host "Cannot find catalog $cat." -ForegroundColor Red
        $errorcount++
    }
}
#If one or more catalog(s) got an error, stop processing
if($errorcount -ne 0){
    Write-Host "One of the catalog does not exist. Please, check there is no mistype or the catalog(s) exist(s) before continuing." -ForegroundColor Red
    Stop-Transcript 
    break
}

#Check if the VDICount can be split equally when -Split is set
if($Split){
    Write-Host "Checking VDICount can be split equally between the catalogs... " -NoNewline
    if($VDICount%$catalogcount){
        Write-Host "No" -ForegroundColor Yellow
        while ($continue -notlike "y" -and $continue -notlike "n") {
            $continue = Read-Host "VDICount cannot be split equally between the catalogs. Do you want to continue and split unevenly between the catalogs? Y/N"
        }
        if($continue -match "y"){
            $VDICount = [math]::Floor($VDICount/$catalogcount)
            Write-Host "$VDICount VM(s) will be created in each catalog." -ForegroundColor Yellow
            while ($continue -notlike "y" -and $reboot -notlike "n") {
                $continue = Read-Host "Do you want to continue? Y/N"
            }
            if($continue -notmatch "y"){
                Write-Host "Execution ended by the user." -ForegroundColor Yellow
                Stop-Transcript 
                break
            }
        } else {
            Write-Host "Execution ended by the user." -ForegroundColor Yellow
                Stop-Transcript 
                break
        }
    }
}

#DELIVERYGROUP
<#


#>


#Stop logging
Stop-Transcript 





<#
function ProvisionWindows10 {
    param (
        [parameter(position=0,Mandatory=$true)] $VDICount
    )
    $VDICount = $VDICount / 2
    #Provision VDI on GV1 Catalog
    $IdentityPool = Get-AcctIdentityPool -IdentityPoolName "Windows 10 - GV1 LUN14x"
    Log "INFO: Creating Machine Account for GV1 Pool"
    $adAccounts = New-AcctADAccount -Count $VDICount -IdentityPoolUid $IdentityPool.IdentityPoolUid
    Log "INFO: Creating the virtual machines"
    $provTaskId = New-ProvVM -AdAccountName @($adAccounts.SuccessfulAccounts) -ProvisioningSchemeName "Windows 10 - GV1 LUN14x" -RunAsynchronously
    $provtask = Get-ProvTask -TaskId $provTaskId
    $totalpercent = 0
    While($provtask.Active -eq $true){
        try {
            $totalpercent = If ($provTask.TaskProgress) {$provTask.TaskProgress} else {0}
        }
        catch {
        }
        Write-Progress -Activity "Tracking progress" -status  "$totalPercent% Complete:" -percentComplete $totalpercent
        Start-Sleep 3
        $provtask = Get-ProvTask -TaskId $provTaskId
    }
    $ProvVMS = Get-ProvVM -ProvisioningSchemeUid "f58e430f-5760-447c-a611-4d015ffdf5f2" | Where-Object {$_.Tag -ne "Brokered"}
    Log "INFO: Assigning machines to the Catalog"
    Foreach($VM in $ProvVMS){
        $VMName = $VM.VMName
        Log "INFO: Locking VM $VMName"
        Lock-ProvVM -ProvisioningSchemeName "Windows 10 - GV1 LUN14x" -Tag "Brokered" -VMID @($VM.VMId)
        Log "INFO: Adding VM $VMName"
        New-BrokerMachine -Cataloguid "174" -MachineName $VM.ADAccountName | Out-Null
        Add-BrokerMachine -MachineName "adir\$VMName" -DesktopGroup "Windows 10"
    }
    Log "INFO: $VDICount VDI created in Windows 10 - GV1 LUN14x and added to Windows 10 Desktop Group"
    #Reset variables
    $adAccounts = $null
    $ProvVMS = $null
    #Provision VDI on GV2 Catalog
    $IdentityPool = Get-AcctIdentityPool -IdentityPoolName "Windows 10 - GV2 LUN24x"
    Log "INFO: Creating Machine Account for GV2 Pool"
    $adAccounts = New-AcctADAccount -Count $VDICount -IdentityPoolUid $IdentityPool.IdentityPoolUid
    Log "INFO: Creating the virtual machines"
    $provTaskId = New-ProvVM -AdAccountName @($adAccounts.SuccessfulAccounts) -ProvisioningSchemeName "Windows 10 - GV2 LUN24x" -RunAsynchronously
    $provtask = Get-ProvTask -TaskId $provTaskId
    $totalpercent = 0
    While($provtask.Active -eq $true){
        try {
            $totalpercent = If ($provTask.TaskProgress) {$provTask.TaskProgress} else {0}
        }
        catch {
        }
        Write-Progress -Activity "Tracking progress" -status  "$totalPercent% Complete:" -percentComplete $totalpercent
        Start-Sleep 3
        $provtask = Get-ProvTask -TaskId $provTaskId
    }
    $ProvVMS = Get-ProvVM -ProvisioningSchemeUid "85a29b0a-87fe-4066-a8b6-03c3f338c400" | Where-Object {$_.Tag -ne "Brokered"}
    Log "INFO: Assigning machines to the Catalog"
    Foreach($VM in $ProvVMS){
        $VMName = $VM.VMName
        Log "INFO Locking VM $VMName"
        Lock-ProvVM -ProvisioningSchemeName "Windows 10 - GV2 LUN24x" -Tag "Brokered" -VMID @($VM.VMId)
        Log "INFO: Adding VM $VMName"
        New-BrokerMachine -Cataloguid "170" -MachineName $VM.ADAccountName | Out-Null
        Add-BrokerMachine -MachineName "adir\$VMName" -DesktopGroup "Windows 10"
    }
    Log "INFO: $VDICount VDI created in Windows 10 - GV2 LUN24x and added to Windows 10 Desktop Group"
}

Write-Host `r`n "Continual Progress Report is also being saved to" $OutFilePath -BackgroundColor Yellow -ForeGroundColor DarkBlue
Log "INFO: Script started by $env:USERDOMAIN\$env:USERNAME"
ProvisionWindows10 -VDIcount $VDICount
Log "####################################################################################################"
#>