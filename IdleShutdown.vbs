' IdleShutdown.vbs
' Launches IdleShutdown.ps1 fully hidden (no console flash).
' Resolves its own folder, so it can live anywhere alongside IdleShutdown.ps1.

Dim shell, fso, here
Set fso   = CreateObject("Scripting.FileSystemObject")
here      = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\IdleShutdown.ps1""", 0, False
Set shell = Nothing
