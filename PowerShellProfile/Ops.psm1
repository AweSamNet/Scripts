[CmdletBinding()]
param(
    $defaultRoot = "C:\",
    $localModules
)
### 
### Operations related functionality
###

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$opsScriptPath = (Get-Item $MyInvocation.MyCommand.Definition).FullName

$defaultWatchedChocolateyInstallPath = Join-Path $ScriptPath "Watched\ChocolateyInstalls.txt"
$defaultSystemNotificationsPath = Join-Path $ScriptPath "Watched\SystemNotifications.txt"

$argmentList = $psBoundParameters.Values | % { $_ }

#Import "Common" -ArgumentList:$argmentList
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

function Restart-Pageant()
{
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "pageant.lnk"

    $process = Get-Process -Name pageant -ErrorAction SilentlyContinue
    if($process)
    {
        Stop-Process $process -Force
    }
    
    ii $shortcutPath
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

Add-Type @'
public enum NotificationSeverity {
    High,
    Medium,
    Low,
}
'@

function New-SystemNotification (
    [Parameter(Mandatory)][NotificationSeverity]$severity,
    [Parameter(Mandatory)][string]$source,
    [Parameter(Mandatory)][string]$message
    )
{
    $date = Get-Date
    $notification = @{
        Date = $date;
        Severity = $severity;
        Source = $source;
        Message = $message;
        
    }

    Add-Record -record:$notification -storePath:$defaultSystemNotificationsPath
}

function Get-SystemNotifications([switch]$format)
{
    $notifications = Get-Records -storePath:$defaultSystemNotificationsPath

    if($format)
    {
        return Format-SystemNotifications $notifications
    }
    
    return ,$notifications
}

function Format-SystemNotification([Parameter(ValueFromPipeline = $true)] $notification)
{
    process
    {
        $esc = "$([char]27)"
        $defaultForeground = "$esc[0m"

        $severityColor = "$esc[0m"
        if($notification.Value.Severity -eq [NotificationSeverity]::High)
        {
            $severityColor = "$esc[91m"
        }
        elseif ($notification.Value.Severity -eq [NotificationSeverity]::Medium)
        {
            $severityColor = "$esc[93m"
        }
        
        $severity = "$severityColor$([NotificationSeverity]$notification.Value.Severity)$defaultForeground"

        return [PSCustomObject]@{
            Id = $notification.Id;
            Severity = $severity;
            Date = $(Convert-UTCtoLocal $notification.Value.Date)
            Source = $notification.Value.Source
            Message = $notification.Value.Message
        }
    }
}

function Format-SystemNotifications($notifications)
{    
    if(!$notifications -or !($notifications |any) )
    {
        return
    }

    return $notifications | Format-SystemNotification | Format-Table -AutoSize
}

function Display-SystemNotifications()
{
    do
    {
        $notifications = @()
        (Get-SystemNotifications)  `
            | Sort-Object -Property `
                @{Expression = {$_.Value.Severity}; Ascending = $true}, `
                @{Expression = {$_.Value.Date}; Ascending = $true} `
            | % { $notifications += $_ }
            
        if(!$notifications)
        {
            pause "No new notifications to display."
            return
        }

        Format-SystemNotifications $notifications

        $answer = Read-Host "What would you like to do? Clear [a]ll, Read [0-9] Id, [Enter] Cancel)]"
        $id = $answer -as [int]

        if(!$answer -or !$answer.Trim())
        {
            return
        }

        if($answer -match "a")
        {
            Clear-SystemNotifications
            Write-Host "System Notifications Cleared"        
            return
        }

        if($answer -and $answer.Trim() -and $id)
        {
            if($notifications | any { $_.Id -eq $id })
            {
                $notification = $notifications | where { $_.Id -eq $id }
                
                while ($notification)
                {
                    clear
                    $notification | Format-SystemNotification | Out-Host

                    $options = @()
                    $index = $notifications.indexOf($notification)
                    
                    if($index -ne 0)
                    {
                        $options += ,@([ConsoleKey]::LeftArrow, "[<] Previous")
                    }
                    
                    if($index -ne $notifications.Count - 1)
                    {
                        $options += ,@([ConsoleKey]::RightArrow, "[>] Next")
                    }
                    
                    $options += ,@([ConsoleKey]::Delete, "[Del] Delete")
                    $options += ,@([ConsoleKey]::Enter, "[Enter] Return")
                    
                    $answer = Read-Input -singleKey -options:$options
                    
                    if($answer.VirtualKeyCode -eq [ConsoleKey]::LeftArrow)
                    {
                        $notification = $notifications[$index - 1]
                        continue
                    }
                    
                    if($answer.VirtualKeyCode -eq [ConsoleKey]::RightArrow)
                    {
                        $notification = $notifications[$index + 1]
                        continue
                    }
                    
                    if($answer.VirtualKeyCode -eq [ConsoleKey]::Enter)
                    {
                        clear
                        break
                    }
                    
                    if($answer.VirtualKeyCode -eq [ConsoleKey]::Delete)
                    {
                        Remove-Record -id:$notification.Id -storePath:$defaultSystemNotificationsPath

                        if($index -eq $notifications.Count - 1)
                        {
                            clear
                            break
                        }
                        
                        $notifications = $notifications | where { $_.Id -ne $notification.Id }
                        $notification = $notifications[$index]
                    }
                }
            }
        }
    } until ($false)
}

function Clear-SystemNotifications()
{
    Clear-List -storePath:$defaultSystemNotificationsPath
}

# function Find-TextInFiles(
    # [string] $fullPath=".", 
    # [string[]]$textToFind, 
    # [string[]]$filter="*", 
    # [string[]]$exclude, 
    # [switch]$fn, 
    # [switch]$first, 
    # [int]$parentProgressId, 
    # [int]$totalThreads,
    # [array]$files)
    
function Parse-PSTranscriptionLog(
    [string]$transcriptionDirectory,
    [string]$outputPath)
{
    $startTime = Get-Date
    try
    {
        $lines = Find-TextInFiles -fullPath:$transcriptionDirectory -textToFind:"^\*+$" -regEx #| Out-File -FilePath $outputPath        
        $lines = $lines | sort File, Line
        
        
        
    }
    finally
    {
        $result = ($(get-date) - $startTime)
        Write-Host $result
    }
    
}

Export-ModuleMember -Function  *-*