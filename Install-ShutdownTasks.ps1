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

    The scripts folder is auto-detected ($ScriptsDir defaults to this script's
    own location), so the whole set can live in any folder with no edits.

    Registering scheduled tasks requires admin rights, so this script
    self-elevates: if you launch it un-elevated (e.g. with
        powershell -NoProfile -ExecutionPolicy Bypass -File "<folder>\Install-ShutdownTasks.ps1"
    ) it relaunches itself through a UAC prompt and keeps that window open so
    you can read the result.
    -------------------------------------------------------------------------
#>

param(
    [string]$ScriptsDir   = $PSScriptRoot,                    # defaults to this script's own folder
    [string]$IdleTaskUser = "$env:USERDOMAIN\$env:USERNAME",  # whose session shows the dialog
    [int]$IdleMinutes     = 30,
    [int]$WarningSeconds  = 60,
    [int]$NoUserMinutes   = 30,
    [int]$NoUserCheckMins = 5,                                # how often the SYSTEM task runs
    [switch]$Force,                                           # pass -Force to BOTH scripts
    [switch]$NoLockDown                                       # skip folder ACL hardening
)

# ============================================================================
# Self-elevate: if not running as Administrator, relaunch elevated (UAC) with
# the same parameters, then exit this (un-elevated) instance.
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not elevated - relaunching with administrator rights (approve the UAC prompt)..." -ForegroundColor Yellow

    # -NoExit keeps the elevated window open so you can see the output / errors.
    $relaunch = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', ('"{0}"' -f $PSCommandPath))

    # Forward any parameters you passed so customizations survive the relaunch.
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $relaunch += "-$($kv.Key)" }
        } else {
            $relaunch += "-$($kv.Key)"
            $relaunch += ('"{0}"' -f $kv.Value)
        }
    }

    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch
    } catch {
        Write-Host "Elevation cancelled or failed. Re-run from an elevated PowerShell prompt." -ForegroundColor Red
    }
    return
}

$ErrorActionPreference = 'Stop'

# If launched in a way where $PSScriptRoot is empty (e.g. pasted into a console),
# fall back to the current directory so we still have a sensible scripts folder.
if ([string]::IsNullOrWhiteSpace($ScriptsDir)) { $ScriptsDir = (Get-Location).Path }

$idlePs   = Join-Path $ScriptsDir   'IdleShutdown.ps1'
$nuPs     = Join-Path $ScriptsDir   'NoUserShutdown.ps1'
$stateDir = Join-Path $env:ProgramData 'IdleShutdown'

# --- preflight: are the script files present? -------------------------------
$missing = @($idlePs, $nuPs) | Where-Object { -not (Test-Path $_) }
if ($missing) {
    Write-Host "Missing script file(s):" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" }
    Write-Host "Copy IdleShutdown.ps1 and NoUserShutdown.ps1 into $ScriptsDir first, then re-run."
    return
}

$forceArg = if ($Force) { ' -Force' } else { '' }

# ===== IdleShutdown : interactive, fires at logon + on session connect ======
# Launch powershell directly. The script hides its own console window at startup
# (see IdleShutdown.ps1), so no VBScript launcher is needed; -WindowStyle Hidden
# trims the startup flash. ExecutionTimeLimit Zero = unlimited (script loops forever).
$idleArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$idlePs`"" +
           " -IdleMinutes $IdleMinutes -WarningSeconds $WarningSeconds$forceArg"

$idleAction    = New-ScheduledTaskAction    -Execute 'powershell.exe' -Argument $idleArg
$idlePrincipal = New-ScheduledTaskPrincipal -UserId $IdleTaskUser -LogonType Interactive -RunLevel Limited
$idleSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

# Triggers: at logon (fresh sign-in) + on RDP connect + on unlock. RDP *reconnect*
# is not a logon, so without the session triggers the watcher wouldn't restart for
# a reconnected session. The script's mutex stops duplicates if several fire at once.
$idleLogon = New-ScheduledTaskTrigger -AtLogOn -User $IdleTaskUser
$sstcClass = Get-CimClass -Namespace 'Root\Microsoft\Windows\TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger'
$idleConnect = New-CimInstance -CimClass $sstcClass -ClientOnly
$idleConnect.StateChange = 3            # TASK_REMOTE_CONNECT (RDP connect)
$idleConnect.UserId      = $IdleTaskUser
$idleConnect.Enabled     = $true
$idleUnlock = New-CimInstance -CimClass $sstcClass -ClientOnly
$idleUnlock.StateChange  = 8            # TASK_SESSION_UNLOCK
$idleUnlock.UserId       = $IdleTaskUser
$idleUnlock.Enabled      = $true
$idleTriggers = @($idleLogon, $idleConnect, $idleUnlock)

Register-ScheduledTask -TaskName 'IdleShutdown' `
    -Description 'Shut down after user inactivity (with cancellable warning).' `
    -Action $idleAction -Trigger $idleTriggers -Principal $idlePrincipal -Settings $idleSettings -Force | Out-Null
Write-Host "Registered 'IdleShutdown'  -> runs as $IdleTaskUser at logon / RDP connect / unlock ($IdleMinutes min idle)." -ForegroundColor Green

# Start it now so the watcher is live immediately instead of waiting for next logon.
try {
    Start-ScheduledTask -TaskName 'IdleShutdown'
    Write-Host "  Started 'IdleShutdown' now (watcher is live; it won't act until you're actually idle)." -ForegroundColor Green
} catch {
    Write-Host "  Could not start 'IdleShutdown' now: $($_.Exception.Message)" -ForegroundColor Yellow
}

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

# Run it once now so it starts its checks immediately instead of waiting for the first tick.
try {
    Start-ScheduledTask -TaskName 'NoUserShutdown'
    Write-Host "  Ran 'NoUserShutdown' once now (you're logged on, so it just logs and exits)." -ForegroundColor Green
} catch {
    Write-Host "  Could not start 'NoUserShutdown' now: $($_.Exception.Message)" -ForegroundColor Yellow
}

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
Write-Host "Verify : Get-ScheduledTask | Where-Object TaskName -in 'IdleShutdown','NoUserShutdown' | Format-Table TaskName, State"
Write-Host "Logs   : `$env:LOCALAPPDATA\IdleShutdown.log   and   $stateDir\nouser.log"
