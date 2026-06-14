# Automatic Shutdown for Windows

Two complementary scheduled tasks that power a Windows machine down when it isn't
being used, plus scripts to install and remove them **without touching the Task
Scheduler GUI**.

| Scenario | Script | Runs as | Trigger |
|----------|--------|---------|---------|
| Logged in, but away from the keyboard | `IdleShutdown.ps1` | you (interactive) | at logon, then loops |
| Nobody logged on at all (lock/login screen) | `NoUserShutdown.ps1` | SYSTEM | every few minutes |

The two cover different gaps and can run together: `IdleShutdown` handles "signed in
but idle" and shows a cancellable warning; `NoUserShutdown` handles "no one is signed
in" and runs silently in the background.

All scripts assume the folder **`C:\Scripts`**. Change it with the installer's
`-ScriptsDir` parameter if you use a different location.

---

## Files

| File | Purpose |
|------|---------|
| `IdleShutdown.ps1` | Inactivity watcher. Shuts down after no input for N minutes, unless the machine is busy (remote session, build, download, playback, high CPU/network). Shows a countdown dialog with a **Cancel** button first. |
| `NoUserShutdown.ps1` | "No user logged on" watcher. Shuts down once nobody has been logged on for N minutes. No dialog. |
| `Install-ShutdownTasks.ps1` | Registers both scheduled tasks and (by default) locks down the folders. No GUI required. |
| `Uninstall-ShutdownTasks.ps1` | Removes both scheduled tasks. |
| `IdleShutdown.vbs` | *Optional.* Launches `IdleShutdown.ps1` with zero console flash. Only needed if you configure the idle task manually and want it fully hidden. |

---

## Quick start (recommended)

1. Copy `IdleShutdown.ps1`, `NoUserShutdown.ps1`, `Install-ShutdownTasks.ps1`, and
   `Uninstall-ShutdownTasks.ps1` into `C:\Scripts`.
2. Open **PowerShell as Administrator** (right-click → Run as administrator).
3. Run the installer:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Install-ShutdownTasks.ps1
   ```

That registers both tasks with sensible defaults (30 min idle, 60 s warning, 30 min
no-user, checked every 5 min) and hardens the folders. To customize:

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Install-ShutdownTasks.ps1 `
  -IdleMinutes 45 -WarningSeconds 90 -NoUserMinutes 20 -NoUserCheckMins 5
```

Confirm the tasks exist:

```
Get-ScheduledTask IdleShutdown, NoUserShutdown | Format-Table TaskName, State
```

To remove everything later:

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Uninstall-ShutdownTasks.ps1
```

### Installer parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-ScriptsDir` | `C:\Scripts` | Folder holding the scripts. |
| `-IdleTaskUser` | current user | Account whose session shows the idle dialog. Override if you elevate with a different account than the one you log in with daily. |
| `-IdleMinutes` | `30` | Idle minutes before the warning. |
| `-WarningSeconds` | `60` | Countdown length. |
| `-NoUserMinutes` | `30` | Minutes with no user logged on before shutdown. |
| `-NoUserCheckMins` | `5` | How often the SYSTEM task runs. |
| `-Force` | off | Pass `-Force` to **both** scripts (force-close apps without save prompts). |
| `-NoLockDown` | off | Skip the folder ACL hardening. |

---

## Manual setup (without the installer)

If you'd rather create the tasks by hand, these `schtasks` commands are the
equivalent. Run them from an **elevated** Command Prompt or PowerShell.

**NoUserShutdown** (SYSTEM, every 5 minutes, runs with no one logged in):

```
schtasks /Create /TN "NoUserShutdown" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F /TR "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\Scripts\NoUserShutdown.ps1\""
```

**IdleShutdown** (interactive, at logon, runs as you):

```
schtasks /Create /TN "IdleShutdown" /SC ONLOGON /IT /RL LIMITED /F /TR "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Scripts\IdleShutdown.ps1\""
```

> **Important gotcha for the idle task:** tasks created with `schtasks` get a default
> 3-day run limit, which would silently kill the idle loop after 72 hours. Remove the
> limit (the installer does this for you):
>
> ```
> $t = Get-ScheduledTask IdleShutdown; $t.Settings.ExecutionTimeLimit = 'PT0S'; Set-ScheduledTask IdleShutdown -Settings $t.Settings
> ```

