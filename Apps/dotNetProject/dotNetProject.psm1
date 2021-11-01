param(
    [string]$drive,
    [Parameter(Mandatory=$true)]$dotNetProjects
)

new-alias msb2019 "$drive\Program Files (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe" -Scope Global

new-alias msb msb2019 -Scope Global

#mstest location
$mst = "$drive\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\MSTest.exe"
new-alias mst $mst -Scope Global

#vstest location
$vstest = "$drive\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"
new-alias vstest $vstest -Scope Global


if(-not(Test-Path Variable:\dotNetProjects) -or !$dotNetProjects)
{
    Write-Output ""
    Write-Highlight 'Variable $dotNetProjects not found or poorly formed'
    Write-Output ""
    
    Write-Output `
'The parameter $dotNetProjects contains information for .Net projects to be managed.  
You should pass this parameter when loading this module from your $localModules set in $profile (Edit-Profile).
If you do not have any project specific modules to load many functions in this module will fail.

You can use the following as a template:
'

    Write-Highlight -highlightColor "DarkGray" -text '
------------------------------------------------------------------------------------------------
    
$dotNetProjects = @{  
    Name = "MyProject";
    MainDirectory ="...";
    RepositoryPath ="...";
    BaseRemote = "upstream";    # remote for the git repository fetch
    BaseBranch = "next";        # the default branch to base new feature branches on
    PushRemote = "origin";      # default remote to push to
    SolutionPath = "...";
    RepositoryUrl = "https://github.com/AweSamNet/AweSamNet/"
    GitUserName = "slombardo"
}
    
------------------------------------------------------------------------------------------------'
    $openProfile = Read-Host "Would you like to view your system profile?[y/n]"

    if($openProfile -eq "y")
    {
        Edit-Profile
    }
}
    
if (-not(Get-Command "nuget.exe" -ErrorAction SilentlyContinue))
{
    if(!(Test-IsAdmin))
    {
        sudo choco install Nuget.CommandLine -y
    }
    else 
    {
        choco install Nuget.CommandLine -y
    }
}
    
if (-not(Get-Command "npm" -ErrorAction SilentlyContinue))
{
    if(!(Test-IsAdmin))
    {
        sudo choco install nodejs-lts -y
    }
    else 
    {
        choco install nodejs-lts -y
    }

}

$scriptPath = (Get-Item $MyInvocation.MyCommand.Definition).FullName

function Edit-dotNetProject
{
    notepad++ $scriptPath
}

function getBuildTimesPath ([Parameter(Mandatory=$true)]$project)
{
    $project = getProject $project
    return Join-Path $project.MainDirectory "build times\"
}

function getBranchWatchFilePath ([Parameter(Mandatory=$true)]$project)
{
    $project = getProject $project
    return Join-Path $project.MainDirectory "Branch Watch\$($project.Name) Branches.txt"
}

function getBuildKeywordWatchFilePath ([Parameter(Mandatory=$true)]$project)
{
    $project = getProject $project
    return Join-Path $project.MainDirectory "Keyword Watch\$($project.Name) Build Keywords.txt"
}

function getTestResultsPath ([Parameter(Mandatory=$true)]$project)
{
    $project = getProject $project
    return Join-Path $project.MainDirectory "test results\"
}

function getProject($project = $null)
{
    if ($project -eq $null)
    {
        return $dotNetProjects
    }
    
    if(-not($project -is [string]))
    {
        return $project
    }
    
    return $dotNetProjects | where { $_.Name -eq $project } | select -First 1
}

# Go to your main project folder
function gomain ($project)
{
    $project = getProject $project
    
    "Moving to $($project.Name) Main directory"
    cd $project.MainDirectory
}

# Go to project repository
function go ($project)
{
    $project = getProject $project

    "Moving to $($project.Name) repository"
    cd $project.RepositoryPath
}

function Get-DotNetProjectCommands ([int]$columns = 3)
{
    $names = Get-Command -Module dotNetProject | % { $_.Name }
    
    Write-Table $names $columns
}

# Rebuild the solution
function Build(
    [Parameter(Mandatory=$true)]$project,
    [switch]$all, 
    [switch]$build, 
    [switch]$rebase, 
    [string]$projectNames = $null,
    [switch]$pause,
    [switch]$y
    )
{   
    $project = getProject $project

    go $project
    
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
                -and(-not $projectNames))
            {
                $all = $true
            }
        }
        
        if($all -or $rebase)
        {           
            Update-ProjectGit -project:$project -gitpDuration:([ref]$fetchTime) -y:$y -pause:$pause | % {
                $output += $_
                $_
            }
        }
            
        if(-not $?)
        {
            Write-Error 'Rebase failed.'
            return;
        }
        
        if($all -or $build -or $projectNames)
        {
            $buildStart = $(Get-Date)
            $buildOutput = @()
            
            Start-Build $project $projectNames | % {
                $buildOutput += $_
                $_ | Write-Highlight -pause:$pause -textsToHighlight "-- failed" 
            }
            
            Find-SurroundingText -text $buildOutput -regexPattern "(^|\W)($($keywords | % {"|$_"}) -join '')" | % {
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
        
        Write-Host "Displaying failures and keywords:........... press enter to continue"
        Write-Host
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        # get watched keywords
        
        $keywords = Get-WatchedProjectBuildKeywords $project -keywordsOnly
                
        Find-SurroundingText -text $output -regexPattern "(^|\W)($($keywords | % {"|$_"}) -join '')" -pause | Write-Highlight -textsToHighlight (@$keywords)
        
        Write-Host "Total Elapsed Time: $elapsedTime"
        Write-Host "Finished at: $finishedAt"
        
        Save-BuildTimes $project $fetchTime $buildTime
    }
}

$fetchDurationName = "fetchDuration"
$buildDurationName = "buildDuration"

function Save-BuildTimes([Parameter(Mandatory=$true)]$project, $fetchDuration, $buildDuration)
{
    $project = getProject $project

    $now = $(Get-Date)
    $totalExecution = @{
        "date" = $now
        $fetchDurationName = $fetchDuration
        $buildDurationName = $buildDuration
    }
    
    $today = [System.DateTime]::Today
    
    $fileName =  "$($project.Name) $($today.ToString('yyyy-MM-dd'))"
 
    $todayPath = Join-Path $(getBuildTimesPath $project) $today.ToString("yyyy-MM") | `
        Join-Path -ChildPath $fileName
    
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

function Get-BuildTimes([Parameter(Mandatory=$true)]$project, $start = $null, $end = $null, [switch]$totals, [switch]$average)
{
    $project = getProject $project

    $fetchCount = 0
    $buildCount = 0

    $buildTimesPath = getBuildTimesPath $project

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

function Start-Build(
    [Parameter(Mandatory=$true)]$project,
    [string]$projectNames = $null)
{
    $project = getProject $project

    go $project
    
    $solutionPath = $project.SolutionPath
    
    if(!($projectNames))
    {
        $projectNames = "Build"
    }    

    nuget restore $solutionPath
    
    & msb $solutionPath /t:$projectNames /m 
}

function Get-ProjectWatchForBranch([Parameter(Mandatory=$true)]$project, [string]$branch)
{
    $project = getProject $project    
    return Get-ProjectWatchedBranches | where { $_.branch -eq $branch } | select -First 1    
}

$rebaseFailed = "Rebase was not able to continue."

function Update-ProjectGit(
    [Parameter(Mandatory=$true)]$project,
    [ref]$gitpDuration, 
    [switch]$doWatch=$true, 
    [switch]$y,
    [switch]$pause)
{        
    $project = getProject $project

    $originalBranch = Get-CurrentBranch

    $rebaseSuccess = $true
    
    $watchPath = $null
    
    if($doWatch)
    {
        $watchPath = getBranchWatchFilePath $project                   
    }
    
    # see if there is a watch for this branch and if the base branch is not the default base branch
    $baseBranch = $project.BaseBranch
    $baseRemote = $project.BaseRemote

    $matchingWatch = Get-ProjectWatchForBranch $project $originalBranch
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

    gitp -baseRemote:$baseRemote -baseBranch:$baseBranch -a -pushRemote:$project.PushRemote -branchWatchStorePath:$watchPath -silent:$y -pause:$pause | % {
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

function Compare-Git
{
    Param
    (
        [Parameter(Mandatory=$true)]$project,
        [string] $baseBranch,
        [string] $currentBanch = $null,
        [switch] $upstream              # compare branches on the upstream exclusively (not from personal account branch)
    )
    $project = getProject $project

    go $project
    
    if(-not $currentBanch)
    {
        $currentBanch = Get-CurrentBranch
    }

    if(-not $baseBranch)
    {
        $matchingWatch = Get-ProjectWatchForBranch $project $currentBanch
        if($matchingWatch)
        {
            "Comparing from branch $($matchingWatch.baseRemote)/$($matchingWatch.baseBranch)"
            $baseBranch = $matchingWatch.baseBranch
            $baseRemote = $matchingWatch.baseRemote
        }
    }
    
    if(-not $baseBranch)
    {
        $baseBranch = $project.BaseBranch
    }
    
    $compareUrl = $null
    if($upstream)
    {
        $compareUrl = "$($project.RepositoryUrl)/compare/$baseBranch...$currentBanch"
    }
    else
    {
        $userName = ""
        if($project.GitUserName)
        {
            $userName = "$($project.GitUserName):"
        }
        $compareUrl = "$($project.RepositoryUrl)/compare/$baseBranch...$userName$currentBanch"
    }
    Start-Process 'chrome.exe' $compareUrl

    return $compareUrl
}
Set-Alias git-compare Compare-Git -Scope Global

function New-ProjectBranch(
    [Parameter(Mandatory=$true)]$project,
    [Parameter(Mandatory=$true)]$branchName, 
    $branchFromRemote, 
    $branchFrom, 
    [switch]$noPrompt)
{
    $project = getProject $project

    if(!$branchFromRemote)
    {
        $branchFromRemote = $project.BaseRemote
    }

    if(!$branchFrom)
    {
        $branchFrom = $project.BaseBranch
    }

    go $project
    
    $originalBranch = Get-CurrentBranch
    New-Branch -branchName:$branchName -branchFromRemote:$branchFromRemote -branchFrom:$branchFrom -noPrompt:$noPrompt
    Update-ProjectGit $project
    $originalBranch = Get-CurrentBranch

    Update-ProjectGit $project
    
    Run-StashedOperation({
        git checkout $branchName
    })
}

function Watch-ProjectBranch(
    [Parameter(Mandatory=$true)]$project,
    [string]$branch = $(Get-CurrentBranch),
    [string]$baseRemote,
    [string]$baseBranch,
    [string]$pushRemote
)
{
    $project = getProject $project
    
    if(!$branch) {
        throw "No branch provided to watch."
    }
    
    if(!$baseRemote) {
        $baseRemote = $project.BaseRemote
    }
    
    if(!$baseBranch) {
        $baseBranch = $project.BaseBranch
    }
    
    if(!$pushRemote) {
        $pushRemote = $project.PushRemote
    }
    
    Watch-Branch -branch:$branch `
                 -storePath getBranchWatchFilePath $project `
                 -repoPath $project.RepositoryPath `
                 -baseRemote:$baseRemote `
                 -baseBranch:$baseBranch `
                 -pushRemote:$pushRemote `
                 -pushBranch:$branch
}

function Unwatch-ProjectBranch(
    [Parameter(Mandatory=$true)]$project,
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath)
{
    $project = getProject $project    
    Unwatch-Branch -branch:$branch -storePath getBranchWatchFilePath $project
}

function Get-ProjectWatchedBranches($project)
{
    $project = getProject $project
    Get-WatchedBranches getBranchWatchFilePath $project
}

function Watch-ProjectBuildKeywords(
    [Parameter(Mandatory=$true)]$project,
    [Parameter(Mandatory=$true)][string]$keyword,
    [switch]$isRegex)
{
    $project = getProject $project
    $path = getBuildKeywordWatchFilePath $project
    
    $itemToWatch = @{
        Keyword = $keyword;
        IsRegEx = $isRegex.IsPresent;
    }

    Add-Record -record:$itemToWatch -storePath:$path

    Get-WatchedProjectBuildKeywords $project
}

function Get-WatchedProjectBuildKeywords([Parameter(Mandatory=$true)]$project, [switch]$keywordsOnly)
{
    $project = getProject $project
    $path = getBuildKeywordWatchFilePath $project

    $keywordsToWatch = Get-JsonFromFile $path
    
    if($keywordsOnly)
    {
        return $keywordsToWatch | % { IIF $.Value.IsRegEx {$_.Value.Keyword} {[Regex]::Escape($_.Value.Keyword)} }
    }
    
    return {$keywordsToWatch}.Invoke()
}

function Unwatch-ProjectBuildKeywords(
    [Parameter(Mandatory=$true)]$project,
    [int]$id=0
)
{
    $project = getProject $project
    $path = getBuildKeywordWatchFilePath $project
    
    Unwatch-Something -id:$id -storePath:$path

    Get-WatchedProjectBuildKeywords $project
}