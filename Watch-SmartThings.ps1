function HandleError($exception)
{
    $failedAt = Get-Date
    $message = @"
Watch-SmartThings failed at $failedAt with error message:
"$($exception.Exception.Message)"

on :
"$($exception.Exception.StackTrace)"
"@

    Write-Output $message
    New-BurntToastNotification -Text $message
    New-SystemNotification -severity:Medium -source:"Watch-SmartThings" -message:$message
}

try
{
    . (Resolve-Path 'D:\Users\sam\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -limtedStartUp
}
catch
{
    HandleError $_
}

while($true)
{
    try
    {
        Watch-SmartThings
    }    
    catch 
    {
        HandleError $_
    }
    finally
    {
        Start-Sleep (60 * 5)
    }
}