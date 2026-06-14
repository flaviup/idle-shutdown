#Requires -RunAsAdministrator
<#
    Uninstall-ShutdownTasks.ps1
    Removes the IdleShutdown and NoUserShutdown scheduled tasks.
    Script files in the scripts folder are left in place.
    Run from an ELEVATED PowerShell prompt.
#>

param(
    [string]$ScriptsDir = 'C:\Scripts',
    [switch]$RemoveState   # also delete the state/log folder
)

$stateDir = Join-Path $env:ProgramData 'IdleShutdown'

foreach ($t in 'IdleShutdown', 'NoUserShutdown') {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
        Write-Host "Removed scheduled task '$t'." -ForegroundColor Green
    } else {
        Write-Host "Scheduled task '$t' not found (already removed?)." -ForegroundColor Yellow
    }
}

if ($RemoveState -and (Test-Path $stateDir)) {
    Remove-Item $stateDir -Recurse -Force
    Write-Host "Removed state folder $stateDir." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Script files in $ScriptsDir were left in place." -ForegroundColor Cyan
