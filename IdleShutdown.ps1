# IdleShutdown.ps1
# Shuts down Windows after N minutes of no keyboard/mouse input,
# BUT skips shutdown if the machine is "busy": active remote session
# (RDP / AnyDesk / etc.), high CPU/network, or watched processes running.
# Shows a warning dialog with a Cancel button + countdown first.

param(
    [int]$IdleMinutes    = 30,    # minutes of no local input before warning
    [int]$WarningSeconds = 60,    # countdown length on the warning dialog
    [int]$CpuBusyPercent = 25,    # >= this avg CPU% => considered busy
    [int]$NetBusyKBps    = 200,   # >= this total net KB/s => considered busy
    [double]$AnyDeskCpuFrac = 0.03, # AnyDesk CPU as fraction of 1 core => live session
    [switch]$Force,               # if set, uses shutdown /f (force-close apps)
    [string]$LogFile     = "$env:LOCALAPPDATA\IdleShutdown.log"
)

# ---- single-instance guard -------------------------------------------------
$mutex = New-Object System.Threading.Mutex($false, "Global\IdleShutdownScript")
if (-not $mutex.WaitOne(0)) { exit }   # another copy already running

# ---- hide our own console window (no VBS) ----------------------------------
# An interactive scheduled task launches powershell with a console window, and
# -WindowStyle Hidden isn't reliable (it can re-show on RDP reconnect), so we
# hide it from here. A brief flash at startup is possible before it disappears.
# Wrapped in try/catch so a failure here never stops the watcher.
try {
    Add-Type -Name WinHide -Namespace Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    $__hwnd = [Native.WinHide]::GetConsoleWindow()
    if ($__hwnd -ne [IntPtr]::Zero) { [void][Native.WinHide]::ShowWindow($__hwnd, 0) }  # 0 = SW_HIDE
} catch {}

# ---- logging ---------------------------------------------------------------
function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

# Process names that should block shutdown if running (downloads / builds / playback).
# Match is case-insensitive, no .exe. Tune this list to your machine.
$BusyProcesses = @(
    # remote access (AnyDesk handled separately via active-session detection below)
    # 'rustdesk','TeamViewer','TeamViewer_Service','parsecd',
    # downloads / sync
    # 'qbittorrent','transmission-qt','aria2c',
    'wget','curl',
    # 'idman','fdm',
    # 'OneDrive','Dropbox',
    'rclone',
    # builds / dev (your workloads)
    'dart','flutter','gradle','java','node','msbuild','cl','link','cmake',
    'cargo','rustc','python','python3',
    # 'docker','dockerd','com.docker.backend',
    # Elixir / Erlang -- on Windows the BEAM VM runs *inside* erl.exe (there is
    # no separate beam.smp process as on Linux). epmd and erlsrv are persistent
    # daemon/service processes, so they are deliberately NOT listed (they'd block
    # shutdown whenever Erlang is merely installed).
    'erl','werl','escript',
    # Clojure -- JVM-based work (clj/clojure/lein/shadow-cljs) already shows up as
    # 'java'/'node' above. 'bb' (babashka) is a native GraalVM binary that does
    # NOT use the JVM, so it must be listed explicitly. clj-kondo is similar.
    # 'bb',
    'clj-kondo','clojure','clj','lein',
    # media playback
    'vlc','mpv','mpc-hc64','mpc-hc'#,'PotPlayerMini64','wmplayer','Spotify'
)

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class IdleTimer {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static double IdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        return (Environment.TickCount - lii.dwTime) / 1000.0;
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- busy detectors --------------------------------------------------------

# Active remote session: RDP shows up as an active session whose name is NOT
# "Console". AnyDesk/TeamViewer/etc. attach to the console session, so we catch
# those via their processes in $BusyProcesses below.
function Test-RemoteSession {
    try {
        $q = qwinsta 2>$null
        if ($q) {
            foreach ($line in $q) {
                # active session not on the physical console = remote (RDP)
                if ($line -match '\bActive\b' -and $line -notmatch '(?i)\bconsole\b') {
                    return $true
                }
            }
        }
    } catch {}
    # Fallback: any rdp listener with an established inbound connection
    try {
        $rdp = Get-NetTCPConnection -LocalPort 3389 -State Established -ErrorAction SilentlyContinue
        if ($rdp) { return $true }
    } catch {}
    return $false
}

# Active AnyDesk session: AnyDesk merely *running* sits at ~0% CPU; a *live*
# session (someone viewing/controlling) continuously uses CPU for screen
# capture/encode. We sample AnyDesk's total processor time over a few seconds
# and treat sustained CPU above a small fraction of one core as an active
# session. This is version-independent -- it doesn't depend on trace-log line
# formats, which change between AnyDesk releases.
function Test-AnyDeskActiveSession {
    param([double]$CpuFracThreshold, [int]$SampleMs = 4000)
    $p0 = Get-Process -Name 'AnyDesk' -ErrorAction SilentlyContinue
    if (-not $p0) { return $false }                  # not running => no session
    $t0 = ($p0 | Measure-Object -Property CPU -Sum).Sum
    Start-Sleep -Milliseconds $SampleMs
    $p1 = Get-Process -Name 'AnyDesk' -ErrorAction SilentlyContinue
    if (-not $p1) { return $false }
    $t1 = ($p1 | Measure-Object -Property CPU -Sum).Sum
    $frac = ($t1 - $t0) / ($SampleMs / 1000.0)       # processor-seconds per wall-second
    return ($frac -ge $CpuFracThreshold)
}

# Best-effort: last accepted incoming connection from AnyDesk's trace (log only).
# connection_trace.txt is UTF-16 and records connection *starts* with no end
# marker, so it can't tell us "still connected" -- used purely to enrich the log.
function Get-AnyDeskLastIncoming {
    $paths = @("$env:APPDATA\AnyDesk\connection_trace.txt",
               "$env:ProgramData\AnyDesk\connection_trace.txt")
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                $inc = Get-Content -Path $p -ErrorAction Stop |   # BOM auto-detects UTF-16
                       Where-Object { $_ -match 'Incoming' } | Select-Object -Last 1
                if ($inc) { return ($inc.Trim() -replace '\s+', ' ') }
            } catch {}
        }
    }
    return $null
}

