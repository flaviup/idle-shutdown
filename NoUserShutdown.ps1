# NoUserShutdown.ps1
# Shuts the machine down after no interactive user has been logged on for
# N minutes. Intended to run as SYSTEM from a scheduled task that fires every
# few minutes "whether a user is logged on or not" -- so it works at the
# lock/login screen when nobody is signed in.
#
# It does NOT show a dialog (there is no one to see it). The "for N minutes"
# grace period is tracked with a small timestamp file, so the script itself is
# stateless between runs and survives reboots cleanly.

param(
    [int]$NoUserMinutes = 30,                                   # shut down after this long with no user
    [switch]$Force,                                            # use shutdown /f (force-close)
    [switch]$DryRun,                                           # log what it WOULD do; don't shut down
    [string]$StateFile = "$env:ProgramData\IdleShutdown\nouser.flag",
    [string]$LogFile   = "$env:ProgramData\IdleShutdown\nouser.log"
)

# ---- setup -----------------------------------------------------------------
$dir = Split-Path -Parent $LogFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

# ---- "is anyone logged on?" ------------------------------------------------
# Locale-independent: every interactive desktop session (active, locked, OR a
# disconnected RDP session whose programs are still running) has exactly one
# explorer.exe owned by that user. If none exists, no interactive user is
# present. Disconnected sessions are deliberately counted as "logged on" so we
# never shut down on top of someone's still-running session.
function Test-AnyUserLoggedOn {
    try {
        $explorers = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop
        foreach ($p in $explorers) {
            $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
            if ($owner -and $owner.ReturnValue -eq 0 -and $owner.User) {
                if ($owner.User -notin @('SYSTEM','LOCAL SERVICE','NETWORK SERVICE')) {
                    return $true
                }
            }
        }
    } catch {
        # If detection itself fails, assume someone IS logged on (fail safe:
        # never shut down on an error).
        Log "Detection error: $($_.Exception.Message) -- assuming user present."
        return $true
    }
    return $false
}

# ---- main ------------------------------------------------------------------
if (Test-AnyUserLoggedOn) {
    if (Test-Path $StateFile) {
        Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
        Log "User logged on -- clearing no-user timer."
    }
    return
}

# No user is logged on. Start (or continue) the grace timer.
if (-not (Test-Path $StateFile)) {
    (Get-Date).ToString("o") | Set-Content -Path $StateFile -Encoding ASCII
    Log "No user logged on -- grace timer started (${NoUserMinutes} min)."
    return
}

# Timer already running -- how long has it been?
$since   = $null
try { $since = [datetime]::Parse((Get-Content $StateFile -Raw)) } catch {}
if (-not $since) {
    # corrupt/unreadable flag: reset it rather than act on bad data
    (Get-Date).ToString("o") | Set-Content -Path $StateFile -Encoding ASCII
    Log "State file unreadable -- timer reset."
    return
}

$elapsed = ((Get-Date) - $since).TotalMinutes
if ($elapsed -ge $NoUserMinutes) {
    if ($DryRun) {
        Log ("DRYRUN: no user for {0:N1} min >= {1} -- would shut down now." -f $elapsed, $NoUserMinutes)
    } else {
        $sdArgs = if ($Force) { @('/s','/f','/t','0') } else { @('/s','/t','0') }
        Log ("No user for {0:N1} min >= {1} -- shutting down ({2})." -f $elapsed, $NoUserMinutes, ($sdArgs -join ' '))
        Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
        & shutdown.exe @sdArgs
    }
} else {
    Log ("No user for {0:N1} min (threshold {1})." -f $elapsed, $NoUserMinutes)
}
