# Idle Shutdown for Windows

Automatically shuts Windows down after a period of no keyboard/mouse activity, but
**skips the shutdown if the machine is actually busy** — an active remote session,
a running build or download, media playback, or high CPU/network load. Before
shutting down it shows a warning dialog with a countdown and a **Cancel** button;
moving the mouse also cancels.

## Files

| File | Purpose |
|------|---------|
| `IdleShutdown.ps1` | The main script. Watches for inactivity, checks whether the machine is busy, shows the warning, and shuts down. |
| `IdleShutdown.vbs` | Optional launcher that starts the PowerShell script **fully hidden** (no console window flashes at logon). |

Suggested location: `C:\Scripts\`. See the security note at the end about locking the folder down.

---

## How it works

1. Every 30 seconds the script checks how long the machine has been idle, using the
   Windows `GetLastInputInfo` API (real keyboard/mouse input — not just "screen on").
2. Once idle time reaches `IdleMinutes`, it runs a **busy check** before doing
   anything. If any of these are true it logs the reason, waits, and does *not* shut
   down:
   - **RDP** — an active (connected) remote desktop session exists.
   - **AnyDesk** — a *live* session is in progress. Detected via AnyDesk's CPU usage,
     so merely having AnyDesk installed/running does **not** block shutdown — only an
     actual connection does.
   - **Watched processes** — a download, build, or media player from the configured
     list is running (qBittorrent, OneDrive, Flutter/Dart, Java, Node, Docker, Erlang
     `erl`, babashka `bb`, VLC, etc.).
   - **CPU** at or above `CpuBusyPercent`.
   - **Network** at or above `NetBusyKBps`.
3. If the machine is genuinely idle, the warning dialog appears with a countdown.
   Clicking **Cancel shutdown**, pressing Esc, or moving the mouse cancels it.
4. If the countdown reaches zero, it re-checks "busy" one last time (in case a
   download started during the countdown) and then shuts down.

All decisions are written to a log file (default `%LOCALAPPDATA%\IdleShutdown.log`)
so you can see exactly why it shut down — or why it didn't.

---

## Parameters

All parameters are optional; the defaults are shown.

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-IdleMinutes` | `30` | Minutes of no keyboard/mouse input before the warning appears. |
| `-WarningSeconds` | `60` | Length of the cancellable countdown on the warning dialog. |
| `-CpuBusyPercent` | `25` | If total CPU is at/above this percent, the machine is considered busy and shutdown is skipped. |
| `-NetBusyKBps` | `200` | If total network throughput is at/above this (KB/s), shutdown is skipped. |
| `-AnyDeskCpuFrac` | `0.03` | AnyDesk CPU usage, as a fraction of one core, above which a live AnyDesk session is assumed (0.03 = 3% of one core). |
| `-Force` | *(off)* | Switch. When present, force-closes apps without letting them save (`shutdown /s /f`). When absent, a graceful shutdown lets apps prompt to save. |
| `-LogFile` | `%LOCALAPPDATA%\IdleShutdown.log` | Where decisions are logged. |

---

## Calling the script

Because the script can shut your machine down, the recommended way to run it is with
a **per-command execution-policy bypass** — this relaxes the policy for that single
run only and leaves the system default untouched.

Normal run with defaults (30 min idle, 60 s warning, graceful shutdown):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\IdleShutdown.ps1"
```

Custom values:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\IdleShutdown.ps1" -IdleMinutes 45 -WarningSeconds 90
```

Force-close apps on shutdown (use with care — no save prompts):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\IdleShutdown.ps1" -Force
```

### "running scripts is disabled on this system"

If you call the script **without** `-ExecutionPolicy Bypass`, Windows may block it:

```
... cannot be loaded because running scripts is disabled on this system.
```

Fix it either per-command (preferred) by adding the flag as shown above, or
permanently for your user only:

```
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`RemoteSigned` allows local scripts you wrote to run while still requiring downloaded
scripts to be signed. The per-command bypass is the more contained choice and is what
the scheduled task and the `.vbs` launcher already use, so changing the system policy
is not required.

---

## Testing it

