###
### Git ShortCuts / Workflow Helpers
###

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Edit-Git
{
    notepad++ $(Join-Path $ScriptPath 'Git.psm1')
}

function Get-GitCommands ([int]$columns = 3)
{
    $names = Get-Command -Module Git | % { $_.Name }    
    Write-Table $names $columns
}

function Initialize-GitSubmodules()
{
    git submodule update --init --recursive
}
Set-Alias Init-GitSubmodules Initialize-GitSubmodules -Scope Global

function Get-CurrentBranch
{
    return git symbolic-ref --short HEAD
}

function Get-LatestCode(
    $baseRemote="upstream", 
    $baseBranch="next", 
    $pushRemote="origin", 
    [Switch]$a,
    [switch]$subModuleUpdate,
    [switch]$silent,
    $branchWatchStorePath,
    [switch]$ignoreWatched,
    [switch]$pause)
{    
    $success = $False
    $stashed = $False
    
    $originalBranch = Get-CurrentBranch

    if(!([string]::IsNullOrEmpty($(git status --porcelain))))
    {
        Write-Host "Stashing changes."
        
        if($pause)
        {
            pause
        }
        
        git stash
        $stashed = $True
    }

    #switch to $baseBranch so that we can prune the branch we are on if it is already merged in
    git checkout $baseBranch

    if($a)
    {
        git fetch --all -v --progress --prune
    }
    else
    {
        #always fetch $pushRemote
        if($pushRemote -and $baseRemote -ne $pushRemote)
        {
            git fetch $pushRemote -v --progress --prune
        }
        git fetch $baseRemote -v --progress --prune
    }
    
    #always rebase the local branch based on the remote branch
    git rebase $baseRemote/$baseBranch
    if($subModuleUpdate)
    {
        git submodule update --recursive --init --rebase --progress
    }

    
    # now push base branch to push remote if the push remote is different to keep it up to date
    if($pushRemote -and $baseRemote -ne $pushRemote)
    {
        Write-Host "Pushing rebased $baseBranch to $pushRemote"
        
        if($pause)
        {
            pause
        }
        
        git push $pushRemote $baseBranch -f
    }
    
    # if we are watching any branches then rebase them here
    if(!$ignoreWatched -and $branchWatchStorePath -and (Test-Path $branchWatchStorePath))
    {
        $body = Get-Content $branchWatchStorePath -Raw 
        
        if($body)
        {
            $branchesToWatch = ConvertFrom-Json $body
            if($branchesToWatch)
            {
                Write-Host "-------------------------"                
                Write-Host "Updating watched branches"
                Write-Host "-------------------------"                
                Write-Host
                # $newBranchToWatch = @{
                    # "branch" = $branch
                    # "repoPath" = $repoPath     
                    # "baseRemote" = $baseRemote
                    # "baseBranch" = $baseBranch
                    # "pushRemote" = $pushRemote
                    # "pushBranch" = $pushBranch
                    
                # }
                
                if($pause)
                {
                    pause
                }
                
                $originalPath = (Resolve-Path .\).Path
                $branchesToWatch | where {$_ -and($_.branch -ne $originalBranch)} | % {
                    if( !$_.branch )
                    {
                        Write-Host "WARNING: empty branch found in branch watch store: $branchWatchStorePath"
                        continue
                    }
                    
                    if(!$_.repoPath)
                    {
                        Write-Host "WARNING: no repoPath for branch: $($_.branch) in branch watch store: $branchWatchStorePath"
                        continue
                    }
                    
                    if(!$_.baseRemote)
                    {
                        Write-Host "WARNING: no baseRemote for branch: $($_.branch) in branch watch store: $branchWatchStorePath"
                        continue
                    }
                    
                    if(!$_.baseBranch)
                    {
                        Write-Host "WARNING: no baseBranch for branch: $($_.branch) in branch watch store: $branchWatchStorePath"
                        continue
                    }
                    
                    if(!$_.pushRemote)
                    {
                        $_.pushRemote = $_.baseRemote
                    }
                    
                    if(!$_.pushBranch)
                    {
                        $_.pushBranch = $_.branch
                    }
                    
                    Write-Host "Updating watched branch: $($_.branch)"
                    Write-Host
                    
                    
                    if($pause)
                    {
                        pause
                    }
                    
                    cd "$($_.repoPath)"
                    stash {
                        git checkout $_.branch
                        git rebase "$($_.baseRemote)/$($_.baseBranch)"
                        
                        # push to the push remote to keep it up to date
                        if($_.pushRemote -and (($_.baseRemote -eq $_.pushRemote -and $_.baseBranch -ne $_.pushBranch) -or ($_.baseRemote -ne $_.pushRemote)))
                        {
                            if($silent)
                            {
                                $doPush = "Y"
                            }
                            else 
                            {
                                $doPush = Read-Host "Would you like to push rebased watched branch: $($_.branch) to remote: $($_.pushRemote)/$($_.pushBranch)? (Y/N)"            
                            }
                            
                            if($doPush -eq "Y")
                            {
                                Write-Host "Pushing rebased $($_.pushBranch) to $($_.pushRemote)"
                                git push $_.pushRemote $_.pushBranch -f
                            }
                        }
                    }
                    
                    Write-Host
                }
                
                Write-Host "----------------------------------"
                Write-Host "Finished Updating watched branches"
                Write-Host "----------------------------------"
                Write-Host
                        
                if($pause)
                {
                    pause
                }
                
                #back to original path
                cd $originalPath
                git checkout $originalBranch
            }
        }
    }
    
    #switch back to the original branch IF the branch still exists or we have stashed changes.
    if(!([string]::IsNullOrEmpty($(git show-ref refs/heads/$originalBranch))) -or ($stashed -eq $TRUE))
    {
        git checkout $originalBranch
        git rebase $baseRemote/$baseBranch
    }   

    if($stashed -eq $TRUE)
    {
        Write-Host "Popping changes."
        git stash pop
    }    
    $success = $True
    
    return $success
}
Set-Alias gitp Get-LatestCode -Scope Global

