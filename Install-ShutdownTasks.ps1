#Requires -RunAsAdministrator
<#
    Install-ShutdownTasks.ps1
    -------------------------------------------------------------------------
    Registers the two scheduled tasks WITHOUT using the Task Scheduler GUI:

      IdleShutdown    Runs in your interactive session at logon. Shuts down
                      after inactivity, showing the cancellable warning dialog.
                      Runs as YOU, with limited privileges (no admin needed to
                      shut down your own machine).

      NoUserShutdown  Runs as SYSTEM every few minutes, whether or not anyone
                      is logged on. Shuts down once nobody has been logged on
                      for the configured time. No dialog (no one to see it).

    Also (by default) locks the scripts + state folders to admin-write-only.
    Run this from an ELEVATED PowerShell prompt.
    -------------------------------------------------------------------------
#>

param(
    [string]$ScriptsDir   = 'C:\Scripts',
    [string]$IdleTaskUser = "$env:USERDOMAIN\$env:USERNAME",  # whose session shows the dialog
    [int]$IdleMinutes     = 30,
    [int]$WarningSeconds  = 60,
    [int]$NoUserMinutes   = 30,
    [int]$NoUserCheckMins = 5,                                # how often the SYSTEM task runs
    [switch]$Force,                                           # pass -Force to BOTH scripts
    [switch]$NoLockDown                                       # skip folder ACL hardening
)

$ErrorActionPreference = 'Stop'
$idlePs   = Join-Path $ScriptsDir   'IdleShutdown.ps1'
$nuPs     = Join-Path $ScriptsDir   'NoUserShutdown.ps1'
$stateDir = Join-Path $env:ProgramData 'IdleShutdown'

# --- preflight: are the script files present? -------------------------------
$missing = @($idlePs, $nuPs) | Where-Object { -not (Test-Path $_) }
if ($missing) {
    Write-Host "Missing script file(s):" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" }
    Write-Host "Copy IdleShutdown.ps1 and NoUserShutdown.ps1 into $ScriptsDir first, then re-run."
    exit 1
}

$forceArg = if ($Force) { ' -Force' } else { '' }

# ===== IdleShutdown : interactive, fires at logon ==========================
# -WindowStyle Hidden keeps the console from lingering (a brief flash at logon
# is possible; the optional IdleShutdown.vbs launcher avoids even that).
# ExecutionTimeLimit Zero = unlimited, required because the script loops forever
# (the default task limit of 3 days would otherwise kill it).
$idleArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$idlePs`"" +
           " -IdleMinutes $IdleMinutes -WarningSeconds $WarningSeconds$forceArg"

$idleAction    = New-ScheduledTaskAction    -Execute 'powershell.exe' -Argument $idleArg
$idleTrigger   = New-ScheduledTaskTrigger   -AtLogOn -User $IdleTaskUser
$idlePrincipal = New-ScheduledTaskPrincipal -UserId $IdleTaskUser -LogonType Interactive -RunLevel Limited
$idleSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName 'IdleShutdown' `
    -Description 'Shut down after user inactivity (with cancellable warning).' `
    -Action $idleAction -Trigger $idleTrigger -Principal $idlePrincipal -Settings $idleSettings -Force | Out-Null
Write-Host "Registered 'IdleShutdown'  -> runs as $IdleTaskUser at logon ($IdleMinutes min idle)." -ForegroundColor Green

# ===== NoUserShutdown : SYSTEM, every N minutes, logged on or not ===========
$nuArg = "-NoProfile -ExecutionPolicy Bypass -File `"$nuPs`" -NoUserMinutes $NoUserMinutes$forceArg"

$nuAction    = New-ScheduledTaskAction    -Execute 'powershell.exe' -Argument $nuArg
$nuTrigger   = New-ScheduledTaskTrigger   -Once -At (Get-Date) `
                    -RepetitionInterval (New-TimeSpan -Minutes $NoUserCheckMins) `
                    -RepetitionDuration (New-TimeSpan -Days 3650)   # ~indefinite, avoids XML quirks
$nuPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$nuSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName 'NoUserShutdown' `
    -Description 'Shut down when no interactive user is logged on.' `
    -Action $nuAction -Trigger $nuTrigger -Principal $nuPrincipal -Settings $nuSettings -Force | Out-Null
Write-Host "Registered 'NoUserShutdown' -> runs as SYSTEM every $NoUserCheckMins min ($NoUserMinutes min no-user)." -ForegroundColor Green

# ===== folder hardening =====================================================
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }

if (-not $NoLockDown) {
    function Lock-Folder([string]$path) {
        # Well-known SIDs are locale-independent (group NAMES are localized on
        # non-English Windows and would make icacls fail):
        #   S-1-5-18      = Local SYSTEM
        #   S-1-5-32-544  = Administrators
        #   S-1-5-32-545  = Users
        & icacls $path /inheritance:r `
            /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Host "  (icacls exit $LASTEXITCODE for $path)" -ForegroundColor Yellow }
    }
    Lock-Folder $ScriptsDir
    Lock-Folder $stateDir
    Write-Host "Hardened $ScriptsDir and $stateDir (admins/SYSTEM write, users read-only)." -ForegroundColor Green
} else {
    Write-Host "Skipped ACL hardening (-NoLockDown). You should still restrict $ScriptsDir to admins." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host "Verify : Get-ScheduledTask IdleShutdown, NoUserShutdown | Format-Table TaskName, State"
Write-Host "Logs   : `$env:LOCALAPPDATA\IdleShutdown.log   and   $stateDir\nouser.log"
Write-Host "Test   : run a no-user dry run with  .\NoUserShutdown.ps1 -DryRun -NoUserMinutes 2  (see README)"
