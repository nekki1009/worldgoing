@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_acceptance.ps1" -Suite c3 %*
set "RESULT=%ERRORLEVEL%"
pause
exit /b %RESULT%
