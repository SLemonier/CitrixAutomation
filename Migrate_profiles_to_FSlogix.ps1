<#
 .Synopsis
 Migrate UPM users profiles and users redirected folders to VHDx Fslogix containers.

 .Description
 TODO

 .Parameter Profiles
 Specify the profiles to migrate to Fslogix containers. You can specify a user or a list of users.
 This parameter is optionnal. If -Profiles is not set, the script will migrate all the profiles in the UPM directory.


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
    [Parameter(Mandatory=$false)] [string[]]$Profiles,
    [Parameter(Mandatory=$true)] [string]$UPMProfilesFolder,
    [Parameter(Mandatory=$false)] [string]$RedirectedFolders,
    [Parameter(Mandatory=$true)] [string]$FSlogixFolder,
    [Parameter(Mandatory=$false)] [switch]$Usernamefirst,
    [Parameter(Mandatory=$true)] [ValidateSet('vhd','vhdx')][string]$VDiskType,
    [Parameter(Mandatory=$true)] [Int]$VDiskSize,
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\Migrate_profiles_to_FSlogix.log"
)

#Start logging
Start-Transcript -Path $LogFile

################################################################################################
#Checking the parameters
################################################################################################

#Check if the UPMProfilesFolder parameter is set or if it contains user profiles
Write-Host "Validating UPMProfilesFolder..." -NoNewline
if(Test-Path -Path $UPMProfilesFolder){
    if($Profiles){
    $error = 0
        foreach($Profile in $Profiles){
            if(!(Test-Path -Path $UPMProfilesFolder\$Profile\UPM_Profile)){
                Write-host "At least one profile is not a UPM profile or path cannot be resolved. Please check the `$Profiles parameter" -ForegroundColor Red
                $error++
                break
            }
        }
        if($error -eq 0){
            Write-Host "OK" -ForegroundColor Green
        }else{
            Stop-Transcript
            break
        }
    }else{
        $ValidateUPMFolder = (Get-ChildItem -Path $UPMProfilesFolder -Recurse | Select -First 1).Name      
        if(Test-Path -Path $UPMProfilesFolder\$ValidateUPMFolder\UPM_Profile){
            write-host "OK" -ForegroundColor Green
        } else {
            Write-Host "Path does not contain UPM Profiles. Please check `$UPMProfilesFolder parameter" -ForegroundColor Red
            Stop-Transcript
            break
        }
    }
} else {
    Write-host "Path is not valid. Please check `$UPMProfilesFolder parameter" -ForegroundColor Red
}

#Check if the RedirectedFolders parameter is set or if it contains user profiles
Write-Host "Validating RedirectedFolders..." -NoNewline
if(Test-Path -Path $RedirectedFolders){
    if($Profiles){
    $error = 0
        foreach($Profile in $Profiles){
            if(!(Test-Path -Path $RedirectedFolders\$Profile\Documents)){
                Write-host "At least one folder does not contain Redirected folders or path cannot be resolved. Please check the `$RedirectedFolders parameter" -ForegroundColor Red
                $error++
                break
            }
        }
        if($error -eq 0){
            Write-Host "OK" -ForegroundColor Green
        }else{
            Stop-Transcript
            break
        }
    }else{
        $ValidateFolder = (Get-ChildItem -Path $RedirectedFolders -Recurse | Select -First 1).Name      
        if(Test-Path -Path $RedirectedFolders\$ValidateFolder\Documents){
            write-host "OK" -ForegroundColor Green
        } else {
            Write-Host "Path does not contain Redirected folders. Please check `$RedirectedFolders parameter" -ForegroundColor Red
            Stop-Transcript
            break
        }
    }
} else {
    Write-host "Path is not valid. Please check `$RedirectedFolders parameter" -ForegroundColor Red
}

#Check if the FSlogixFolder exists and is accessible
Write-host "Validating FSLogixFolder..." -NoNewline
If(Test-Path -Path $FSlogixFolder){
    Write-Host "OK" -ForegroundColor Green
} Else {
    Write-Host "Path is not valid. Please check `$FSlogixFolder paramater" -ForegroundColor Red
    Stop-Transcript
    break
} 

################################################################################################
#Migrating the profiles
################################################################################################

