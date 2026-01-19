###  
### Commands for executing github api opperations
###

Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

Import-Module $ScriptPath\Common -DisableNameChecking

function Edit-Github
{
    notepad++ $(Join-Path $ScriptPath 'Github.psm1')
}

function Get-GithubCommands ([int]$columns = 3)
{
    $names = Get-Command -Module Github | % { $_.Name }    
    Write-Table $names $columns
}

$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
$SolutionPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "../.." ))
$githubApiUri = "https://api.github.com/"

function GetGithubToken()
{
    $token = ""
    $tokenPath = $(Join-Path $ScriptDir "githubkey.txt")

    if(Test-Path $tokenPath)
    {
        # token should be in the first line of the file
        Get-Content $tokenPath | ForEach-Object{
            $token = $_
        }
    }

    # no token file found
    if([string]::IsNullOrWhiteSpace($token))
    {
        while ([string]::IsNullOrWhiteSpace($token))
        {
            Write-Host "No Github Personal Access Token found.  Please enter your token now.  If you do not have one in Github, you can create one here:"
            Write-Host "https://github.com/settings/tokens" -ForegroundColor Blue
        
            $userName = Read-Host -Prompt "Input Github username"
            $token = Read-Host -Prompt "Input token"
        }

        $token = $($userName + ":" + $token)

        Write-Host
        $saveToken = "Invalid"
        while($saveToken -ne "y" -and $saveToken -ne "yes" -and $saveToken -ne "n"  -and $saveToken -ne "no" -and -not [string]::IsNullOrWhiteSpace($saveToken))
        {
            $saveToken =  $(Read-Host -Prompt "Would you like to remember this token for future use [N]/Y?").Trim()
        }

        if($saveToken -eq "y" -or $saveToken -eq "yes")
        {
            $newFile = New-Item $tokenPath -type file -force -Value $token
        }
    }

    return $token
}