function Run-StashedOperation([Parameter(Mandatory=$true)][scriptblock]$command)
{
    $stashed = $False
    if(!([string]::IsNullOrEmpty($(git status --porcelain))))
    {
        Write-Host "Stashing changes."
        git stash
        $stashed = $True
    }

    Invoke-Command -ScriptBlock:$command  4>&1
    
    if($stashed -eq $TRUE)
    {
        Write-Host "Popping changes."
        git stash pop
    }
}
Set-Alias stash Run-StashedOperation -Scope Global

function New-Branch(
    [Parameter(Mandatory=$true)]$branchName, 
    [Parameter(Mandatory=$true)]$branchFromRemote, 
    [Parameter(Mandatory=$true)]$branchFrom, 
    [switch]$noPrompt)
{
    $created = $False
    $stashed = $False
    $originalBranch = Get-CurrentBranch

    try
    {
        #if there are any untracked changes, try to stash them
        if(!([string]::IsNullOrEmpty($(git status --porcelain))))
        {
            #set the default response
            $doStash = ""    
            if(!$noPrompt)
            {
                #Get the DB to drop
                $doStash = Read-Host "Your current branch '" $originalBranch "' has changes that are not committed.  Do you want to stash? (if not this operation will be canceled) (Y/N)"
            }
            else
            {
                # Revert changes to modified files.
                git reset --hard

                # Remove all untracked files and directories.
                git clean -fdx
            }

            #if we are forcing noPrompt, or the user wants to stash changes, then stash.  Otherwise cancel out.
            if($doStash -eq "Y")
            {
                git stash
                $stashed = $TRUE
            }
            elseif($doStash)
            {
                return $False
            }
        }

        #switch to $branchFrom to get a fresh branch
        git checkout $branchFrom

        #switch to the new branch 
        git checkout -b $branchName
        
        if($stashed -eq $TRUE)
        {
            Write-Host "Popping changes."
            git stash pop
        }   
        
        $created = $True
    }
    catch
    {
        Write-Error "Failed to create branch"
        return $False
    }
    return $created
}

function New-Patch ([Parameter(Mandatory=$true)]$patchFolder, [Parameter(Mandatory=$true)]$patchFromBranch)
{
    $branch = Get-CurrentBranch
    $patchFolder = Join-Path $patchFolder $branch

    if(!(test-path $patchFolder))
    {
        New-Item -ItemType Directory -Force -Path $patchFolder
    }
    
    $files = get-childitem -Path $patchFolder
    $folders = @()
    $files | where-object { $_.PSIsContainer } | % {
        $folders += $_
    }

    $newFolderName = $folders.Count + 1
    $newFilesFolder = (Join-Path $patchFolder $newFolderName)
    $lastFolder = $null

    $output = git.exe format-patch -o "$newFilesFolder" $patchFromBranch

    $files = get-childitem -Path $patchFolder
    $folders = @()
    $files | where-object { $_.PSIsContainer } | % {
        $folders += $_
    }

    if($folders.Count -gt 1)
    {
        $lastFolder = $folders.Count - 1
    }

    if($lastFolder -ne $null)
    {
        $originalFiles = @()
        
        # get the differences in the past folders
        for($i = $lastFolder; $i -gt 0; $i--)
        {
            get-childitem -Path (Join-Path $patchFolder $i) | %{
                $originalFiles += (Get-Content $_.FullName -First 1)
            }
        }
        
        (get-childitem -Path $newFilesFolder) | %{
            $newHash = (Get-Content $_.FullName -First 1)
            
            # if the hash has already been loaded, get rid of this file
            if($originalFiles -contains $newHash)
            {
                rm (Join-Path $newFilesFolder $_)
            }            
        }
    }
        
    # see if there are any patches left
    $patchFiles = @()
    (get-childitem -Path $newFilesFolder) | % { $patchFiles += $_ }
    
    if($patchFiles.Count -eq 0)
    {
        rm $newFilesFolder
        Write-Host "No differences to patch.  Patch not created."    
        return $false
    }
    else
    {
        Write-Host "New patch for $branch created in '$newFilesFolder'"
        return $true
    }
}

