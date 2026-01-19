### Import Modules that are used in the common profile 
param(
	[String]$defaultRoot = "C:",    
    $localModules
)


$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$profileScriptPath = (Get-Item $MyInvocation.MyCommand.Definition).FullName
function Edit-GlobalProfile
{
    notepad++ $profileScriptPath
}

function global:Import($Module, [switch]$silent, $ArgumentList=$null, $path=$null)
{
    $loaded = $False
    If (Get-Module $Module)
    { 
        Remove-Module $Module
        $loaded = $True
    }
    
    if($path -eq $null)
    {
        $Module = Join-Path $global:ScriptPath $Module
    }
    else {
        $Module = $path
    }
        
    Import-Module -Name:$Module -ArgumentList:$ArgumentList -DisableNameChecking
    
    if($silent)
    {
        return
    }
    
    if(!$loaded)
    {
        Write-Host "Loaded" $Module
    }
    else
    {
        Write-Host "Refreshed" $Module
    }
}

## ------------------------------------------------
## Do things that should be loaded on PS start here
## ------------------------------------------------
$arguments = @(
    $defaultRoot,
    $localModules
)

Import -Module:Common -silent -ArgumentList:$arguments


## This is where all the modules (besides Common) are loaded.  Adding new modules is done in Reset-Modules
Reset-Modules -silent

Install-Chocolatey

## ------------------------------------------------
## Print out some semi-useful help information on starting PS
## ------------------------------------------------
 
Write-Output "**************************Developer PowerShell Profile******************************************"
Write-Output ""

Write-Output "To view additional available commands, use Get-Command -Module (ModuleName: Common, Git, Github)"
Write-Output "To get help on a specific command (if available), use Get-Help (Command) i.e. Get-Help Build-All"
Write-Output ""

Write-Output "************************************************************************************************"
