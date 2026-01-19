function HandleError($exception)
{
    $failedAt = Get-Date
    $message = @"
Watch-PiHole failed at $failedAt with error message:
"$($exception.Exception.Message)"

on :
"$($exception.Exception.StackTrace)"
"@

    Write-Output $message
    New-BurntToastNotification -Text $message
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
        Watch-PiHole
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