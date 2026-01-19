### 
### Describes application structure.
### Load module via `Import-Module $ScriptPath\Applications -ArugmentList "Debug|Release"
###

param(
	[String]$Configuration="Debug",
	[String]$SolutionPath = $SolutionRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module $ScriptPath\Common
# Import-Module $ScriptPath\Deploy -DisableNameChecking

## This is a block of configured applications that you can select to deploy
## The general concept here is that each object inside of $Applications is a separte app,
## denoted with a Package location and workflows based on the environment. For instance,
## Code inside of $Applications.SampleAppName.Environments.Production = { } is executed during the deployment to that environment
## and can include copying files, restarting services, or really whatever needs to be done

## TODO The website URLs should be pulled from something centralized instead

$Applications = @{
	Renterfull = @{
		AppType = "Web";
	    Package = Join-Path $SolutionPath "Web Applications\Renterfull";
        DomainName = "Renterfull.com";
        SubDomain = $null;        
		Environments = @{
			Production = 
			{ 
				Deploy-Site-New $Applications.Renterfull $Environments.Production.Web "Renterfull" 
				#Notify-NewRelic "Renterfull" "$env:BUILD_NUMBER"
				Ping-Website "https://www.Renterfull.com"	
			}
		};
	};
    Api = @{
        AppType = "Web";
        Package = Join-Path $SolutionPath "Web Applications\Api";
        DomainName = "Renterfull.com";
        SubDomain = "api";
        Environments = @{
			Production = 
			{ 
				Deploy-Site-New $Applications.Api $Environments.Production.Web "Renterfull" 
				#Notify-NewRelic "Api" "$env:BUILD_NUMBER"
				Ping-Website "https://api.Renterfull.com"	
			}
        };
    };
};

## This is a block of environments and the servers that make up that environment
## These environment definitions are all the same, but are configured so they can be adaptable 
## if we move non-prod environments to different machines. Since each machine in an "type", i.e. Web or MW,
## should have the same settings, we don't include information about what the file share path is or anything else

$Environments = @{
	Production = @{
	    Web = @("ServerName01", 
				"ServerName02");
	};    
};

Export-ModuleMember -Variable @('Applications')
