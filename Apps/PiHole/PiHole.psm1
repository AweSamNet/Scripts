### 
### Operations related functionality
###

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Edit-PiHole
{
    notepad++ $ScriptPath
}

function Get-PiHoleCommands ([int]$columns = 3)
{
    $names = Get-Command -Module PiHole | % { $_.Name }
    Write-Table $names $columns
}


if(-not(Test-Path Variable:\PiHoleServers))
{
    Write-Output ""
    Write-Highlight 'Variable $global:PiHoleServers not found'    
    Write-Output ""
    
    Write-Output `
'The variable $global:PiHoleServers contains addresses to pi-hole servers.  
You should add this variable to your $profile (Edit-Profile) with the desired modules specified.
If you do not have any environment specific modules to load you should still create an empty array.

You can use the following as a template:
'

    Write-Highlight -highlightColor "DarkGray" -text '
------------------------------------------------------------------------------------------------
    
$global:PiHoleServers = @{
    Default = @{
        Name ="Home";
        ServerAddress = "http://192.168.1.103";
        Key = "randomkeyhere";
    };
}
    
------------------------------------------------------------------------------------------------'
    $openProfile = Read-Host "Would you like to view your system profile?[y/n]"

    if($openProfile -eq "y")
    {
        Edit-Profile
    }
}

$defaultWatchedPiHoleKnownClients = Join-Path $ScriptPath "Watched\PiHoleKnownClients.txt"
$defaultPiHoleClientsAlerts = Join-Path $ScriptPath "Watched\PiHoleClientsAlerts.txt"
$defaultWatchedPiHoleQueryPath = Join-Path $ScriptPath "Watched\PiHoleQueries.txt"
$defaultWatchedPiHoleResultsPath = Join-Path $ScriptPath "Watched\PiHoleResults.txt"

function Watch-PiHoleQuery(
    [string]$query,
    [string]$storePath=$defaultWatchedPiHoleQueryPath,
    [string[]]$devices,
    [string[]]$excludedDevices,
    [switch]$private
    )
{
    $list = {Get-WatchedPiHoleQueries $storePath}.Invoke()
    
    $id = iif $list { ($list | measure -Property Id -Maximum).maximum + 1 } 1
    
    $queryToWatch = @{
        Id = $id;
        Query = $query;
        Devices = $devices;
        ExcludedDevices = $excludedDevices;
        Private = $private.IsPresent;
    }
    
    $list.Add($queryToWatch)

    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    Get-WatchedPiHoleQueries $storePath
}

function Get-WatchedPiHoleQueries([string]$storePath = $defaultWatchedPiHoleQueryPath)
{
    Get-JsonFromFile $storePath
}

function Edit-WatchedPiHoleQueries([string]$storePath = $defaultWatchedPiHoleQueryPath)
{
    notepad++ $storePath
}

function Unwatch-PiHoleQuery(
    [string]$query="",
    [int]$id=0,
    [string]$storePath=$defaultWatchedPiHoleQueryPath
)
{
    $queriesToWatch = @()
    
    if ((Test-Path ($storePath)))
    {
        $queriesToWatch = ConvertFrom-Json (Get-Content $storePath -Raw)
    }
    
    $list = {$queriesToWatch}.Invoke()
    $toRemove  = $list | where { 
        $_.Id -eq $id `
        -or( $_.Query -eq $query)
    } | select -First 1
    
    if($toRemove)
    {
        $list.Remove($toRemove)
    } 
    
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    Get-WatchedPiHoleQueries $storePath
}

function Get-PiHoleResults([string]$storePath = $defaultWatchedPiHoleResultsPath, [switch]$raw, [switch]$all)
{
    $data = Get-JsonFromFile $storePath 
    
    if($raw)
    {
        return $data
    }
    else{
    
        return $data | % {
            $_.PSObject.Properties.Remove("Status")
            Add-Member -InputObject $_ -NotePropertyName "LocalDate" -NotePropertyValue $(Convert-UTCtoLocal $_.UtcDate)
            
            if($all -or $_.Server -eq $PiHoleServers.Default.Name )
            {
                [PSCustomObject]$_
            }
        } | Sort-Object -Property LocalDate | Format-Table
    }
}

