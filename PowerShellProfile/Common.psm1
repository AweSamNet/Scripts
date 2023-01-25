###
### Common Profile functions for all users
### Load module via `Import-Module $ScriptPath\Common -ArugmentList "C:\path"
###
[CmdletBinding()]
param(
    $defaultRoot = "C:\",
    $localModules
)

$boundParameters = $psBoundParameters.Values 

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

Export-ModuleMember -Variable @('ScriptPath')

function Edit-Common
{
    notepad++ $(Join-Path $ScriptPath 'Common.psm1')
}

function Edit-Profile
{
    if (-not(Get-Command "notepad++" -ErrorAction SilentlyContinue))
    {
        notepad $profile
        return
    }    
    notepad++ $profile
}

function Get-CommonCommands ([int]$columns = 3)
{
    $names = Get-Command -Module Common | % { $_.Name }
    Write-Table $names $columns
}

function Set-Shortcut( [string]$SourceExe, [string]$DestinationPath, [string]$StartIn, $ArgumentList)
{
    
    if( $ArgumentList -is [array])
    {
        $argumentsJoined = ""
        foreach ($argument in $ArgumentList)
        {
            $argumentsJoined += """$argument"" "
        }
        $ArgumentList = $argumentsJoined
    }
    
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($DestinationPath)

    $Shortcut.TargetPath = $SourceExe
    $Shortcut.Arguments = $ArgumentList
    $Shortcut.WorkingDirectory = $StartIn
    
    $Shortcut.Save()
}

function Install-Chocolatey()
{
    if(-not $env:ChocolateyInstall -or -not (Test-Path "$env:ChocolateyInstall"))
    {
        Write-Output "Chocolatey Not Found, Installing..."
        Set-ExecutionPolicy Bypass
        iex ((new-object net.webclient).DownloadString('http://chocolatey.org/install.ps1')) 
    }
}
function Is-Installed( [Parameter(Mandatory=$true)][string]$software)
{
    return (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { 
        HasProperty $_ "DisplayName"} `
        | Where { $_.DisplayName -match $software }) -ne $null
}
function xsd()
{
    & (Find-Program "Microsoft SDKs\Windows\v7.0A\Bin\xsd.exe") $args
}

function Get-Sha1Hash()
{
    <#
        Thank you Brad Wilson
        http://bradwilson.typepad.com/blog/2010/03/calculating-sha1-in-powershell.html
    #>

    [Reflection.Assembly]::LoadWithPartialName("System.Security") | out-null
    $sha1 = new-Object System.Security.Cryptography.SHA1Managed

    $args | %{
        resolve-path $_ | %{
            Write-Output ([System.IO.Path]::GetFilename($_.Path))

            $file = [System.IO.File]::Open($_.Path, "open", "read")
            $sha1.ComputeHash($file) | %{
                Write-Output -nonewline $_.ToString("x2")
            }
            $file.Dispose()

            Write-Output
            Write-Output
        }
    }
}

## Open URL in Browsers
function Open-Chrome($url)
{
    Start-Process 'chrome.exe' "$url"
}
Set-Alias chrome Open-Chrome -Scope Global


function RemoteDesktop($server)
{
    mstsc /v:"$server" 
}

function Watch-Output($toTail, $lines = 5)
{    
    if($toTail -is [string] -and (Test-Path $toTail))
    {
        Get-Content -Path $toTail -Tail $lines -Wait
    }
    elseif($toTail.GetType().ImplementedInterfaces.Contains([type]"System.Collections.ICollection"))
    {
        # get the start length 
        $count = $toTail.Count
        $length = iif ($count -gt $lines) $lines $count

        # get the first few lines
        for($i = $count - $length; $i -lt $count; $i++)
        {
            "" + ($i + 1) + ": " + $toTail[$i]
        }
        
        while($true)
        {
            $newCount = $toTail.Count
            
            if($newCount -gt $count)
            {
                # get the length of new lines
                $length = $newCount - $count 
                $count = $newCount
                
                # get all lines since the last count
                for($i = $count - $length; $i -lt $count; $i++)
                {
                    "" + ($i + 1) + ": " + $toTail[$i]
                }
            }
            
            Start-Sleep -m 500
        }
    }
    # if this is just an object, tail the Out-String    
    else
    {
        $result = $null
        
        while($true)
        {
            $newResult = $toTail | Out-String -width 1000
            if($newResult -ne $result)
            {
                $result = $newResult
                "" + (Get-Date) + ": " + $result
            }
        
            Start-Sleep -m 500
        }
    }
}
Set-Alias tail Watch-Output -Scope Global

function Protect-File($InFile, $OutFile, $Password)
{
    & "$ToolsPath\openssl.exe" cast5-cbc -base64 -k $Password -e -in $InFile -out $OutFile
}

function Unprotect-File($InFile, $OutFile, $Password)
{
    & "$ToolsPath\openssl.exe" cast5-cbc -base64 -k $Password -d -in $InFile -out $OutFile
}

function Reset-Modules([switch]$silent)
{
    Import Git -ArgumentList:$boundParameters -silent:$silent 
    Import Ops -ArgumentList:$boundParameters -silent:$silent
    Import Github -ArgumentList:$boundParameters -silent:$silent
    
    if(Test-Path Variable:\localModules)
    {
        foreach($module in $localModules)
        {
            Import -Module:$module.Name -path:$module.Path -ArgumentList:$module.ArgumentList
        }
    }
    cd $defaultRoot
}

function Find-ReplaceTextInFiles([Parameter(Mandatory=$true)] $fullPath, $textToFind, $replaceWith, [switch]$fn )
{
    $files = Get-ChildItem  $fullPath -rec -File
    $index = 0

    foreach ($file in $files)
    {
        Write-Progress -Activity "Replacing in matching files" -Status $("File " + ($index + 1) + " of " + $files.Count ) -PercentComplete($index / $files.Count * 100 )
        $index++

        (Get-Content $file.PSPath) |
            Foreach-Object { $_ -replace $textToFind, $replaceWith } |
            Set-Content $file.PSPath
    }

    if($fn)
    {
        $files | Rename-Item -NewName {$_.name -replace $textToFind, $replaceWith }
    }
}

function WriteTextInFilesProgress(
    [Parameter(Mandatory=$true)][int]$progressId, 
    [int]$parentProgressId,
    [string[]]$filter,
    [Parameter(Mandatory=$true)][string[]]$textToFind,
    [string[]]$exclude,
    [Parameter(Mandatory=$true)][int]$index,
    [Parameter(Mandatory=$true)][int]$total,
    [Parameter(Mandatory=$true)][int]$totalFound,
    [switch]$first
)
{    
    $activity = $("Searching files: " + [string]::Join(", ", $filter) + " for ")
    if($first)
    {
        $activity += "first"
    }

    $activity += $(": " +[string]::Join(", ", $textToFind))
    
    if($exclude -and $exclude.Count -gt 0)
    {
        $activity += $(" - Excluding: ")
        $activity += [string]::Join(", ", $exclude)
    }

    $status = $("File " + ($index + 1) + " of " + $total + ". Found: " + $totalFound  )

    Write-Progress -Id $progressId -ParentId $parentProgressId -Activity $activity -Status $status -PercentComplete($index / $total * 100 ) 
}

function Find-TextInFiles(
    [string] $fullPath=".", 
    [string[]]$textToFind, 
    [string[]]$filter="*", 
    [string[]]$exclude, 
    [switch]$fn, 
    [switch]$first, 
    [int]$parentProgressId, 
    [int]$totalThreads,
    [array]$files,
    [switch]$regEx)
{
    $fullPath = Convert-Path $fullPath
    try
    {
        $progressId = 1
        if(-not $parentProgressId)
        {
            $parentProgressId = 0
        }
        elseif ($parentProgressId -eq $progressId)
        {
            $progressId++
        }

        $activity = $("Building list of files of type " + [string]::Join(", ", $filter) + " in: " + $fullPath)
        $fileCount = 0
        if(-not $totalThreads)
        { 
            $totalThreads = 1
        }

        [array]$fileSplits = @()

        for($i = 0; $i -lt $totalThreads; $i++)
        {
            [array]$split = @()
            $fileSplits += ,$split
        }

        if(-not $files -or $fileSplits.Count -eq 0)
        {
            $files = Get-ChildItem  $fullPath -Recurse -File | Where-Object{
                foreach($criteria in $exclude)
                {
                    if($_.FullName -match [Regex]::Escape($criteria)){
                        return $false
                    }
                }
                foreach($criteria in $filter)
                { 
                    if($_.FullName -like $criteria){
                        return $true
                    }
                }

                return $false
            } | ForEach-Object { 

                $collectionIndex = $fileCount % $totalThreads
                $fileSplits[$collectionIndex] += ,$_
                Write-Progress -Activity $activity -Status $("Found: " + ++$fileCount) -Id $progressId -ParentId $parentProgressId
                $_
            }
        }
        else
        {
            $files | ForEach-Object { 

                $collectionIndex = $fileCount % $totalThreads
                $fileSplits[$collectionIndex] += ,$_
                $fileCount++
            }
        }

        $index = 0;
        $totalMatching = 0;

        $searchThread = {
            param(
                [string]$marker,
                [array]$filesSplit,
                [array]$textToFind,
                $first,
                $fn,
                [bool]$regEx
            )
            $exit = $false

            foreach ($file in $filesSplit)
            {    
                if($first -and ($exit -or (Test-Path "$marker")))
                {
                    $exit = $true
                    break;
                }

                # yield an empty result to signal file progress starting
                $null

                $textToFind | ForEach-Object{
                    if($regEx)
                    {
                        $escapedText = $_
                    }
                    else
                    {
                        $escapedText = [Regex]::Escape($_)
                    }

                    if($fn -and ($file.Name -match $escapedText))
                    {
                        $fileLinePair = @{
                            File = $file.FullName;
                            Line = "File name";
                        }
                    
                        # yield return the file
                        $fileLinePair

                        if($first)
                        {
                            $exit = $true
                            break;
                        }
                    }
                }
                $lineCount = 0

                if($first -and ($exit -or (Test-Path "$marker")))
                {
                    break;
                }

                (Get-Content $file.PSPath) |
                    Foreach-Object{
                        $lineCount++
                        foreach($text in $textToFind)
                        {
                            if($regEx)
                            {
                                $escapedText = $text
                            }
                            else
                            {
                                $escapedText = [Regex]::Escape($text)
                            }

                            #Write-Host $escapedText
                            if($_ -match $($escapedText))
                            {
                                $fileLinePair = @{
                                    File = $file.FullName;
                                    Line = $("Line " + $lineCount + ": " + $_);
                                }

                                # yield return the file
                                $fileLinePair

                                if($first)
                                {
                                    $exit = $true
                                    break;
                                }
                            }
                        }

                        if($first -and ($exit -or (Test-Path "$marker")))
                        {
                            break;
                        }
                    }

                if($first -and ($exit -or (Test-Path "$marker")))
                {
                    break;
                }
            }
        }

        $jobs = @()
        $searchId = Get-Date -Format yyyymmddThhmmssmsms
    
        $marker = (Join-Path $ScriptPath $($searchId + ".complete.txt"))

        Write-Progress -Activity $("Starting search threads") -Status $("Started 0 of " + $totalThreads) -Id $progressId -ParentId $parentProgressId -PercentComplete 0

        # split the files into segments and run the threads
        for($i = 0; $i -lt $totalThreads; $i++)
        {
            $jobs += Start-Job -ScriptBlock $searchThread -ArgumentList $marker,$fileSplits[$i],$textToFind,$first,$fn,$regEx | ForEach-Object{            
                Write-Progress -Activity $("Starting search threads") -Status $("Started " + ($i + 1) + " of " + $totalThreads) -Id $progressId -ParentId $parentProgressId -PercentComplete (($i + 1) / $totalThreads * 100)
                $_
            }
        }
        $complete = $false
    
        while(-not $complete)
        {        
            $complete = $true
            #see if all jobs are complete
            $jobs | ForEach-Object{
                if($_.State -eq "Running")
                {
                    $complete = $false                
                }
            }

            if(-not $complete)
            {
                Start-Sleep -Seconds 1
            }

            $jobs | Receive-Job | ForEach-Object{
                # if null is returned, a file was completed with no match
                if(-not $_)
                {
                    $index++
                }
                # when a match is returned increment the count and yield the result
                else{
                    $totalMatching++
                    #[System.Threading.Interlocked]::Increment([ref]$totalMatching)
                    $_

                    if($first -and -not (Test-Path "$marker"))
                    {
                        $markerFile = New-Item $marker -type file
                    }
                }

                WriteTextInFilesProgress    -progressId:$progressId `
                                            -parentProgressId:$parentProgressId `
                                            -filter:$filter `
                                            -textToFind:$textToFind `
                                            -exclude:$exclude `
                                            -index:$index `
                                            -total:$files.Count `
                                            -totalFound:$totalMatching `
                                            -first:$first
            }

        }    

        $completedJobs = Wait-Job -Job $jobs
    }
    finally
    {
        if($first -and (Test-Path "$marker"))
        {
            Remove-Item $marker
        }
    }
}

function Find-HighlightTextInFiles(
    [string] $fullPath=".", 
    [string[]]$textToFind, 
    [string[]]$filter="*", 
    [string[]]$exclude, 
    [switch]$fn, 
    [switch]$first, 
    [int]$parentProgressId, 
    [int]$totalThreads,
    [array]$matches=$null,
    [array]$files)

{
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    $fullPath = Convert-Path $fullPath

    if(-not $matches)
    {
        $matches=@()
        @(Find-TextInFiles $fullPath -textToFind:$textToFind -filter:$filter -fn:$fn -first:$first -parentProgressId:$parentProgressId -exclude:$exclude -totalThreads:$totalThreads -files $files | ForEach-Object{
            
            $matches += ,$_
            try
            {
                Write-Highlight $($_["File"] + ": " + $_["Line"]) $textToFind
            }
            catch
            {
                Write-Error "Failed here"
                $_
                $_["File"]
            }
        })
    }
    else
    {
        $matches | ForEach-Object{
            Write-Highlight $($_["File"] + ": " + $_["Line"]) $textToFind
        }
    }

    if(-not $matches -or $matches.Count -eq 0)
    {
        $message = "No Matches Found"
        Write-Highlight $($message) $message
        return
    }
    Write-Host "Total Elapsed Time: $($elapsed.Elapsed.ToString())"
}

function Get-RedirectedUrl {

    Param (
        [Parameter(Mandatory=$true)]
        [String]$URL
    )

    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect=$false
    $response=$request.GetResponse()
    $response.GetResponseHeader("Location")
}

# ex: "((\W|^)edm.*|.*edmunds.*)"
function Find-SurroundingText(
    [Parameter(ValueFromPipeline=$true)]
    [string[]] $text, 
    [string] $path,
    [Parameter(Mandatory=$true)]
    [string]$regexPattern, 
    [int]$linePaddingCount=5,
    [switch]$pause)
{
    process
    {
        if($path -and (Test-Path $path))
        {
            $text = [System.IO.File]::ReadLines($path)
        }
        
        for($index = 0; $index -lt $text.Count; $index++)
        {
            [int]$minIndex = $index - $linePaddingCount
            [int]$maxIndex = $index + $linePaddingCount
            
            if($minIndex -lt 0)
            {
                $minIndex = 0
            }
            if($maxIndex -gt $text.Count -1)
            {
                $maxIndex = $text.Count -1
            }    
            $found = $false

            for($i = $index; $i -le $maxIndex; $i++)
            {
                $nextLine = $text[$i]
                # if this line is within 5 lines of a match, return it
                if($nextLine -match $regexPattern)
                {
                    $text[$index]
                    $found = $true
                    break
                }
            }
            
            if(-not $found)
            {
                #if this line is within 5 lines after a match, return it    
                for($i = $index; $i -ge $minIndex; $i--)
                {
                    $prevLine = $text[$i]
                    if($prevLine -match $regexPattern)
                    {
                        $text[$index]
                        $found = $true
                    }
                    
                    # if this is the 5th line after a match, add a break
                    if($found -and $i -eq $minIndex)
                    {
                        "`n---------------------------------------------------------------------------------------------------`n"
                       
                        if($pause)
                        {
                            $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                        }
                    }
                    
                    if($found)
                    {
                        break
                    }
                }
            }
        }
    }
}

function Write-Highlight([Parameter(ValueFromPipeline=$true)] [string[]]$text, [string[]]$textsToHighlight=$null, [switch]$pause, $highlightColor = "Yellow" )
{
    process
    {
        if(!$text) {
            return
        }
        
        $defaultFg = (get-host).ui.rawui.ForegroundColor
        $defaultBg = (get-host).ui.rawui.BackgroundColor
    
        $splitText = @()
    
        if(-not $textsToHighlight)
        {
            $text | % { Write-Host $_ -ForegroundColor Black -BackgroundColor $highlightColor }
            return
        }
            # loop through existing line splits to see if they can be split more
        :nextLine foreach($line in $text)
        {
            [Collections.Generic.List[String]]$newSplits = ,$line
            if(-not($textsToHighlight -contains $line))
            {
                foreach($textToHighlight in $textsToHighlight)
                {
                    if(!$textToHighlight){
                        continue
                    }
                    
                    $finished = $false
                    $replaceIndex = $null
                    $replaceWith = $null
                    $skipToIndex = 0
                    :nextSplit while(-not $finished)
                    {  
                        for($i = $skipToIndex; $i -lt $newSplits.Count; $i++)
                        {
                            $lineSplit = $newSplits[$i]
                            
                            # if the line is already a split, move on
                            if($textsToHighlight -contains $lineSplit)
                            {
                                $skipToIndex = $i + 1
                                $replaceIndex = $null
                                continue nextSplit
                            }
                            
                            $split = [Regex]::Split($lineSplit, $("(?i)(" + [Regex]::Escape($textToHighlight) + ")"))

                            if($split.Count -gt 1)
                            {
                                $replaceIndex = $i
                                $replaceWith = $split
                                break
                            }
                        }
                        $skipToIndex = 0
                        if($replaceIndex -ne $null)
                        {
                            # remove the original line and replace it with the splits
                            $newSplits.RemoveAt($replaceIndex)

                            # now insert the splits at the proper index
                            $newSplits.InsertRange($replaceIndex, $replaceWith)
                            
                            # now set the lines to the main collection
                            $splitText = ,$newSplits.ToArray()  
                            continue
                        }
                        
                        $finished = $true
                    }
                }
            }
            $splitText = ,$newSplits.ToArray()  
        }
        
        for($i = 0; $i -lt $splitText.Count; $i++)
        {
            $split = $splitText[$i]
            for($j = 0; $j -lt $split.Count; $j++)
            {
                if(-not $textsToHighlight -or ($textsToHighlight.Count -eq 0) `
                    -or $textsToHighlight -contains $split[$j]) 
                {
                    Write-Host $split[$j] -NoNewline -ForegroundColor Black -BackgroundColor $highlightColor
                }
                else
                {
                    Write-Host $split[$j] -NoNewline -ForegroundColor $defaultFg -BackgroundColor $defaultBg
                }
                
                Write-Host -ForegroundColor $defaultFg -BackgroundColor $defaultBg -NoNewline
                
                if($pause `
                    -and $textsToHighlight `
                    -and ($textsToHighlight.Count -gt 0) `
                    -and $split `
                    -and $split.Count -gt 0 `
                    -and ($textsToHighlight -contains $split[$j]))
                {
                    Write-Host
                    cmd /c pause #| out-null
                }
            }
            Write-Host -ForegroundColor $defaultFg -BackgroundColor $defaultBg
        }
    }
}

function Convert-UTCtoLocal
{
    param(
        [parameter(Mandatory=$true)]
        $UTCTime
    )

    [datetime]::SpecifyKind($UTCTime,'Utc').ToLocalTime()
}
    
function ConvertFrom-UtcEpochSeconds([Parameter(Mandatory=$true)][long]$seconds)
{
    $origin = New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
   
    return $origin.AddSeconds($seconds)
}

function ConvertTo-UtcEpochSeconds([Parameter(Mandatory=$true)][DateTime]$date)
{
    $origin = New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    (New-TimeSpan -Start $origin -End $date).TotalSeconds
}

function Find-InJson(
    [parameter(Mandatory=$true)]
    $json,
    [parameter(Mandatory=$true)]
    [ScriptBlock]$where)
{
    if($json -is [string])
    {
        try
        {
            # see if this is a path to a file.
            if(Test-Path $json)
            {
                $json = Get-Content $json | Out-String
            }
        }
        catch
        {
            # if anything fails just try to convert to json
        }
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")        
        $jsonserial= New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer 
        $jsonserial.MaxJsonLength = [int]::MaxValue
        $json = $jsonserial.DeserializeObject($json)
    }
    
    return $json | Where-Object $where
}

# Set the window title
function Set-Title
{
    $Host.UI.RawUI.WindowTitle = $args[0]
}    
Set-Alias title Set-Title -Scope Global

function New-PsSession([Parameter(Mandatory=$true)][scriptblock]$command, [string]$title=$null, [switch]$native)
{
    $sb = @'
&{
    param([string]$title, [scriptblock]$command)
    if($title){
        title $title;
    }

    Invoke-Command -ScriptBlock $command 4>&1
    
    Write-Host 'Press any key to continue ...'

    title 'Stopped '+$title
    
    $x = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} -title '
'@+$title+@'
' -command { 
'@+$command+'}'

    if((Is-Installed conemu) -and !$native)
    {
        # -new_console is a conemu command.  
        invoke-expression "powershell -new_console -noexit -Command { $sb }"
    }
    else{
        # for non conemu environments, to open in a new ps session use:
        Start-Process powershell -ArgumentList "-noexit -Command $sb "
    }
}

function Test-IsAdmin
{
    $wid=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp=new-object System.Security.Principal.WindowsPrincipal($wid)
    $adm=[System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}

# Quickly edit your hosts file
function Edit-HostsFile{
    if(-not(Test-IsAdmin))
    {
        if (-not(Get-Command "sudo" -ErrorAction SilentlyContinue))
        {
            Write-Host "You must have admin rights to edit hosts file.  Please open a new console window with admin rights."
            return
        }
        sudo notepad++ 'C:\windows\system32\Drivers\etc\hosts'        
    }
}

function Test-InlineIf($if, $ifTrue, $ifFalse) {
    if ($if) 
    {
        if ($ifTrue -is "ScriptBlock") 
        {
            &$ifTrue
        } 
        else 
        {
            return $ifTrue
        }
    }
    else {
        if ($ifFalse -is "ScriptBlock") 
        {
            &$ifFalse
        } 
        else 
        {
            return $ifFalse
        }
    }
}
Set-Alias iif Test-InlineIf -Scope Global

function Get-DataFiles([Parameter(Mandatory)][string]$path, $start = $null, $end = $null)
{
    $directories = @()
    
    if(Test-Path $path)
    {
        $directories = dir $path -Directory
    }
    
    $directories = $directories | where {
        $directoryDate = Get-Date $_.Name
        
        $startMonth = $null
        $endMonth = $null
        
        if($start -ne $null){
            $startMonth = Get-Date "$($start.Year)-$($start.Month)"
        }
        
        if($end -ne $null){        
            $endMonth = Get-Date "$($end.Year)-$($end.Month)"
        }
        
        if(($startMonth -eq $null -or($directoryDate -ge $startMonth)) `
            -and($endMonth -eq $null -or($directoryDate -le $endMonth )))
        {
            return $true
        }
        
        return $false
    }
    
    # get a list of all the files that match
    $directories | % {
        dir $_.FullName -File | where {
            $fileDate = Get-Date $_.Name
            
            $startDay = $null
            $endDay = $null
            
            if($start -ne $null){
                $startDay = $start.Date
            }
            
            if($end -ne $null){        
                $endDay = $end.Date
            }
            
            ($startDay -eq $null -or($fileDate -ge $startDay)) `
                -and($endDay -eq $null -or($fileDate -le $endDay ))            
        } | % { $_ }
    }
}

function Get-JsonFromFile([Parameter(Mandatory)][string]$storePath){
    if (-not (Test-Path $storePath))
    {
        $output = New-Item -ItemType File -Force -Path $storePath 
    }
    
    $content = Get-Content $storePath -Raw
    
    if(!$content){
        return
    }
    
    $results = ConvertFrom-Json $content 
    
    try{
        if($results -is [array] -and $results.Count -le 1)
        {
            return ,({$results}.Invoke())
        }
        else
        {
            return {$results}.Invoke()
        }
    }
    catch
    {
        Write-Error "Failed trying to invoke file $storePath"
        throw
    }
}

function Get-CurrentUserCredentials ($message = $null)
{
    $msg = "Enter the username and password that will run the task";
    $Host.UI.PromptForCredential("Task username and password",$msg,"$env:userdomain\$env:username",$env:userdomain)
}

function Suspend-Console([string]$message)
{
    if($message)
    {
        Write-Host "$message.........."
    }
    Write-Host "Press any key to continue..."
    try
    {
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch
    {
        Read-Host
    }
}
Set-Alias pause Suspend-Console -Scope Global

function Write-Table([string[]]$values, [int]$columns = 3, [int]$padding = 3) 
{
    # get the largest command name length and add a spacer of 3    
    $maxLength = ($values | Measure-Object -Maximum -Property Length).Maximum + $padding
    
    # get column height 
    $height = [int][Math]::Ceiling($values.Count / $columns)
    
    $cols = @()
    
    $totalSplit = 0
    
    $result = ""
    $colHeight = $height
    for ($i = 0; $i -lt $values.Count; $i += $colHeight) 
    {
        # get the columns height 
        $colHeight = [int][Math]::Ceiling(($values.Count - $totalSplit) / ($columns - $cols.Count))
        
        $totalSplit += $colHeight
        
        $subsetMaxIndex = $i + $colHeight - 1
        
        if($subsetMaxIndex -gt $values.Count)
        {
            $subsetMaxIndex = $values.Count - 1
        }
        
        $cols += ,@($values[$i..$subsetMaxIndex])
    }
    
    for ($i = 0; $i -lt $height; $i++)
    {
        $row = ""
        for ($col = 0; $col -lt $cols.Length; $col++)
        {
            # make sure that we have enough lines in this column
            if($i -lt $cols[$col].Length)
            {
                $value = $cols[$col][$i]
                
                $originalLength = $value.Length
                # do padding
                for($c = $originalLength; $c -le $maxLength; $c++)
                {
                    $value += " "
                }
                
                $row += $value
            }
        }
        $result += "$row`n"
    }
    
    return $result
}

function Update-Record(
    $record,
    [scriptblock]$query,
    [int]$id=0,
    [Parameter(Mandatory=$true)][string]$storePath
){
    Remove-Record $query $id $storePath
    Add-Record $record $id $storePath
}
Set-Alias Update-WatchedItem Update-Record -Scope Global
Set-Alias upsert Update-Record -Scope Global


function Add-Record(
    $record,
    $id = 0,
    [Parameter(Mandatory=$true)][string]$storePath    
)
{
    $list = Get-Records $storePath
    
    if($list -eq $null)
    {
        $list = @()
    }
    
    if($id -le 0)
    { 
        $id = iif $($list -and $list.Count -gt 0) {($list | measure -Property Id -Maximum).maximum + 1} {1}
    }
    
    $record = @{
        Id = $id;
        Value = $record;
    }
    
    $list += $record
    $body = ConvertTo-Json $list -Depth 10
    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    
}
Set-Alias Watch-Something Add-Record -Scope Global
Set-Alias watch Add-Record -Scope Global

function Get-Records([Parameter(Mandatory=$true)][string]$storePath)
{
    $toWatch = @()
    
    if ((Test-Path $storePath) -eq $true)
    {
        $content = Get-Content $storePath -Raw
        if(-not $content)
        {
            return
        }
        
        $toWatch = ConvertFrom-Json $content
    }
    
    return ,$toWatch
}
Set-Alias Get-Watched Add-Record -Scope Global

function Remove-Record(
    [scriptblock]$query,
    [int]$id=0,
    [Parameter(Mandatory=$true)][string]$storePath
)
{
    $list = Get-Records $storePath
    
    $toRemove = $null

    if($id -gt 0)
    {
        $toRemove = $list | where { 
            $_.Id -eq $id
        } | select -First 1
    }
    else
    {       
        $toRemove = $list | where $query | select -First 1
    }
    
    if($toRemove)
    {
        $list = [System.Collections.ArrayList]$list
        $success = $list.Remove($toRemove)
    } 
    
    $body = ConvertTo-Json $list -Depth 10

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
}
Set-Alias Unwatch-Something Remove-Record -Scope Global
Set-Alias unwatch Remove-Record -Scope Global

function Clear-List([Parameter(Mandatory=$true)][string]$storePath)
{
    if(Test-Path $storePath)
    {
        rm $storePath
    }
}

function Read-Required(
    [Parameter(Mandatory=$true)]$prompt,
    [string[]]$values,
    [switch]$emptyIsLastValue,
    [string]$valueDescription=$null
    )
{
    if(!$valueDescription)
    {
        $valueDescription = $values -join "/"
        if($emptyIsLastValue)
        {
            $valueDescription += " or Enter"
        }
        $valueDescription = "[$valueDescription]"
    }
    
    do
    {
        $answer = $(Read-Host "$prompt $valueDescription").Trim()        
    } while (!($values -contains $answer -or($emptyIsLastValue -and !$answer)))
    
    if(!$answer -and $emptyIsLastValue)
    {
        $answer = $values[-1]
    }
    
    return $answer
}

# helper to turn PSCustomObject into a list of key/value pairs
function Get-ObjectMembers {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [PSCustomObject]$obj
    )
    $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
        $key = $_.Name
        [PSCustomObject]@{Key = $key; Value = $obj."$key"}
    }
}

function Get-ObjectHasProperty($object, $propertyName)
{
    return [bool]($object.PSobject.Properties.name -like $propertyName)
}
Set-Alias HasProperty Get-ObjectHasProperty -Scope Global

function Get-IsNullOrEmpty([Parameter(ValueFromPipeline=$True)]$value=$null)
{
    if($null -eq $value)
    {
        return $true
    }
    
    if($value -is [array])
    {
        return @($value).Count -eq 0
    }
    
    return $false
}
Set-Alias IsNullOrEmpty Get-IsNullOrEmpty -Scope Global

if(-not(Test-Path Variable:\localModules) -or $localModules -eq $null)
{
    Write-Output ""
    Write-Highlight 'Parameter $localModules not passed to Common module'    
    Write-Output ""
    
    Write-Output `
'The parameter $localModules is used to load environment specific modules.  
You must pass this variable in to your $profile (Edit-Profile) with the desired modules specified.
If you do not have any environment specific modules to load you should still pass an empty array.

You can use the following as a template:
'

    Write-Highlight -highlightColor "DarkGray" -text '
------------------------------------------------------------------------------------------------
    
    $global:localModules = @(
        @{
            Path = "D:\Users\Sam\Google Drive\Scripts\Apps\SampleModule";
            Name = "SampleModule";
            ArgumentList = @($myParameterOne, $myParameterTwo);
        }
    )
    
------------------------------------------------------------------------------------------------'
    $openProfile = Read-Host "Would you like to view your system profile?[y/n]"

    if($openProfile -eq "y")
    {
        Edit-Profile
    }
}

function Read-Input(
    $message = "",
    [Array] $options = @(),
    [switch] $singleKey)
{
    $message = @($message)
    if( $options | any { $_ -isNot [Array] -or $_.Count -ne 2 })
    {
        $argumentException = New-Object System.ArgumentException '$options must be a two-dimensional array of [key:string, text:string]'
        throw $argumentException
    }
    
    $message += ($options | % { $_[1] }) -join ", "
    
    if($singleKey)
    {
        do
        {
            Write-Host $message
                # `r for enter
                $answer = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        } until ($options | any { $_[0] -eq $answer.Character -or $_[0] -eq $answer.VirtualKeyCode})
    }
    else
    {
        do
        {
            # "" for enter
            $answer = Read-Host
        } until ($options | any { $_[0].Trim() -eq $answer.Trim()})
    }   
    
    return $answer
}
    
function Read-Int(
    
    [Parameter(Mandatory=$true)][string]$prompt,
    [ScriptBlock]$additionalValidation = $null
    )
{
    $value = -1;
    do {
      $inputString = read-host $prompt
      $value = $inputString -as [int]
      $ok = $inputString -and $inputString.Trim() `
        -and $value `
        -and(!$additionalValidation -or (&$additionalValidation $value))
      if ( -not $ok ) { write-host "You must enter an integer." }
    }
    until ( $ok )

    return $value
}

function Test-AnyOld ([ScriptBlock]$FilterScript)
{    
    begin {
        $done = $false
    }
    process { 
        if (!$done)
        {
            # Note the use of $_ | ... to provide pipeline input
            # and the use of ForEach-Object to evaluate the script block.
            if (!$FilterScript -or ($_ | ForEach-Object $FilterScript)) {
                $done = $true
            }
        }
    }
    end {
        $done
    }
}

function Test-Any {
    [CmdletBinding()]
    param(
        [ScriptBlock] $Filter,
        [Parameter(ValueFromPipeline = $true)] $InputObject
    )
    process {
      if (-not $Filter -or (Foreach-Object $Filter -InputObject $InputObject)) {
          $true # Signal that at least 1 [matching] object was found
          # Now that we have our result, stop the upstream commands in the
          # pipeline so that they don't create more, no-longer-needed input.
          (Add-Type -Passthru -TypeDefinition '
            using System.Management.Automation;
            namespace net.same2u.PowerShell {
              public static class CustomPipelineStopper {
                public static void Stop(Cmdlet cmdlet) {
                  throw (System.Exception) System.Activator.CreateInstance(typeof(Cmdlet).Assembly.GetType("System.Management.Automation.StopUpstreamCommandsException"), cmdlet);
                }
              }
            }')::Stop($PSCmdlet)
      }
    }
    end { $false }
}
Set-Alias any Test-Any -Scope Global

Export-ModuleMember -Function *-*