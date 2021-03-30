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
  Creation Date:  2021-03-22
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)][Alias("OF")][ValidateNotNullOrEmpty()] [string]$OutFilePath="C:\Temp\Morning_Report.log"
)

$Dev = $true
$DeliveryController # = "CXDCACA023"
$DeliveryGroup = @(
    "W12 XenApp PCS 11-2"
)
$sites = @(
    "https://citrixint.adir.implisis.ch",
    "https://citrixint-qual.adir.implisis.ch"
)
$profilefolders = @(
    "\\CXUPMSIS069\CTXW10_profiles$",
    "\\CXUPMSIS069\CTXW10_redirected$",
    "\\CXUPMSIS069\CTXW10_o365token$"
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
        $warning = 0
        foreach($DG in $DeliveryGroup){
            Write-Host "Checking if DeliveryGroup ""$DG"" exists..." -NoNewline
            if(Get-BrokerDesktopGroup -AdminAddress $DeliveryController -Name $DG -ErrorAction Ignore){
                Write-host "OK" -ForeGroundColor Green
            } Else {
                $warning++
                Write-host "Failed" -ForeGroundColor Red
                Write-host "$DG is not a valid DeliveryGroup." -ForeGroundColor Red
            }
        }
        if($warning -ne 0){
            Write-host "At least, one DeliveryGroup does not exist. Please, check the parameter then restart the script" -ForeGroundColor Red
            Stop-Transcript
            exit
        }
    }

    ###################################################################################################################
# Check Broker Site settings
###################################################################################################################
function CheckBrokerSite{

    $warning = 0

    Write-host "Checking Broker Site..." -NoNewline
    $SiteProperties = Get-BrokerSite -AdminAddress $DeliveryController

    if($SiteProperties.ConnectionLeasingEnabled -eq $True){
        $warning++
        $mailbodyintermediate += "<div style=""color:red;"">Connection Leasing is enabled. Feature is deprecated and should be turned off!</div>"
    }

    if($SiteProperties.LocalHostCacheEnabled -eq $False){
        $warning++
        $mailbodyintermediate += "<div style=""color:red;"">Local Host Cache is disabled. Site is not secured in case of an SQL outage ! Feature should be turned on!</div>"
    }

    if($SiteProperties.LicensingGracePeriodActive -eq $true){
        $warning++
        $mailbodyintermediate += "<div style=""color:red;"">Site is in Licensing Grace Period! Communication with License Server is no longer active and require investigation!!</div>"
    }

    if($warning -eq 0){
        $mailbody += "<table style='background:green'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Site</p></td><td style='text-align:right;border:none'>OK</td></span></b></tr></table><br/>"
    } else {
        if($warning -eq 1){
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Site</p></td><td style='text-align:right;border:none'>$warning warning</td></span></b></tr></table><br/>"
        } else {
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Site</p></td><td style='text-align:right;border:none'>$warning warnings</td></span></b></tr></table><br/>"
        }    
    }
    $mailbody += $mailbodyintermediate

    return $mailbody
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
        $resources = Get-BrokerMachine -AdminAddress $DeliveryController -DesktopGroupName $DeliveryGroup | Select-Object MachineName,PowerState,InMaintenanceMode,RegistrationState
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
        $mailbody += "<table style='background:green'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Delivery Groups</p></td><td style='text-align:right;border:none'>OK</td></span></b></tr></table><br/>"
    } else {
        if($warning -eq 1){
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Delivery Groups</p></td><td style='text-align:right;border:none'>$warning warning</td></span></b></tr></table><br/>"
        } else {
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Delivery Groups</p></td><td style='text-align:right;border:none'>$warning warnings</td></span></b></tr></table><br/>"
        }    
    }
    $mailbody += $mailbodyintermediate

    return $mailbody
}

