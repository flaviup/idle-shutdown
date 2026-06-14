' IdleShutdown.vbs
' Launches IdleShutdown.ps1 fully hidden (no console flash).
' Adjust the path below if you saved the script elsewhere.

Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Scripts\IdleShutdown.ps1"" -Force", 0, False
Set shell = Nothing
