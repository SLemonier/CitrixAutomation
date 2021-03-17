<#
.SYNOPSIS
  Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
  Then email report to Citrix engineers.
.DESCRIPTION
  Check all PCS XenApp servers are up and running at 8:00.
  Email report to Citrix engineers.
.Parameter Dev
 During script development, send the report to the "Dev" recipients list.
.Parameter DeliveryController
 Specifiy the Delivery Controller to use for the provision
 This parameter is optionnal, by default it will use with the local machine.
.EXAMPLE
    PS C:\PSScript > Morning_Report.ps1 
    Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
.EXAMPLE
    PS C:\PSScript > Morning_Report.ps1 -DeliveryController "CTXDDC01"
    Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
.EXAMPLE
    PS C:\PSScript > Morning_Report.ps1 -Dev
    Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details),
    then send the mail to the "Dev" recipients list (to avoid spam during script development).
.INPUTS
    None. You cannot pipe objects to this script.
.OUTPUTS
    No objects are output from this script. This script creates its own logs files.
.NOTES
  Version:        0.2
  Author:         Steven Lemonier
  Creation Date:  2021-03-08
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)] [switch]$Dev,
    [Parameter(Mandatory=$false)] [string]$DeliveryController,
    [Parameter(Mandatory=$false)] [string[]]$DeliveryGroup,
    [Parameter(Mandatory=$False)][Alias("OF")][ValidateNotNullOrEmpty()] [string]$OutFilePath="C:\Temp\Morning_Report.log"
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
    Stop-Transcript
    exit
}

#Check if the DeliveryGroup(s) specified in parameter exist(s)
if($DeliveryGroup){
    $error = 0
    foreach($DG in $DeliveryGroup){
        Write-Host "Checking if DeliveryGroup ""$DG"" exists..." -NoNewline
        if(Get-BrokerDesktopGroup -AdminAddress $DeliveryController -Name $DG -ErrorAction Ignore){
            Write-host "OK" -ForeGroundColor Green
        } Else {
            Write-host "Failed" -ForeGroundColor Red
            Write-host "$DG is not a valid DeliveryGroup. Please, check the parameter then restart the script" -ForeGroundColor Red
        }
    }
    if($error -ne 0){
        Stop-Transcript
        exit
    }
}

###################################################################################################################
# Mail settings
###################################################################################################################

# E-mail report details
$emailFrom = "citrix@hospicegeneral.ch"
if($Dev){
    $emailTo = "steven.lemonier@hospicegeneral.ch"
} else {
    $emailTo = "Steven.Lemonier@hospicegeneral.ch", "Cedric.Bosson@hospicegeneral.ch"
}
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


function CheckDeliveryGroup{
    param(
        [parameter(Mandatory=$true)] [string]$DG
    )
###################################################################################################################
# Check all servers from specified DeliveryGroup are up and running at 8:00.
###################################################################################################################

    $error = 0

    $Servers = Get-BrokerMachine -AdminAddress $DeliveryController -DesktopGroupName $DG | Select MachineName,PowerState,InMaintenanceMode,RegistrationState
    foreach($server in $Servers){
        $MachineName = $server.MachineName
        if($server.Powerstate -ne "On"){
            $error++
            $mailbody += "<div style=""color:orange;"">$MachineName is not powered On! Script is powering On the server...</div>"
            New-BrokerHostingPowerAction -AdminAddress $DeliveryController -MachineName $MachineName -Action TurnOn
            Start-Sleep -Seconds 120
            if((Get-BrokerMachine -AdminAddress $DeliveryController -MachineName $MachineName).PowerState -ne "On" -and (Get-BrokerMachine -MachineName $MachineName).RegistrationState -ne "Registered"){
                $mailbody += "<div style=""color:red;"">Cannot start and register $MachineName. Please check the server manually.</div>"
            }
        }
        if($server.inMaintenanceMode -eq $true){
            $error++
            $mailbody += "<div style=""color:orange;"">$MachineName is in Maintenance Mode! Script is disabling maintenance mode...<br/></div>"
            Get-BrokerMachine -AdminAddress $DeliveryController -MachineName $MachineName | Set-BrokerMachine -InMaintenanceMode $false
            if((Get-BrokerMachine -AdminAddress $DeliveryController -MachineName $MachineName).InMaintenanceMode -eq $true){
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

    return $mailbody
}

###################################################################################################################
# Construction report
###################################################################################################################

foreach($DG in $DeliveryGroup){
    $mailbody = CheckDeliveryGroup -DeliveryGroup $DG
}

###################################################################################################################
# Sending email
###################################################################################################################

$mailbody = $mailbody + "</body>"
$mailbody = $mailbody + "</html>"
 

Send-MailMessage -to $emailTo -from $emailFrom -subject "Citrix Morning Report" -Body $mailbody -BodyAsHtml -SmtpServer $smtpServer

Stop-Transcript