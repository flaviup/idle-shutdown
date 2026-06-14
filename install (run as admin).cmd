@echo off
REM install (run as admin).cmd
REM Right-click this file -> "Run as administrator" to register the shutdown tasks.
REM The pause at the end keeps the window open so you can read the result.

powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Install-ShutdownTasks.ps1" -Force

echo.
pause
