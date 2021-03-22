<#
.SYNOPSIS
  Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
  Then email report to Citrix engineers.
.DESCRIPTION
  If corresponding parameters are set:
    - Check all resources from on or more DeliveryGroup are up and running when the script is executed (-DeliveryGroup)
  Finally, email report to Citrix engineers.
  Without any parameter set, the script will only send an empty mail if smtp server and recipients settings are correct.
.EXAMPLE
    PS C:\PSScript > Morning_Report.ps1 -DeliveryController "CTXDDC01" 
    Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details).
.EXAMPLE
    PS C:\PSScript > Morning_Report.ps1 -DeliveryGroup "VDI","XenApp"
    Run some checks during the morning and ensure the Citrix infrastructure is compliamt with our tresholds (check Description for more details),
    check all resources associated to "VDI" and "XenApp" delivery groups are up and running,
    then send the mail to the "Dev" recipients list (to avoid spam during script development).
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
    [Parameter(Mandatory=$False)][Alias("OF")][ValidateNotNullOrEmpty()] [string]$OutFilePath="C:\Temp\Morning_Report.log"
)

$Dev = $true
$DeliveryController # = "CXDCACA023"
$DeliveryGroup = @(
    "W12 XenApp PCS 11-2",
    "truc"
)
$sites = @(
    "truc",
    "https://citrixint.adir.implisis.ch",
    "https://cxstfaca025.adir.implisis.ch"
)

# E-mail report details
$emailFrom = "citrix@hospicegeneral.ch"
if($Dev){
    $emailTo = "steven.lemonier@hospicegeneral.ch"
} else {
    $emailTo = "Steven.Lemonier@hospicegeneral.ch", "Cedric.Bosson@hospicegeneral.ch"
}
$smtpServer    = "smtp.implisis.ch"

Start-Transcript -Path $OutFilePath -Append

################################################################################################
#Checking the parameters
################################################################################################


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
                $error++
                Write-host "Failed" -ForeGroundColor Red
                Write-host "$DG is not a valid DeliveryGroup." -ForeGroundColor Red
            }
        }
        if($error -ne 0){
            Write-host "At least, one DeliveryGroup does not exist. Please, check the parameter then restart the script" -ForeGroundColor Red
            Stop-Transcript
            exit
        }
    }


###################################################################################################################
# Check all resources from specified DeliveryGroup are up and running at 8:00.
###################################################################################################################
function CheckDeliveryGroup{
    param(
        [parameter(Mandatory=$true)] [string[]]$DeliveryGroupList
    )
    $warning = 0
    
    foreach($DeliveryGroup in $DeliveryGroupList){
        $errorDG = 0
        $resources = Get-BrokerMachine -AdminAddress $DeliveryController -DesktopGroupName $DeliveryGroup | Select MachineName,PowerState,InMaintenanceMode,RegistrationState
        foreach($resource in $resources){
            $MachineName = $resource.MachineName
            if($resource.Powerstate -ne "On"){
                $error++
                $warning++
                $mailbodyintermediate += "<div style=""color:orange;"">$MachineName is not powered On! Script is powering On the resource...</div>"
                New-BrokerHostingPowerAction -AdminAddress $DeliveryController -MachineName $MachineName -Action TurnOn
                Start-Sleep -Seconds 120
                if((Get-BrokerMachine -AdminAddress $DeliveryController -MachineName $MachineName).PowerState -ne "On" -and (Get-BrokerMachine -MachineName $MachineName).RegistrationState -ne "Registered"){
                    $mailbodyintermediate += "<div style=""color:red;"">Cannot start and register $MachineName. Please check the resource manually.</div>"
                }
            }
            if($resource.inMaintenanceMode -eq $true){
                $error++
                $warning++
                $mailbody += "<div style=""color:orange;"">$MachineName is in Maintenance Mode! Script is disabling maintenance mode...<br/></div>"
                Get-BrokerMachine -AdminAddress $DeliveryController -MachineName $MachineName | Set-BrokerMachine -InMaintenanceMode $false
                if((Get-BrokerMachine -AdminAddress $DeliveryController -MachineName $MachineName).InMaintenanceMode -eq $true){
                    $mailbodyintermediate += "<div style=""color:red;"">Cannot exit Maintenance Mode on $MachineName. Please check the resource manually.</div><br/>"
                } else {
                    $mailbodyintermediate += "$MachineName is now out of Maintenance Mode.<br/>"
                }
            }
        }

        if($error -eq 0){
            $mailbodyintermediate += "<div style=""color:green;"">All resources from $DeliveryGroup are up and registered!</div>"
        } else {
            $mailbodyintermediate += "<div style=""color:green;"">Other resources from $DeliveryGroup are up and registered.</div>"
        }
    }
    if($warning -eq 0){
        $mailbody += "<table style='background:green;border:none'><tr width=450px><td><p><b><span style='color:white'>Delivery Groups</span></b></p></td><td align='right'>OK</td></tr></table><br/>"
    } else {
        $mailbody += "<table style='background:red;border:none'><tr width=450px><td><p><b><span style='color:white'>Delivery Groups</span></b></p></td><td align='right'>$warning warning(s)</td></tr></table><br/>"
    }
    $mailbody += $mailbodyintermediate

    return $mailbody
}

