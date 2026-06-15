@echo off
REM install (run as admin).cmd
REM Right-click this file -> "Run as administrator" to register the shutdown tasks.
REM %~dp0 resolves to the folder THIS file sits in, so the whole set can live
REM anywhere - no path editing needed. The pause keeps the window open.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ShutdownTasks.ps1" -Force

echo.
pause