function MigrateProfile {
    param(
        [parameter(Mandatory=$true)] [string]$Username
    )
    Write-host "Migrating $Username data at" (Get-Date) 
    Try{
        $sid = (New-Object System.Security.Principal.NTAccount($Username)).translate([System.Security.Principal.SecurityIdentifier]).Value
        If($Usernamefirst){
            $FSlogixProfileFolder = Join-Path $FSlogixFolder ($Username + "_" + $sid)
        } else {
            $FSlogixProfileFolder = Join-Path $FSlogixFolder ($sid + "_" + $Username)
        }

        #Create Fslogix user folder if it does not exist
        if (test-path $FSlogixProfileFolder){
            $continue = ""
            while($continue -notlike "y" -and $continue -notlike "n"){
                $continue = Read-Host "FSlogix Profile folder already exists for $profile. Folder will be deleted. Do you want to continue? Y/N"
            }
            if($continue -match "y"){
                Remove-Item -Path $FSlogixProfileFolder -Recurse -Force | Out-Null
                New-Item -Path $FSlogixProfileFolder -ItemType directory | Out-Null
            }
            if($continue -notmatch "y"){
                Write-Host "$Profile won't be migrated." -ForegroundColor Yellow
                Continue
            } 
        } else {
            New-Item -Path $FSlogixProfileFolder -ItemType directory | Out-Null
        }
        Write-Host "Creating $VDiskType for $profile..." -NoNewline

        & icacls $FSlogixProfileFolder /setowner "$env:userdomain\$Username" /T /C >> $null
        & icacls $FSlogixProfileFolder /grant $env:userdomain\$Username`:`(OI`)`(CI`)F /T >> $null

        $VDisk = Join-Path $FSlogixProfileFolder ("Profile_" + $Username+"." + $VDiskType)
        $script1 = "create vdisk file=`"$VDisk`" maximum=$VDiskSize type=expandable"

        $script2 = "sel vdisk file=`"$VDisk`"`r`nattach vdisk"

        $script3 = "sel vdisk file=`"$VDisk`"`r`ncreate part prim`r`nselect part 1`r`nformat fs=ntfs quick"
        
        $script4 = "sel vdisk file=`"$VDisk`"`r`nsel part 1`r`nassign letter=Z"
        $script5 = "sel vdisk file`"$VDisk`"`r`ndetach vdisk"
        
        
        $script1 | diskpart | Out-Null
        Write-Host "OK" -ForegroundColor Green
        Write-Host "Attaching vdisk..." -NoNewline
        $script2 | diskpart | Out-Null
        Write-Host "OK" -ForegroundColor Green
        Write-Host "Partitioning vdisk..." -NoNewline
        Start-Sleep -s 5  
        $script3 | diskpart | Out-Null
        Write-Host "OK" -ForegroundColor Green
        Write-host "Mounting vdisk on Z:\..." -NoNewline
        $script4 | diskpart | Out-Null
        Write-Host "OK" -ForegroundColor Green
        Write-Host "Creating Profile folder on Vdisk and setting ACLs..." -NoNewline
        & label Z: Profile-$Username
        New-Item -Path Z:\Profile -ItemType directory | Out-Null
        # set permissions on the profile
        start-process icacls "Z:\Profile /setowner SYSTEM"
        Start-Process icacls -ArgumentList "Z:\Profile /inheritance:r"
        $cmd1 = "Z:\Profile /grant $env:userdomain\$Username`:`(OI`)`(CI`)F"
        Start-Process icacls -ArgumentList "Z:\Profile /grant SYSTEM`:`(OI`)`(CI`)F"
        Start-Process icacls -ArgumentList "Z:\Profile /grant Administrators`:`(OI`)`(CI`)F"
        Start-Process icacls -ArgumentList $cmd1

        Write-Host "OK" -ForegroundColor Green

        # Migrate Data from RedirectedFolders to FSlogix if $RedirectedFolders exists
        If($RedirectedFolders -ne $null){
            Write-Host "Migrating Data from Redirected folder to FSlogix..." -NoNewline
            & robocopy "$RedirectedFolders\$Username\" Z:\Profile /E /Purge /r:0 | Out-Null
            Write-Host "OK" -ForegroundColor Green
        }

        # Migrate Data from UPM to FSlogix if $UPMProfilesFolder exists
        if($UPMProfilesFolder -ne $null){
            Write-Host "Migrating Data from UPM to FSlogix..." -NoNewline
            & robocopy "$UPMProfilesFolder\$Username\UPM_Profile\" Z:\Profile /E /Purge /r:0 | Out-Null
            Write-Host "OK" -ForegroundColor Green
        }

        # Add FSlogix Data
        if (!(Test-Path "Z:\Profile\AppData\Local\FSLogix")) {
            Write-Host "Populating FSLogix Data..." -NoNewline
            New-Item -Path "Z:\Profile\AppData\Local\FSLogix" -ItemType directory | Out-Null
        
            $regtext = "Windows Registry Editor Version 5.00
            [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid]
            `"ProfileImagePath`"=`"C:\\Users\\$Username`"
            `"FSL_OriginalProfileImagePath`"=`"C:\\Users\\$Username`"
            `"Flags`"=dword:00000000
            `"State`"=dword:00000000
            `"ProfileLoadTimeLow`"=dword:00000000
            `"ProfileLoadTimeHigh`"=dword:00000000
            `"RefCount`"=dword:00000000
            `"RunLogonScriptSync`"=dword:00000000
            "

            $regtext | Out-File "Z:\Profile\AppData\Local\FSLogix\ProfileData.reg" -Encoding ascii

            Write-Host "OK" -ForegroundColor Green
        }

        #Detach disk
        Write-Host "Detaching vdisk..." -NoNewline
        $script5 | diskpart | Out-Null
        Write-Host "OK" -ForegroundColor Green
        Write-Host "Data migration ended at" (Get-Date)

    } 
    Catch {
        Write-Host "An error occured while processing $username." -ForegroundColor Red
        Write-Host "Ensure the vdisk has been detached before continuing" -ForegroundColor Yellow
        Pause
    }
}

if($Profiles){
    foreach($profile in $profiles){
        MigrateProfile $Profile
    }
} Else {
    
}

Stop-Transcript