function Clear-PiHoleResults()
{
    if(Test-Path $defaultWatchedPiHoleResultsPath)
    {
        rm $defaultWatchedPiHoleResultsPath
    }
}

function Save-PiHoleResults($results, [string]$storePath = $defaultWatchedPiHoleResultsPath)
{
    $list = {Get-PiHoleResults $storePath -raw}.Invoke()
    
    $resultsArray = @()
    $toSave = @()

    if($results -is [array])
    {
        $resultsArray = $results
    }
    else
    {
        $resultsArray += $results
    }
    
    :resultsArray foreach($result in $resultsArray)
    {
        if($list)
        {            
            :existing foreach($existing in $list)
            {
                # this result already exists, don't add it
                if($existing.UtcDate -eq $result.UtcDate `
                    -and $existing.Url -eq $result.Url)
                {
                    continue resultsArray
                }
            }
        }
        $toSave += $result
    }

    if(-not($toSave))
    {
        return $false
    }
    
    $toSave | %{ $list.Add($_) }
    
    $body = ConvertTo-Json $list

    $output = New-Item -ItemType File -Force -Path $storePath -Value $body
    
    return $true
}

function Watch-PiHole()
{
    Write-output "default is $defaultWatchedPiHoleResultsPath"
        
    $results = Find-WatchedPiHoleQueries
        
    if($results)
    {
        if(Save-PiHoleResults $results)
        {
            $message = "Pi-Hole sites triggered.  View Log."
        
            New-BurntToastNotification -Text $message
            New-SystemNotification -severity:Low -source:"Watch-PiHole" -message:$message
        }
    }
    
    if(Find-PiHoleWatchedAndUnknownClients)
    {
        $message = "Pi-Hole registered unkonwn devices on the network.  View Log."
        New-BurntToastNotification -Text $message
        New-SystemNotification -severity:Low -source:"Watch-PiHole" -message:$message
    }
}

function Watch-PiHoleKnownClients(
    [Parameter(Mandatory=$true)]$device,
    [string]$storePath = $defaultWatchedPiHoleKnownClients
    )
{
    upsert -record $device -query {$_.Value.hwaddr -eq $device.hwaddr} -storePath $storePath
}

function Unwatch-PiHoleKnownClients(
    $piHoleServer = $PiHoleServers.Default,
    $deviceName,
    [int]$id=0,
    [string]$storePath = $defaultWatchedPiHoleKnownClients)
{
    Unwatch-Something {
        $_.Value.Server -eq $piHoleServer `
        -and $_.Value.DeviceName -eq $deviceName
    } $id $storePath
}

function Get-WatchedPiHoleKnownClients([string]$storePath = $defaultWatchedPiHoleKnownClients)
{
    Get-JsonFromFile $storePath
}

function Get-PiHoleClientsAlerts([string]$storePath = $defaultPiHoleClientsAlerts)
{
    $esc = "$([char]27)"
    do
    {
        $alerts = Get-JsonFromFile $storePath
        
        if($alerts -eq $null -or $alerts.Count -eq 0)
        {
            pause "No alerts logged"
            return
        }
        
        displayClientAlerts $alerts
        
        $answer = Read-Host ("Would you like to $esc[92mE$esc[0mdit a device on this list or $esc[92mC$esc[0mlear this list? [e/c or any key]").Trim()
        
        
        if($answer -eq "e")
        {
            $id = Read-Host "Which one?"
            if($id -match '^[0-9]+$')
            {
                $matchingAlert = $alerts | where {$_.Id -eq [int]$id } | select -First 1
                
                if(-not $matchingAlert)
                {
                    continue
                }

                # here we need to get the known device by mac address
                $device = Get-WatchedPiHoleKnownClients | where { $_.Value.hwaddr -eq $matchingAlert.Value.DeviceName } | select -First 1
                
                $deviceJson = $device.Value | ConvertTo-Json
                Write-Host $deviceJson
                
                do 
                {
                    $track = (Read-Host "Would you like to track this device? [y/n]").Trim()
                } while(-not ($track -match '^[yn]$'))
                
                if($track -eq "y")
                {
                    do
                    {
                        $warn = (Read-Host "Would you like to be warned when this device is found? [y/n]").Trim()
                    } while(-not ($warn -match '^[yn]$'))

                    
                    # here we need to set the warn to true and upsert it
                    $device.Value.Warn = $true
                    Watch-PiHoleKnownClients -device:$device.Value
                }
                
                do{
                    $removeAlert = (Read-Host "Would you like to clear this alert? [y/n]").Trim()
                } while(-not ($removeAlert -match '^[yn]$'))

                if($removeAlert -eq "y")
                {
                    unwatch -id $id -storePath $storePath
                }
            }
        }
        elseif($answer -eq "c")
        {
                            
            do{
                $clearAlerts = (Read-Host "Are you sure you want to clear all alerts? [y/n]").Trim()                
            } while(-not ($clearAlerts -match '^[yn]$'))
            
            if($clearAlerts -eq "y")
            {
                Clear-List $storePath
            }
        }
    } while ($answer -and "ec" -match $answer)
}

function displayClientAlerts($alerts)
{    
    $esc = "$([char]27)"
    foreach ($alert in $alerts | Sort-Object -Property Id)
    {
        Write-Host "[$($alert.Id)] Server=$($alert.Value.Server); DeviceName=$($alert.Value.DeviceName); Queries=$($alert.Value.Queries);"
        
        foreach($date in $alert.Value.History)
        {
            $color = IIF $($date.Status -eq "start") $("$esc[92m") $("$esc[91m")
            
            Write-Host "    - $(Convert-UTCtoLocal $date.Date), Status=$color$($date.Status)$esc[0m"
        }
        Write-Host
    }    
}

function Add-PiHoleClientsAlerts(
    [Parameter(Mandatory=$true)]$piHoleServer,
    [Parameter(Mandatory=$true)]$deviceName,   
    [Parameter(Mandatory=$true)]$totalQueries,       
    [string]$storePath = $defaultPiHoleClientsAlerts)
{
    $date = Get-Date
    $list = Get-Records $storePath
    
    $filter = { $_.Value.Server -eq $piHoleServer -and $_.Value.DeviceName -eq $deviceName }

    $alertRecord = $list | Where-Object $filter | select -First 1
  
    if(-not $alertRecord)
    {
    
        $alert = @{
            Server = $piHoleServer;
            DeviceName = $deviceName;
            Queries = $totalQueries;
            History = @(
                @{
                    Date = $date;
                    Status = "start";
                }
            );
        }
        
        upsert -record $alert -query $filter -storePath $storePath
        
        return $true
    }
    elseif($alertRecord.Value.Queries -ne $totalQueries)
    {
        $alert = $alertRecord.Value
        $status = "start"
        
        # get the last status to see the current status
        $lastStatus = $alert.History[-1]
        
        if($lastStatus.Status -eq "start")
        {
            $status = ""
        }
        
        # if the last status is just an ongoing alert, remove it and add a more current one.
        if($lastStatus.Status -eq "")
        {
            $status = ""
            $history = {$alert.History}.Invoke()
            
            $removed = $history.Remove($lastStatus)
            $alert.History = $history
        }
        
        $alert.History += @{
            Date = $date;
            Status = $status;
        }
        
        $alert.Queries = $totalQueries
        
        upsert -id $alertRecord.Id -record $alert -query $filter -storePath $storePath        
        
        return ($status -ne "")
    }
    elseif($alertRecord.Value.Queries -eq $totalQueries)
    {
        $alert = $alertRecord.Value
        $status = "end"
        
        # get the last status to see the current status
        $lastStatus = $alert.History[-1]
        
        if($lastStatus.Status -ne $status)
        {
            $lastStatus.Status = $status
            
            upsert -id $alertRecord.Id -record $alert -query $filter -storePath $storePath
            return $true
        }    
    }
    
    return $false
}

function Find-PiHoleWatchedAndUnknownClients()
{
    $knownClients = Get-WatchedPiHoleKnownClients
    
    $servers = ConvertFrom-Json (Get-PiHoleAllClientsV6 -all) | Get-ObjectMembers
    $alerts = @{}
    $found = $false
    
    foreach($server in $servers)
    {
        if($server.Key -ne "Home")
        {
            continue
        }
        # get the clients
        $clients = $server.Value
        
        foreach($client in $clients)
        {   
            $filter = {$client.hwaddr -eq $_.Value.hwaddr}
            # see if this client matches any we know of
            $matchingKnown = $knownClients | Where-Object $filter | select -First 1
                        
            $deviceName = $client.hwaddr
            if([string]::IsNullOrWhiteSpace($deviceName))
            {
                continue
            }

            # if($matchingKnown)
            # {
                # pause "in"
                # # alert here with device name
                # $deviceName = $matchingKnown.Value.DeviceName
            # }
            
            # here we want to upsert the device, but don't forget to transfer the Warn flag
            
            $warn = IIF $matchingKnown {$matchingKnown.Value.Warn} $false
            
            $client | Add-Member -NotePropertyName Warn -NotePropertyValue $warn -Force
            $client | Add-Member -NotePropertyName Server -NotePropertyValue $server.Key -Force
            
            $filter = { $_.Value.hwaddr -eq $deviceName }
            upsert -record $client -query $filter -storePath $defaultWatchedPiHoleKnownClients
            
            if(-not $matchingKnown -or($matchingKnown -and $matchingKnown.Value.Warn -eq $true))
            {
                $success = Add-PiHoleClientsAlerts $server.Key $deviceName $client.numQueries               
                $found = $found -or $success
            }
        }
    }
    
    return $found
}

function Get-PiHoleAllClients($piHoleServer = $PiHoleServers.Default, [switch]$all)
{
    $servers = @()
    $data = @{}

    if($all){
        $PiHoleServers.Keys | % {
            $servers += $PiHoleServers.Item($_)                   
        }
    }
    else {
        $servers += $piHoleServer          
    }    
        
    $servers | % {
        $uri = "$($_.ServerAddress)/admin/api.php?getQuerySources=90&auth=$($_.Key)"

        try {
        
            Write-Host "Searching: $uri"
        
            $request = Invoke-WebRequest -Method GET -Uri $uri -UseBasicParsing
            
            $data[$_.Name] = ConvertFrom-Json $request.Content;
        }
        catch{}
    }
        
    return $data | ConvertTo-JSON
}

function Get-PiHoleAllClientsV6 {
    [CmdletBinding()]
    param(
        $PiHoleServer = $PiHoleServers.Default,
        [switch]$all,
        [int]$N = 0  # v6: 0 => all clients
    )

    if ($All) {
        $servers = $PiHoleServers.Keys | ForEach-Object { $PiHoleServers.Item($_) }
    } else {
        $servers = @($PiHoleServer)
    }

    $data = @{}

    foreach ($srv in $servers) {

        $session = $null
        try {
            $base = $srv.ServerAddress
            if ([string]::IsNullOrWhiteSpace($base)) {
                throw "ServerAddress is empty for '$($srv.Name)'"
            }

            $base = $base.TrimEnd('/')

            if (-not [string]::IsNullOrWhiteSpace($srv.Key)) {
                $session = New-PiHoleSession -Base $base -Password $srv.Key -AuthStyle Query

                $sid = [uri]::EscapeDataString($session.Sid)  # important when SID is in the URI
                $uri = "$($session.Base)/api/network/devices?N=$N&sid=$sid"
            }
            else {
                $uri = "$base/api/history/devices?N=$N"
            }

            Write-Host ("Pi-hole v6 clients query: " + ($uri -replace 'sid=[^&]+', 'sid=<redacted>'))
            $resp = Invoke-RestMethod -Method GET -Uri $uri -TimeoutSec 30
            $data[$srv.Name] = $resp.devices
        }
        catch {
            Write-Warning ("Pi-hole clients fetch failed for '{0}': {1}" -f $srv.Name, $_.Exception.Message)
        }
        finally {
            if ($session) { Remove-PiHoleSession -Session $session }
        }
    }

    return ($data | ConvertTo-Json -Depth 25)
}


function New-PiHoleSession {
    param(
        [Parameter(Mandatory)][string]$Base,        # e.g. http://192.168.1.103 or https://pi.hole
        [Parameter(Mandatory)][string]$Password,    # UI or App password
        [ValidateSet('Header','Query')][string]$AuthStyle = 'Query' # Query is most compatible
    )
    $payload = @{ password = $Password } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method POST -Uri "$Base/api/auth" `
            -Body $payload -ContentType 'application/json' -TimeoutSec 10
    
    if (-not $resp.session.valid) { throw "Auth failed." }
    
    [pscustomobject]@{
        Base    = $Base
        Sid     = $resp.session.sid
        Headers = @{ 'X-FTL-SID' = $resp.session.sid }
        Style   = $AuthStyle
        Created = Get-Date
    }
}

function Remove-PiHoleSession {
    param([Parameter(Mandatory)]$Session)
    try {
        if ($Session.Style -eq 'Header') {
            Invoke-RestMethod -Method DELETE -Uri "$($Session.Base)/api/auth" `
              -Headers $Session.Headers -TimeoutSec 5 | Out-Null
        } else {
            Invoke-RestMethod -Method DELETE -Uri "$($Session.Base)/api/auth?sid=$($Session.Sid)" `
              -TimeoutSec 5 | Out-Null
        }
    } catch { 
        Write-Warning ("Pi-hole queries failed: " + $_.Exception.Message)
        throw
    } # ignore; we're just cleaning up
}

# Normalize each row whether it's an array or an object
function Convert-PiHoleQueryRow {
    param($row)

    if ($row -is [System.Array]) {
        # Typical order: [time, type, domain, client, status, ...]
        [pscustomobject]@{
            Time   = [int]$row[0]
            Type   = $row[1]
            Domain = $row[2]
            Client = $row[3]
            Status = $row[4]
        }
    }
    else {
        # Object shape (varies across builds)
        $has = { param($n) $row.PSObject.Properties.Name -contains $n }
        $t = 0
        if (&$has 'time')       { $t = $row.time }
        elseif (&$has 'timestamp'){ $t = $row.timestamp }
        elseif (&$has 'date')   { $t = $row.date }

        [pscustomobject]@{
            Time   = [int]$t
            Type   = $row.type
            Domain = $row.domain
            Client = $row.client
            Status = $row.status
        }
    }
}

function Get-PiHoleAllQueriesV6 {
    [CmdletBinding()]
    param(
        [datetime]$From     = (Get-Date).AddMinutes(-15).ToUniversalTime(),
        [datetime]$Until    = (Get-Date).ToUniversalTime(),
        $PiHoleServer       = $PiHoleServers.Default,
        [int]$Start         = 0,
        [int]$Length        = 500,
        [switch]$Disk
    )

    $fe = ConvertTo-UtcEpochSeconds $From
    $ue = ConvertTo-UtcEpochSeconds $Until
    #$qs = "start=$Start&length=$Length&from=$fe&until=$ue" + ($(if($Disk){'&disk=true'}else{''}))
    $qs = "start=$Start&length=$Length" + ($(if($Disk){'&disk=true'}else{''}))

    $session = $null
    try {
        $session = New-PiHoleSession -Base $PiHoleServer.ServerAddress -Password $PiHoleServer.Key -AuthStyle Query
        $uri = "$($session.Base)/api/queries?$qs&sid=$($session.Sid)"
        Write-Host "Pi-hole v6 query: $uri"

        # Auto-JSON parse → PSCustomObject
        $resp = Invoke-RestMethod -Method GET -Uri $uri -TimeoutSec 30

        # Return a list of normalized objects with named properties
        if ($resp -and $resp.queries) {
            return ($resp.queries | ForEach-Object { Convert-PiHoleQueryRow $_ })
        } else {
            return @()  # empty list
        }
    }
    finally {
        if ($session) { Remove-PiHoleSession -Session $session }
    }
}

function Get-PiHoleAllQueries([DateTime]$from, [DateTime]$until, $piHoleServer = $PiHoleServers.Default)
{
    $uri = "$($piHoleServer.ServerAddress)/admin/api.php?getAllQueries&auth=$($piHoleServer.Key)"
    
    if($from)
    {
        $uFrom = ConvertTo-UtcEpochSeconds $from
        $uri += "&from=$uFrom"
    }
    
    if($until)
    {
        $uUntil = ConvertTo-UtcEpochSeconds $until
        $uri += "&until=$uUntil"
    }
    
    Write-Host "Searching: $uri"
    
    $request = Invoke-WebRequest -Method GET -Uri $uri
    
    $data = ConvertFrom-Json $request.Content
    
    return $data
}

function Format-LogEntry
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true, Mandatory=$true)]
        $LogEntry,
        $server = @{Name = ""}
    )
     
    process
    {
        $statusText = switch ($_.Status) {
                        "GRAVITY" { "blocked by gravity.list" }
                        "FORWARDED" { "forwarded to upstream server" }
                        "CACHE" { "answered by local cache" }
                        "CACHE_STALE" { "answered by local cache" }
                        "BLOCKED" { "blocked by wildcard blocking" }
                        Default { "other" }
                    }

        # $_.Time is Unix epoch seconds from Pi-hole (UTC)
        $dto   = [DateTimeOffset]::FromUnixTimeSeconds([int64]$_.Time)
        $utc   = $dto.UtcDateTime

        [pscustomobject]@{
            UtcDate = $utc
            Server  = $server.Name
            Url     = $_.Domain
            Device  = $_.Client
            Status  = $_.Status
        }
    }
}

function Find-WatchedPiHoleQueries ([switch]$debug)
{
    foreach($server in $PiHoleServers.Values)
    {
        try {
            $rows = Get-PiHoleAllQueriesV6 -PiHoleServer $server
            if($debug){ pause $rows }           # $rows is ALREADY the array; don't use $rows.queries

            $watchedList = Get-WatchedPiHoleQueries

            $rows |
              Where-Object {
                $q = $_                             # has .Domain, .Client, .Status, .Time
                $match = $false
                foreach ($searchValue in $watchedList)
                {
                    $m = ($q.Domain -match $searchValue.Query)
                    
                    $m = $m `
                        -and ( `
                            $searchValue.Devices -eq $null `
                            -or $searchValue.Devices.Count -eq 0 `
                            -or $searchValue.Devices.Contains($q.Client.ip) `
                            -or $searchValue.Devices.Contains($q.Client.name) `
                        )
                    
                    $m = $m `
                        -and ( `
                            -not $searchValue.ExcludedDevices `
                            -or -not ( `
                                $searchValue.ExcludedDevices.Contains($q.Client.ip) `
                                -or $searchValue.ExcludedDevices.Contains($q.Client.name) `
                            ) `
                        )

                    if ($m) { 
                        $match = $true;
                        break 
                    }
                }
                $match
              } |
              Format-LogEntry -server:$server
        }
        catch {
            Write-Host "Couldn't connect to server: $($server.Name) on: $($server.ServerAddress)" -ForegroundColor Red
            Write-Warning ($_.Exception.Message)
        }
    }
}


Export-ModuleMember -Function  *-*