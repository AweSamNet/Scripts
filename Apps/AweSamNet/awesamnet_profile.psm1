param(
    [String]$drive = "C:"
)
$awesamnetScriptPath = (Get-Item $MyInvocation.MyCommand.Definition).FullName

function Edit-AweSamNetProfile
{
    notepad++ $awesamnetScriptPath
}
$awesamnetPath = "$drive\Git Workspace\AweSamNet\"
$global:awesamnetRepoPath = Join-Path $awesamnetPath 'AweSamNet'

$global:awesamnetSystemPath = "$drive\AweSamNet"

$global:awesamnetBuildTimesPath = Join-Path $awesamnetPath "AweSamNet build times\"
$global:awesamnetTestResultsPath = Join-Path $awesamnetPath "AweSamNet test results\"

$global:awesamnetBranchWatchFilePath = Join-Path $awesamnetPath "Branch Watch\AweSamNet Branches.txt"

$global:awesamnetBuildKeywordWatchFilePath = Join-Path $awesamnetPath "Keyword Watch\AweSamNet Build Keywords.txt"

# Go to your AweSam.Net source folder
function goawesamnet
{
    "Moving to AweSamNet repository"
    cd $awesamnetRepoPath
}

function Get-AweSamNetCommands ([int]$columns = 3)
{
    $names = Get-Command -Module awesamnet_profile | % { $_.Name }
    
    Write-Table $names $columns
}

# Rebuild the solution
function Build-AweSamNet(
    [switch]$all, 
    [switch]$build, 
    [switch]$rebase, 
    [string]$projects = $null,
    [switch]$pause,
    [switch]$y
    )
{   
	goawesamnet
    
    $startTime = $(get-date)    
    $buildTime = $null
    $fetchTime = $null
    
    $output = @()
    try
    {
        # set $all to true if no other switches are passed
        if(-not $all)
        {
            if( -not $rebase `
                -and(-not $build) `
                -and(-not $projects))
            {
                $all = $true
            }
        }
        
        if($all -or $rebase)
        {           
            gitp-awesamnet ([ref]$fetchTime) -project:$project -y:$y -pause:$pause | % {
                $output += $_
                $_
            }
        }
            
        if(-not $?)
        {
            Write-Error 'Rebase failed.'
            return;
        }
        
        if($all -or $build -or $projects)
        {
            $buildStart = $(Get-Date)
            $buildOutput = @()
            
            Start-BuildAweSamNet $projects | % {
                $buildOutput += $_
                $_ | Write-Highlight -pause:$pause -textsToHighlight "-- failed" 
            }
            
            Find-SurroundingText -text $buildOutput -regexPattern "((^|\W)build failed|-- failed)" | % {
                $output += $_
            }
            $buildTime = ($(get-date) - $buildStart).Ticks
        }
        
        if(-not $?)
        {
            Write-Error 'Solution build failed.'
            return;
        }
    }
    finally
    {
        $elapsedTime = $(get-date) - $startTime
        $finishedAt = Get-Date
        
        Write-Host "Displaying all failures:........... press enter to continue"
        Write-Host
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        # get watched keywords
        
        $keywords = Get-WatchedAweSamNetBuildKeywords
        
        Find-SurroundingText -text $output -regexPattern "(^|\W)(failed|Error$($($keywords | % {"|$_"}) -join ''))" -pause | Write-Highlight -textsToHighlight (("failed","Error") + $keywords)
        
        Write-Host "Total Elapsed Time: $elapsedTime"
        Write-Host "Finished at: $finishedAt"
        
        Save-BuildTimes $fetchTime $buildTime
    }
}

$fetchDurationName = "fetchDuration"
$buildDurationName = "buildDuration"

function Save-BuildTimes($fetchDuration, $buildDuration)
{
    $now = $(Get-Date)
    $totalExecution = @{
        "date" = $now
        $fetchDurationName = $fetchDuration
        $buildDurationName = $buildDuration
    }
    
    $today = [System.DateTime]::Today
    
    $buildTimesPath = $awesamnetBuildTimesPath
    
    $todayPath = Join-Path $buildTimesPath $today.ToString("yyyy-MM")
    $todayPath = Join-Path $todayPath $today.ToString("yyyy-MM-dd")
    
    $allBuildTimes = @()
    
    if ((Test-Path ($todayPath)))
    {      
        $allBuildTimes = ConvertFrom-Json (Get-Content $todayPath -Raw)
    }
    
    $list = {$allBuildTimes}.Invoke()
    $list.Add($totalExecution)
    
    $body = ConvertTo-Json $list
    
    $void = New-Item -ItemType File -Force -Path $todayPath -Value $body
    
    Get-FriendlyBuildTime $totalExecution
}

