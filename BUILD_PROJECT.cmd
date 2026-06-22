@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Build-Project.ps1"
if errorlevel 1 (
  echo.
  echo Build failed. Review the messages above.
  pause
  exit /b 1
)
echo.
echo Build completed. The package is in the packages folder.
pause
