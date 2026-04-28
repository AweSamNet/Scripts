###  
### Commands for executing SmartThings api opperations
###

Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Import-Module $ScriptPath\Common -DisableNameChecking

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Edit-SmartThings
{
    notepad++ $(Join-Path $ScriptPath 'SmartThings.psm1')
}

function Get-SmartThingsCommands ([int]$columns = 3)
{
    $names = Get-Command -Module SmartThings | % { $_.Name }    
    Write-Table $names $columns
}

$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
$apiUri = "https://api.smartthings.com/"
$apiVersion = "v1"

$defaultWatchedTemperatureMonitors = Join-Path $ScriptPath "Watched\SmartThingsTemperatureMonitors.txt"
$defaultWatchedLocks = Join-Path $ScriptPath "Watched\SmartThingsLocks.txt"
$defaultWatchedLocksHistory = Join-Path $ScriptPath "Watched\SmartThingsLocksHistory\"
$defaultWatchedPiHoleQueryPath = Join-Path $ScriptPath "Watched\PiHoleQueries.txt"
$defaultWatchedRateLimits = Join-Path $ScriptPath "Watched\SmartThingsRateLimits.txt"

function GetSmartThingsToken()
{
    $token = ""
    $tokenPath = $(Join-Path $ScriptDir "smartthingskey.txt")

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
            Write-Host "No SmartThings Personal Access Token found.  Please enter your token now.  If you do not have one in SmartThings, you can create one here:"
            Write-Host "https://account.smartthings.com/tokens" -ForegroundColor Blue
        
            $userName = Read-Host -Prompt "Input SmartThings username"
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

function GetSmartThingsUri([Parameter(Mandatory=$true)][string]$partialUri, [string[]]$ArgumentList)
{
    $query = ""

    if($ArgumentList -and $ArgumentList.Count -gt 0)
    {
        $query += "?" + [string]::Join("+", $ArgumentList)
    }

    $path = New-Object Uri($apiUri + $apiVersion + "/")
    $path = New-Object Uri($path,$($partialUri + $query))

    return $path.ToString();
}

function SmartThingsGet(
    [Parameter(Mandatory=$true)][string]$partialUri, 
    [string[]]$ArgumentList, 
    [hashtable]$headers, 
    [string]$rateLimitType,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    SmartThingsRequest "GET" $partialUri $ArgumentList $headers $rateLimitType -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function SmartThingsPost(
    [Parameter(Mandatory=$true)][string]$partialUri, 
    [string[]]$ArgumentList, [hashtable]$headers, 
    [string]$rateLimitType, [string]$body,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    SmartThingsRequest "POST" $partialUri $ArgumentList $headers $rateLimitType $body -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function GetCredentials ()
{
    $token = GetSmartThingsToken
    $tokenSplit =  $token.Split(":")
    $username = $tokenSplit[0]
    $password = $tokenSplit[1]
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

    return @{
        Credential = New-Object System.Management.Automation.PSCredential($username, $(ConvertTo-SecureString $password -AsPlainText -Force))
        UserName = $username
        Password = $password
    }
}

function SendSmartThingsRequest(
    [Parameter(Mandatory=$true)][string]$method, 
    [Parameter(Mandatory=$true)][string]$partialUri, 
    [string[]]$ArgumentList, 
    [hashtable]$headers, 
    [string]$rateLimitType,
    [string]$body = $null,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{

    $credential = GetCredentials

    $rateLimits = @{}
    if($headers -eq $null)
    {
        $headers = @{}
    }
    $headers.Add("Authorization", "Bearer $($credential.Password)")
    
    # get rate limit if exists
    $rateLimit = {Get-WatchedSmartThingsRateLimits -watchedRateLimitsStorePath:$watchedRateLimitsStorePath}.Invoke() | where {
        $_.userName -eq $credential.UserName -and $_.rateLimitType -eq $rateLimitType
    } | select -First 1
   
    if($rateLimit)
    {
        # see if the wait time is over
        $resetDate = $rateLimit.dateRequested.AddMilliseconds($rateLimit.resetMilliseconds)
        
        if($resetDate -gt (Get-Date).ToUniversalTime() -and $rateLimit.remainingRequests -eq 1 )
        {
            WaitForRateLimit $resetDate $rateLimitType
        }
    }
    
    $uri = GetSmartThingsUri $partialUri $ArgumentList 
    
    $totalRetrySeconds = 0
    $retryDelay = 3
    $maxRetrySeconds = 60

    $response = $null
    $requestStart = [DateTime]::UtcNow
    
    do
    {
        try
        {
            # pause "Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -Credential $credential.Credential -Body:$body -UseBasicParsing"
            
            if($body)
            {
                $response = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -Credential $credential.Credential -Body:$body -UseBasicParsing
            }
            else
            {
                $response = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -Credential $credential.Credential -UseBasicParsing
            }
            
            WatchSmartThingsRateLimit `
                -userName $credential.UserName `
                -rateLimitType $rateLimitType `
                -dateRequested $response.Headers["Date"] `
                -remainingRequests $response.Headers["X-RateLimit-Remaining"] `
                -resetMilliseconds $response.Headers["X-RateLimit-Reset"]
               
            Write-HttpResponse $response $uri $rateLimitType $body

            break
        }
        catch
        {
            Write-Host "Caught Exception: $_"
            # if failure retry 
            $totalRetrySeconds += $retryDelay
            $retryTime = [DateTime]::UtcNow.AddSeconds($retryDelay)
            
            WaitForRetry $retryTime "Caught Exception: $_" "Waiting for retry"
            
            if(([DateTime]::UtcNow - $requestStart).TotalSeconds -ge $maxRetrySeconds)
            {
                throw
            }
        }
    } until(([DateTime]::UtcNow - $requestStart).TotalSeconds -ge $maxRetrySeconds)
    
    return $response
}

function SmartThingsRequest(
    [Parameter(Mandatory=$true)][string]$method, 
    [Parameter(Mandatory=$true)][string]$partialUri, 
    [string[]]$ArgumentList, 
    [hashtable]$headers, 
    [string]$rateLimitType,
    [string]$body = $null,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $response = SendSmartThingsRequest -method:$method `
                                       -partialUri:$partialUri `
                                       -ArgumentList:$ArgumentList `
                                       -headers:$headers `
                                       -rateLimitType:$rateLimitType `
                                       -body:$body `
                                       -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
                                       
    return (ConvertFrom-Json $response.Content)
}

$rateLimitTypes = @{
    Apps = "Apps"
    InstalledApps = "InstalledApps"
    Execution = "Execution"
    Locations = "Locations"
    Rooms = "Rooms"
    Subscriptions = "Subscriptions"
    Schedules = "Schedules"
    Devices = "Devices"
    DeviceProfiles = "DeviceProfiles"
    LocationModes = "LocationModes"
    Scenes = "Scenes"
    Commands = "Commands"
    Components = "Components"
}

Export-ModuleMember -Variable @('rateLimitTypes')

function WaitForRateLimit([Parameter(Mandatory=$true)][DateTime]$resetTime, [Parameter(Mandatory=$true)][string]$rateLimitType)
{
    WaitForRetry $resetTime "SmartThings rate limit exceeded." "Rate limit for $rateLimitType exceeded.  Waiting for reset."
}

function WaitForRetry(
    [Parameter(Mandatory=$true)][DateTime]$resetTime, 
    [Parameter(Mandatory=$true)][string]$activity,
    [Parameter(Mandatory=$true)][string]$status)
{
    $totalSecondsToWait = $($resetTime - [DateTime]::UtcNow).TotalSeconds
    
    while([DateTime]::UtcNow -lt $resetTime)
    {
        $secondsRemaining  = $($resetTime - [DateTime]::UtcNow).TotalSeconds

        Write-Progress -Id 999 -Activity $activity -Status $status `
            -SecondsRemaining $secondsRemaining `
            -PercentComplete ( ($totalSecondsToWait - $secondsRemaining) / $totalSecondsToWait * 100)
        Start-Sleep 1
    }    

    Write-Progress -Id 999 -Completed -Activity $activity -Status $status `
        -SecondsRemaining 0 `
        -PercentComplete 100
}

function Write-HttpResponse([Parameter(Mandatory=$true)]$response, [Parameter(Mandatory=$true)][string]$uri, [Parameter(Mandatory=$true)][string]$rateLimitType, [string]$body )
{
    $date = Get-Date
    $path = Join-Path $ScriptPath "Logs\$rateLimitType\$($date.Year)-$($date.Month)\$($date.Year)-$($date.Month)-$($date.Day)-$rateLimitType.log"
    try
    {
        $log = {Get-JsonFromFile $path}.Invoke()

        $logEntry = @{
            "uri" = $uri
            "statusCode" = $response.StatusCode
            "headers" = $response.Headers
            "content" = $response.Content
            "requestBody" = $body
        }

        $log.Add($logEntry)

        $body = ConvertTo-Json $log -Depth 10
        $output = New-Item -ItemType File -Force -Path $path -Value $body
    }
    catch
    {
        Write-Error "Cannot write rateLimit for $uri, $rateLimitType"
        throw $_
    }
}


function WatchSmartThingsRateLimit(
    [Parameter(Mandatory=$true)][string]$userName,
    [Parameter(Mandatory=$true)][string]$rateLimitType,
    [Parameter(Mandatory=$true)][DateTime]$dateRequested,
    [Parameter(Mandatory=$true)][int]$remainingRequests,
    [Parameter(Mandatory=$true)][long]$resetMilliseconds,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits
    
)
{
    $newRateToWatch = @{
        "userName" = $userName
        "rateLimitType" = $rateLimitType
        "dateRequested" = $dateRequested
        "remainingRequests" = $remainingRequests
        "resetMilliseconds" = $resetMilliseconds
    }    
    
    $list = {Get-WatchedSmartThingsRateLimits $watchedRateLimitsStorePath}.Invoke()
    
    # see if this rate limit exists, and if it does remove it so we can replace it.
    $toRemove  = $list | where { 
        $_ `
        -and $_.userName -eq $userName `
        -and $_.rateLimitType -eq $rateLimitType
    } | select -First 1

    if($toRemove)
    {
        $success = $list.Remove($toRemove)
    }

    $list.Add($newRateToWatch)

    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $watchedRateLimitsStorePath -Value $body
}

function Get-WatchedSmartThingsRateLimits([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    Get-JsonFromFile $watchedRateLimitsStorePath
}

function Get-SmartThingsLocations([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    (SmartThingsGet "locations" -rateLimitType:$rateLimitTypes.Locations -watchedRateLimitsStorePath:$watchedRateLimitsStorePath).items
}

function Get-SmartThingsDevices([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    (SmartThingsGet "devices" -rateLimitType:$rateLimitTypes.Devices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath).items
}

function Get-SmartThingsRooms([Parameter(Mandatory=$true)][string]$locationId, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    (SmartThingsGet "locations/$locationId/rooms" -rateLimitType:$rateLimitTypes.Rooms -watchedRateLimitsStorePath:$watchedRateLimitsStorePath).items
}

function Get-SmartThingsDevice([Parameter(Mandatory=$true)][string]$deviceId, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    (SmartThingsGet "devices/$deviceId" -rateLimitType:$rateLimitTypes.Devices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath)
}

function Get-SmartThingsDeviceStatus([Parameter(Mandatory=$true)][string]$deviceId, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    (SmartThingsGet "devices/$deviceId/status" -rateLimitType:$rateLimitTypes.Devices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath)
}

function Get-SmartThingsDeviceHealth([Parameter(Mandatory=$true)][string]$deviceId, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    (SmartThingsGet "devices/$deviceId/health" -rateLimitType:$rateLimitTypes.Devices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath)
}

function Get-SmartThingsComponentStatus(
    [Parameter(Mandatory=$true)][string]$deviceId, 
    [Parameter(Mandatory=$true)][string]$componentId, 
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    SmartThingsGet "devices/$deviceId/components/$componentId/status" -rateLimitType:$rateLimitTypes.Components -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function Get-SmartThingsCapabilityStatus(
    [Parameter(Mandatory=$true)][string]$deviceId, 
    [Parameter(Mandatory=$true)][string]$componentId, 
    [Parameter(Mandatory=$true)][string]$capabilityId, 
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    SmartThingsGet "devices/$deviceId/components/$componentId/capabilities/$capabilityId/status" -rateLimitType:$rateLimitTypes.Components -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function ChooseSmartThingsLock([string[]]$excludeIds = $null, 
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $devices = @()
    Get-SmartThingsDevices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath | where { ($_.type -eq "DTH" -and $_.deviceTypeName -contains "Z-Wave Lock") -or ($_.components[0].categories | any {$_.name -eq "SmartLock"})} | Sort-Object label | % { $devices += $_ }

    if($excludeIds)
    {
        Write-Host "Excluding $excludeIds"
        $filtered = @()
        $devices | where { -not $excludeIds.Contains($_.deviceId) } | % { $filtered += $_ }
        $devices = $filtered
    }
    
    $locations = Get-SmartThingsLocations -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    
    $rooms = $locations | % {
        Get-SmartThingsRooms $_.locationId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    }
    
    $selectedDevice = $null
        
    do{
        displayDeviceStatuses $locations $rooms $devices -displayIndex
       
        Write-Host "[$($devices.Count)] Cancel"
        
        $answer = Read-Host "Select a lock"
        
        if(-not ($answer -match '^[0-9]+$') -or (0 -gt $answer -or $answer -gt $devices.Count ))
        {
            continue
        }

        if($answer -eq $devices.Count)
        {
            return
        }
        
        $selectedDevice = $devices[$answer]
        
    } while (-not $selectedDevice)
    
    return $selectedDevice
}

function Set-SmartThingsLockCode([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $codeName = Read-Host "Who will use this code?"
    
    $addAnotherCode = "y"
    
    $codes = @{}

    while ($addAnotherCode -eq "y")
    {
        $selectedDevice = ChooseSmartThingsLock -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        
        if(-not $selectedDevice){
            return
        }
        
        $componentStatus = Get-SmartThingsComponentStatus $selectedDevice.deviceId $selectedDevice.components[0].id -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
            
        $code = $codes[$componentStatus.lockCodes.codeLength.value]

        if($code)
        {
            do{
                $reuseCode = Read-Host "Do you still want to use the code: $($code)? [y/n]"
            } while (-not($reuseCode -match "[yn]"))
            
            if($reuseCode -match "n")
            {
                $code = $null
            }
        }
        
        if(-not $code)
        {
            do {
                $code = Read-Host "Enter a $($componentStatus.lockCodes.codeLength.value) digit numeric code" 
            } while (-not($code -match "^\d{$($componentStatus.lockCodes.codeLength.value)}$"))
            
            $codes[$componentStatus.lockCodes.codeLength.value] = $code
        }
        
        # figure out the next ID to use
        $nextId = 0
        $ids = (ConvertFrom-Json $componentStatus.lockCodes.lockCodes.value).psobject.properties | Sort-Object Name | % { $_.Name }
        
        for($i = 1; $i -le $componentStatus.lockCodes.maxCodes.value; $i++)
        {
            if(-not($ids) -or -not($ids.Contains($i.ToString())))
            {
                $nextId = $i
                break
            }
        }

        # create a post for commands
        $body = @{
            "commands" = 
                @(@{
                    "component" = $selectedDevice.components[0].id
                    "capability" = "lockCodes"
                    "command" = "setCode"
                    "arguments" = @($nextId, $code, $codeName)
                })
        }

        SmartThingsPost "devices/$($selectedDevice.deviceId)/commands" -body (ConvertTo-Json $body -Depth 3) -rateLimitType $rateLimitTypes.Commands -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        
        $addAnotherCode = Read-Host "Would you like to add this code to another device?[y/n]" 
    }
}

function displayLockCodes(    
    $codes, 
    [int]$startingCount = 0
){
    $codeCount = $startingCount
    
    foreach ($code in $codes)
    {
        Write-Host "[$codeCount] $($code.Value) ($($code.Name))"
        $codeCount++
    }    
}

function displayDeviceStatus(
    $location,
    $room,
    $device)
{
    $status = Get-SmartThingsComponentStatus $device.deviceId $device.components[0].id

    Write-Host "$($device.label) ($($location.name) - $($room.name)" -NoNewline
    
    if(HasProperty $status 'lock')
    {
        Write-Host " [" -NoNewline
        Write-Host $status.lock.lock.value -NoNewline -ForegroundColor (iif ($status.lock.lock.value -ne "locked") "Red" "Green")
        Write-Host "]" -NoNewline
    }
    
    Write-Host ")"
}

function displayDeviceStatuses(
    $locations,
    $rooms,
    $devices,
    [switch]$displayIndex)
{
    $deviceCount = 0
    foreach($device in $devices)
    {
        if(HasProperty $device 'roomId')
        {
            $room = $rooms | where { $_.roomId -eq $device.roomId } | select -First 1
        }
        else     
        {
            $room = @{
                name = '[No room assigned]'
            }
        }
        
        $location = $locations | where { $_.locationId -eq $device.locationId } | select -First 1
        
        if($displayIndex)
        {
            Write-Host "[$($deviceCount)] " -NoNewline
        }

        displayDeviceStatus $location $room $device -displayIndex:$displayIndex
        
        $deviceCount++
    }
}

function Get-SmartThingsLockCodes(
    [string]$deviceId, 
    [string]$componentId, 
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits,
    [switch]$all)

{  
    if($all)
    {
        $done = $false
        $locations = Get-SmartThingsLocations -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        $rooms = $locations | % {
            Get-SmartThingsRooms $_.locationId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        }

        while (-not $done) {    
            $allCodes = @();
            $deviceCount = 0
            
            # get all device ids        
            $devices = Get-SmartThingsDevices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath | where { ($_.type -eq "DTH" -and $_.deviceTypeName -contains "Z-Wave Lock") -or ($_.components[0].categories | any {$_.name -eq "SmartLock"})} | Sort-Object label

            foreach ($device in $devices)
            {
                $room = $rooms | where { $_.roomId -eq $device.roomId } | select -First 1
                $location = $locations | where { $_.locationId -eq $device.locationId } | select -First 1

                displayDeviceStatus $location $room $device
            
                # get lock codes
                $codes = Get-SmartThingsLockCodes $device.deviceId $device.components[0].id -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
            
                displayLockCodes $codes $allCodes.Count
                
                $allCodes += $codes | %{
                    return @{
                        "deviceId" = $device.deviceId
                        "componentId" = $device.components[0].id
                        "code" = $_
                    }
                }
                
                Write-Host
            }

            $esc = "$([char]27)"
           
            Write-Host "[$esc[91mr$esc[0m] Remove codes"
            Write-Host "[$esc[92ma$esc[0m] Add codes"
            Write-Host "[any key] Cancel"
            $answer = Read-Host "What would you like to do?"
            
            if($answer -match "r")
            {        
                $answer = Read-Host "Which code would you like to remove?"
                
                if(-not ($answer -match '^[0-9]+$') -or (0 -gt [int]$answer -or [int]$answer -gt $allCodes.Count ))
                {
                    continue
                }

                if($answer -eq $allCodes.Count)
                {
                    $done = $true
                    return
                }
                
                $selectedCode = $allCodes[$answer]
    
                $response = removeLockCode $selectedCode.deviceId $selectedCode.componentId $selectedCode.code.Name $watchedRateLimitsStorePath                
            }
            elseif($answer -match "a")
            {
                Set-SmartThingsLockCode $watchedRateLimitsStorePath
            }
            else 
            {
                $done = $true
                return
            }
        }
    }
    else{
        $componentStatus = Get-SmartThingsComponentStatus $deviceId $componentId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        
        return (ConvertFrom-Json $componentStatus.lockCodes.lockCodes.value).psobject.properties | Sort-Object Name
    }
}

function Get-SmartThingsLockCode(
    [Parameter(Mandatory=$true)][string]$deviceId, 
    [Parameter(Mandatory=$true)][string]$componentId, 
    [Parameter(Mandatory=$true)][string]$codeId, 
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits
)
{
    return Get-SmartThingsLockCodes $deviceId $componentId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath | where { $_.Name -eq $codeId } | select -First 1
}

function ChooseSmartThingsLockCode(
    [Parameter(Mandatory=$true)][string]$deviceId, 
    [Parameter(Mandatory=$true)][string]$componentId, 
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $codes = Get-SmartThingsLockCodes $deviceId $componentId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath

    do
    {
        displayLockCodes $codes
        
        Write-Host "[$($codes.Count)] Cancel"
        $answer = Read-Host "Select a code to remove"
        
        if(-not $answer){
            return $null
        }
        
        if(-not ($answer -match '^[0-9]+$') -or (0 -gt [int]$answer -or [int]$answer -gt $codes.Count ))
        {
            continue
        }

        if($answer -eq $codes.Count)
        {
            return $null
        }
        
        $selectedCode = $codes[$answer]
    } while (-not $selectedCode)
    
    return $selectedCode
}

function Remove-SmartThingsLockCode([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $selectedDevice = ChooseSmartThingsLock -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    if(-not $selectedDevice)
    {
        return
    }

    $selectedCode = ChooseSmartThingsLockCode $selectedDevice.deviceId $selectedDevice.components[0].id -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    
    if(-not $selectedCode)
    {
        return
    }
    
    $codeName = $selectedCode.Name
    $componentId = $selectedDevice.components[0].id
    
    removeLockCode $selectedDevice.deviceId $componentId $codeName $watchedRateLimitsStorePath
}

function removeLockCode($deviceId, $componentId, $codeName, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    # create a post for commands
    $body = @{
        "commands" = 
            @(@{
                "component" = $componentId
                "capability" = "lockCodes"
                "command" = "deleteCode"
                "arguments" = @([int]$codeName)
            })
    }    

    SmartThingsPost "devices/$($deviceId)/commands" -body (ConvertTo-Json $body -Depth 3) -rateLimitType $rateLimitTypes.Commands -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function Lock-SmartThingsLock([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $selectedDevice = ChooseSmartThingsLock -watchedRateLimitsStorePath:$watchedRateLimitsStorePath  
    if(-not $selectedDevice)
    {
        return
    }
    
    # create a post for commands
    $body = @{
        "commands" = 
            @(@{
                "component" = $selectedDevice.components[0].id
                "capability" = "lock"
                "command" = "lock"
                "arguments" = @()
            })
    }    

    SmartThingsPost "devices/$($selectedDevice.deviceId)/commands" -body (ConvertTo-Json $body -Depth 3) -rateLimitType $rateLimitTypes.Commands -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function Unlock-SmartThingsLock([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $selectedDevice = ChooseSmartThingsLock -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    if(-not $selectedDevice)
    {
        return
    }    
    
    # create a post for commands
    $body = @{
        "commands" = 
            @(@{
                "component" = $selectedDevice.components[0].id
                "capability" = "lock"
                "command" = "unlock"
                "arguments" = @()
            })
    }    

    SmartThingsPost "devices/$($selectedDevice.deviceId)/commands" -body (ConvertTo-Json $body -Depth 3) -rateLimitType $rateLimitTypes.Commands -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
}

function Clear-WatchedSmartThingsRateLimits([string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    if(Test-Path $watchedRateLimitsStorePath)
    {
        rm $watchedRateLimitsStorePath
    }
}

# text coloring ASCII: https://powershell.org/forums/topic/how-to-use-ansi-vt100-formatting-in-powershell-ooh-pretty-colors/
function Get-DeviceBatteryStatus($device)
{
    $esc = "$([char]27)"
    return $(IIF $($device.Battery -gt 50) $("$esc[92m") `
                $(IIF $($device.Battery -gt 15) $("$esc[93m") `
                $(IIF $($device.Battery -gt 0) $("$esc[91m") ""`
                    ))) + "$($device.Battery)$esc[0m"
}

function Get-DeviceTemperature($device)
{
    $esc = "$([char]27)"
    $temp = $device.Data.Data.temperatureMeasurement.temperature.value
    return $(IIF $($temp -le 5) $("$esc[96m")  "") + "$temp$esc[0m"
}

function Get-DeviceHumidity($device)
{
    if(-not( HasProperty $device.Data.Data 'relativeHumidityMeasurement')){
        return "[N/A]"
    }

    $esc = "$([char]27)"
    $humidity = $device.Data.Data.relativeHumidityMeasurement.humidity.value
    $unit = $device.Data.Data.relativeHumidityMeasurement.humidity.unit
    
    return $(IIF $($humidity -lt 30) $("$esc[93m") `
            $(IIF $($humidity -gt 50) $("$esc[96m") `
                $("$esc[92m")
                )) + "$humidity$unit$esc[0m"
}

function Format-WatchedSmartThingsLocks($devices)
{
    $esc = "$([char]27)"

    return $devices | %{
        [PSCustomObject]@{
            Label = $_.Label;
            Battery = Get-DeviceBatteryStatus $_            
            Status = IIF $($_.Status -eq 'locked') $("$esc[92m$($_.Status)$esc[0m") $("$esc[91m$($_.Status)$esc[0m");
            LastReportedOn = IIF $($_.LastReportedDate -ne $null) $(Convert-UTCtoLocal $_.LastReportedDate) $null
            State = $(IIF $($_.State -eq 'OFFLINE') $("$esc[91m") `
                $(IIF $($_.State -eq 'ONLINE') $("$esc[92m") "")) + "$($_.State)$esc[0m"
        }
    } | Format-Table -AutoSize
}

function Get-WatchedSmartThingsLocks( 
    [string]$watchedLocksStorePath = $defaultWatchedLocks,
    [switch]$status)
{
    $devices = Get-JsonFromFile $watchedLocksStorePath
    $esc = "$([char]27)"
    if($status){
        return Format-WatchedSmartThingsLocks $devices
    }
    
    return $devices
}

function Watch-SmartThingsLock([string] $watchedLocksStorePath = $defaultWatchedLocks, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $list = {Get-WatchedSmartThingsLocks $watchedLocksStorePath}.Invoke()
    
    $id = iif $list { ($list | measure -Property Id -Maximum).maximum + 1 } 1
    $excludeIds = $list | % { $_.DeviceId }
    $device = ChooseSmartThingsLock -excludeIds:$excludeIds -watchedRateLimitsStorePath:$watchedRateLimitsStorePath

    if(-not $device){
        return
    }
    
    $date = Get-Date
    
    $toWatch = @{
        Id = $id;
        DeviceId = $device.deviceId;
        ComponentId = $device.components[0].id;
        Status = $null;
        Data = @{ Data = $null };
        RoomId = $device.roomId;
        LocationId = $device.locationId;
        Label = $device.label;
        Battery = 0;
        LastReportedDate = $date;
    }
    
    $list.Add($toWatch)
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $watchedLocksStorePath -Value $body
    Get-WatchedSmartThingsLocks $watchedLocksStorePath
}

function Clear-WatchedSmartThingsLock([string]$watchedLocksStorePath = $defaultWatchedLocks)
{
    if(Test-Path $watchedLocksStorePath)
    {
        rm $watchedLocksStorePath
    }
}

#INCOMPLETE
function Create-MonthLockHistoryFile([DateTime]$date, $watchedLocksHistoryPath=$defaultWatchedLocksHistory)
{
    # if the directory doesn't exist, create it
    if (-not (Test-Path $watchedLocksHistoryPath))
    {
        $output = New-Item -ItemType Directory -Force -Path $watchedLocksHistoryPath 
    }
    
    if($date -eq $null)
    {
        $date = Get-Date -Format "yyyy-MM"
    }

    # create this month's file
    $fileName = "$date.txt"
    $path = Join-Path $watchedLocksHistoryPath $fileName
    $output = New-Item -ItemType File -Force -Path $path 
}

function Get-WatchedSmartThingsLockHistory($id, [Nullable[DateTime]]$from, [Nullable[DateTime]]$to=$null, $watchedLocksHistoryPath=$defaultWatchedLocksHistory)
{
    $watchedLocksHistoryPath = Join-Path $watchedLocksHistoryPath $id
    $files = Get-ChildItem -Path $watchedLocksHistoryPath

    # determine the month files to get
    if ($files -eq $null)
    {
        return $null
    }
    
    $history = @()
    #loop through the files and only keep the ones we want
    $regex = '(?<filedate>\d{4}(?:\.|-|_)?\d{2})[^0-9]'
    $files | where {
        
        # get year and month from file name
        if($_.Name -match $regex)
        {
            $nameDate = Get-Date $Matches[0]
            if((!$from -or $from -le $nameDate) -and (!$to -or $nameDate -le $to))
            {
                $fileHistory = Get-JsonFromFile $_.FullName
                
                if((any {$fileHistory}) -and ($to -and $fileHistory[0].date -gt $to))
                {
                    $fileHistory = $fileHistory | where {(!$from -or $from -le $_.date) -and (!$to -or $_.date -le $to)}
                }
                $history = @($fileHistory) + $history
            }
        }
    }

    return $history
}

function Set-WatchedSmartThingsLockHistory($id, [DateTime]$date, [Array]$history, $watchedLocksHistoryPath=$defaultWatchedLocksHistory)
{
    $idPath = Join-Path $watchedLocksHistoryPath $id
    $monthPath = Join-Path $idPath "$($date.ToString('yyyy-MM')).txt"
    
    if (-not (Test-Path $idPath))
    {
        $output = New-Item -ItemType Directory -Force -Path $idPath 
    }

    $body = ConvertTo-Json $history -Depth 10
    $output = New-Item -ItemType File -Force -Path $monthPath -Value $body
}

function Split-SmartThingsLocksHistory($watchedLocksStorePath=$defaultWatchedLocks, $watchedSmartThingsLocksHistoryPath=$defaultWatchedLocksHistory)
{
    #get all devices
    $watchedLocks = Get-WatchedSmartThingsLocks -watchedLocksStorePath:$watchedLocksStorePath
    
    foreach($watchedLock in $watchedLocks)
    {
        #get or create ID directory
        $idPath = Join-Path $watchedSmartThingsLocksHistoryPath $watchedLock.Id
        
        if (-not (Test-Path $idPath))
        {
            $output = New-Item -ItemType Directory -Force -Path $idPath 
        }
        
        $date = $null
        $historyGroup = @()
        
        #loop through the history and create the files as needed
        foreach($entry in $watchedLock.History)
        {
            if($entry.date -isnot [DateTime])
            {
                continue
            }
            
            #if the month  is different from the previous month, write the previous month
            if($date -ne $null -and( $entry.date -eq $null -or $entry.date.Year -ne $date.Year -or $entry.date.Month -ne $date.Month ))
            {
                $monthPath = Join-Path $idPath "$($date.ToString('yyyy-MM')).txt"
                
                $body = ConvertTo-Json $historyGroup -Depth 10
                $output = New-Item -ItemType File -Force -Path $monthPath -Value $body
                
                $historyGroup = @()                
            }
            
            if($entry.date -ne $null)
            {
                $date = $entry.date
            }
            $historyGroup += $entry
        }
        
        $watchedLock.History = $null
        
        if($date -ne $null)
        {
            $monthPath = Join-Path $idPath "$($date.ToString('yyyy-MM')).txt"

            $body = ConvertTo-Json $historyGroup -Depth 10
            $output = New-Item -ItemType File -Force -Path $monthPath -Value $body
        }
    }
    
    $body = ConvertTo-Json $watchedLocks -Depth 10
    $output = New-Item -ItemType File -Force -Path $watchedLocksStorePath -Value $body
}

function Watch-SmartThingsLocks($locations, $rooms, $watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $deviceChanges = @()
    $watchedLocks = Get-WatchedSmartThingsLocks -watchedLocksStorePath:$watchedLocksStorePath
    
    foreach($watchedLock in $watchedLocks)
    {
        $recent = Get-SmartThingsComponentStatus $watchedLock.DeviceId $watchedLock.ComponentId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        
        $jsonData = ConvertTo-Json $recent.lock.lock.data -Depth 10
        
        $data = @{
            "Data" = $recent.lock.lock.data
        }
        
        $date = Get-Date
        $watchedLock.LastReportedDate = $date

        $location = $locations | where { $_.locationId -eq $watchedLock.LocationId } | select -First 1
        $room = $rooms | where { $_.roomId -eq $watchedLock.RoomId } | select -First 1
        
        # get devices history
        
        
        if($recent.lock.lock.value -ne $watchedLock.Status -or($jsonData -ne (ConvertTo-Json $watchedLock.Data.Data -Depth 10)))
        {
            $code = $null
            # if the data contains the codeId then also add the name
            if($jsonData -match "codeId")
            {
                
                $codeId = $recent.lock.lock.data.codeId
                $code = Get-SmartThingsLockCode $watchedLock.DeviceId $watchedLock.ComponentId $codeId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath

                if($code)
                {
                    $data = @{
                        "Name" = $code.Value
                        "Data" = $recent.lock.lock.data
                    }
                }
            }
        
            #create a history entry
            $newHistory = @{ 
                date = $date;
                log = "Changed: $($recent.lock.lock.value) - $(ConvertTo-Json $data)"
            }
            
            $watchedLock.Status = $recent.lock.lock.value
            $watchedLock.Data = $data
            
            # get history file 
            $fileDate = Get-Date -Format "yyyy-MM"
            $history = Get-WatchedSmartThingsLockHistory $watchedLock.Id $fileDate            
            
            $history = ,$newHistory + $history

            Set-WatchedSmartThingsLockHistory $watchedLock.Id $fileDate $history
            
            $message = ""
            if($code)
            {
                $message += "$($code.Value) - "
            }

            $message += "$($recent.lock.lock.value) - $($watchedLock.Label) ($($location.name) - $($room.name))"
            $deviceChanges += @{
                Severity = [NotificationSeverity]::Low;
                Message = $message;
            }
        }
        
        #check the status of the battery
        if($recent.battery.battery.value -ne $watchedLock.Battery)
        {
            $watchedLock.Battery = $recent.battery.battery.value            
            if($recent.battery.battery.value -lt 10)
            {
                $deviceChanges += @{
                    Severity = [NotificationSeverity]::Medium;
                    Message = "Low Battery: $($recent.battery.battery.value) on $($watchedLock.Label) ($($location.name) - $($room.name))";
                }
            }
        }
        
        #check health of the device
        $healthWarnings = CheckDeviceHealth $watchedLock -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        if($healthWarnings -ne $null)
        {
            $deviceChanges += $healthWarnings
        }
    }

    $body = ConvertTo-Json $watchedLocks -Depth 10
    $output = New-Item -ItemType File -Force -Path $watchedLocksStorePath -Value $body
    
    return $deviceChanges

}

function CheckDeviceHealth($watchedDevice, $watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    #check health of the device
    $deviceHealth = Get-SmartThingsDeviceHealth $watchedDevice.DeviceId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    if(-not( HasProperty $watchedDevice "State"))
    {
        Add-Member -InputObject $watchedDevice -NotePropertyName "State" -NotePropertyValue $null
    }
    
    if(-not( HasProperty $watchedDevice "LastUpdatedDate"))
    {
        Add-Member -InputObject $watchedDevice -NotePropertyName "LastUpdatedDate" -NotePropertyValue $null
    }
    
    if($watchedDevice.LastUpdatedDate -ne $deviceHealth.lastUpdatedDate)
    {
        $watchedDevice.LastUpdatedDate = $deviceHealth.lastUpdatedDate
    }

    if($deviceHealth.state -ne $watchedDevice.State)
    {
        $watchedDevice.State = $deviceHealth.state
        if($deviceHealth.state -ne "ONLINE")
        {

            return @{
                Severity = [NotificationSeverity]::High;
                Message = "Device $($deviceHealth.state): $($watchedDevice.Label) ($($location.name) - $($room.name))";
            }
        }
    }
    return $null
}

function ChooseSmartThingsTemperatureMonitors([string[]]$excludeIds = $null,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $devices = Get-SmartThingsDevices -watchedRateLimitsStorePath:$watchedRateLimitsStorePath | where {
        $_.components | where {
            $_.capabilities | where { $_.id -eq 'temperatureMeasurement' }
        }
    } | Sort-Object label
    
    if($excludeIds)
    {
        Write-Host "Excluding $excludeIds"
        $devices = $devices | where { -not $excludeIds.Contains($_.deviceId) }
    }

    $locations = Get-SmartThingsLocations -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    
    $rooms = $locations | % {
        Get-SmartThingsRooms $_.locationId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    }
    
    $selectedDevice = $null
        
    do{
        displayDeviceStatuses $locations $rooms $devices -displayIndex
       
        Write-Host "[$(@($devices).Count)] Cancel"
        
        $answer = Read-Host "Select a temoerature monitor"
        
        if(-not ($answer -match '^[0-9]+$') -or (0 -gt $answer -or $answer -gt @($devices).Count ))
        {
            continue
        }

        if($answer -eq @($devices).Count)
        {
            return
        }
        
        $selectedDevice = $devices[$answer]
        
    } while (-not $selectedDevice)
    
    return $selectedDevice
}


function Format-WatchedSmartThingsTemperatureMonitors($devices)
{
    $esc = "$([char]27)"

    return  $devices = $devices | Sort-Object Label | %{
        $mode = "[N/A]"
        $setpoint = "[N/A]"

        if(HasProperty $_.Data.Data 'thermostat')
        {
            $mode = $_.Data.Data.thermostat.thermostatMode.value
        }
        
        if($mode -eq 'heat')
        {            
            if(HasProperty $_.Data.Data 'thermostat')
            {
                $setpoint = $_.Data.Data.thermostat.heatingSetpoint.value
            }
        }
        elseif(HasProperty $_.Data.Data 'thermostatHeatingSetpoint')
        {
            $setpoint = $_.Data.Data.thermostatHeatingSetpoint.heatingSetpoint.value
        }

        elseif($mode -eq 'cool')
        {            
            if(HasProperty $_.Data.Data 'thermostat')
            {
                $setpoint = $_.Data.Data.thermostat.coolingSetpoint.value
            }
        }
        elseif(HasProperty $_.Data.Data 'thermostatCoolingSetpoint')
        {
            $setpoint = $_.Data.Data.thermostatCoolingSetpoint.coolingSetpoint.value
        }
        
        [PSCustomObject]@{
            Label = $_.Label;
            Battery = Get-DeviceBatteryStatus $_
            CurrentHumidity = Get-DeviceHumidity $_
            CurrentTemp = Get-DeviceTemperature $_
            CurrentMode = $(IIF $($mode -eq 'heat') $("$esc[91m") `
                $(IIF $($mode -eq 'cool') $("$esc[96m") "")) + "$mode$esc[0m"
            
            CurrentSetpoint = $setpoint
            
            LastReportedOn = IIF $($_.LastReportedDate -ne $null) $(Convert-UTCtoLocal $_.LastReportedDate) $null
            State = $(IIF $($_.State -eq 'OFFLINE') $("$esc[91m") `
                $(IIF $($_.State -eq 'ONLINE') $("$esc[92m") "")) + "$($_.State)$esc[0m"

        }
    } | Format-Table -AutoSize
}

function Get-WatchedSmartThingsTemperatureMonitors( 
    [string]$watchedTemperatureMonitorsStorePath = $defaultWatchedTemperatureMonitors,
    [switch]$status)
{
    $devices = Get-JsonFromFile $watchedTemperatureMonitorsStorePath
    if($status){     
        return Format-WatchedSmartThingsTemperatureMonitors $devices
    }
    
    return $devices
}

function Watch-SmartThingsTemperatureMonitor([string] $watchedTemperatureMonitorsStorePath = $defaultWatchedTemperatureMonitors, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $list = {Get-WatchedSmartThingsTemperatureMonitors $watchedTemperatureMonitorsStorePath}.Invoke()
    
    $id = iif $list { ($list | measure -Property Id -Maximum).maximum + 1 } 1
    $excludeIds = $list | % { $_.DeviceId }
    $device = ChooseSmartThingsTemperatureMonitors -excludeIds:$excludeIds -watchedRateLimitsStorePath:$watchedRateLimitsStorePath

    if(-not $device){
        return
    }
    
    $date = Get-Date
    
    $toWatch = @{
        Id = $id;
        DeviceId = $device.deviceId;
        ComponentId = $device.components[0].id;
        Data = @{ Data = $null };
        RoomId = $device.roomId;
        LocationId = $device.locationId;
        Label = $device.label;
        Battery = 0;
        LastReportedDate = $date;
        LowestOutdoorTemperature = $null;
        LowestOutdoorTemperatureDate = $null;
        HighestOutdoorTemperature = $null;
        HighestOutdoorTemperatureDate = $null;
        LowestIndoorTemperature = $null;
        LowestIndoorTemperatureDate = $null;
        HighestIndoorTemperature = $null;
        HighestIndoorTemperatureDate = $null;
    }
    
    $list.Add($toWatch)
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $watchedTemperatureMonitorsStorePath -Value $body
    Get-WatchedSmartThingsTemperatureMonitors $watchedTemperatureMonitorsStorePath
}

function Clear-WatchedSmartThingsTemperatureMonitors([string]$watchedTemperatureMonitorsStorePath = $defaultWatchedTemperatureMonitors)
{
    if(Test-Path $watchedTemperatureMonitorsStorePath)
    {
        rm $watchedTemperatureMonitorsStorePath
    }
}

function Watch-SmartThingsTemperatureMonitors($locations, $rooms, 
    [string]$watchedTemperatureMonitorsStorePath = $defaultWatchedTemperatureMonitors,
    [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $deviceChanges = @()

    $devices = Get-WatchedSmartThingsTemperatureMonitors -watchedTemperatureMonitorsStorePath:$watchedTemperatureMonitorsStorePath
    
    foreach($device in $devices)
    {
        $recent = Get-SmartThingsComponentStatus $device.DeviceId $device.ComponentId -watchedRateLimitsStorePath:$watchedRateLimitsStorePath       
        
        $date = Get-Date
        $device.LastReportedDate = $date

        $jsonData = ConvertTo-Json $recent -Depth 10
        
        $data = @{
            "Data" = $recent
        }
        
        $location = $locations | where { $_.locationId -eq $device.LocationId } | select -First 1
        $room = $rooms | where { $_.roomId -eq $device.RoomId } | select -First 1           

        # if indoor temp is lower than the lowest, then record it.
        if($device.LowestIndoorTemperature -eq $null -or $device.LowestIndoorTemperature -ge $recent.temperatureMeasurement.temperature.value)
        {
            $device.LowestIndoorTemperature = $recent.temperatureMeasurement.temperature.value
            $device.LowestIndoorTemperatureDate = $recent.temperatureMeasurement.temperature.timestamp
        }
            
        # if indoor temp is higher than the highest, then record it.
        if($device.HighestIndoorTemperature -eq $null -or $device.HighestIndoorTemperature -le $recent.temperatureMeasurement.temperature.value)
        {
            $device.HighestIndoorTemperature = $recent.temperatureMeasurement.temperature.value
            $device.HighestIndoorTemperatureDate = $recent.temperatureMeasurement.temperature.timestamp
        }
        $device.Data = $data

        $message = ""
        $message += "$($device.Label) ($($location.name) - $($room.name))"

        # if the temperature is dangerous alert        
        if($recent.temperatureMeasurement.temperature.value -le 5)
        {
            $deviceChanges += @{
                Severity = [NotificationSeverity]::High;
                Message = "Temp very low for $message`: $recent.temperatureMeasurement.temperature.value"
            }
        }
        
        #check the status of the battery
        if(HasProperty $recent 'battery')
        {
            if($recent.battery.battery.value -ne $device.Battery)
            {
                $device.Battery = $recent.battery.battery.value            
                
                if($recent.battery.battery.value -lt 10)
                {
                    $deviceChanges += @{
                        Severity = [NotificationSeverity]::Medium;
                        Message = "Low Battery: $($recent.battery.battery.value) on $message"
                    }
                }
            }
        }
        else
        {
            $device.Battery = "[N/A]"
        }
       
        #check health of the device
        $healthWarnings = CheckDeviceHealth $device -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
        if($healthWarnings -ne $null)
        {
            $deviceChanges += $healthWarnings
        }
    }

    $body = ConvertTo-Json $devices -Depth 10
    $output = New-Item -ItemType File -Force -Path $watchedTemperatureMonitorsStorePath -Value $body
    
    return $deviceChanges

}

function Watch-SmartThings([string]$watchedLocksStorePath = $defaultWatchedLocks, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $deviceChanges = @()
    
    $locations = Get-SmartThingsLocations -watchedRateLimitsStorePath:$watchedRateLimitsStorePath

    $rooms = $locations | % {
        Get-SmartThingsRooms $_.locationId
    }

    $deviceChanges += @(Watch-SmartThingsLocks -locations:$locations -rooms:$rooms -watchedRateLimitsStorePath:$watchedRateLimitsStorePath)
    
    $deviceChanges += @(Watch-SmartThingsTemperatureMonitors -locations:$locations -rooms:$rooms -watchedRateLimitsStorePath:$watchedRateLimitsStorePath)

    foreach($change in $deviceChanges)
    {        
        New-BurntToastNotification -Text $change.Message
        New-SystemNotification -severity:$change.Severity -source "Watch-SmartThings" -message $change.Message
    }
}

function Get-SmartThingsLockHistory([DateTime]$from, [DateTime]$to, [string]$watchedRateLimitsStorePath = $defaultWatchedRateLimits)
{
    $selectedDevice = ChooseSmartThingsLock -watchedRateLimitsStorePath:$watchedRateLimitsStorePath
    if(-not $selectedDevice)
    {
        return
    }
    $device = Get-WatchedSmartThingsLocks | where { $_.deviceId -eq $selectedDevice.deviceId }
    Get-WatchedSmartThingsLockHistory $device.Id $from $to
}

function Show-Locks()
{
    Get-WatchedSmartThingsLocks -status:$true 
    
    Write-Host
    
    $answer = Read-Host "Would you like to see active lock codes? [y/n (or any key)]"
    
    if($answer -match "y")
    {
         Get-SmartThingsLockCodes -all
    }
    
}
Set-Alias displayLocks Show-Locks -Scope Global

Export-ModuleMember -Function  *