### Or via the Task Scheduler GUI

The only settings that matter and differ between the two tasks:

- **IdleShutdown** — General tab: **Run only when user is logged on**. Trigger: **At
  log on**. Action: `powershell.exe` with arguments
  `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Scripts\IdleShutdown.ps1"`.
  Settings: turn off "Stop the task if it runs longer than..." (it loops forever).
- **NoUserShutdown** — General tab: **Run whether user is logged on or not**, change
  user to **SYSTEM**, **Run with highest privileges**. Trigger: **On a schedule**,
  **One time**, repeat every **5 minutes** indefinitely. Action: `powershell.exe` with
  `-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\NoUserShutdown.ps1"`.

The fully-hidden `IdleShutdown.vbs` launcher is an alternative idle-task action
(`wscript.exe "C:\Scripts\IdleShutdown.vbs"`) if the brief console flash bothers you.
Note Windows is deprecating VBScript, so the `-WindowStyle Hidden` approach above is
the more future-proof choice.

---

## Script parameters

### IdleShutdown.ps1

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-IdleMinutes` | `30` | Minutes of no keyboard/mouse input before the warning. |
| `-WarningSeconds` | `60` | Length of the cancellable countdown. |
| `-CpuBusyPercent` | `25` | At/above this total CPU%, the machine is "busy" and shutdown is skipped. |
| `-NetBusyKBps` | `200` | At/above this total network KB/s, shutdown is skipped. |
| `-AnyDeskCpuFrac` | `0.03` | AnyDesk CPU (fraction of one core) above which a *live* AnyDesk session is assumed. |
| `-Force` | off | Force-close apps on shutdown (`/s /f`), no save prompts. |
| `-LogFile` | `%LOCALAPPDATA%\IdleShutdown.log` | Decision log. |

### NoUserShutdown.ps1

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-NoUserMinutes` | `30` | Minutes with no interactive user before shutdown. |
| `-Force` | off | Force-close on shutdown. |
| `-DryRun` | off | Log what it *would* do instead of shutting down (for testing). |
| `-StateFile` | `%ProgramData%\IdleShutdown\nouser.flag` | Timestamp file tracking the grace period. |
| `-LogFile` | `%ProgramData%\IdleShutdown\nouser.log` | Decision log. |

---

## How each script decides to shut down