function Get-BusyReason {
    # Returns a string reason if busy, or $null if idle/free to shut down.

    # 1. Remote sessions
    if (Test-RemoteSession) { return 'active remote (RDP) session' }
    if (Test-AnyDeskActiveSession -CpuFracThreshold $AnyDeskCpuFrac) {
        $who = Get-AnyDeskLastIncoming
        if ($who) { return "active AnyDesk session (last incoming: $who)" }
        return 'active AnyDesk session'
    }

    # 2. Watched processes (remote tools, downloads, builds, playback)
    $running = Get-Process -ErrorAction SilentlyContinue |
               Where-Object { $BusyProcesses -contains $_.ProcessName } |
               Select-Object -ExpandProperty ProcessName -Unique
    if ($running) { return "process active: $($running -join ', ')" }

    # 3. CPU load (sampled briefly)
    try {
        $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor |
                Where-Object { $_.Name -eq '_Total' }).PercentProcessorTime
        if ($cpu -ge $CpuBusyPercent) { return "CPU busy ($cpu%)" }
    } catch {}

    # 4. Network throughput
    try {
        $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface
        $kbps = ($net | Measure-Object -Property BytesTotalPersec -Sum).Sum / 1024
        if ($kbps -ge $NetBusyKBps) { return ("network busy ({0:N0} KB/s)" -f $kbps) }
    } catch {}

    return $null
}

# ---- warning dialog --------------------------------------------------------
function Show-ShutdownWarning {
    param([int]$Seconds)

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = 'Inactivity Shutdown'
    $form.Size            = New-Object System.Drawing.Size(420, 170)
    $form.StartPosition   = 'CenterScreen'
    $form.TopMost         = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Size     = New-Object System.Drawing.Size(380, 50)
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Font     = New-Object System.Drawing.Font('Segoe UI', 11)
    $form.Controls.Add($label)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text     = 'Cancel shutdown'
    $btn.Size     = New-Object System.Drawing.Size(160, 35)
    $btn.Location = New-Object System.Drawing.Point(130, 80)
    $btn.Add_Click({ $form.DialogResult = 'Cancel'; $form.Close() })
    $form.Controls.Add($btn)
    $form.CancelButton = $btn

    $script:remaining = $Seconds
    $label.Text = "No activity detected. Shutting down in $script:remaining seconds..."

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $script:remaining--
        $label.Text = "No activity detected. Shutting down in $script:remaining seconds..."
        if ([IdleTimer]::IdleSeconds() -lt 3) { $form.DialogResult = 'Cancel'; $form.Close() }
        if ($script:remaining -le 0)          { $form.DialogResult = 'OK';     $form.Close() }
    })

    $form.Add_Shown({ $form.Activate(); $timer.Start() })
    $result = $form.ShowDialog()
    $timer.Stop(); $timer.Dispose(); $form.Dispose()
    return $result
}

# ---- main loop -------------------------------------------------------------
Log "Started (idle=$IdleMinutes min, warn=$WarningSeconds s, force=$($Force.IsPresent))"
try {
    while ($true) {
        Start-Sleep -Seconds 30

        if (([IdleTimer]::IdleSeconds() / 60) -lt $IdleMinutes) { continue }

        # Idle long enough -- but is the machine actually busy?
        $reason = Get-BusyReason
        if ($reason) {
            Log "Idle reached but busy: $reason -- skipping."
            # back off so we don't re-check every 30s while busy
            Start-Sleep -Seconds 120
            continue
        }

        Log "Idle + free. Showing warning."
        $result = Show-ShutdownWarning -Seconds $WarningSeconds

        if ($result -eq 'OK') {
            # Final re-check in case something started during the countdown
            $reason = Get-BusyReason
            if ($reason) { Log "Aborted at last second: $reason"; continue }

            $sdArgs = if ($Force) { @('/s','/f','/t','0') } else { @('/s','/t','0') }
            Log "Shutting down ($($sdArgs -join ' '))."
            & shutdown.exe @sdArgs
            break
        } else {
            Log "Cancelled by user/activity."
        }
    }
}
finally {
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
