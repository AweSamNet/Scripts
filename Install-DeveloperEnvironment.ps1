#
#    This script is designed to configure required local dev tools 
#

$ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition;

& "$ScriptPath\PowerShellProfile\Install-Profile.ps1"

. $PROFILE

if(-not(Test-IsAdmin))
{
    Write-Host "You need to run this script with administrator rights."
    return
}

# install BurntToast so that we can get notifications from background services
Write-Output "Installing BurntToast"
Install-Module -Name BurntToast

Add-Content $profile @'

Update-WatchedGithubIssues
'@
