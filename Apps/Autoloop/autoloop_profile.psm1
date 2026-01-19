param(
    [String]$drive = "C:"
)
$loopScriptPath = (Get-Item $MyInvocation.MyCommand.Definition).FullName

function Edit-LoopProfile
{
    # notepad++ $(Join-Path $loopScriptPath 'Scripts\renterfull_profile.ps1')
    notepad++ $loopScriptPath
}
$loopPath = "$drive\Git Workspace\Loop\"
$global:loopRepoPath = Join-Path $loopPath 'Loop'
$global:csaRepoPath = Join-Path $loopPath 'Csa'
$global:csaDeploymentPath = Join-Path $csaRepoPath  'Csa\Deployment\bin\'

$global:loopSystemPath = "$drive\Loop"
$global:loopPatchFolder = Join-Path $loopPath "Loop Patches\"
$global:csaPatchFolder = Join-Path $loopPath "Csa Patches\"

$global:loopBuildTimesPath = Join-Path $loopPath "Loop build times\"
$global:csaBuildTimesPath = Join-Path $loopPath "Csa build times\"
$global:loopTestResultsPath = Join-Path $loopPath "Loop test results\"
$global:csaTestResultsPath = Join-Path $loopPath "Csa test results\"

$global:loopBranchWatchFilePath = Join-Path $loopPath "Branch Watch\Loop Branches.txt"
$global:csaBranchWatchFilePath = Join-Path $loopPath "Branch Watch\Csa Branches.txt"

$global:loopBuildKeywordWatchFilePath = Join-Path $loopPath "Keyword Watch\Loop Build Keywords.txt"
$global:csaBuildKeywordWatchFilePath = Join-Path $loopPath "Keyword Watch\Csa Build Keywords.txt"

# Go to your Loop source folder
function goloop
{
    "Moving to loop repository"
    cd $loopRepoPath
}

function gocsa
{
    "Moving to CSA repository"
    cd $csaRepoPath
}

# A quick alias to LoopData.exe
new-alias lda $(Join-Path $loopRepoPath 'Scripts\lda.ps1')
new-alias csadeploy $(Join-Path $csaRepoPath '\Csa\Deployment\bin\Deploy.exe')

function Get-LoopCommands ([int]$columns = 3)
{
    $names = Get-Command -Module Autoloop_profile | % { $_.Name }
    
    Write-Table $names $columns
}

