param(
    [string]$drive,
    [Parameter(Mandatory=$true)]$dotNetProjects
)

new-alias msb2019 "$drive\Program Files (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe" -Scope Global

new-alias msb msb2019 -Scope Global

#mstest location
$mst = "$drive\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\MSTest.exe"
new-alias mst $mst -Scope Global

#vstest location
$vstest = "$drive\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"
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
    RepositoryUrl = "https://github.com/AweSamNet/AweSamNet/";
    GitUserName = "slombardo";
    TestPaths = @(
        ...,
        ...,
        ...
    );
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
    [switch]$tests,
    [string]$projectNames = $null,
    [string[]]$testsToRun = $null,
    [switch]$pause,
    [array]$testCategories,
    [array]$ignoreTestCategories,
    [switch]$y
    )
{   
    $project = getProject $project

    go $project
    
    $startTime = $(get-date)    
    $buildTime = $null
    $fetchTime = $null
    $testRunTime = $null
    
    $output = @()
    try
    {
        # set $all to true if no other switches are passed
        if(-not $all)
        {
            if( -not $rebase `
                -and(-not $build) `
                -and(-not $tests) `
                -and(-not $testsToRun) `
                -and(-not $testCategories) `
                -and(-not $ignoreTestCategories) `
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
            $buildTime = ($(Get-Date) - $buildStart).Ticks
        }
        
        if(-not $?)
        {
            Write-Error 'Solution build failed.'
            return;
        }
        
        if($all -or $tests -or $testsToRun -or $testCategories -or $ignoreTestCategories)
        {
            $testsStart = $(Get-Date)
            
            # if(-not $ignoreTestCategories)
            # {
                # $ignoreTestCategories = @("IntegrationTest", "NotContinuous")
            # }
            
            Run-ProjectTests -project:$project -testsToRun:$testsToRun -categories:$testCategories -ignoredCategories:$ignoreTestCategories

            $testRunTime = ($(Get-Date) - $testsStart).Ticks
        }
    }
    finally
    {
        $elapsedTime = $(Get-Date) - $startTime
        $finishedAt = Get-Date
        
        Write-Host "Displaying failures and keywords:........... press enter to continue"
        Write-Host
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        # get watched keywords
        
        $keywords = Get-WatchedProjectBuildKeywords $project -keywordsOnly
                
        Find-SurroundingText -text $output -regexPattern "(^|\W)($($keywords | % {"|$_"}) -join '')" -pause | Write-Highlight -textsToHighlight ($keywords)
        
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

    gitp -baseRemote:$baseRemote -baseBranch:$baseBranch -a -pushRemote:$project.PushRemote -branchWatchStorePath:$watchPath -silent:$y -subModuleUpdate -pause:$pause | % {
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
    
    # push it to set the default upstream
    git push -u $project.PushRemote $branchName -f
    
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

function Run-ProjectTests(
    [Parameter(Mandatory=$true)]$project,
    [switch]$highlightFailed=$true,
    [string[]] $testsToRun, 
    [array]$categories, 
    [array]$ignoredCategories)
{
    $project = getProject $project
    
    $testsExist = $false
    
    if($project.Keys -contains "TestPaths")
    {
        if(-not(IsNullOrEmpty $project.TestPaths))
        {
            $testsExist = $true
        }
    }

    if(!$testsExist)
    {
        Write-Host "There are no specified tests to run."
        return
    }

    Write-Host "Running Tests"

    $command = '$failedTests = @();'
    $command += '$results = "";'
    $command += "vstest "
    
    $project.TestPaths | %{ $command += "'$_' "}
    
    
    if($testsToRun)
    {
        $command += " /tests:"
        $command += $testsToRun -join ','
    }

    Write-Host
    $testCaseFilter = $null
    if($categories -or $ignoredCategories)
    {    
        $command += " --testadapterpath:. "
    }
        
    $categoriesFilter = $null
    if($categories)
    {
        Write-Host "Running Test Categories: " -NoNewline
        Write-Highlight $($categories -join " | ") -highlightColor Green
        
        $categoriesFilter = "($(($categories | %{ return "Category=$_" }) -join "|"))"
        $testCaseFilter += $categoriesFilter
    }
    
    $ignoredCategoriesFilter = $null
    if($ignoredCategories)
    {
        Write-Host "Ignoring Tests: " -NoNewline
        Write-Highlight $($ignoredCategories -join " | ")

        $ignoredCategoriesFilter += "($(($ignoredCategories | %{ return "Category!=$_" }) -join "&"))"
        
        if($categoriesFilter)
        {
            $testCaseFilter += "&"
        }
        
        $testCaseFilter += $ignoredCategoriesFilter
    }
    if($testCaseFilter -and -not $testsToRun)
    {
        $testCaseFilter = " --TestCaseFilter:`"$testCaseFilter`""

        Write-Host $testCaseFilter
        $command += $testCaseFilter
    }
    
    Write-Host
    # $command += " /Parallel "
    # $command += " 2>&1 "
    
    if($highlightFailed)
    {
        $command += @'
| % { 
    if( $_ -match "^\s*failed\s+")
    {
        $failedTests += $_
    }
    
    if($_ -match "^Total tests:")
    {
        $results = $_
    }
    return $_
}
'@
        $command += " | Write-Highlight -textsToHighlight 'failed';"
        $command += "    Save-ProjectTestResults $($project.Name)"
        $command += ' $failedTests (Get-CurrentBranch) $results ` '
    }

    $lastBaseBranchTestResults = Get-ProjectLastTestResults -project:$project -branch:$project.BaseBranch 
    
    Invoke-Expression $command -ErrorAction SilentlyContinue -ErrorVariable Err `
        | Write-Highlight -textsToHighlight "failed","Error"
    
    Write-ProjectTestResults $project $lastBaseBranchTestResults -testsToRun:$testsToRun    
}

function Save-ProjectTestResults([Parameter(Mandatory=$true)]$project, [string[]]$failedTests, $branch, $message)
{
    $project = getProject $project
    $resultsPath = getTestResultsPath $project
    
    $now = $(Get-Date)
    $testResults = @{
        "date" = $now
        "failedTests" = $failedTests
        "branch" = $branch
        "message" = $message
    }
    
    $today = [System.DateTime]::Today
    
    $todayPath = Join-Path $resultsPath $project.Name | `
        Join-Path -ChildPath $today.ToString("yyyy-MM") | `
            Join-Path -ChildPath $today.ToString("yyyy-MM-dd")
    
    $allTestResults = @()
    
    if ((Test-Path ($todayPath)))
    {      
        $allTestResults = ConvertFrom-Json (Get-Content $todayPath -Raw)
    }
    
    $list = {$allTestResults}.Invoke()
    $list.Add($testResults)
    
    $body = ConvertTo-Json $list
    
    New-Item -ItemType File -Force -Path $todayPath -Value $body
}

function Get-ProjectLastTestResults([Parameter(Mandatory=$true)]$project, $start = $null, $end = $null, $branch)
{
    $project = getProject $project
    $resultsPath = Join-Path $(getTestResultsPath $project) $project.Name 
    

    $allFiles = Get-DataFiles $resultsPath $start $end    

    # return all entries as objects
    $allFiles | Sort-Object FullName -Descending | % {
        $body = Get-Content $_.FullName -Raw 
        
        if($body)
        {
            $testResults = ConvertFrom-Json $body
            if($testResults)
            {
                $testResults | Sort-Object date -Descending | where {
                    $branch -eq $null -or($_.branch -eq $branch)
                } | Select-Object -first 1
            }
        }
    } | Select-Object -first 1
}

function  Write-ProjectTestResults ([Parameter(Mandatory=$true)]$project, $originalTestResults = @{}, [string[]] $testsToRun, [string]$branch)
{            
    $project = getProject $project
    $resultsPath = getTestResultsPath $project
    $lastTestResults = Get-ProjectLastTestResults $project
    
    "-------------------------------------------------------------"
    "Failed Tests (newly failing tests highlighted): "
    "-------------------------------------------------------------"
    
    $newlyFailedTests = @()
    $failedTestPattern = "^\s*Failed\s+\S*\s?"
    
    foreach ($currentlyFailedTest in $lastTestResults.failedTests)
    {
        if($originalTestResults -eq $null -or( `
            [bool]($originalTestResults.PSobject.Properties.name -match "failedTests")))
        {
            $match = [Regex]::Match($currentlyFailedTest, $failedTestPattern)

            $failedTestExists = $false
            foreach ($originallyFailedItem in $originalTestResults.failedTests)
            {
                if($originallyFailedItem -match $match.Value)
                {
                    $failedTestExists = $true
                    break;
                }
            }
            
            if(!$failedTestExists)
            {
                Write-Highlight $currentlyFailedTest
                $newlyFailedTests += $currentlyFailedTest
                continue
            }            
        }
        
        Write-Host $currentlyFailedTest
    }
    
    $currentBranch = IIf $branch $branch "current $($lastTestResults.branch):"

    if(!$testsToRun)
    {
        if($originalTestResults -and [bool]($originalTestResults.PSobject.Properties.name -match "failedTests"))
        {
            $newlyPassedTests = @()
            
            foreach ($originallyFailedTest in $originalTestResults.failedTests)
            {
                $match = [Regex]::Match($originallyFailedTest, $failedTestPattern)
                
                # if the originally failing test matches our pattern
                if($match.Success)
                {
                    $isStillFailing = $false
                    
                    # loop through the currently failing tests
                    foreach ($currentlyFailedTest in $lastTestResults.failedTests)
                    {
                        # if currently failing test matches the previously failing test, then it still fails
                        if($currentlyFailedTest -match $match.Value)
                        {
                            $isStillFailing = $true
                            break
                        }
                    }

                    if(!$isStillFailing)
                    {
                        $newlyPassedTests += $match.Value
                    }
                    continue
                }
                
                if(-not($lastTestResults.failedTests -contains $originallyFailedTest))
                {
                    $newlyPassedTests += $match.Value
                }
            }
            
            if($newlyPassedTests)
            {
                "-------------------------------------------------------------"
                "Newly Passed Tests: "
                "-------------------------------------------------------------"
            }
            
            $newlyPassedTests | %{
                Write-Highlight $_ -highlightColor Green
            }
        }
                
        for($i = $currentBranch.length; $i -lt 27; $i++)
        {
            $currentBranch += " "
        }
        
        Write-Host
        if($originalTestResults -and [bool]($originalTestResults.PSobject.Properties.name -match "failedTests"))
        {
            Write-Host "Base branch $($project.BaseBranch) ($($originalTestResults.date)): $($originalTestResults.message )"
        }
    }
    Write-Host "$currentBranch $($lastTestResults.message )"
    
    if(!$lastTestResults.failedTests -or !$newlyFailedTests)
    {
        $message = IIf $lastTestResults.failedTests "(ish).  (Some tests failed, but they also failed on base branch $($project.BaseBranch))" ""
        Write-Host
        Write-Highlight "     ALL TESTS PASS$message!     " -highlightColor Green
    }
}

function Install-Vsix([String] $packageName)
{
    $errorActionPreference = "Stop"
     
    $baseProtocol = "https:"
    $baseHostName = "marketplace.visualstudio.com"
     
    $uri = "$($baseProtocol)//$($baseHostName)/items?itemName=$($packageName)"
    $vsixLocation = "$($env:Temp)\$([guid]::NewGuid()).vsix"
     
    $vsInstallDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"
     
    if (!($vsInstallDir)) {
        Write-Error "Visual Studio InstallDir registry key missing"
        Exit 1
    }
     
    Write-Host "Grabbing VSIX extension at $($uri)"
    $html = Invoke-WebRequest -Uri $uri -UseBasicParsing -SessionVariable session
     
    Write-Host "Attempting to download $($packageName)..."
    $anchor = $html.Links |
    Where-Object { (HasProperty $_ "class") -and $_.class -eq 'install-button-container' } |
    Select-Object -ExpandProperty href

    if (!($anchor)) {
      Write-Error "Could not find download anchor tag on the Visual Studio Extensions page"
      Exit 1
    }
    Write-Host "Anchor is $($anchor)"
    $href = "$($baseProtocol)//$($baseHostName)$($anchor)"
    Write-Host "Href is $($href)"
    Invoke-WebRequest $href -OutFile $vsixLocation -WebSession $session
     
    if (!(Test-Path $vsixLocation)) {
      Write-Error "Downloaded VSIX file could not be located"
      Exit 1
    }
    Write-Host "VSInstallDir is $($vsInstallDir)"
    Write-Host "VSIXLocation is $($vsixLocation)"
    Write-Host "Installing $($packageName)..."
    Start-Process -Filepath "$($vsInstallDir)\VSIXInstaller" -ArgumentList "/q /a $($vsixLocation)" -Wait
     
    Write-Host "Cleanup..."
    rm $vsixLocation
    
    Write-Host "Installation of $($packageName) complete!"
}