###################################################################################################################
# Check the certificates are still valid or alert if expiration date is less than 30 fays.
###################################################################################################################
function CheckCertificate{
    param(
        [parameter(Mandatory=$true)] [string[]]$sites
    )

    $minCertAge = 30 #in days
    $timeoutMs = 10000
    $warning = 0
    # Disable certificate validation
    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    foreach($URL in $sites){
        $certExpiresIn = ""

        if(!($URL.StartsWith("https://"))){
            $URL = "https://$URL"
        }

        Write-Host "Checking $URL... "
        $req = [Net.HttpWebRequest]::Create($URL)
        $req.Timeout = $timeoutMs
        try {
            $req.GetResponse() |Out-Null
        } catch {
            $warning++
            Write-Host "FAILED: "$_ -ForeGroundColor Red
            $mailbodyintermediate += "<div style=""color:red;"">$URL does not respond to WebRequest! $_</div>"
        }
        if($null -ne $req.ServicePoint.Certificate.GetExpirationDateString()){
            $expDate = $req.ServicePoint.Certificate.GetExpirationDateString()
            $certExpDate = [datetime]::ParseExact($expDate, “dd/MM/yyyy HH:mm:ss”, $null)
            [int]$certExpiresIn = ($certExpDate - $(get-date)).Days
            if ($certExpiresIn -gt $minCertAge){
                Write-Host "The $URL certificate expires in $certExpiresIn days [$certExpDate]" -ForeGroundColor Green
                $mailbodyintermediate += "<div style=""color:green;"">$URL certificate expires in $certExpiresIn days [$certExpDate]</div>"
            } else {
                $warning++
                $mailbodyintermediate += "<div style=""color:red;"">$URL certificate expires in $certExpiresIn days</div>"
                Write-Host "The $URL certificate expires in $certExpiresIn days" -ForeGroundColor Red
            }
        }
    }

    if($warning -eq 0){
        $mailbody += "<table style='background:green'><b><span style='color:white'><tr width=450px><td style='border:none'><p>SSL Certificates</p></td><td style='text-align:right;border:none'>OK</td></span></b></tr></table><br/>"
    } else {
        if($warning -eq 1){
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>SSL Certificates</p></td><td style='text-align:right;border:none'>$warning warning</td></span></b></tr></table><br/>"
        } else {
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>SSL Certificates</p></td><td style='text-align:right;border:none'>$warning warnings</td></span></b></tr></table><br/>"
        }
    }
    $mailbody += $mailbodyintermediate

    return $mailbody
}

###################################################################################################################
# Check the profile folders for orphaned SIDs.
###################################################################################################################
function CheckProfileFolders {
    param(
        [parameter(Mandatory=$true)] [string[]]$folders
    )
    $warning = 0

    foreach($folder in $folders){
        Write-host "Checking $folder..." -NoNewline
        if(Test-Path -path $folder){
            $orphanedSID = Get-ChildItem -path $folder | Get-ACL | Where-Object { $_.Owner -match "S-1-5-" } | Select-Object Path,Owner
            foreach($Account in $orphanedSID){
                $warning++
                $path = (Convert-Path $Account.Path).Replace("E:","$folder")
                $mailbodyintermediate += "<div style=""color:red;"">$path has an orphaned SID as owner!</div>"
                if((Get-Date -Format dd) -eq 1){
                    Remove-Item -Path $path -Recurse -Force
                } else {
                    $mailbodyremediate += "<div>Remove-Item -path $path -Recurse -Force</div>"
                }
            }
        } else {
            Write-host "Failed" -ForeGroundColor Red
            $warning++
            $mailbodyintermediate += "<div style=""color:red;"">$Folder does not exist!</div>"
        }

        Write-host "OK" -ForeGroundColor Green
    }

    if((Get-Date -Format dd) -eq 1){
        write-host "First day of the month, purging folders with orphaned SID as owner..."
        $mailbodytop += "<div>First day of the month, folowing folders will be purged:</div>"
        if($warning -gt 10){
            Write-Host "Too many folders to purge, commands should be executed manually."
            $mailbodytop += "<div style=""color:red;"">Too many folders to purge, commands should be executed manually.</div>"
        } else {
            $mailbodytop += "<div style=""color:red;"">First day of the month, folowwing folders will be purged:</div>"
        }
    }

    if($warning -eq 0){
        $mailbody += "<table style='background:green'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Profiles</p></td><td style='text-align:right;border:none'>OK</td></span></b></tr></table><br/>"
        if((Get-Date -Format dd) -eq 1){
            $mailbodytop += "<div style=""color:green;"">No folder to purge!</div>"
        }
    } else {
        if($warning -eq 1){
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Profiles</p></td><td style='text-align:right;border:none'>$warning warning</td></span></b></tr></table><br/>"
        } else {
            $mailbody += "<table style='background:red'><b><span style='color:white'><tr width=450px><td style='border:none'><p>Profiles</p></td><td style='text-align:right;border:none'>$warning warnings</td></span></b></tr></table><br/>"
        }
    }
    $mailbody += $mailbodytop
    $mailbody += $mailbodyintermediate
    $mailbody += "<br/>"
    $mailbody += $mailbodyremediate

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
$mailbody += CheckCertificate -sites $sites
$mailbody += "<br/>"
$mailbody += CheckProfileFolders -folders $profilefolders


###################################################################################################################
# Sending email
###################################################################################################################

$mailbody = $mailbody + "</body>"
$mailbody = $mailbody + "</html>"
 

Send-MailMessage -to $emailTo -from $emailFrom -subject "Citrix Morning Report" -Body $mailbody -BodyAsHtml -SmtpServer $smtpServer

Stop-Transcript