<#
    Uninstall-ShutdownTasks.ps1
    -------------------------------------------------------------------------
    Removes the IdleShutdown and NoUserShutdown scheduled tasks.
    Self-elevates if not run as administrator.

    Switches:
      -RemoveState   also delete the state/log folder (%ProgramData%\IdleShutdown)
      -RestoreAcl    restore default permissions on the scripts folder
                     (undo the installer's folder hardening)

    Script files in the scripts folder are left in place.
    -------------------------------------------------------------------------
#>

param(
    [string]$ScriptsDir = 'C:\Scripts',
    [switch]$RemoveState,
    [switch]$RestoreAcl
)

# ============================================================================
# Self-elevate: if not running as Administrator, relaunch elevated (UAC) with
# the same parameters, then exit this (un-elevated) instance.
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not elevated - relaunching with administrator rights (approve the UAC prompt)..." -ForegroundColor Yellow
    $relaunch = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', ('"{0}"' -f $PSCommandPath))
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $relaunch += "-$($kv.Key)" }
        } else {
            $relaunch += "-$($kv.Key)"; $relaunch += ('"{0}"' -f $kv.Value)
        }
    }
    try { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch }
    catch { Write-Host "Elevation cancelled or failed. Re-run from an elevated PowerShell prompt." -ForegroundColor Red }
    return
}

$stateDir = Join-Path $env:ProgramData 'IdleShutdown'

# --- remove the scheduled tasks ---
foreach ($t in 'IdleShutdown', 'NoUserShutdown') {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
        Write-Host "Removed scheduled task '$t'." -ForegroundColor Green
    } else {
        Write-Host "Scheduled task '$t' not found (already removed?)." -ForegroundColor Yellow
    }
}

# --- remove state/logs ---
if ($RemoveState -and (Test-Path $stateDir)) {
    Remove-Item $stateDir -Recurse -Force
    Write-Host "Removed state folder $stateDir." -ForegroundColor Green
}

# --- undo the folder hardening ---
if ($RestoreAcl -and (Test-Path $ScriptsDir)) {
    & icacls $ScriptsDir /reset | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Restored default permissions on $ScriptsDir." -ForegroundColor Green
    } else {
        Write-Host "  (icacls /reset exit $LASTEXITCODE for $ScriptsDir)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Script files in $ScriptsDir were left in place." -ForegroundColor Cyan
Write-Host "To remove them too, just delete the $ScriptsDir folder."
