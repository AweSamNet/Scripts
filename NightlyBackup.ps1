function HandleError($exception)
{
    $failedAt = Get-Date
    $message = @"
Nightly backup failed at $failedAt with error message:
"$($_.Exception.Message)"

on :
"$($_.Exception.StackTrace)"
"@

    New-BurntToastNotification -Text $message
    New-SystemNotification -severity:Medium -source:"NightlyBackup" -message:$message
}

try{
    . (Resolve-Path 'D:\Users\sam\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')  -limtedStartUp

    $start = Get-Date
    $message = "Starting nightly backup at $start"

    New-BurntToastNotification -Text $message
    New-SystemNotification -severity:Low -source:"NightlyBackup" -message:$message
    Backup-PC
}
catch {
    HandleError $_

    return 
}
finally
{
    $finishedAt = Get-Date
    $message = "Nightly Backup finished at $finishedAt.  Total duration: $($finishedAt - $start)"

    New-BurntToastNotification -Text $message
    New-SystemNotification -severity:Low -source:"NightlyBackup" -message:$message
}