### 
### Operations related functionality
###

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$opsScriptPath = (Get-Item $MyInvocation.MyCommand.Definition).FullName

function Edit-Ops
{
    notepad++ $opsScriptPath
}

function Get-OpsCommands ([int]$columns = 3)
{
    $names = Get-Command -Module Ops | % { $_.Name }    
    Write-Table $names $columns
}

function Backup-Path(
    [string]$from, 
    [string]$to,
    [string]$logPath,
    [int]$retryCount=2,
    [int]$waitTime=10)
{
    Robocopy "$from" "$to" /MIR /XA:SH /R:$retryCount /W:$waitTime /LOG+:"$logPath" /tee /eta /fft > $null
}

function Set-PageantStartup($keyFiles, $keysDirectory)
{
    if(!$keysDirectory)
    {
        Write-Host "Are all your keys in the same directory[y/n]?"
        $sameDirectory = $(Read-Host).Trim()

        if($sameDirectory.Trim() -eq "y")
        {
            Write-Host "Enter the path where your keys are stored:"
            $keysDirectory = $(Read-Host).Trim()
        }
    }
    
    if(!$keyFiles)
    {
        $keyFiles = @()

        Write-Host "Enter each key file path (or file name if using a shared directory):"
        $count = 1
        do{
            $path = $(Read-Host $count).Trim()

            $count = $count + 1
            if($path)
            {
                $keyFiles += $path
            }
        } while ($path -ne "")
        
    }

    $pageant = Get-Command pageant
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "pageant.lnk"  
    
    Set-Shortcut $pageant $shortcutPath $keysDirectory $keyFiles
    
    # now setup plink for git in console 
    $git_ssh = [System.Environment]::GetEnvironmentVariable("GIT_SSH")
    
    if(!$git_ssh)
    {
        $plink = Get-Command plink
        [Environment]::SetEnvironmentVariable("GIT_SSH", $plink.Source, "Machine")
    }
}

# https://learn-powershell.net/2010/08/22/balloon-notifications-with-powershell/
function Notify-Windows(
    [Parameter(Mandatory=$true)]
    [string]$text, 
    [string]$icon="Info",
    [string]$title )
{
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

    $objNotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $objNotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $objNotifyIcon.BalloonTipIcon = $icon 
    $objNotifyIcon.BalloonTipText = $text
    $objNotifyIcon.BalloonTipTitle = $title
    $objNotifyIcon.Visible = $True 
    $objNotifyIcon.ShowBalloonTip(10000)
}

$defaultWatchedChocolateyInstallPath = Join-Path $ScriptPath "Watched\ChocolateyInstalls.txt"

function Watch-ChocolateyInstall(
    [string]$appName,
    [string]$arguments,
    [string]$storePath=$defaultWatchedChocolateyInstallPath
)
{    
    $watch = @{
        AppName = $appName;
        args = $arguments;
    }
    
    Watch-Something -record:$watch -storePath:$storePath
}

function Unwatch-ChocolateyInstall(
    [string]$appName="",
    [int]$id=0,
    [string]$storePath=$defaultWatchedChocolateyInstallPath
)
{
    Unwatch-Something { $_.Value.AppName -eq $appName} $id $storePath
}

function Get-WatchedChocolateyInstalls([string]$storePath = $defaultWatchedChocolateyInstallPath)
{
    Get-JsonFromFile $storePath
}

function Run-ChocolateyInstalls($storePath = $defaultWatchedChocolateyInstallPath, [switch]$y)
{   
    Get-WatchedChocolateyInstalls $storePath | % {
        $command = "choco install $($_.Value.AppName)"
        
        if($_.Value.args)
        {
            $command += " --package-parameters ""$($_.Value.args)"""
        }
        
        if($y)
        {
            $command += " -y"
        }
        
        invoke-expression $command
    }
}

function Update-ChocolateyInstalls([switch]$y)
{
    Get-WatchedChocolateyInstalls $storePath | % {
        
        if($y)
        {
            choco upgrade $_.Value.AppName -y
        }
        else
        {
            choco upgrade $_.Value.AppName
        }
    }
}

function Get-PowershellTasks()
{
    try
    {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\PowerShell\ScheduledJobs\" -erroraction 'silentlycontinue'
        return $tasks
    }
    catch
    {
        # do nothing if there are no tasks
    }
}

function Show-PowerShellTasks(){
    $index = 0
    
    $answer = "y"
    while ($answer -match "y")
    {
        try{
            $index = 0
            $tasks = Get-PowershellTasks
            if(!$tasks -or $tasks.Count -eq 0)
            {
                Read-Host "No powershell Scheduled Tasks configured.  (Press any key to continue...)"
                return $null
            }        
            $tasks | Out-String | Write-Host
        
            $answer = Read-Host "Do you want to start/stop any of these tasks [y/n (or any key)]?"
            
            if($answer -match "y")
            {
                Write-Host
                $tasks | % {
                    Write-Host "[$index] $($_.TaskName)"
                    $index++
                }
                
                Write-Host
                $task = Read-Host "Which task?"
                
                if(-not ($task -match '^[0-9]+$') -or (0 -gt [int]$task -or [int]$task -gt $tasks.Count ))
                {
                    continue
                }

                if($task -eq $tasks.Count)
                {
                    return $null
                }
                
                $selectedTask = $tasks[$task]
                
                if($selectedTask.State -eq 'Running')
                {
                    Stop-ScheduledTask -TaskPath $selectedTask.TaskPath $selectedTask.TaskName
                }
                elseif ($selectedTask.State -eq 'Ready')
                {
                    Start-ScheduledTask -TaskPath $selectedTask.TaskPath $selectedTask.TaskName
                }
            }
        }
        catch
        {
            Read-Host "No powershell Scheduled Tasks running.  (Press any key to continue...)"
            return $null
        }    
    }
}
Set-Alias displayPowerShellTasks Show-PowerShellTasks -Scope Global

function Enable-PSTranscriptionLogging([Parameter(Mandatory)][string]$OutputDirectory)
{
     # Registry path
     $basePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'

     # Create the key if it does not exist
     if(-not (Test-Path $basePath))
     {
         $null = New-Item $basePath -Force

         # Create the correct properties
         New-ItemProperty $basePath -Name "EnableInvocationHeader" -PropertyType Dword
         New-ItemProperty $basePath -Name "EnableTranscripting" -PropertyType Dword
         New-ItemProperty $basePath -Name "OutputDirectory" -PropertyType String
     }

     # These can be enabled (1) or disabled (0) by changing the value
     Set-ItemProperty $basePath -Name "EnableInvocationHeader" -Value "1"
     Set-ItemProperty $basePath -Name "EnableTranscripting" -Value "1"
     Set-ItemProperty $basePath -Name "OutputDirectory" -Value $OutputDirectory

}

Export-ModuleMember -Function  *-*