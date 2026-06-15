# Automatic Shutdown for Windows

Two complementary scheduled tasks that power a Windows machine down when it isn't
being used, plus scripts (and one-click wrappers) to install and remove them
**without touching the Task Scheduler GUI**.

| Scenario | Script | Runs as | Trigger |
|----------|--------|---------|---------|
| Logged in, but away from the keyboard | `IdleShutdown.ps1` | you (interactive) | at logon, then loops |
| Nobody logged on at all (lock/login screen) | `NoUserShutdown.ps1` | SYSTEM | every few minutes |

The two cover different gaps and can run together: `IdleShutdown` handles "signed in
but idle" and shows a cancellable warning; `NoUserShutdown` handles "no one is signed
in" and runs silently in the background.

The bundle is **relocatable** — put the folder wherever you like and everything
resolves relative to itself: the install/uninstall scripts default their `-ScriptsDir`
to their own location, and the `.cmd` / `.vbs` launchers resolve paths from theirs. No
path editing is needed. The examples below use `C:\Scripts`, but any path works.

---

## Files

| File | Purpose |
|------|---------|
| `IdleShutdown.ps1` | Inactivity watcher. Shuts down after no input for N minutes, unless the machine is busy (remote session, build, download, playback, high CPU/network). Shows a countdown dialog with a **Cancel** button first. |
| `NoUserShutdown.ps1` | "No user logged on" watcher. Shuts down once nobody has been logged on for N minutes. No dialog. |
| `Install-ShutdownTasks.ps1` | Registers both scheduled tasks and (by default) locks down the folders. **Self-elevates** via UAC if not run as admin. |
| `Uninstall-ShutdownTasks.ps1` | Removes the tasks; optionally the state/logs (`-RemoveState`) and the folder hardening (`-RestoreAcl`). Self-elevates. |
| `install (run as admin).cmd` | One-click launcher. Right-click -> **Run as administrator** to install with `-Force`. |
| `uninstall (run as admin).cmd` | One-click launcher. Right-click -> **Run as administrator** to fully uninstall (tasks + state + ACL restore). |
| `IdleShutdown.vbs` | *Optional.* Launches `IdleShutdown.ps1` with zero console flash. Only needed if you switch the idle task to use it (see the installer comments). |

---

## Quick start

Copy the script files plus the `.cmd` wrappers into a folder of your choice (these
examples use `C:\Scripts`), then **either**:

**Easiest — right-click `install (run as admin).cmd` -> Run as administrator.**
That installs with `-Force` and pauses at the end so you can read the result.

**Or run the installer directly** (it self-elevates — you do *not* need to open an
elevated prompt first; it shows a UAC prompt and keeps the elevated window open):

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Install-ShutdownTasks.ps1
```

To customize, pass parameters (these survive the UAC relaunch):

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Install-ShutdownTasks.ps1 -IdleMinutes 45 -WarningSeconds 90 -NoUserMinutes 20 -Force
```