function Get-FriendlyBuildTime($buildTime)
{
    if($buildTime)
    {
        $buildDuration = IIf $buildTime.buildDuration $buildTime.buildDuration 0
        $fetchDuration = IIf $buildTime.fetchDuration $buildTime.fetchDuration 0

        $loggedTime = 
        @{
            date = $buildTime.date
            buildDuration = [timespan]$buildDuration
            fetchDuration = [timespan]$fetchDuration
            Total = [timespan][long](0 + `
                $buildDuration + $fetchDuration)
        }    
        
        return $loggedTime
    }
    
    return $null
}

function Get-BuildTimes($start = $null, $end = $null, [switch]$totals, [switch]$average)
{
    $fetchCount = 0
    $buildCount = 0

    $buildTimesPath = $awesamnetBuildTimesPath

    $allFiles = Get-DataFiles $buildTimesPath $start $end
    $allBuildTimes = @()
    
    # return all entries as objects
    $allFiles | % {
        $body = Get-Content $_.FullName -Raw 
        
        if($body)
        {
            $buildTimes = ConvertFrom-Json $body
            if($buildTimes)
            {
                $buildTimes = $buildTimes | where {
                    if(($start -eq $null -or($_.date -ge $start)) `
                        -and($end -eq $null -or($_.date -le $end )))
                    {
                        return $true
                    }
                    
                    return $false
                } | % {
                    if($_) {
                        
                        $allBuildTimes += Get-FriendlyBuildTime $_
                    }
                }
            }
        }
    }
    
    if($totals){
        Get-TotalBuildTime $allBuildTimes
    }
    
    if($average)
    {
        Get-AverageBuildTimes $allBuildTimes
    }
    
    if(-not $totals -and -not $average)
    {
        return $allBuildTimes
    }
}

function Get-TotalBuildTime($buildTimes)
{
    $totalTime = @{
        Name = "Totals";
        fetchDuration = 0;
        buildDuration = 0;
        Total        = 0;
    }

    $buildTimes | % {
        if($_.fetchDuration) { $totalTime.fetchDuration += $_.fetchDuration }
        if($_.buildDuration) { $totalTime.buildDuration += $_.buildDuration }
        if($_.Total) { $totalTime.Total += $_.Total }
    }

    return $totalTime
}

function Get-AverageBuildTimes($buildTimes)
{
    $fetchCount = 0
    $buildCount = 0
    
    if($buildTimes -and $buildTimes.length)
    {
        $buildTimes | % {
            $buildCount += IIf $_.buildDuration 1 0
            $fetchCount += IIf $_.fetchDuration 1 0
        }
        
        $totalTime = Get-TotalBuildTime $buildTimes
    
        $fetchAverage = [TimeSpan]::FromHours((IIf $totalTime.fetchDuration {$totalTime.fetchDuration.TotalHours / $fetchCount} 0))
        $buildAverage = [TimeSpan]::FromHours((IIf $totalTime.buildDuration {$totalTime.buildDuration.TotalHours / $buildCount} 0))
        $totalAverage = [TimeSpan]::FromHours((IIf $totalTime.Total {$totalTime.Total.TotalHours / $buildTimes.length} 0))
        
        @{
            Name = "Averages";
            fetchDuration = $fetchAverage;
            buildDuration = $buildAverage;
            totals = $totalAverage;
        }
    }    
}

function Start-BuildAweSamNet(
    [string]$projects = $null)
{
    $solutionPath = ""
    
	goawesamnet
	
	$solutionPath = $(Join-Path $awesamnetRepoPath 'UmbracoCMS.sln')
	
	if(!($projects))
	{
		$projects = "Build"
	}    
    
    nuget restore $solutionPath
    
	& msb $solutionPath /t:$projects /m 
}

function gitp-awesamnet (
    [ref]$gitpDuration, 
    [switch]$y,
    [switch]$pause)
{
    $originalBranch = Get-CurrentBranch
	$duration = $null
	Update-AweSamNetGit ([ref]$duration) -y:$y -pause:$pause
	if($gitpDuration)
	{
		$gitpDuration.Value = $duration
	}
    
}

function Get-AweSamNetWatchForBranch([string]$branch)
{
	return Get-AweSamNetWatchedBranches | where { $_.branch -eq $branch } | select -First 1    
}

$rebaseFailed = "Rebase was not able to continue."

function Update-AweSamNetGit(
    [ref]$gitpDuration, 
    [switch]$doWatch=$true, 
    [switch]$y,
    [switch]$pause)
{        
    $originalBranch = Get-CurrentBranch

    $rebaseSuccess = $true
    
    $watchPath = $null
    
    if($doWatch)
    {
		$watchPath = $awesamnetBranchWatchFilePath                    
	}
    
    # see if there is a watch for this branch and if the base branch is not next
    $pushRemote = $null
    $baseRemote = "upstream"
    $baseBranch = "next"

	$pushRemote = "origin"

    $matchingWatch = Get-AweSamNetWatchForBranch $originalBranch
    if($matchingWatch)
    {
        "Rebasing branch $originalBranch from branch $($matchingWatch.baseRemote)/$($matchingWatch.baseBranch)"

        if($pause)
        {
            pause
        }
        
        $baseBranch = $matchingWatch.baseBranch
        $baseRemote = $matchingWatch.baseRemote
    }
    
    if($pause)
    {
        pause
    }
    
    $gitpStart = $(get-date) 

    gitp -baseRemote:$baseRemote -baseBranch:$baseBranch -a -pushRemote:$pushRemote -branchWatchStorePath:$watchPath -silent:$y -pause:$pause | % {
        if($_ -match "(--abort|CONFLICT|It looks like git-am is in progress)")
        {
            $rebaseSuccess = $false
        }
        
        $_
    }
    
    if($gitpDuration)
    {
        $gitpDuration.Value = ($(get-date) - $gitpStart).Ticks
    }
    
    if(-not $rebaseSuccess)
    {
        throw $rebaseFailed
    }
}

