@echo off
REM uninstall (run as admin).cmd
REM Right-click this file -> "Run as administrator" to FULLY remove everything:
REM   - both scheduled tasks (IdleShutdown, NoUserShutdown)
REM   - the state/log folder (C:\ProgramData\IdleShutdown)
REM   - the folder-permission hardening on C:\Scripts (restores defaults)
REM The script files themselves are left in place; delete C:\Scripts to remove them.
REM The pause at the end keeps the window open so you can read the result.

powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Uninstall-ShutdownTasks.ps1" -RemoveState -RestoreAcl

echo.
pause
