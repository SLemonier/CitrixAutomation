[CmdletBinding()]
Param(
    # Declaring input variables for the script
    [Parameter(Mandatory=$false)] [string]$Share,
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\CreateCTXShares.log"
)

Start-Transcript -Path $Logfile

function CreateFolder {
    param (
        [string]$Foldername
    )

    New-Item -path $Share\$foldername -itemtype Directory

    $AdministratorsGroupName="RCCAD\CHVGGS-CTX_Admins"
    $UsersGroupName="RCCAD\Domain Users"

    # Get Creator Owner Name 

    $objSID = New-Object System.Security.Principal.SecurityIdentifier ("S-1-3-0")
    $objGroup = $objSID.Translate( [System.Security.Principal.NTAccount])
    $CreatorOwnerName=$objGroup.Value

    # Grant Administrators FullControl / this folder, Subfolders and files
    $acl = Get-Acl "$Share\$foldername$ProfileDir"
    $permission = "$AdministratorsGroupName","FullControl","ObjectInherit, ContainerInherit", "None","Allow"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    $acl | Set-Acl "$Share\$foldername" 

    # Grant users ListDirectory,CreateDirectories / this folder only
    $acl = Get-Acl "$Share\$foldername"
    $permission = "$UsersGroupName","ListDirectory,CreateDirectories","None, None", "None","Allow"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    $acl | Set-Acl "$Share\$foldername"    
    
    # Grant Creator Owner FullControl / Subfolders and files
    $acl = Get-Acl "$Share\$foldername" 
    $permission = "$CreatorOwnerName","FullControl","ObjectInherit, ContainerInherit", "InheritOnly","Allow"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    $acl | Set-Acl "$Share\$foldername"
}

CreateFolder -Foldername "ServerOS_ProfileContainer"
CreateFolder -Foldername "FolderRedirection"