### IdleShutdown
1. Every 30 s it reads how long since the last keyboard/mouse input (`GetLastInputInfo`).
2. Once idle ≥ `IdleMinutes`, it runs a **busy check** and skips (logging the reason) if:
   - an **RDP** session is connected;
   - a **live AnyDesk** session is detected (via AnyDesk's CPU — merely running AnyDesk does *not* block shutdown);
   - a **watched process** is running (downloads, builds, players — see the `$BusyProcesses` list in the script);
   - **CPU** ≥ `CpuBusyPercent`, or **network** ≥ `NetBusyKBps`.
3. Otherwise it shows the countdown dialog. **Cancel**, Esc, or moving the mouse aborts.
4. At zero it re-checks "busy" once more (in case a download started mid-countdown), then shuts down.

### NoUserShutdown
1. Each run checks whether any interactive user is logged on, in a **locale-independent**
   way: every interactive desktop session (active, locked, or a disconnected RDP session
   whose programs are still running) has exactly one `explorer.exe` owned by that user.
2. If a user is present, it clears the grace timer and exits.
3. If nobody is present, it writes a timestamp the first time, and on later runs compares
   elapsed time to `NoUserMinutes`. Once exceeded, it shuts down.
4. If detection itself errors, it assumes a user *is* present and does nothing (fail-safe).

Both scripts log every decision, so you can always see why a shutdown did or didn't happen.

---

## Testing

### IdleShutdown — use short values

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\IdleShutdown.ps1 -IdleMinutes 1 -WarningSeconds 15
```

Stop touching the keyboard/mouse. After ~1 minute the dialog appears with a 15 s
countdown. Click **Cancel** (or move the mouse) to abort; let it run to confirm
shutdown. Test the busy guards by starting a download / opening VLC / connecting RDP
or AnyDesk while idle — the log should show it skipping. Watch the log live:

```
Get-Content "$env:LOCALAPPDATA\IdleShutdown.log" -Wait -Tail 20
```

### NoUserShutdown — use `-DryRun`

You can't watch the "no user" path while logged in, so use the dry-run switch, which
logs what it would do instead of shutting down. Register a fast dry-run task:

```
schtasks /Create /TN "NoUserShutdown" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F /TR "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\Scripts\NoUserShutdown.ps1\" -NoUserMinutes 2 -DryRun"
```

Then **sign out** (not just lock — locking still counts as logged on). Wait a few
minutes, sign back in, and read the log:

```
Get-Content "$env:ProgramData\IdleShutdown\nouser.log" -Tail 20
```

You should see the grace timer start, then a `DRYRUN: ... would shut down` line. Once
happy, re-run the installer (or recreate the task) without `-DryRun` and with your real
threshold. You can also sanity-check detection while logged in — it should report a
user present:

```
powershell -ExecutionPolicy Bypass -File C:\Scripts\NoUserShutdown.ps1 -DryRun
Get-Content "$env:ProgramData\IdleShutdown\nouser.log" -Tail 3
```

### Verifying process names (idle task)

A wrong process name silently matches nothing. With each tool running, confirm it
shows up under the name in `$BusyProcesses`:

```
Get-Process erl, bb, dart, java, node -ErrorAction SilentlyContinue
```

---

## Tuning the idle busy-list

`$BusyProcesses` near the top of `IdleShutdown.ps1` lists programs that block shutdown
while running (case-insensitive, no `.exe`). Notes:

- **Elixir / Erlang:** on Windows the BEAM VM runs *inside* `erl.exe` (no separate
  `beam.smp` as on Linux), so `erl` covers `mix`, `iex`, and Phoenix. `epmd` and
  `erlsrv` are intentionally excluded — they're persistent daemons/services that would
  block shutdown whenever Erlang is merely installed.
- **Clojure:** JVM work (`clj`, `clojure`, `lein`, `shadow-cljs`) already shows up as
  `java`/`node`. `bb` (babashka) is a native GraalVM binary that does *not* use the JVM,
  so it's listed explicitly.
- **AnyDesk** is handled by live-session detection, not this list, so installing/running
  AnyDesk alone won't block shutdown.

The CPU and network thresholds are a backstop for heavy processes whose names aren't listed.

---

## Known limitations

- **Idle detection is local input only.** Long-running work with no keyboard/mouse input
  is invisible to the idle timer — which is exactly why the busy checks exist as guards.
- **Disconnected RDP counts as "logged on"** in `NoUserShutdown` (its `explorer.exe`
  persists), so the machine won't shut down on top of a disconnected session's running
  programs. If you instead want "shut down when nobody is *actively connected*", that
  needs session-state detection (the locale-sensitive `qwinsta`/`quser` route).
- **In `IdleShutdown`, a disconnected RDP session is *not* counted as active**, so an
  idle machine can shut down with that session's unsaved work open — and `-Force` would
  skip the save prompts. Be cautious with `-Force` on machines you RDP into.
- **AnyDesk static-screen sessions** may register as low CPU; lower `-AnyDeskCpuFrac` if a
  connected-but-idle session slips through.
- **`qwinsta` text parsing is locale-sensitive.** The idle task's RDP check relies on the
  English words "Active"/"Console" in `qwinsta` output; verify on localized Windows.
- **The warning dialog renders on the console session.** If the screen is off/locked or
  you're in a different context you may not see it — and waking the screen by moving the
  mouse also cancels the shutdown.

---

## Security notes

- **Lock down `C:\Scripts`** (and `C:\ProgramData\IdleShutdown`). The installer does this
  by default using well-known SIDs: SYSTEM and Administrators get full control, Users get
  read/execute only. This matters because `NoUserShutdown` runs as **SYSTEM** and
  `IdleShutdown` runs at every logon — if a non-admin process could rewrite either script,
  it would run with those privileges. This is the single most important hardening step.
- **Use `-ExecutionPolicy Bypass` per command** (as all the examples do) rather than
  loosening the machine-wide execution policy, so Windows' default protections stay in
  place for everything else.
- **`-Force` removes the save-prompt safety net.** Leave it off unless you specifically
  want unconditional shutdowns; the default graceful shutdown lets apps prompt to save.