function Find-HighlightGithubCode([string[]]$searchString, [Parameter(Mandatory=$true)][string]$repo, [parameter(ValueFromPipeline)]$results, [string[]]$path)
{
    $defaultFg = (get-host).ui.rawui.ForegroundColor
    $defaultBg = (get-host).ui.rawui.BackgroundColor

    $indent = "            "
    $miscCodeBlock = " ...                                                            "
    Write-Host "____________________________________________________________________________"
    Write-Host 

    if(-not $results -and $searchString)
    {
        $results = Find-GithubCode $searchString $repo $path
    }

    if(-not $results.items -or $results.items.Count -eq 0)
    {
        Write-Highlight "No Matches"
        Write-Host "____________________________________________________________________________"
        Write-Host 

        return
    }

    $results.items | ForEach-Object{
        $item = $_
        Write-Host "Html url  : " -NoNewline
        Write-Host $item.html_url -ForegroundColor Blue
        Write-Host "Path      : " -NoNewline

        [string[]]$fileNameSearchStrings = @()
        $_.text_matches | ForEach-Object {
            $text_match = $_
            # build the highlights for file name
             $text_match.matches | ForEach-Object{
                $fileNameSearchStrings += ,$_.text
            }
        }

        Write-Highlight $item.path $fileNameSearchStrings

        Write-Host "Matches   : " -NoNewline
        $count = 0
        [string[]]$fileNameSearchStrings = @()
        $_.text_matches | ForEach-Object {
            if( $count++ -gt 0)
            {
                Write-Host
                Write-Host $indent -NoNewline
                Write-Host $miscCodeBlock -BackgroundColor $defaultFg -ForegroundColor $defaultBg
                Write-Host
                Write-Host $indent -NoNewline
            }

            $text_match = $_

            [string]$fragment = $text_match.fragment
            $lastPos = 0
            
            # get matches
            $text_match.matches | ForEach-Object{
                $match = $_
                
                # if the match doesn't start at the beginning of the fragment, then just print the first portion
                if($match.indices[0] -gt $lastPos)
                {
                    $firstSplit = $fragment.Substring($lastPos, $match.indices[0] - $lastPos)
                    Write-Host $firstSplit.Replace("`n", $("`n" + $indent)) -NoNewline -ForegroundColor $defaultFg -BackgroundColor $defaultBg            
                }

                $highlight = $fragment.Substring($match.indices[0], ($match.indices[1] - $match.indices[0]))
                Write-Host $highlight.Replace("`n", $("`n" + $indent)) -NoNewline -ForegroundColor Black -BackgroundColor Yellow

                # save the last position in case there are other matches for this fragment
                $lastPos = $match.indices[1]
            }
            
            # print the last part of the fragment
            if($lastPos -lt $fragment.Length)
            {
                $lastSplit = $fragment.Substring($lastPos)
                Write-Host $lastSplit.Replace("`n", $("`n" + $indent)) -NoNewline -ForegroundColor $defaultFg -BackgroundColor $defaultBg            
            }
            
            Write-Host -ForegroundColor $defaultFg -BackgroundColor $defaultBg
        }

        Write-Host "____________________________________________________________________________"
        Write-Host 
    }

    Write-Host $(  "`nNOTE: There is currently a peculiarity with github search api in that if `n" + `
                   "there is more than one text_match fragment, and the second fragment contains `n" + `
                   "a better match than the first fragment, the full match will not be returned `n" + `
                   "from the api if it is preceded with a partial match, and the fragment will `n" + `
                   "be truncated at the end of the partial match.  In this way, it could appear `n" + `
                   "that the returned result is inaccurate via the API, while the same search `n" + `
                   "string on the github website may return the complete fragment. `n`n" + `
                   "tl;dr: When in doubt, double check the search string with the github website. ") `
        -ForegroundColor $defaultBg -BackgroundColor $defaultFg


}

function Get-GithubAllIssues(
    [Parameter(Mandatory=$true)][string]$owner, 
    [Parameter(Mandatory=$true)][string]$repo, 
    [string]$page = 1)
{
    GithubGet -partialUri "/repos/$owner/$repo/issues?state=all&per_page=100&page=$page" -ArgumentList $args -headers @{Accept = "application/vnd.github.v3.text-match+json"}
}

function Get-GithubIssue(
    [Parameter(Mandatory=$true)][string]$owner, 
    [Parameter(Mandatory=$true)][string]$repo, 
    [Parameter(Mandatory=$true)][string]$issueNumber)
{
    GithubGet -partialUri "/repos/$owner/$repo/issues/$issueNumber" -ArgumentList $args -headers @{Accept = "application/vnd.github.v3.text-match+json"}
}

function Find-GithubCode([Parameter(Mandatory=$true)][string[]]$searchString, [string]$repo, [string[]]$path)
{
    if(-not [string]::IsNullOrWhiteSpace($repo))
    {
        $repo = "repo:$repo"
    }
    else
    {
        $repo = [string]::Empty
    }

    [array]$paths = @()
    if($path -and $path.Count -gt 0)
    {
        $path |ForEach-Object{

            $paths += "path:$_"
        }
    }

    $args = "q=$searchString",$repo
    $args += $paths

    GithubGet -partialUri "/search/code" -ArgumentList $args -headers @{Accept = "application/vnd.github.v3.text-match+json"}
}

function GetGithubUri([Parameter(Mandatory=$true)][string]$partialUri, [string[]]$ArgumentList)
{
    $query = ""

    if($ArgumentList -and $ArgumentList.Count -gt 0)
    {
        $query += "?" + [string]::Join("+", $ArgumentList)
    }

    $path = New-Object Uri("https://api.github.com/")
    $path = New-Object Uri($path,$($partialUri + $query))

    return $path.ToString();
}

function Get-GithubRateLimits([string]$username, [string]$password, [hashtable]$headers)
{
    try
    {
        if(-not($username) -or(-not($password)))
        {
            $token = GetGithubToken
            $tokenSplit =  $token.Split(":")
            $username = $tokenSplit[0]
            $password = $tokenSplit[1]
        }
        
        $credential = New-Object System.Management.Automation.PSCredential($username, $(ConvertTo-SecureString $password -AsPlainText -Force))
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

        $rateLimits = @{}
        if($headers -eq $null)
        {
            $headers = @{}
            $headers.Add("Authorization", "Basic $base64AuthInfo")
        }
        
        $rateLimits = Invoke-RestMethod -Method Get `
                                        -Uri $(GetGithubUri "/rate_limit") `
                                        -Headers  $headers `
                                        -ErrorAction Stop `
                                        -Credential $credential 
        
        return $rateLimits
    }
    catch
    {
        Write-Error $_
    }

}

function GithubGet([Parameter(Mandatory=$true)][string]$partialUri, [string[]]$ArgumentList, [hashtable]$headers)
{
    $token = GetGithubToken
    $tokenSplit =  $token.Split(":")
    $username = $tokenSplit[0]
    $password = $tokenSplit[1]
    $credential = New-Object System.Management.Automation.PSCredential($username, $(ConvertTo-SecureString $password -AsPlainText -Force))
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

    $rateLimits = @{}
    if($headers -eq $null)
    {
        $headers = @{}
    }
    $headers.Add("Authorization", "Basic $base64AuthInfo")

    # see if we are performing a search 
    $isSearch = $partialUri.Split("/",[StringSplitOptions]::RemoveEmptyEntries)[0].Trim() -like "search"
    
    # loop until we are no longer exceeding our rate limit
    do
    {
    
        $limitReached = $false
        $resetTime = $null


        $rateLimits = Get-GithubRateLimits -username:$username -password$password -headers:$headers
        
        if($isSearch)    
        {
            $limitReached = $rateLimits.resources.search.remaining -eq 0
            $resetTime = $rateLimits.resources.search.reset
        }
        else
        {
            $limitReached = $rateLimits.resources.core.remaining -eq 0
            $resetTime = $rateLimits.resources.core.reset
        }

        if($limitReached)
        {
            WaitForRateLimit $(ConvertFrom-UtcEpochSeconds $resetTime) $partialUri
        }
    } until (-not $limitReached)

    $uri = GetGithubUri $partialUri $ArgumentList 
    
    $totalRetrySeconds = 0
    $retryDelay = 10
    $maxRetrySeconds = 60

    # apparently the github rate limit reset is not always accurate.  After calling the rate limit api and waiting the designated amount of time
    # and then calling the rate limit api a second time to confirm we waited long enough, on occasion github still returns a 403... so loop again.
    do
    {
        try
        {
            return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -Credential $credential -ContentType "application/json"    
        }
        catch
        {        
        Write-Error $_
        
    pause "failed"
            # if failure retry 
            $totalRetrySeconds += $retryDelay
            $retryTime = [DateTime]::UtcNow.AddSeconds($retryDelay)
            WaitForRateLimit $retryTime $partialUri

            if($totalRetrySeconds -ge $maxRetrySeconds)
            {
                throw
            }
        }            
    } until($totalRetrySeconds -ge $maxRetrySeconds) 
}

function WaitForRateLimit([Parameter(Mandatory=$true)][DateTime]$resetTime, [Parameter(Mandatory=$true)][string]$partialUri)
{
    $totalSecondsToWait = $($resetTime - [DateTime]::UtcNow).TotalSeconds
    
    while([DateTime]::UtcNow -lt $resetTime)
    {
        $secondsRemaining  = $($resetTime - [DateTime]::UtcNow).TotalSeconds

        Write-Progress -Id 999 -Activity "Github rate limit exceeded." -Status $("Rate limit for uri " + $partialUri + " exceeded.  Waiting for reset.") `
            -SecondsRemaining $secondsRemaining `
            -PercentComplete ( ($totalSecondsToWait - $secondsRemaining) / $totalSecondsToWait * 100)
        Start-Sleep 1
    }    

    Write-Progress -Id 999 -Completed -Activity "Github rate limit exceeded." -Status $("Rate limit for uri " + $partialUri + " exceeded.  Waiting for reset.") `
        -SecondsRemaining 0 `
        -PercentComplete 100
}

$defaultWatchedIssuesPath = Join-Path $ScriptPath "Watched\Issues.txt"

function Update-WatchedGithubIssues(
   [string]$storePath = $defaultWatchedIssuesPath
)
{
    $changed = $false
    $list = {Get-WatchedGithubIssues $storePath}.Invoke()
    
    if($list -eq $null -or $list.Count -eq 0){
        return
    }
    
    Write-Host "Scanning for watched Github issue changes..."

    $list | % {
        $updatedIssue = Get-GithubIssue -owner $_.owner -repo $_.repo -issueNumber $_.issueNumber            
        
        if($updatedIssue.state           -ne $_.state `
            -or $updatedIssue.title      -ne $_.title `
            -or $updatedIssue.html_url   -ne $_.html_url `
            -or $updatedIssue.url        -ne $_.url `
            -or $updatedIssue.created_at -ne $_.created_at `
            -or $updatedIssue.updated_at -ne $_.updated_at `
            -or $updatedIssue.closed_at  -ne $_.closed_at)
        {
            $output = 
"owner       : $($_.owner)
repo        : $($_.repo)
issueNumber : $($_.issueNumber)
title       : $($updatedIssue.title)
html_url    : $($updatedIssue.html_url)
url         : $($updatedIssue.url)
state       : $($_.state) => $($updatedIssue.state)
created_at  : $($_.created_at) => $($updatedIssue.created_at)
updated_at  : $($_.updated_at) => $($updatedIssue.updated_at)
closed_at   : $($_.closed_at) => $($updatedIssue.closed_at)"

            if(!$changed)
            {
                $changed = $true
                Write-Host "-----------------------------------------------"
                Write-Host "The following watched issues have been updated:"
                Write-Host 
            }

            $highlight = @()
            if($updatedIssue.state -ne $_.state){
                $highlight += IIf $updatedIssue.state $updatedIssue.state "state" 
            }
            if($updatedIssue.title -ne $_.title){
                $highlight += IIf $updatedIssue.title $updatedIssue.title "title" 
            }
            if($updatedIssue.html_url -ne $_.html_url){
                $highlight += IIf $updatedIssue.html_url $updatedIssue.html_url "html_url" 
            }
            if($updatedIssue.url -ne $_.url){
                $highlight += IIf $updatedIssue.url $updatedIssue.url "url" 
            }
            if($updatedIssue.created_at -ne $_.created_at){
                $highlight += IIf $updatedIssue.created_at $updatedIssue.created_at "created_at"
            }
            if($updatedIssue.updated_at -ne $_.updated_at){
                $highlight += IIf $updatedIssue.updated_at $updatedIssue.updated_at "updated_at"
            }
            if($updatedIssue.closed_at -ne $_.closed_at){
                $highlight += IIf $updatedIssue.closed_at $updatedIssue.closed_at "closed_at"
            }
            
            $output | Write-Highlight -textsToHighlight $highlight
            
            $_.title = $updatedIssue.title
            $_.html_url = $updatedIssue.html_url
            $_.url = $updatedIssue.url
            $_.state = $updatedIssue.state    
            $_.created_at = $updatedIssue.created_at
            $_.updated_at = $updatedIssue.updated_at
            $_.closed_at = $updatedIssue.closed_at 
        }
    }
    
    if($changed)
    {
        $body = ConvertTo-Json $list

        $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    }
}

function Watch-GithubIssue(
    [Parameter(Mandatory=$true)][string]$owner, 
    [Parameter(Mandatory=$true)][string]$repo, 
    [Parameter(Mandatory=$true)][string]$issueNumber,
    [string]$storePath = $defaultWatchedIssuesPath)
{
    $newIssueToWatch = @{
        "owner" = $owner
        "repo" = $repo
        "issueNumber" = $issueNumber
    }
    
    $issue = Get-GithubIssue -owner $owner -repo $repo -issueNumber $issueNumber
    
    $newIssueToWatch.title = $issue.title
    $newIssueToWatch.html_url = $issue.html_url
    $newIssueToWatch.url = $issue.url
    $newIssueToWatch.state = $issue.state    
    $newIssueToWatch.created_at = $issue.created_at
    $newIssueToWatch.updated_at = $issue.updated_at
    $newIssueToWatch.closed_at = $issue.closed_at 
    
    $list = {Get-WatchedGithubIssues $storePath}.Invoke()
    $list.Add($newIssueToWatch)

    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    Get-WatchedGithubIssues $storePath
}

function Export-GithubIssues {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $issues,

        [string] $OutputPath = "github-issues.csv"
    )

    $output = @()

    foreach ($issue in $issues) {
        $labels = ($issue.labels | ForEach-Object { $_.name }) -join ", "
        $output += [PSCustomObject]@{
            Id         = $issue.number
            Title      = $issue.title
            State      = $issue.state
            Labels     = $labels
            CreatedAt  = $issue.created_at
            UpdatedAt  = $issue.updated_at
            Assignee   = if ($issue.assignee) { $issue.assignee.login } else { "" }
            Author     = $issue.user.login
            Body       = ($issue.body -replace "`r`n", " " -replace "`n", " ") -replace ",", ";"
        }
    }

    $output | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($output.Count) issues to '$OutputPath'"
}

function Get-WatchedGithubIssues([string]$storePath = $defaultWatchedIssuesPath)
{
    Get-JsonFromFile $storePath
}

function Unwatch-GithubIssue(
    [Parameter(Mandatory=$true)][string]$owner, 
    [Parameter(Mandatory=$true)][string]$repo, 
    [Parameter(Mandatory=$true)][string]$issueNumber,
    [string]$storePath = $defaultWatchedIssuesPath)
{
    $issuesToWatch = @()
    
    if ((Test-Path ($storePath)))
    {
        $issuesToWatch = ConvertFrom-Json (Get-Content $storePath -Raw)
    }
    
    $list = {$issuesToWatch}.Invoke()
    $toRemove  = $list | where { 
        $_ `
        -and $_.owner -eq $owner `
        -and $_.repo -eq $repo `
        -and $_.issueNumber -eq $issueNumber
    } | select -First 1
    
    if($toRemove)
    {
        $list.Remove($toRemove)
    } 
    
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    Get-WatchedGithubIssues $storePath
}