**Verify** the tasks were created (this form does not error if they're absent):

```
Get-ScheduledTask | Where-Object TaskName -in 'IdleShutdown','NoUserShutdown' | Format-Table TaskName, State
```

### Uninstall

**Easiest — right-click `uninstall (run as admin).cmd` -> Run as administrator.**
This is a *full* uninstall: removes both tasks, deletes the state/log folder, and
restores default permissions on `C:\Scripts`. The script files themselves are left in
place (delete the `C:\Scripts` folder manually to remove them).

Or run the uninstaller directly (also self-elevates):

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Uninstall-ShutdownTasks.ps1 -RemoveState -RestoreAcl
```

Omit the switches to remove only the tasks and leave state/permissions untouched.

### Installer parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-ScriptsDir` | the script's own folder | Folder holding the scripts. Auto-detected (`$PSScriptRoot`); override only to point elsewhere. |
| `-IdleTaskUser` | current user | Account whose session shows the idle dialog. Override if you elevate with a different account than the one you log in with daily. |
| `-IdleMinutes` | `30` | Idle minutes before the warning. |
| `-WarningSeconds` | `60` | Countdown length. |
| `-NoUserMinutes` | `30` | Minutes with no user logged on before shutdown. |
| `-NoUserCheckMins` | `5` | How often the SYSTEM task runs. |
| `-Force` | off | Pass `-Force` to **both** scripts (force-close apps without save prompts). The install `.cmd` sets this. |
| `-NoLockDown` | off | Skip the folder ACL hardening. |

---

## Notes on the wrappers and elevation

- The whole set is **relocatable with no edits**. `Install-ShutdownTasks.ps1` and
  `Uninstall-ShutdownTasks.ps1` default `-ScriptsDir` to `$PSScriptRoot` (their own
  folder), the `.cmd` wrappers launch the installer via `%~dp0` (the folder the `.cmd`
  sits in), and `IdleShutdown.vbs` resolves its own folder too. Move the folder anywhere
  and everything still points at itself. The registered tasks are written with whatever
  absolute path the folder resolves to at install time, so if you later *move* the folder,
  re-run the installer from the new location to repoint the tasks.
- Both `Install-ShutdownTasks.ps1` and `Uninstall-ShutdownTasks.ps1` **self-elevate**:
  if launched un-elevated they relaunch through a UAC prompt (with `-NoExit`, so the
  elevated window stays open to show output). Running them from an already-elevated
  window skips the extra prompt and shows output inline.
- The **`.cmd` wrappers** get a native "Run as administrator" right-click entry (which
  `.ps1` files lack) and are **not** subject to PowerShell's execution policy, so the
  "running scripts is disabled" error can't occur on the wrapper itself.

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
2. Once idle >= `IdleMinutes`, it runs a **busy check** and skips (logging the reason) if:
   - an **RDP** session is connected;
   - a **live AnyDesk** session is detected (via AnyDesk's CPU - merely running AnyDesk does *not* block shutdown);
   - a **watched process** is running (downloads, builds, players - see the `$BusyProcesses` list in the script);
   - **CPU** >= `CpuBusyPercent`, or **network** >= `NetBusyKBps`.
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

### IdleShutdown - use short values

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\IdleShutdown.ps1 -IdleMinutes 1 -WarningSeconds 15
```

Stop touching the keyboard/mouse. After ~1 minute the dialog appears with a 15 s
countdown. Click **Cancel** (or move the mouse) to abort; let it run to confirm
shutdown. Test the busy guards by starting a download / opening VLC / connecting RDP
or AnyDesk while idle - the log should show it skipping. Watch the log live:

```
Get-Content "$env:LOCALAPPDATA\IdleShutdown.log" -Wait -Tail 20
```

### NoUserShutdown - use `-DryRun`

You can't watch the "no user" path while logged in, so use the dry-run switch, which
logs what it would do instead of shutting down. Register a fast dry-run task:

```
schtasks /Create /TN "NoUserShutdown" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F /TR "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\Scripts\NoUserShutdown.ps1\" -NoUserMinutes 2 -DryRun"
```

Then **sign out** (not just lock - locking still counts as logged on). Wait a few
minutes, sign back in, and read the log:

```
Get-Content "$env:ProgramData\IdleShutdown\nouser.log" -Tail 20
```

You should see the grace timer start, then a `DRYRUN: ... would shut down` line. Once
happy, re-run the installer (or recreate the task) without `-DryRun` and with your real
threshold. You can also sanity-check detection while logged in - it should report a
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
  `erlsrv` are intentionally excluded - they're persistent daemons/services that would
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
  is invisible to the idle timer - which is exactly why the busy checks exist as guards.
- **Disconnected RDP counts as "logged on"** in `NoUserShutdown` (its `explorer.exe`
  persists), so the machine won't shut down on top of a disconnected session's running
  programs. If you instead want "shut down when nobody is *actively connected*", that
  needs session-state detection (the locale-sensitive `qwinsta`/`quser` route).
- **In `IdleShutdown`, a disconnected RDP session is *not* counted as active**, so an
  idle machine can shut down with that session's unsaved work open - and `-Force` would
  skip the save prompts. Be cautious with `-Force` on machines you RDP into.
- **AnyDesk static-screen sessions** may register as low CPU; lower `-AnyDeskCpuFrac` if a
  connected-but-idle session slips through.
- **`qwinsta` text parsing is locale-sensitive.** The idle task's RDP check relies on the
  English words "Active"/"Console" in `qwinsta` output; verify on localized Windows.
- **The warning dialog renders on the console session.** If the screen is off/locked or
  you're in a different context you may not see it - and waking the screen by moving the
  mouse also cancels the shutdown.

---

## Security notes

- **Lock down `C:\Scripts`** (and `C:\ProgramData\IdleShutdown`). The installer does this
  by default using well-known SIDs: SYSTEM and Administrators get full control, Users get
  read/execute only. This matters because `NoUserShutdown` runs as **SYSTEM** and
  `IdleShutdown` runs at every logon - if a non-admin process could rewrite either script,
  it would run with those privileges. The full uninstall (`-RestoreAcl`) reverts this
  hardening back to default inheritance.
- **Use `-ExecutionPolicy Bypass` per command** (as all the examples do) rather than
  loosening the machine-wide execution policy, so Windows' default protections stay in
  place for everything else.
- **`-Force` removes the save-prompt safety net.** The install `.cmd` enables it for
  unattended shutdowns; if you'd rather have save prompts, install without `-Force`
  (run the installer directly instead of the `.cmd`).