###################################################################################################################
# Check the certificates are still valid or alert if expiration date is less than 30 fays.
###################################################################################################################
function CheckCertificate{
    param(
        [parameter(Mandatory=$true)] [string]$URL
    )

    $minCertAge = 30 #in days
    $timeoutMs = 10000
    # Disable certificate validation
    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

    if(!($URL.StartsWith("https://"))){
        $URL = "https://$URL"
    }

    Write-Host "Checking $URL... "
    $req = [Net.HttpWebRequest]::Create($URL)
    $req.Timeout = $timeoutMs
    try {
        $req.GetResponse() |Out-Null
    } catch {
        Write-Host "FAILED: "$_ -ForeGroundColor Red
        $mailbody += "<div style=""color:red;"">$URL does not respond to WebRequest! $_</div>"
    }
    if($req.ServicePoint.Certificate.GetExpirationDateString() -ne $null){
        $expDate = $req.ServicePoint.Certificate.GetExpirationDateString()
        $certExpDate = [datetime]::ParseExact($expDate, “dd/MM/yyyy HH:mm:ss”, $null)
        [int]$certExpiresIn = ($certExpDate - $(get-date)).Days
        $certName = $req.ServicePoint.Certificate.GetName()
        if ($certExpiresIn -gt $minCertAge){
            Write-Host "The $URL certificate expires in $certExpiresIn days [$certExpDate]" -ForeGroundColor Green
            $mailbody += "<div>$URL certificate expires in $certExpiresIn days [$certExpDate]</div>"
        } else {
            $mailbody += "<div style=""color:red;"">$URL certificate expires in $certExpiresIn days</div>"
            Write-Host "The $URL certificate expires in $certExpiresIn days" -ForeGroundColor Red
        }
    }
    return $mailbody
}
    
###################################################################################################################
# Mail settings
###################################################################################################################

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
# Constructing report
###################################################################################################################

$mailbody += CheckDeliveryGroup -DeliveryGroup $DeliveryGroup
 
$mailbody += "<br/>"
$mailbody += "<table style='background:black;border:none'><tr><td width=450px><p><b><span style='color:white'>SSL Certificates</span></b></p></td></tr></table><br/>"
 
 
foreach($URL in $sites){
    $mailbody += CheckCertificate -URL $URL
}
###################################################################################################################
# Sending email
###################################################################################################################

$mailbody = $mailbody + "</body>"
$mailbody = $mailbody + "</html>"
 

Send-MailMessage -to $emailTo -from $emailFrom -subject "Citrix Morning Report" -Body $mailbody -BodyAsHtml -SmtpServer $smtpServer

Stop-Transcript