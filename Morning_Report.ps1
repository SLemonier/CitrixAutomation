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
    [Parameter(Mandatory=$true)] [string]$Account,
    [Parameter(Mandatory=$true)] [string]$Password,
    [Parameter(Mandatory=$false)] [string]$Path="C:\Scripts",
    [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()] [string]$LogFile=".\SetAutologon.log"
)

#Start logging
Start-Transcript -Path $LogFile

#Setting variables prior to their usage is not mandatory
Set-StrictMode -Version 2

################################################################################################
#Checking the parameters
################################################################################################
