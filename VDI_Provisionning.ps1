<#
.SYNOPSIS
  Provision a given number of Windows 10 VDI
.DESCRIPTION
  Provision a given number of Windows 10 VDI provided as a paramter
.EXAMPLE
    PS C:\PSScript > VDI_Provisionning.ps1 -VDICount 10 
    Provision 10 new non persistent Windows 10 VDI, split equally between the two DTC (GV1 and GV2)
.INPUTS
    None. You cannot pipe objects to this script.
.OUTPUTS
    No objects are output from this script. This script creates its own logs files.
.NOTES
  Version:        0.1
  Author:         Steven Lemonier
  Creation Date:  2020-11-04
#>

[CmdletBinding()]
Param(
    # Declaring input variables for the script
    [Parameter(Position=0, Mandatory=$true)] [int]$VDICount,
    [Parameter(Position = 1, Mandatory=$False)][Alias("OF")][ValidateNotNullOrEmpty()] [string]$OutFilePath="C:\Temp\VDI_Provisionning.log"
)

Set-StrictMode -Version 2
Add-PSSnapin Citrix* -erroraction silentlycontinue

function Log {
    param (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$log
    )
    if(Test-Path -Path $OutFilePath){
        if((get-item $OutFilePath).Length -gt 5mb){
            $date = Get-date -Format yyyy-MM-dd
            Move-Item -Path $OutFilePath -Destination "C:\Temp\VDI_Provisionning-$date.log"
        }
    }
    $ScriptTime = Get-Date -Format yyyy.MM.dd-HH:mm:ss
    if($log -match "ERROR"){
        Write-host "[$scriptTime] $log" -ForegroundColor Red
    } 
    elseif ($log -match "OK") {
        Write-host "[$scriptTime] $log" -ForegroundColor Green
    }else{
        Write-Host "[$scriptTime] $log"
    }
    "[$scriptTime] $log" | Out-File -FilePath $OutFilePath -Append
}

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