Use short values so you don't have to wait 30 minutes. From a PowerShell window:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\IdleShutdown.ps1" -IdleMinutes 1 -WarningSeconds 15
```

Then **stop touching the keyboard and mouse**. After ~1 minute idle the warning
dialog should appear with a 15-second countdown.

- Click **Cancel shutdown** (or press Esc, or move the mouse) — it should cancel and
  the log should record "Cancelled by user/activity."
- Let the countdown finish — it should shut down (or, with no `-Force`, give apps a
  chance to prompt).

**Test the busy checks** (these should *prevent* shutdown — verify in the log):

- **Download / playback:** start a large download or open VLC, then let the machine
  go idle. The log should say it skipped with the process name or "network busy."
- **RDP:** connect via Remote Desktop, then let it idle. The log should report
  "active remote (RDP) session."
- **AnyDesk:** start a real AnyDesk session and let it idle. The log should report
  "active AnyDesk session." Disconnect and confirm it then proceeds normally. If a
  static-screen session slips through, lower `-AnyDeskCpuFrac` to `0.01`–`0.02`.

**Watch the log live** while testing:

```
Get-Content "$env:LOCALAPPDATA\IdleShutdown.log" -Wait -Tail 20
```

**Verify process names** for tools you care about (a wrong name silently matches
nothing). With each tool running:

```
Get-Process erl, bb, clojure, lein, dart, java -ErrorAction SilentlyContinue
```

If a tool isn't listed under one of the configured names, edit the `$BusyProcesses`
array near the top of `IdleShutdown.ps1`.

---

## Running it automatically at logon (Task Scheduler)

This is how to make Windows start the watcher every time you log in.

1. Open **Task Scheduler** → **Create Task** (not "Create Basic Task").
2. **General** tab:
   - Give it a name, e.g. `Idle Shutdown`.
   - Select **Run only when user is logged on** (required — the warning dialog must
     be visible on your desktop).
3. **Triggers** tab → **New** → Begin the task: **At log on** → your user.
4. **Actions** tab → **New** → Action: **Start a program**.
   - To show a brief console window, use:
     - Program/script: `powershell.exe`
     - Add arguments:
       `-NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\IdleShutdown.ps1"`
   - To run **fully hidden** (recommended), use the VBS launcher instead:
     - Program/script: `wscript.exe`
     - Add arguments: `"D:\Scripts\IdleShutdown.vbs"`
5. **Conditions** tab: if this is a desktop, uncheck **Start the task only if the
   computer is on AC power**.
6. **Settings** tab: uncheck **Stop the task if it runs longer than...** (the script
   is meant to run indefinitely).

To pass custom parameters from the task, append them to the Arguments field (for the
PowerShell action) or edit them inside the `.vbs` (for the wscript action). For
example, to force-close apps: add `-Force` to the end of the PowerShell arguments.

### The VBS launcher

`IdleShutdown.vbs` starts the script with no visible console window. Its content runs
PowerShell hidden; edit the path (and any parameters) inside it if your script lives
elsewhere:

```vbs
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""D:\Scripts\IdleShutdown.ps1""", 0, False
```

To add parameters, put them inside the inner quotes, e.g.
`...IdleShutdown.ps1"" -IdleMinutes 45 -Force`.

> Note: Windows is gradually deprecating VBScript. If the `.vbs` launcher ever stops
> working after an update, switch the task back to the `powershell.exe` action with
> `-WindowStyle Hidden` added, or use a shortcut set to "Minimized."

---

## Tuning the busy list

The `$BusyProcesses` array near the top of `IdleShutdown.ps1` controls which programs
block shutdown when running. Names are case-insensitive and **without** the `.exe`.
Notes on the trickier ones:

- **Elixir / Erlang:** on Windows the BEAM VM runs inside `erl.exe` (there is no
  separate `beam.smp` process as on Linux), so `erl` covers `mix`, `iex`, and Phoenix.
  `epmd` and `erlsrv` are intentionally excluded — they are persistent daemons/services
  that would block shutdown whenever Erlang is merely installed.
- **Clojure:** JVM-based work (`clj`, `clojure`, `lein`, `shadow-cljs`) already shows
  up as `java` or `node`, which are listed. `bb` (babashka) is a native GraalVM binary
  that does **not** use the JVM, so it is listed explicitly.
- **AnyDesk** is *not* in this list — it is handled separately by live-session
  detection, so installing/running AnyDesk alone won't block shutdown.

The CPU and network thresholds act as a backstop: even a heavy process whose name
isn't listed will usually be caught by `-CpuBusyPercent` or `-NetBusyKBps`.

---

## Known limitations

- **Idle detection is local input only.** Long-running work with no keyboard/mouse
  input is invisible to the idle timer itself — that's exactly why the busy checks
  (processes, CPU, network, remote sessions) exist as guards.
- **Disconnected RDP sessions.** If someone connects via RDP, does work, then closes
  the client *without logging off*, the session becomes "disconnected" and is not
  counted as active — the machine can still shut down, and with `-Force` it would not
  prompt to save the orphaned session's work. Be cautious with `-Force` on machines
  you RDP into.
- **AnyDesk static-screen sessions.** Detection is based on CPU; a connected session
  with a completely static screen and no interaction may register as low usage. Lower
  `-AnyDeskCpuFrac` if needed.
- **`qwinsta` text parsing is locale-sensitive.** On non-English Windows the RDP check
  relies on the words "Active"/"Console" appearing in English `qwinsta` output. Verify
  with `qwinsta` while connected if you run a localized Windows.
- **The warning dialog renders on the console session.** If the screen is off/locked
  or you're in a different remote/console context, you may not see it; note that
  waking the screen by moving the mouse also cancels the shutdown.

---

## Security note

Whatever folder holds `IdleShutdown.ps1` (and the `.vbs`) should be **writable by
administrators only**. The script runs at every logon with your privileges, so if a
non-admin process can rewrite it, that process effectively runs as you. This is the
most important hardening step in the whole setup — more so than the execution policy.
Running with the per-command `-ExecutionPolicy Bypass` (rather than loosening the
system-wide policy) keeps Windows' default protections in place for everything else.
