@echo off
setlocal
pwsh -NoProfile -File "%~dp0scripts\sync-repository.ps1" -Action Pull %*
exit /b %errorlevel%
