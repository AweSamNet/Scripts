$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (!(test-path $profile)) 
{
    New-Item -path $profile -type file -force
}

$profileLink = ". (Resolve-Path '$ScriptPath\Microsoft.PowerShell_profile.ps1')"
$profileLinkCount = ((gc $PROFILE) | where { $_ -contains $profileLink } | where { $_ -like "*$profileLink*" })

if(!$profileLinkCount)
{
    Add-Content $profile $profileLink
}