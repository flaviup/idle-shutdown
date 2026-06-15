@echo off
REM uninstall (run as admin).cmd
REM Right-click this file -> "Run as administrator" to FULLY remove everything:
REM   - both scheduled tasks (IdleShutdown, NoUserShutdown)
REM   - the state/log folder (%ProgramData%\IdleShutdown)
REM   - the folder-permission hardening on the scripts folder (restores defaults)
REM %~dp0 resolves to the folder THIS file sits in, so it works wherever the set
REM lives. The script files themselves are left in place; delete the folder to
REM remove them. The pause keeps the window open so you can read the result.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-ShutdownTasks.ps1" -RemoveState -RestoreAcl

echo.
pause
