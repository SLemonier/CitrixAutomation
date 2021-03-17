﻿<#
.SYNOPSIS
  Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
  Then email report to Citrix engineers.
.DESCRIPTION
  Check all PCS XenApp servers are up and running at 8:00.
  Email report to Citrix engineers.
.EXAMPLE
    PS C:\PSScript > Morning_Report.ps1 
    Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
.INPUTS
    None. You cannot pipe objects to this script.
.OUTPUTS
    No objects are output from this script. This script creates its own logs files.
.NOTES
  Version:        0.1
  Author:         Steven Lemonier
  Creation Date:  2021-03-08
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)] [switch]$Dev,$
    [Parameter(Mandatory=$false)] [string]$DeliveryController,
    [Parameter(Position = 1, Mandatory=$False)][Alias("OF")][ValidateNotNullOrEmpty()] [string]$OutFilePath="C:\Temp\Morning_Report.log"
)

Start-Transcript -Path $OutFilePath -Append

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

###################################################################################################################
# Mail settings
###################################################################################################################

# E-mail report details
$emailFrom = "citrix@hospicegeneral.ch"
$emailTo = "Steven.Lemonier@hospicegeneral.ch", "Cedric.Bosson@hospicegeneral.ch"
$smtpServer    = "smtp.implisis.ch"

$mailbody = $mailbody + "<!DOCTYPE html>"
$mailbody = $mailbody + "<html>"

$mailbody = $mailbody + "<head>"
$mailbody = $mailbody + "<style>"
$mailbody = $mailbody + "BODY{background-color:#fbfbfb; font-family: Arial;}"
$mailbody = $mailbody + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; width:60%; }"
$mailbody = $mailbody + "TH{border-width: 1px;padding: 0px;border-style: solid;border-color: black; text-align:left;}"
$mailbody = $mailbody + "TD{border-width: 1px;padding: 0px;border-style: solid;border-color: black;}"
$mailbody = $mailbody + "</style>"
$mailbody = $mailbody + "</head>"

$mailbody = $mailbody + "<body>"


###################################################################################################################
# Check all PCS XenApp servers are up and running at 8:00.
###################################################################################################################

$error = 0

$PCSServers = Get-BrokerMachine -DesktopGroupName "W12 XenApp PCS 11-2" | Select MachineName,PowerState,InMaintenanceMode,RegistrationState
foreach($server in $PCSServers){
    $MachineName = $server.MachineName
    if($server.Powerstate -ne "On"){
        $error++
        $mailbody += "<div style=""color:orange;"">$MachineName is not powered On! Script is powering On the server...</div>"
        New-BrokerHostingPowerAction -MachineName $MachineName -Action TurnOn
        Start-Sleep -Seconds 120
        if((Get-BrokerMachine -MachineName $MachineName).PowerState -ne "On" -and (Get-BrokerMachine -MachineName $MachineName).RegistrationState -ne "Registered"){
            $mailbody += "<div style=""color:red;"">Cannot start and register $MachineName. Please check the server manually.</div>"
        }
    }
    if($server.inMaintenanceMode -eq $true){
        $error++
        $mailbody += "<div style=""color:orange;"">$MachineName is in Maintenance Mode! Script is disabling maintenance mode...<br/></div>"
        Get-BrokerMachine -MachineName $MachineName | Set-BrokerMachine -InMaintenanceMode $false
        if((Get-BrokerMachine -MachineName $MachineName).InMaintenanceMode -eq $true){
            $mailbody += "<div style=""color:red;"">Cannot exit Maintenance Mode on $MachineName. Please check the server manually.</div><br/>"
        } else {
            $mailbody += "$MachineName is now out of Maintenance Mode.<br/>"
        }
    }
}

if($error -eq 0){
    $mailbody += "<div style=""color:green;"">All PCS XenApps servers are up and registered!</div>"
} else {
    $mailbody += "<div style=""color:green;"">Other PCS XenApps servers are up and registered.</div>"
}


###################################################################################################################
# Sending email
###################################################################################################################

$mailbody = $mailbody + "</body>"
$mailbody = $mailbody + "</html>"
 

Send-MailMessage -to $emailTo -from $emailFrom -subject "Hospice General Citrix Morning Report" -Body $mailbody -BodyAsHtml -SmtpServer $smtpServer

Stop-Transcript