function Apply-Patch([Parameter(Mandatory=$true)]$patchFolder)
{
    $branch = Get-CurrentBranch

    $files = get-childitem -Path $patchFolder
    $folders = @()
    $files | where-object { $_.PSIsContainer } | % {
        $folders += $_
    }

    $newPatchDirectory = $folders.Count
    $patchFiles = @()
    (Get-ChildItem -Path (Join-Path $patchFolder $newPatchDirectory)) | % {
        $patchFiles += $_.FullName
    }

    $patchFiles | % {
        git.exe am --3way --ignore-space-change --keep-cr "$_"
    }
}

function Watch-Branch(
    [string]$branch, 
    [Parameter(Mandatory=$true)]
    [string]$storePath, 
    [string]$repoPath = $((Resolve-Path .\).Path), 
    [Parameter(Mandatory=$true)]
    [string]$baseRemote, 
    [Parameter(Mandatory=$true)]
    [string]$baseBranch,
    [string]$pushRemote=$baseRemote,
    [string]$pushBranch=$branch)
    
{
    if(!$branch){
        $branch = Get-CurrentBranch
    }
    
    if(!$branch) {
        throw "No branch provided to watch."
    }
    
    $newBranchToWatch = @{
        "branch" = $branch
        "repoPath" = $repoPath
        "baseRemote" = $baseRemote
        "baseBranch" = $baseBranch
        "pushRemote" = $pushRemote
        "pushBranch" = $pushBranch
    }
    
    $branchesToWatch = @()
    
    $list = {Get-WatchedBranches $storePath}.Invoke()
    $list.Add($newBranchToWatch)

    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    Get-WatchedBranches $storePath
}

function Get-WatchedBranches([string]$storePath)
{
    $branchesToWatch = $null
    if ((Test-Path ($storePath)))
    {
        $branchesToWatch = ConvertFrom-Json (Get-Content $storePath -Raw)
    }
    
    if($branchesToWatch)
    {
        {$branchesToWatch}.Invoke()
    }
}

function Unwatch-Branch(
    [Parameter(Mandatory=$true)]
    [string]$branch, 
    [Parameter(Mandatory=$true)]
    [string]$storePath)
{
    $branchesToWatch = @()
    
    if ((Test-Path ($storePath)))
    {
        $branchesToWatch = ConvertFrom-Json (Get-Content $storePath -Raw)
    }
    
    $list = {$branchesToWatch}.Invoke()
    $toRemove  = $list | where { $_ -and $_.branch -eq $branch} | select -First 1
    
    if($toRemove)
    {
        $list.Remove($toRemove)
    } 
    
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    Get-WatchedBranches $storePath
}

function Sync-FilesWithBranch(
    [Parameter(Mandatory=$true)]
    [string]$branchToSyncWith)
{
    $originalBranch = Get-CurrentBranch
    
    do
    {
        $files = @()
        $files += git --no-pager diff --name-status $branchToSyncWith
        
        $doDeletedFiles = $false
        $i = 0; 
        $activity = "Reverting Files on $originalBranch to $branchToSyncWith"
        if($files -ne $null)
        {
            $files | % {
                Write-Progress -Activity $activity -status "$($i+1) of $($files.Count): $_" -percentComplete ((++$i / $files.Count) * 100) -Id 1
                $split = $_.Split("`t")
                if($split[0] -match "[A]")
                {
                    rm $split[1]
                    $doDeletedFiles = $true
                }
                else
                {
                    git checkout $branchToSyncWith $split[1]
                }
            }    
        }
    } until (-not $doDeletedFiles)
    
    Write-Progress -Activity $activity -Completed -Id 1
}





# $PoshGitPath = (Join-Path $ScriptPath "posh-git")

# Import-Module $PoshGitPath -Scope Global

# & "$PoshGitPath\profile.example.ps1"

Export-ModuleMember -Function *-*