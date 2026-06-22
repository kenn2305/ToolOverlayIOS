@echo off
chcp 65001 >nul
cd /d "%~dp0"
title OverlayIOSTOOL - Build .deb

echo ============================================
echo   OverlayIOSTOOL - Build 1 nut (.deb)
echo ============================================
echo.

where wsl >nul 2>&1
if errorlevel 1 goto NOWSL

for /f "usebackq delims=" %%i in (`wsl wslpath "%cd%"`) do set "LPATH=%%i"
if "%LPATH%"=="" goto NOPATH

rem Chua co bundle -> thu tu tai tu GitHub Release
if not exist "buildenv\OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz" (
    echo Chua co moi truong build, dang thu tai tu GitHub Release...
    wsl --cd "%LPATH%" -u root -- bash tools/fetch-bundle.sh
)

rem Co bundle -> build offline; khong co -> build online
set "BUILDSCRIPT=build.sh"
set "MODE=ONLINE (tu tai Theos/toolchain/SDK - can mang)"
if exist "buildenv\OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz" (
    set "BUILDSCRIPT=build-offline.sh"
    set "MODE=OFFLINE (dung bundle - nhanh, on dinh)"
)

echo Che do: %MODE%
echo Project (WSL): %LPATH%
echo.
echo Dang cai moi truong build + tao file .deb...
echo (Lan dau co the lau vai phut)
echo.

wsl --cd "%LPATH%" -u root -- bash ./%BUILDSCRIPT%
set RC=%errorlevel%

echo.
if not "%RC%"=="0" goto BUILDFAIL

echo ============================================
echo   BUILD XONG! File .deb nam trong thu muc:
echo   %cd%\packages
echo ============================================
start "" "%cd%\packages"
goto END

:NOWSL
echo [LOI] May nay chua co WSL.
echo Mo PowerShell (Run as Administrator) chay:  wsl --install -d Ubuntu-22.04
echo Khoi dong lai may roi bam lai file nay.
goto END

:NOPATH
echo [LOI] Khong doi duoc duong dan project sang WSL.
goto END

:BUILDFAIL
echo [LOI] Build that bai (xem log phia tren). Ma loi: %RC%
goto END

:END
echo.
pause