function Run-LoopTests(
    [switch]$highlightFailed=$true, 
    [string[]] $tests, 
    [switch]$csa, 
    [array]$categories, 
    [array]$ignoredCategories)
{
    Write-Host "Running Tests"

    $command = '$failedTests = @();'
    $command += '$results = "";'

    if($csa)
    {
        gocsa
        
        $csaTestsPath = $(Join-Path $csaRepoPath '\Csa\UnitTests\bin\Debug\Csa.Tests.dll')
         #Save-TestResults([string[]]$failedTests, $branch, $message )
        $command += "vstest ""$csaTestsPath"""

    }
    else 
    {
        goloop    
    
        $loopDependentTestsPath = $(Join-Path $loopRepoPath '\Class Libraries\LoopDependentTests\bin\Debug\net472\LoopDependentTests.dll')
        $loopLibTestsPath = $(Join-Path $loopRepoPath '\Unit Tests\LoopLib.Tests\bin\Debug\net472\LoopLib.Tests.dll')
        $loopUniversalApiTestsPath = $(Join-Path $loopRepoPath '\Unit Tests\LoopUniversalAPI.Tests\bin\Debug\net472\LoopUniversalApi.Tests.dll')
        $autoloopApiTestsPath = $(Join-Path $loopRepoPath '\Unit Tests\AutoloopAPI.Tests\bin\Debug\net472\AutoloopAPI.Tests.dll')
         #Save-TestResults([string[]]$failedTests, $branch, $message )
        $command += "vstest ""$loopDependentTestsPath"" ""$loopLibTestsPath"" ""$loopUniversalApiTestsPath"" ""$autoloopApiTestsPath"""
    }
    
    if($tests)
    {
        $command += " /tests:"        
        
        $tests | % {
            $command += $tests -join ','
        }
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
    if($testCaseFilter -and -not $tests)
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
    if( $_ -match "^failed")
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
        $command += @'
    Save-TestResults $failedTests (Get-CurrentBranch) $results `
'@
        $command += " -csa:"
        $command += IIf $csa '$true' '$false'
    }

    $lastBetaTestResults = Get-LastTestResults -branch:"beta" -csa:$csa
    
    Invoke-Expression $command -ErrorAction SilentlyContinue -ErrorVariable Err `
        | Write-Highlight -textsToHighlight "failed","Error"
    
    Write-LoopTestResults $lastBetaTestResults -csa:$csa -tests:$tests    
}

function  Write-LoopTestResults ($originalTestResults = @{}, [switch]$csa, [string[]] $tests, [string]$branch)
{            
    $lastTestResults = Get-LastTestResults -csa:$csa
    
    "-------------------------------------------------------------"
    "Failed Tests (newly failing tests highlighted): "
    "-------------------------------------------------------------"
    
    $newlyFailedTests = @()
    
    $lastTestResults.failedTests | %{
        if($originalTestResults -eq $null -or( `
            [bool]($originalTestResults.PSobject.Properties.name -match "failedTests") `
            -and -not($originalTestResults.failedTests -contains $_)))
        {
            Write-Highlight $_
            $newlyFailedTests += $_
        }
        else{
            Write-Host $_
        }
    }
    
    $currentBranch = IIf $branch $branch "current $($lastTestResults.branch):"

    if(!$tests)
    {
        if($originalTestResults -and [bool]($originalTestResults.PSobject.Properties.name -match "failedTests"))
        {
            $newlyPassedTests = $originalTestResults.failedTests | where { -not($lastTestResults.failedTests -contains $_) } 
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
            Write-Host "beta ($($originalTestResults.date)): $($originalTestResults.message )"
        }
    }
    `Write-Host "$currentBranch $($lastTestResults.message )"
    
    if(!$lastTestResults.failedTests -or !$newlyFailedTests)
    {
        Write-Host
        Write-Highlight "     ALL TESTS PASS$(IIf $lastTestResults.failedTests '(ish).  (Some tests failed, but they also failed on beta)' '')!     " -highlightColor Green
    }
}


# Rebuild the Loop solution
function csabd(
    [switch]$highlightFailedTests = $true, 
    [switch]$all, 
    [switch]$db, 
    [switch]$full, 
    [switch]$build, 
    [switch]$rebase, 
    [switch]$tests,
    [switch]$buildAdHocSln,
    [string]$projects = $null,
    [string[]]$testsToRun = $null,
    [switch]$pause)
{
    loopbd -highlightFailedTests:$highlightFailedTests `
        -all:$all `
        -db:$db `
        -full:$full `
        -build:$build `
        -rebase:$rebase `
        -tests:$tests `
        -buildAdHocSln:$buildAdHocSln `
        -projects:$projects `
        -testsToRun:$testsToRun `
        -pause:$pause `
        -csa
}

# Rebuild the Loop solution
function loopbd(
    [switch]$highlightFailedTests = $true, 
    [switch]$all, 
    [switch]$db, 
    [switch]$full, 
    [switch]$build, 
    [switch]$rebase, 
    [switch]$tests,
    [switch]$buildAdHocSln,
    [string]$projects = $null,
    [string[]]$testsToRun = $null,
    [switch]$pause,
    [switch]$csa = $false,
    [array]$testCategories,
    [array]$ignoreTestCategories,
    [switch]$y
    )
{   
    if($csa)
    {
        gocsa
    }
    else 
    {    
        goloop
    }
    
    $startTime = $(get-date)    
    $buildTime = $null
    $fetchTime = $null
    $dbTime = $null
    $testRunTime = $null
    $project = IIf $csa "csa" "loop"
    
    $output = @()
    try
    {
        # set $all to true if no other switches are passed
        if(-not $all)
        {
            if( -not $rebase `
                -and(-not $db) `
                -and(-not $build) `
                -and(-not $tests) `
                -and(-not $testsToRun) `
                -and(-not $testCategories) `
                -and(-not $ignoreTestCategories) `
                -and(-not $projects) `
                -and(-not $buildAdHocSln))
            {
                $all = $true
            }
        }
        
        if($all -or $rebase)
        {           
            gitp-loop ([ref]$fetchTime) -project:$project -y:$y -pause:$pause | % {
                $output += $_
                $_
            }
        }
        
        if(-not $?)
        {
            Write-Error "Could not complete rebase"
        }
        
        if($all -or $db)
        {   
            $dbStart = $(Get-Date)  
            Write-Host "Starting database update:"
            Update-LoopDatabase -full:$full -project:$project | % {
                $output += $_
                $_
            }
            $dbTime = ($(get-date) - $dbStart).Ticks
        }
            
        if(-not $?)
        {
            Write-Error 'Database update failed.'
            return;
        }
        
        if($all -or $build -or $projects -or $buildAdHocSln)
        {
            $buildStart = $(Get-Date)
            $buildOutput = @()
            
            Start-BuildLoop $projects -adHocSln:$buildAdHocSln -csa:$csa | % {
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
        
        if($all -or $tests -or $testsToRun -or $testCategories -or $ignoreTestCategories)
        {
            $testsStart = $(Get-Date)
            
            if(-not $ignoreTestCategories)
            {
                $ignoreTestCategories = @("IntegrationTest", "NotContinuous")
            }
            
            Run-LoopTests -tests:$testsToRun -csa:$csa -categories:$testCategories -ignoredCategories:$ignoreTestCategories
            
            $testRunTime = ($(Get-Date) - $testsStart).Ticks
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
        
        $keywords = Get-WatchedLoopBuildKeywords -project:$project
        
        Find-SurroundingText -text $output -regexPattern "(^|\W)(failed|Error$($($keywords | % {"|$_"}) -join ''))" -pause | Write-Highlight -textsToHighlight (("failed","Error") + $keywords)
        
        Write-Host "Total Elapsed Time: $elapsedTime"
        Write-Host "Finished at: $finishedAt"
        
        Save-BuildTimes $fetchTime $dbTime $buildTime $testRunTime -csa:$csa
    }
}

function Save-TestResults([string[]]$failedTests, $branch, $message, [switch]$csa = $false )
{
    $now = $(Get-Date)
    $testResults = @{
        "date" = $now
        "failedTests" = $failedTests
        "branch" = $branch
        "message" = $message
    }
    
    $today = [System.DateTime]::Today
    
    $resultsPath = IIf $csa $csaTestResultsPath $loopTestResultsPath
    
    $todayPath = Join-Path $resultsPath $today.ToString("yyyy-MM")
    $todayPath = Join-Path $todayPath $today.ToString("yyyy-MM-dd")
    
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

function Get-LastTestResults($start = $null, $end = $null, $branch, [switch]$csa)
{
    $resultsPath = IIf $csa $csaTestResultsPath $loopTestResultsPath

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

$fetchDurationName = "fetchDuration"
$dbDurationName = "dbDuration"
$buildDurationName = "buildDuration"
$testsDurationName = "testsDuration"
$loopAuthDurationName = "loopAuthDuration"

function Save-BuildTimes($fetchDuration, $dbDuration, $buildDuration, $testsDuration, $loopAuthDuration, [switch]$csa)
{
    $now = $(Get-Date)
    $totalExecution = @{
        "date" = $now
        $fetchDurationName = $fetchDuration
        $dbDurationName = $dbDuration
        $buildDurationName = $buildDuration
        $testsDurationName = $testsDuration
        $loopAuthDurationName = $loopAuthDuration
    }
    
    $today = [System.DateTime]::Today
    
    $buildTimesPath = IIf $csa $csaBuildTimesPath $loopBuildTimesPath
    
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
        $dbDuration = IIf $buildTime.dbDuration $buildTime.dbDuration 0
        $fetchDuration = IIf $buildTime.fetchDuration $buildTime.fetchDuration 0
        $testsDuration = IIf $buildTime.testsDuration $buildTime.testsDuration 0
        $loopAuthDuration = IIf $buildTime.loopAuthDuration $buildTime.loopAuthDuration 0

        $loggedTime = 
        @{
            date = $buildTime.date
            buildDuration = [timespan]$buildDuration
            dbDuration = [timespan]$dbDuration
            fetchDuration = [timespan]$fetchDuration
            testsDuration = [timespan]$testsDuration
            loopAuthDuration = [timespan]$loopAuthDuration
            Total = [timespan][long](0 + `
                $buildDuration + $dbDuration + $fetchDuration + $testsDuration + $loopAuthDuration)
        }    
        
        return $loggedTime
    }
    
    return $null
}

function Get-BuildTimes($start = $null, $end = $null, [switch]$totals, [switch]$average, [switch]$csa)
{
    $fetchCount = 0
    $dbCount = 0
    $buildCount = 0
    $testsCount = 0
    $loopAuthCount = 0    

    $buildTimesPath = IIf $csa $csaBuildTimesPath $loopBuildTimesPath

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
                        if(![bool]($_.PSobject.Properties.name -match $loopAuthDurationName))
                        {
                            $_ | Add-Member -MemberType NoteProperty -Name $loopAuthDurationName -Value 0
                        }
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
        dbDuration   = 0;
        buildDuration = 0;
        Total        = 0;
        testsDuration = 0;
        loopAuthDuration = 0;
    }

    $buildTimes | % {
        if($_.fetchDuration) { $totalTime.fetchDuration += $_.fetchDuration }
        if($_.dbDuration) { $totalTime.dbDuration += $_.dbDuration }
        if($_.buildDuration) { $totalTime.buildDuration += $_.buildDuration }
        if($_.Total) { $totalTime.Total += $_.Total }
        if($_.testsDuration) { $totalTime.testsDuration += $_.testsDuration }
        if($_.loopAuthDuration) { $totalTime.loopAuthDuration += $_.loopAuthDuration }
    }

    return $totalTime
}

function Get-AverageBuildTimes($buildTimes)
{
    $fetchCount = 0
    $dbCount = 0
    $buildCount = 0
    $testsCount = 0
    $loopAuthCount = 0    
    
    if($buildTimes -and $buildTimes.length)
    {
        $buildTimes | % {
            $buildCount += IIf $_.buildDuration 1 0
            $dbCount += IIf $_.dbDuration 1 0
            $fetchCount += IIf $_.fetchDuration 1 0
            $testsCount += IIf $_.testsDuration 1 0      
            $loopAuthCount += IIf $_.loopAuthDuration 1 0
        }
        
        $totalTime = Get-TotalBuildTime $buildTimes
    
        $fetchAverage = [TimeSpan]::FromHours((IIf $totalTime.fetchDuration {$totalTime.fetchDuration.TotalHours / $fetchCount} 0))
        $dbAverage = [TimeSpan]::FromHours((IIf $totalTime.dbDuration {$totalTime.dbDuration.TotalHours / $dbCount} 0))
        $buildAverage = [TimeSpan]::FromHours((IIf $totalTime.buildDuration {$totalTime.buildDuration.TotalHours / $buildCount} 0))
        $testsAverage = [TimeSpan]::FromHours((IIf $totalTime.testsDuration {$totalTime.testsDuration.TotalHours / $testsCount} 0))
        $loopAuthAverage = [TimeSpan]::FromHours((IIf $totalTime.loopAuthDuration {$totalTime.loopAuthDuration.TotalHours / $loopAuthCount} 0))
        $totalAverage = [TimeSpan]::FromHours((IIf $totalTime.Total {$totalTime.Total.TotalHours / $buildTimes.length} 0))
        
        @{
            Name = "Averages";
            fetchDuration = $fetchAverage;
            dbDuration = $dbAverage;
            buildDuration = $buildAverage;
            testsDuration = $testsAverage;
            loopAuthDuration = $loopAuthAverage;
            totals = $totalAverage;
        }
    }    
}

function Start-BuildLoop(
    [switch]$adHocSln, 
    [string]$projects = $null,
    [switch]$csa = $false)
{
    $solutionPath = ""
    
    if($csa)
    {
        gocsa
        
        $solutionPath = $(Join-Path $csaRepoPath 'Csa\Csa.sln')
    }
    else
    {
        goloop
        
        if(!$adHocSln)
        {
            $solutionPath = $(Join-Path $loopRepoPath 'Solutions\Loop.sln')
        }
        else 
        {
            $solutionPath = $(Join-Path $loopRepoPath 'Windows Applications\AdHocReports\AdHocReports.sln')
        }
    
        if(!($projects))
        {
            $projects = "Build"
        }
    }
    
    nuget restore $solutionPath
    
    if($csa)
    {        
        & msb csa\CSA.build /t:Compile /p:Configuration=debug
    }
    else
    {
        & msb $solutionPath /t:$projects /m 
        Deploy-Wiq
        goloop
    }
}

function Deploy-Wiq
{
    cd "$drive\wiq"
    Write-Host "Deploying wiq to $drive\wiq"
    xcopy $(Join-Path $loopRepoPath "\Windows Services\TaskExecutionService\bin\Debug\net472\*.*") "$drive\Wiq" /Y /EXCLUDE:WiqSkip.txt
}

function Start-LoopAuth([switch]$build)
{
    $start = $(Get-Date)
    try{
        $loopAuth = Get-Process LoopAuth -ErrorAction SilentlyContinue
        
        if($loopAuth)
        {
            Write-Host "LoopAuth is already running."
            return;
        }
        $env:ASPNETCORE_ENVIRONMENT='Development'
        if($build)
        {
            New-PsSession {
                cd $(Join-Path $loopRepoPath 'Web Applications\LoopAuth');
                dotnet run;
            } -title 'LoopAuth - Running' 
        }
        else
        {
            New-PsSession {
                cd $(Join-Path $loopRepoPath 'Web Applications\LoopAuth');
                dotnet run --no-build;
            } -title 'LoopAuth - Running' 
        }
        
        if(-not $loopAuth)
        {
            Write-Host "Waiting for AuthLoop to start" -NoNewline
        }
        
        while(-not $loopAuth)
        {
            Write-Host "." -NoNewline
            Start-Sleep -s 1        
            $loopAuth = Get-Process LoopAuth -ErrorAction SilentlyContinue
        }
        Start-Process 'chrome.exe' 'autoloop.local/DMS/App'
    }
    finally{
        $time = ($(get-date) - $start).Ticks
        Save-BuildTimes -loopAuthDuration:$time
    }
}

function Start-Wiq ([string]$groupName, [switch]$currentSession)
{
    Deploy-Wiq

    $script = "& { & '$drive\wiq\WiqServer.exe' $groupName}"
    $command = [ScriptBlock]::Create($script)
    
    if($currentSession)
    {
        Invoke-Command -ScriptBlock $command 4>&1
        return 
    }   

    New-PsSession $command -title "Wiq.exe - ${groupName}: Running"
    
    $logFileName = "$drive\Loop\Logs\Wiq Server $groupName*.txt"
    
    $latest = (Get-ChildItem -Path $logFileName | Sort-Object LastAccessTime -Descending | Select-Object -First 1)
    $found = $true
    while($latest -eq $null -or ((Get-Date) - $latest.LastAccessTime).seconds -gt 5)
    {
        if($found)
        {
            Write-Host "Waiting for $groupName to start processing" -NoNewline
            $found = $false
        }
        
        Write-Host "." -NoNewline
        
        # let wiq start the log file
        Start-Sleep -s 2
        $latest = (Get-ChildItem -Path $logFileName | Sort-Object LastAccessTime -Descending | Select-Object -First 1)
    }
    
    Write-Host "`nBeginning tail of $latest.FullName"
    Write-Host "-----------------------------------------------------------------------"
    
    tail $latest.FullName | Write-Highlight -textsToHighlight 'error','exception','fail'
}

function Update-CsaDatabase(
    [switch]$all, 
    [switch]$tables, 
    [switch]$sp, 
    [switch]$dal, 
    [switch]$full)
{
    $project = "csa"
    Update-LoopDatabase `
        -all:$all          `
        -tables:$tables    `
        -sp:$sp            `
        -dal:$dal          `
        -full:$full        `
        -project:$project  

}

function Update-LoopDatabase(
    [switch]$all, 
    [switch]$tables, 
    [switch]$sp, 
    [switch]$dal, 
    [switch]$full, 
    [string]$project = "loop")
{
    if($project -eq "csa")
    {
        cd $csaDeploymentPath
        & csadeploy --configuration=debug --workers=dp
        
        gocsa
    }
    else 
    {
        if(-not $all)
        {
            if(-not($tables) -and(-not $sp) -and(-not($dal)))
            {
                $all = $true
            }
        }
        
        if(-not($full))
        {
            goloop
            & lda --sync
        }
        else
        {
            if($all -or $tables)
            {
                Write-Host Updating databases
                & lda -fb -runall $loopRepoPath
            }
             
            if($all -or $sp)
            {

                $lastRunFileName = Join-path $loopSystemPath "spUpdateRun.last"
                $lastRunDate = $null
                if(Test-Path $lastRunFileName)
                {
                  $lastRunFile = Get-Item $lastRunFileName
                  $lastRunDate = $lastRunFile.LastWriteTime;
                }
                
                Write-Host Updating storedProcs
                
                if($full -or ($lastRunDate -eq $null -or ((Get-Date) - $lastRunDate).TotalDays -gt 1))
                {
                  & lda -p $loopRepoPath
                }
                else
                {
                  & lda -p $loopRepoPath --sync r
                }
                
                # set the last run date
                if($lastRunDate -eq $null)
                {
                  New-Item $lastRunFileName
                }
                else
                {
                  (Get-Item $lastRunFileName).LastWriteTime = (Get-Date)
                }
            }
        }
        if($all -or $dal)
        {
            Write-Host Generating DAL
            & lda -GenerateDAL $loopRepoPath
        }
    }
}

function gitp-loop (
    [ref]$gitpDuration, 
    [string]$project = "loop",
    [switch]$y,
    [switch]$pause)
{
    $originalBranch = Get-CurrentBranch
    if($originalBranch -match "^origin-1.*")
    {
        Update-Origin-1
    }
    else
    {
        $duration = $null
        Update-LoopGit ([ref]$duration) -project:$project -y:$y -pause:$pause
        if($gitpDuration)
        {
            $gitpDuration.Value = $duration
        }
    }
}

function Update-Origin-1{    
    $originalBranch = Get-CurrentBranch

    gitp -baseBranch:"origin-1-beta" -baseRemote:"origin-1"
}

function Get-LoopWatchForBranch([string]$branch, [string]$project = "loop")
{
    if($project -eq "csa")
    {
        return Get-CsaWatchedBranches | where { $_.branch -eq $branch } | select -First 1
    }
    else
    {
        return Get-LoopWatchedBranches | where { $_.branch -eq $branch } | select -First 1
    }
}

$rebaseFailed = "Rebase was not able to continue."
$applyPatchFailed = "Apply-Patch was not able to continue."

function Update-LoopGit(
    [ref]$gitpDuration, 
    [switch]$doWatch=$true, 
    [string]$project = "loop",
    [switch]$y,
    [switch]$pause)
{        
    $originalBranch = Get-CurrentBranch

    $rebaseSuccess = $true
    
    $watchPath = $null
    
    if($doWatch)
    {
        if($project -eq "csa")
        {
            $watchPath = $csaBranchWatchFilePath            
        }
        else 
        {
            $watchPath = $loopBranchWatchFilePath                    
        }
    }
    
    # see if there is a watch for this branch and if the base branch is not beta
    $pushRemote = $null
    $baseRemote = "upstream"
    $baseBranch = "beta"
    if($project -eq "csa")
    {
        $pushRemote = "origin-1"
    }
    else
    {
        $pushRemote = "origin"
    }

    $matchingWatch = Get-LoopWatchForBranch $originalBranch $project
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
    
    Write-Host "Creating a new beta patch"
    
    if($pause)
    {
        pause
    }
    
    $stashed = $False
    $doStash = "Y"
    # if there are any untracked changes, try to stash them
    if(!([string]::IsNullOrEmpty($(git status --porcelain))))
    {
        #Get the DB to drop
        $doStash = Read-Host "Your current branch '" $originalBranch "' has changes that are not committed.  Do you want to stash? (if not this operation will be canceled) (Y/N)"
    }

    if($doStash -eq "Y")
    {
        Run-StashedOperation({
            git fetch --all -v --progress --prune               
            git checkout origin-1-beta
            Sync-FilesWithBranch "upstream/beta"
            
            git add -u
            git commit -m "Git sync"
            
            Write-Host "Pushing patched origin-1-beta to origin-1"
            
            if($pause)
            {
                pause
            }
            
            git push origin-1 origin-1-beta -f
            
            git checkout $originalBranch
        })
        Write-Host "origin-1 up to date with beta."
        
        if($pause)
        {
            pause
        }
    }
    else
    {
        return $False
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

function Get-CsaCompare
{
    Param
    (
        [string] $baseBranch,
        [string] $currentBanch = $null,
        [switch] $upstream,
        [switch] $origin1
    )

    loopcompare -baseBranch:$baseBranch `
                -currentBanch:$currentBanch `
                -upstream:$upstream `
                -origin1:$origin1 `
                -csa
}
Set-Alias csacompare Get-CsaCompare -Scope Global

function Get-LoopCompare
{
    Param
    (
        [string] $baseBranch,
        [string] $currentBanch = $null,
        [switch] $upstream,
        [switch] $origin1,
        [switch] $csa
    )
    
    $project = IIf $csa "Csa" "Loop"
    
    if($csa)
    {
        gocsa
    }
    else 
    {
        goloop
    }
    
    if(-not $currentBanch)
    {
        $currentBanch = Get-CurrentBranch
    }

    if(-not $baseBranch)
    {
        $matchingWatch = Get-LoopWatchForBranch $currentBanch $project
        if($matchingWatch)
        {
            "Rebasing from branch $($matchingWatch.baseRemote)/$($matchingWatch.baseBranch)"
            $baseBranch = $matchingWatch.baseBranch
            $baseRemote = $matchingWatch.baseRemote
        }
    }
    
    if(-not $baseBranch)
    {
        $baseBranch = "beta"
    }
    
    $compareUrl = $null
    if($origin1)
    {
        if($baseBranch -eq "beta")
        {
            $baseBranch = "origin-1-beta"
        }
        $compareUrl = "https://github.com/AweSamNet/$project/compare/$baseBranch...$currentBanch"
    }
    elseif($upstream)
    {
        $compareUrl = "https://github.com/LoopLLC/$project/compare/$baseBranch...$currentBanch"
    }
    else
    {
        $compareUrl = "https://github.com/slombardo/$project/compare/$baseBranch...slombardo:$currentBanch"
    }
    Start-Process 'chrome.exe' $compareUrl

    return $compareUrl
}
Set-Alias loopcompare Get-LoopCompare -Scope Global

function Open-LoopProcess
{
    & 'C:\Users\sam\Documents\Loop\ProcessFlow4.pptx'
}


function New-CsaChangeScript (
    [Parameter(Mandatory=$true)]
    [int] $fogBugzId,
    [Parameter(Mandatory=$true)]
    [string] $description,
    [switch] $beta,
    [switch] $debugEnv,
    [switch] $release,
    [switch] $staging,
    [switch] $sydneyBeta,
    [switch] $sydneyRelease    
)
{
    $changeFolderPath = Join-Path $csaRepoPath "Csa\data\changes"
    if(-not (Test-Path $changeFolderPath))
    {
        Write-Error "Could not find path '$changeFolderPath'"
        return
    }
    
    $now = (Get-Date)
    $changeName = "$(Get-Date -format 'yyyy-MM-dd') $fogBugzId - $description"
    $environment = IIf $beta "Beta" `
                   (IIf $debugEnv "Debug" `
                    (IIf $release "Release" `
                     (IIf $staging "Staging" `
                      (IIf $sydneyBeta "Sydney-Beta" `
                       (IIf $sydneyRelease "Sydney-Release" $null)))))
    
    if($environment)
    {
        $changeFolderPath = Join-Path $changeFolderPath $environment
    }
                   
    $fullPath = Join-Path $changeFolderPath "$changeName.sql"
    
    $script = @"
/*
    ENTER DESCRIPTION HERE
    
    Sam Lombardo - slombardo@autoloop.com, Sam.Lombardo@AweSam.Net
    $(Get-Date -format 'yyyy-MM-dd')
*/

    ENTER CHANGE SCRIPT HERE

"@
    
    New-Item $fullPath -type file -value $script
    explorer.exe /select,$fullPath
}

function New-LoopChangeScript (
    [Parameter(Mandatory=$true)]
    [string] $shard,
    [Parameter(Mandatory=$true)]
    [string] $jiraId,
    [Parameter(Mandatory=$true)]
    [string] $description
)
{
    $changeFolderPath = Join-Path $loopRepoPath "Data\Changes\$shard"
    if(-not (Test-Path $changeFolderPath))
    {
        Write-Error "Could not find path '$changeFolderPath'"
        return
    }
    
    $now = (Get-Date)
    $changeName = "$(Get-Date -format 'yyyy-MM-dd-HH-mm') $jiraId - $description"
    
    if($changeName.Length -gt 80)
    {
        Write-Error "The description '$changeName' must not exceed 80 chars"
        return
    }
    
    $fullPath = Join-Path $changeFolderPath "$changeName.sql"
    
    $script = @"
/*
    ENTER DESCRIPTION HERE
    
    Sam Lombardo - slombardo@autoloop.com, Sam.Lombardo@AweSam.Net
    $(Get-Date -format 'yyyy-MM-dd')
*/

    ENTER CHANGE SCRIPT HERE

insert into dbo.FogbugzCases ( casenumber )
values
(
    '$changeName'
);
"@
    
    New-Item $fullPath -type file -value $script
    explorer.exe /select,$fullPath
}

function New-CsaBranch(
    [Parameter(Mandatory=$true)]$branchName, 
    $branchFromRemote="upstream", 
    $branchFrom="beta", 
    [switch]$noPrompt)
{
    New-LoopBranch -branchName:$branchName -branchFromRemote:$branchFromRemote -branchFrom:$branchFrom -noPrompt:$noPrompt -csa
}

function New-LoopBranch(
    [Parameter(Mandatory=$true)]$branchName, 
    $branchFromRemote="upstream", 
    $branchFrom="beta", 
    [switch]$noPrompt,
    [switch]$csa=$false)
{
    $project = IIf $csa "csa" "loop"
    if($csa)
    {
        gocsa
    }
    else
    {
        goloop
    }
    
    $originalBranch = Get-CurrentBranch
    if(-not( $originalBranch -match "^origin-1.*"))
    {

        New-Branch -branchName:$branchName -branchFromRemote:$branchFromRemote -branchFrom:$branchFrom -noPrompt:$noPrompt
        gitp-loop -project:$project
        $originalBranch = Get-CurrentBranch

        Write-Host "Switching to origin-1 to create a new branch"
    }
    
    $origin1NewBranch = "origin-1-$branchName"
    
    New-Branch -branchName:$origin1NewBranch -branchFromRemote:"origin-1" -branchFrom:"origin-1-beta" -noPrompt:$noPrompt
    git checkout $origin1NewBranch
    
    # push it to set the default upstream
    git push -u "origin-1" $origin1NewBranch -f
    
    gitp-loop -project:$project
    
    Run-StashedOperation({
        git checkout $branchName
    })
}

function New-CsaPatch([Parameter(Mandatory=$true)]$patchFrom)
{
    gocsa
    gitp-loop  -project:"csa"
    $patchFolder = "$drive/Git Workspace/Loop/Csa Patches"
    New-Patch -patchFolder:$patchFolder -patchFrom:$patchFrom    
}

function New-LoopPatch([Parameter(Mandatory=$true)]$patchFrom)
{
    goloop
    gitp-loop
    $patchFolder = "$drive/Git Workspace/Loop/Loop Patches"
    New-Patch -patchFolder:$patchFolder -patchFrom:$patchFrom    
}

function Watch-LoopBranch(
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath = $loopBranchWatchFilePath, 
    [string]$repoPath = $loopRepoPath, 
    [string]$baseRemote = "upstream", 
    [string]$baseBranch = "beta",    
    [string]$pushRemote = $baseRemote,
    [string]$pushBranch = $branch
)
{
    # if(!$branch){
        # $branch = Get-CurrentBranch
    # }
    
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
Set-Alias loopwatch Watch-LoopBranch -Scope Global

function Watch-CsaBranch(
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath = $csaBranchWatchFilePath, 
    [string]$repoPath = $csaRepoPath, 
    [string]$baseRemote = "origin", 
    [string]$baseBranch = "beta"
)
{
    # if(!$branch){
        # $branch = Get-CurrentBranch
    # }
    
    if(!$branch) {
        throw "No branch provided to watch."
    }
    
    Watch-Branch -branch:$branch -storePath:$storePath -repoPath:$repoPath -baseRemote:$baseRemote -baseBranch:$baseBranch
}
Set-Alias csawatch Watch-LoopBranch -Scope Global


function Unwatch-LoopBranch(
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath = $loopBranchWatchFilePath)
{
    Unwatch-Branch -branch:$branch -storePath:$storePath
}
Set-Alias loopunwatch Unwatch-LoopBranch -Scope Global

function Unwatch-CsaBranch(
    [string]$branch = $(Get-CurrentBranch), 
    [string]$storePath = $csaBranchWatchFilePath)
{
    Unwatch-Branch -branch:$branch -storePath:$storePath
}
Set-Alias csaunwatch Unwatch-LoopBranch -Scope Global

function Get-LoopWatchedBranches()
{
    Get-WatchedBranches $loopBranchWatchFilePath
}
Set-Alias loopwatched Get-LoopWatchedBranches -Scope Global

function Get-CsaWatchedBranches()
{
    Get-WatchedBranches $csaBranchWatchFilePath
}
Set-Alias csawatched Get-LoopWatchedBranches -Scope Global

function Watch-LoopBuildKeywords(
    [Parameter(Mandatory=$true)][string]$keyword,
    $project = "loop")
{    
    $path = IIf ($project -eq "csa") $csaBuildKeywordWatchFilePath $loopBuildKeywordWatchFilePath
    
    $list = {Get-WatchedLoopBuildKeywords -project:$project}.Invoke()
    $list.Add($keyword)

    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $path -Value $body
    Get-WatchedLoopBuildKeywords -project:$project
}

function Watch-CsaBuildKeywords(
    [Parameter(Mandatory=$true)][string]$keyword)
{
    Watch-LoopBuildKeywords -keyword:$keyword -project:"csa"
}

function Get-WatchedLoopBuildKeywords(
    $project = "loop")
{
    $path = IIf ($project -eq "csa") $csaBuildKeywordWatchFilePath $loopBuildKeywordWatchFilePath

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

function Get-WatchedCsaBuildKeywords()
{
    Get-WatchedLoopBuildKeywords -project:"csa"
}

function Encrypt-QueryString([HashTable]$values)
{
    $loopLibCommonPath = Join-Path $loopRepoPath "Class Libraries\LoopLibCommon\bin\Debug\LoopLibCommon.dll"
    $assembly = [System.Reflection.Assembly]::LoadFile($loopLibCommonPath)
        
    $eqs = New-Object LoopLib.Common.EncryptedQueryString
    
    $values.keys | % {    
        $eqs.Add($_, $values[$_])
    }
    
    return $eqs.Encrypt()
}

function Decrypt-QueryString([string]$encrypted, [switch]$raw)
{
    $loopLibCommonPath = Join-Path $loopRepoPath "Class Libraries\LoopLibCommon\bin\Debug\LoopLibCommon.dll"
    $assembly = [System.Reflection.Assembly]::LoadFile($loopLibCommonPath)
    
    if(-not $raw)
    {
        return [LoopLib.Common.EncryptedQueryString]::DecryptQueryString($encrypted)
    }
    else{
        $enc = [LoopLib.Common.EncryptedQueryString]::DecryptQueryString($encrypted)
        return $enc.ToString()
    }
}

function Unwatch-LoopBuildKeywords(
    [Parameter(Mandatory=$true)][string]$keyword,
    $project = "loop")
{
    $path = IIf ($project -eq "csa") $csaBuildKeywordWatchFilePath $loopBuildKeywordWatchFilePath

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
    Get-WatchedLoopBuildKeywords -project:$project
}

function Unwatch-CsaBuildKeywords(
    [Parameter(Mandatory=$true)][string]$keyword)
{
    Unwatch-LoopBuildKeywords -keyword:$keyword -project:"csa"
}

function Open-LoopTrello()
{
    Open-Chrome "https://trello.com/b/aCcM6lCj/autoloop"
}

function Open-LoopJiraTicket([string]$jiraId)
{
    if( -not $jiraId)
    {
        # try to get the jira id from the branch name
        $branch = Get-CurrentBranch
        
        if($branch)
        {
            $jiraId = $branch.Substring(2)
        }
    }
    
    if($jiraId)
    {
        Open-Chrome "https://jira.autoloop.com/browse/$jiraId"
    }
}