function Compare-AweSamNetGit
{
    Param
    (
        [string] $baseBranch,
        [string] $currentBanch = $null,
        [switch] $upstream
    )
   	
	goawesamnet
    
    if(-not $currentBanch)
    {
        $currentBanch = Get-CurrentBranch
    }

    if(-not $baseBranch)
    {
        $matchingWatch = Get-AweSamNetWatchForBranch $currentBanch
        if($matchingWatch)
        {
            "Rebasing from branch $($matchingWatch.baseRemote)/$($matchingWatch.baseBranch)"
            $baseBranch = $matchingWatch.baseBranch
            $baseRemote = $matchingWatch.baseRemote
        }
    }
    
    if(-not $baseBranch)
    {
        $baseBranch = "next"
    }
    
    $compareUrl = $null
	if($upstream)
    {
        $compareUrl = "https://github.com/AweSamNet/AweSamNet/compare/$baseBranch...$currentBanch"
    }
    else
    {
        $compareUrl = "https://github.com/AweSamNet/AweSamNet/compare/$baseBranch...slombardo:$currentBanch"
    }
    Start-Process 'chrome.exe' $compareUrl

    return $compareUrl
}
Set-Alias awesamnetcompare Compare-AweSamNetGit -Scope Global

function New-AweSamNetBranch(
    [Parameter(Mandatory=$true)]$branchName, 
    $branchFromRemote="upstream", 
    $branchFrom="next", 
    [switch]$noPrompt)
{
	goawesamnet
    
    $originalBranch = Get-CurrentBranch
	New-Branch -branchName:$branchName -branchFromRemote:$branchFromRemote -branchFrom:$branchFrom -noPrompt:$noPrompt
	gitp-awesamnet
	$originalBranch = Get-CurrentBranch

    gitp-awesamnet
    
    Run-StashedOperation({
        git checkout $branchName
    })
}

function Watch-AweSamNetBranch(
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath = $awesamnetBranchWatchFilePath, 
    [string]$repoPath = $awesamnetRepoPath, 
    [string]$baseRemote = "upstream", 
    [string]$baseBranch = "next",    
    [string]$pushRemote = $baseRemote,
    [string]$pushBranch = $branch
)
{
    if(!$branch) {
        throw "No branch provided to watch."
    }
    
    Watch-Branch -branch:$branch `
                 -storePath:$storePath `
                 -repoPath:$repoPath `
                 -baseRemote:$baseRemote `
                 -baseBranch:$baseBranch `
                 -pushRemote:$pushRemote `
                 -pushBranch:$pushBranch
}

function Unwatch-AweSamNetBranch(
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath = $awesamnetBranchWatchFilePath)
{
    Unwatch-Branch -branch:$branch -storePath:$storePath
}

function Get-AweSamNetWatchedBranches()
{
    Get-WatchedBranches $awesamnetBranchWatchFilePath
}

function Watch-AweSamNetBuildKeywords(
    [Parameter(Mandatory=$true)][string]$keyword)
{    
    $path = $awesamnetBuildKeywordWatchFilePath
    
    $list = {Get-WatchedAweSamNetBuildKeywords}.Invoke()
    $list.Add($keyword)

    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $path -Value $body
    Get-WatchedAweSamNetBuildKeywords
}

function Get-WatchedAweSamNetBuildKeywords()
{
    $path = $awesamnetBuildKeywordWatchFilePath

    if (-not (Test-Path $path))
    {
        $output = New-Item -ItemType File -Force -Path $path 
    }
    
    $content = Get-Content $path -Raw
    
    if(!$content){
        return
    }
    
    $keywordsToWatch = ConvertFrom-Json ($content)
    
    {$keywordsToWatch}.Invoke()
}

function Unwatch-AweSamNetBuildKeywords(
    [Parameter(Mandatory=$true)][string]$keyword)
{
    $path = $awesamnetBuildKeywordWatchFilePath

    $keywordsToWatch = @()
    
    if ((Test-Path ($path)))
    {
        $keywordsToWatch = ConvertFrom-Json (Get-Content $path -Raw)
    }
    
    $list = {$keywordsToWatch}.Invoke()
    $toRemove  = $list | where { 
        $_ `
        -and $_ -eq $keyword
    } | select -First 1
    
    if($toRemove)
    {
        $list.Remove($toRemove)
    }
    
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $path -Value $body
    Get-WatchedAweSamNetBuildKeywords
}

function Open-AweSamNetTrello()
{
    Open-Chrome "https://trello.com/b/itnJ3xsh/development"
}
