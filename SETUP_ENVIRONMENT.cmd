@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Setup-Environment.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. Review the messages above.
  pause
  exit /b 1
)
echo.
echo Environment setup completed.
pause
