    $scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition;
    $scriptFile = $MyInvocation.MyCommand.Definition

    $statePath = Join-Path $scriptPath "Syncro-Install.state"

    function Test-IsAdmin
    {
        $wid=[System.Security.Principal.WindowsIdentity]::GetCurrent()
        $prp=new-object System.Security.Principal.WindowsPrincipal($wid)
        $adm=[System.Security.Principal.WindowsBuiltInRole]::Administrator
        return $prp.IsInRole($adm)
    }
    
    function Save-State($state)
    {
        $body = ConvertTo-Json $state -Depth 10
        $output = New-Item -ItemType File -Force -Path $statePath -Value $body
    }
    
    function Get-State()
    {
        $state = Get-JsonFromFile $statePath
        
        if(!$state)
        {
            $state = @{
                IsSshSet = $false;
                IsGitWorkspacePathSet = $false;
                GitWorkspacePath = "C:\Git-Workspace";
                IsRepositoriesCloned = $false;
                IsRemainingInstallsComplete = $false;
                IsVisualStudioInstalled = $false;
                IsProfileSetUp = $false;
                IsOldDevPacksInstalled = $false;
                IsDotNet35Enabled = $false;
                IsWixInstalled = $false;
                IsNugetConfigured = $false;
            }
        }
        
        return $state
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
    
    function Set-PageantStartup($keyFiles, $keysDirectory)
    {
        if(!$keysDirectory)
        {
            $sameDirectory = $(Read-Host "Are all your keys in the same directory[y/n]?").Trim()

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

    function New-PsSession([Parameter(Mandatory=$true)]$command, [switch]$admin)
    {
        $sb = @'
&{
    param([scriptblock]$command)

    Invoke-Command -ScriptBlock $command 4>&1
    
} -command { 
'@+$command+'}'

        if($admin)
        {
            Start-Process powershell -Verb RunAs -ArgumentList "-noexit -Command $sb"
        }
        else 
        {
            Start-Process powershell -ArgumentList "-noexit -Command $sb"
        }
    }
    
    function Restart-ScriptInAdmin
    {
        New-PsSession "& $scriptFile" -admin        
        stop-process -Id $PID
    }
    
    function Kill-Powershell([Parameter(Mandatory=$true)]$message) {
        Write-SyncroStatus @"
Powershell session needs to be restarted.  

Reason: $message

Closing this window, please rerun the install script.
"@
        Write-Host "Press any key to continue."
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        stop-process -Id $PID
    }
    
    function Write-SyncroStatus ($status)
    {
        Write-Host
        Write-Host "*******************************************************************************"
        Write-Host "Syncro Status: $status"
        Write-Host "*******************************************************************************"
        Write-Host
    }
    
    function Set-Shortcut( [string]$sourceExe, [string]$destinationPath, [string]$startIn, $argumentList)
    {
        
        if( $argumentList -is [array])
        {
            $argumentsJoined = ""
            foreach ($argument in $argumentList)
            {
                $argumentsJoined += """$argument"" "
            }
            $argumentList = $argumentsJoined
        }
        
        $wshShell = New-Object -comObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($destinationPath)

        $shortcut.TargetPath = $sourceExe
        $shortcut.Arguments = $argumentList
        $shortcut.WorkingDirectory = $startIn
        
        $shortcut.Save()
    }
    
    function Write-ProgressHelper ([int]$stepNumber, [string]$message)
    {
        Write-Progress -Id 1 -Activity 'Setting up Developer Environment' -Status "$Message - Step $stepNumber of $steps" -PercentComplete (($stepNumber / $steps) * 100)
    }
    
    function Write-GitRepositoryProgress([int]$stepNumber, [string]$message)
    {
        Write-Progress -ParentId 1 -Id 2 -Activity 'Cloning Git repositories' -Status $Message -PercentComplete (($stepNumber / $gitSteps) * 100)
    }
    
    function Download-AndExtractZip($url, $destinationFolder)
    {
        $zipFile = Download-File $url
        $extractedFolderName = [io.path]::GetFileNameWithoutExtension($zipFile)
        $destination = Join-Path $destinationFolder $extractedFolderName
         
        $extractShell = New-Object -ComObject Shell.Application 
        $files = $extractShell.Namespace($zipFile).Items() 
        $extractShell.NameSpace($destination).CopyHere($files) 
    }

    function Download-File($url)
    {
        $downloadFolder = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        $filePath = Join-Path $downloadFolder (Split-Path -Path $url -Leaf) 
        
        Invoke-WebRequest -Uri $url -OutFile $filePath 
        return $filePath
    }

    function Get-ObjectHasProperty($object, $propertyName)
    {
        return [bool]($object.PSobject.Properties.name -like $propertyName)
    }
    Set-Alias HasProperty Get-ObjectHasProperty -Scope Global

    # Based on http://nuts4.net/post/automated-download-and-installation-of-visual-studio-extensions-via-powershell
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

    function Run-ChocolateyInstalls($storePath = $defaultWatchedChocolateyInstallPath, [switch]$y)
    {
        Get-JsonFromFile $storePath | % {
            $command = "choco install $($_.Value.AppName)"

            if($_.Value.args)
            {
                $command += " --package-parameters ""$($_.Value.args)"""
            }

            if($y)
            {
                $command += " -y"
            }

            Invoke-Expression $command
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
    
    function Is-Installed( [Parameter(Mandatory=$true)][string]$software)
    {
        return (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { 
            HasProperty $_ "DisplayName"} `
            | Where { $_.DisplayName -match $software }) -ne $null
    }

    $steps = ([System.Management.Automation.PsParser]::Tokenize((gc "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"), [ref]$null) | where { $_.Type -eq 'Command' -and $_.Content -eq 'Write-ProgressHelper' }).Count

    $gitSteps = ([System.Management.Automation.PsParser]::Tokenize((gc "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"), [ref]$null) | where { $_.Type -eq 'Command' -and $_.Content -eq 'Write-GitRepositoryProgress' }).Count

    $stepCounter = 0
    $gitStepCounter = 0
    
    $state = Get-State
    
    $status = "Beginning Syncro Agent Team development machine setup"
    Write-SyncroStatus $status
    $progressId = 1
    
    Write-ProgressHelper -Message $status -StepNumber ($stepCounter++)
    
    if(!(Test-IsAdmin))
    {
        Restart-ScriptInAdmin
    }
    
    Write-ProgressHelper -Message "Verifying Chocolatey Install" -StepNumber ($stepCounter++)

    if(!(Get-Command "choco" -ErrorAction SilentlyContinue))
    {
        Write-SyncroStatus "Installing Chocolatey and required git packages"

        # install chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occurred installing Chocolatey.  Exiting, please inspect the console for details."
            exit 1
        }
    }
    
    Write-ProgressHelper -Message "Verifying sudo Install" -StepNumber ($stepCounter++)
    Write-SyncroStatus "Checking for sudo"
    if (!(Get-Command "sudo" -ErrorAction SilentlyContinue))
    {
        choco install sudo -y
        
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occurred installing sudo (used in profile scripts).  Exiting, please inspect the console for details."
            exit 1
        }
    }

    Write-ProgressHelper -Message "Verifying Git Install" -StepNumber ($stepCounter++)
    Write-SyncroStatus "Checking for git"
    if (!(Get-Command "git" -ErrorAction SilentlyContinue))
    {
        choco install git -y
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occurred installing git.  Exiting, please inspect the console for details."
            exit 1
        }
    }

    Write-ProgressHelper -Message "Verifying pageant Install" -StepNumber ($stepCounter++)
    Write-SyncroStatus "Checking for pageant"
    if(!(Get-Command "pageant" -ErrorAction SilentlyContinue))
    {
        choco install tortoisegit -y
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occurred installing tortoisegit (for windows git but also bundled tools).  Exiting, please inspect the console for details."
            exit 1
        }
    }

    Write-ProgressHelper -Message "Verifying plink Install" -StepNumber ($stepCounter++)
    Write-SyncroStatus "Checking for plink"
    if(!(Get-Command "plink" -ErrorAction SilentlyContinue))
    {
        choco install putty -y
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occurred installing putty bundle.  Exiting, please inspect the console for details."
            exit 1
        }
    }

    #start a new admin powershell session
    if(!(Get-Command "pageant" -ErrorAction SilentlyContinue) `
        -or !(Get-Command "git" -ErrorAction SilentlyContinue) `
        -or !(Get-Command "pageant" -ErrorAction SilentlyContinue) `
        -or !(Get-Command "plink" -ErrorAction SilentlyContinue))
    {
        Kill-Powershell "An installed package requires all powershell sessions to be closed before it can be accessible."
    }

    Write-ProgressHelper -Message "Verifying SSH Setup" -StepNumber ($stepCounter++)
    if(!($state.IsSshSet))
    {
        Write-SyncroStatus "Setting up SSH keys for git."

        # important! Ensure the user has set up their SSH keys

        Write-Host "*******************************************************************************"
        Write-Host "Important!  Now that git has been installed, please make sure you generate"
        Write-Host "your ssh keys and save them or you will not be able to fetch the repositories."
        Write-Host "*******************************************************************************"

        Write-Host
        do{
            Write-Host "Would you like to go through Pageant key setup (including startup and PATH)?"
            $setupPageant = (Read-Host "(If you would like to set up ssh manually, type [n]) [y/n]").Trim()
        } while(-not($setupPageant -match '^[yn]$'))
        
        if($setupPageant -ne "y")
        {
            Read-Host "Press enter after you have set up your ssh keys."
        }
        else{
            Set-PageantStartup
            $pageantLink = Join-Path ([Environment]::GetFolderPath('Startup')) "pageant.lnk"
            
            do{
                invoke-item $pageantLink
                Write-Host "Waiting for pageant to load.  If your key requires a passphrase, enter it when the prompt pops up."
                $ready = (Read-Host "Check your task tray for the icon and verify that your key is loaded. Did Pageant load properly?[y/n]").Trim()
            } while ($ready -ne 'y')
        }
        
        if($LASTEXITCODE)
        {
            Write-Host "An error occured setting up ssh.  Exiting, please inspect the console for details."
            exit 1
        }
        
        $state.IsSshSet = $true
        Save-State $state
        
        Kill-Powershell "Powershell sessions must be closed for new ssh settings to be accessible."
    }
    
    # create git workspace
    Write-ProgressHelper -Message "Verifying Git Workspace Setup" -StepNumber ($stepCounter++)
    if(!($state.IsGitWorkspacePathSet))
    {
        Write-SyncroStatus "Setting up git workspace."

        Write-Host
        do{
            $useDefaultGitFolder = (Read-Host "Use the default workspace directory for git repositories? ($($state.GitWorkspacePath))? [y/n]").Trim()
        } while(! ($useDefaultGitFolder -match '^[yn]$'))
        
        if($useDefaultGitFolder -eq "n")
        {
            do{
                $state.GitWorkspacePath = (Read-Host "Enter the default git workspace directory you would like to use").Trim()
                $isPathValid = Test-Path $state.GitWorkspacePath -IsValid
                
                if(!$isPathValid)
                {
                    Write-Host "Path: '$gitFolder' is not valid."
                }
            } while (!$isPathValid)
        }
        
        if (!(Test-Path $state.GitWorkspacePath))
        {
            $output = New-Item -ItemType Directory -Force -Path $state.GitWorkspacePath
        }
                
        if($LASTEXITCODE)
        {
            Write-Host "An error occured setting up the git workspace.  Exiting, please inspect the console for details."
            exit 1
        }
        
        $state.IsGitWorkspacePathSet = $true
        Save-State $state
    }
    
    # clone the repositories
    Write-ProgressHelper -Message "Verifying Git Repositories" -StepNumber ($stepCounter++)
    if(!($state.IsRepositoriesCloned))
    {
        Write-SyncroStatus "Fetching required repositories."

        cd $state.GitWorkspacePath
        
        # even though git does this by default the first time it runs, there is a known bug that freezes git when this
        # happens in the context of a script.  As such we run it manually to avoid this bug.   
        plink.exe -agent -v git@gitlab.com
        
        Write-GitRepositoryProgress -message "Cloning kabuto-app" -stepNumber (++$gitStepCounter)
        git clone --recurse-submodules git@gitlab.com:syncromsp/team-rmm-agent/kabuto-app.git --progress

        Write-GitRepositoryProgress -message "Cloning kabuto-live-windows" -stepNumber (++$gitStepCounter)
        git clone --recurse-submodules git@gitlab.com:syncromsp/team-rmm-agent/kabuto-live-windows.git --progress        

        Write-GitRepositoryProgress -message "Cloning kabuto-live-client" -stepNumber (++$gitStepCounter)
        git clone --recurse-submodules git@gitlab.com:syncromsp/team-rmm-agent/kabuto-live-client.git --progress      
        
        Write-Progress -ParentId 1 -Id 2 -Activity 'Cloning Git repositories' -Status "Finished" -Complete
        
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occurred fetching main scripts git repository.  Exiting, please inspect the console for details."
            exit 1
        }
        
        $state.IsRepositoriesCloned = $true
        Save-State $state
    }
    
    # install visual studio as multiple packages depend on it
    Write-ProgressHelper -Message "Verifying Visual Studio Installed" -StepNumber ($stepCounter++)
    if(!($state.IsVisualStudioInstalled))
    {
        Write-SyncroStatus "Running Visual Studio Install."

        $visualStudioEdition = $(Read-Host "Select Visual Studio edition: Please enter 'p' to install Visual Studio Professional or enter 'c' to install Visual Studio Community edition.").Trim()
        if ($visualStudioEdition.Trim() -eq "p") {
            choco install visualstudio2022professional  --package-parameters "--add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NetCoreTools  --add Microsoft.VisualStudio.Workload.NetWeb --includeRecommended --passive --locale en-US" -y    
            $state.IsVisualStudioInstalled = $true
        }
        elseif ($visualStudioEdition.Trim() -eq "c") {
            choco install visualstudio2022community  --package-parameters "--add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NetCoreTools  --add Microsoft.VisualStudio.Workload.NetWeb --includeRecommended --passive --locale en-US" -y    
            $state.IsVisualStudioInstalled = $true
        }

        $state.IsVisualStudioInstalled = $true
        Save-State $state
    }
    
    # enable .net 3.5
    Write-ProgressHelper -Message "Verifying .Net Framework 3.5 Enabled" -StepNumber ($stepCounter++)
    if(!($state.IsDotNet35Enabled))
    {
        $dotNet35Status = Get-WindowsOptionalFeature -Online | Where-Object -FilterScript {$_.featurename -Like "*netfx3*"}
        if($dotNet35Status.State -ne "Enabled")
        {
            Write-SyncroStatus "Enabling .Net Framework 3.5"
            Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -Source "SourcePath"
            
            Write-SyncroStatus "You must restart your pc before continuing.  Pressing Enter will begin a system restart."
            Read-Host "Ready to restart your pc?"
            
            shutdown -r -t 3
            exit
        }
        
        $state.IsDotNet35Enabled = $true
        Save-State $state
    }
        
    # do remaining developer installs
    Write-ProgressHelper -Message "Verifying Development Tools Installed" -StepNumber ($stepCounter++)
    if(!($state.IsRemainingInstallsComplete))
    {
        Write-SyncroStatus "Running Chocolatey Installs."

        $chocoInstallsPath = Join-Path $state.GitWorkspacePath "kabuto-app\external\dev-setup\ChocolateyInstalls.json"
        Run-ChocolateyInstalls $chocoInstallsPath -y
        
        $state.IsRemainingInstallsComplete = $true
        Save-State $state
    }

    # dl and extract old .net developer packs
    Write-ProgressHelper -Message "Verifying Old .Net Developer Packs Installed" -StepNumber ($stepCounter++)
    if(!($state.IsOldDevPacksInstalled))
    {
        Write-SyncroStatus "Downloading and extracting old dev pack zip files."

        $destinationFolder = "C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\"
        Download-AndExtractZip "https://tc.aurelius.pw/redist/dotnet/v4.0.zip" $destinationFolder
        Download-AndExtractZip "https://tc.aurelius.pw/redist/dotnet/v4.5.zip" $destinationFolder   
        
        $state.IsOldDevPacksInstalled = $true
        Save-State $state
    }
    
    # ensure Nuget source exists
    Write-ProgressHelper -Message "Verifying Nuget Sources exist Installed" -StepNumber ($stepCounter++)
    if(!($state.IsNugetConfigured))
    {
        Write-SyncroStatus "Setting up default nuget sources."
        
        $nugetBody = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
<configuration>
  <packageSources>
    <add key=`"nuget.org`" value=`"https://api.nuget.org/v3/index.json`" protocolVersion=`"3`" />
  </packageSources>
</configuration>"
        
        $nugetPath = Join-Path $env:APPDATA "\NuGet\NuGet.Config"        
        $output = New-Item -ItemType File -Force -Path $nugetPath -Value $nugetBody
        
        $state.IsNugetConfigured = $true
        Save-State $state
    }
    
    # install wix
    Write-ProgressHelper -Message "Verifying Wix Installed" -StepNumber ($stepCounter++)
    if(!($state.IsWixInstalled) -or !(Is-Installed "wix"))
    {
        Write-SyncroStatus "Installing Wix"
            
        $wixExe = Download-File "https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311.exe"
        
        Write-Host "Wix Installer will load next.  Please note that you will need to install the VS plugin next (scripted)."
        Write-Host "You can find the installer in your Downloads folder, upon any failure."
                    
        Write-SyncroStatus "You will need to start Visual Studio for the first time before you can install wix and the wix extension"
        
        Read-Host "Press Enter once you have run and set up Visual Studio for the first time."
        
        Start-Process $wixExe

        Read-Host "Press Enter once you have installed wix from the installer."

        Install-Vsix "WixToolset.WixToolsetvisualstudio2022Extension"
                
        $state.IsWixInstalled = $true
        Save-State $state
    }   
            Write-SyncroStatus @"
            
        Congratulations! Dev machine setup complete!  
        Next steps:
         - Run Visual Studio and load the solution
         - Enter Telerik nuget credentials
         - Build project.
"@
