<#
 .Synopsis
 Configure local machine for autologon as described in James Rankin's article (https://james-rankin.com/articles/the-ultimate-guide-to-windows-logon-optimizations-part-3/).
 .Description
 Configure local machine autologon with given account (no need to specify the domain) and password.
 Configure logon script for the given account to logoff automatically.
 .Parameter Account
 Specifiy the account to use for autologon.
 This parameter is mandatory, ensure the account already exists in the domain.
 .Parameter Password
 Specifiy the account's password to use for autologon.
 This parameter is mandatory, ensure the password is correct.
 .Parameter Path
 Specify the folder where to store batches created by the script.
 This parameter is optionnal, by default, it will store in C:\Scripts.
 .Parameter Log
 Specifiy the output file for the logs.
 This parameter is optionnal, by default, it will create a file in the current directory.
 .Example
 # Configure local machine to autolog the user leogetz with the password P@ssw0rd
 SetAutologon.ps1 -Account leogetz -Password P@ssw0rd
 .Example
 # Configure local machine to autolog the user leogetz with the password P@ssw0rd and store the scripts in C:\Tmp
 SetAutologon.ps1 -Account leogetz -Password P@ssw0rd -Path C:\Tmp
 .Example
 # Configure local machine to autolog the user leogetz with the password P@ssw0rd and store the scripts in C:\Tmp
  and log the output in C:\Temp
 SetAutologon.ps1 -Account leogetz -Password P@ssw0rd -Path C:\Tmp -Log "C:\temp\test.log"
#>

[CmdletBinding()]
Param(
    # Declaring input variables for the script
    [Parameter(Mandatory=$true)] [string]$DeliveryController,
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\Morning_Report.log"
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

################################################################################################
#Processing
################################################################################################


$PCSMachines = (Get-BrokerMachine -CatalogName "W12 XenApp PCS 11*").-DNSName
foreach($machine in $PCSMachines){
    if((Get-BrokerMachine -DNSName $machine).PowerState -ne "On"){
        Write-Host "$machine is not powered on !"
        Write-host "Starting $machine manually..."
        
    }
}