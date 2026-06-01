@echo off
title TPDesktop One-Key Deploy v2.8.0

:: Auto-elevate
net session >nul 2>&1
if %errorLevel% equ 0 goto :admin_ok

whoami /groups 2>nul | findstr /i "S-1-16-12288" >nul 2>&1
if %errorLevel% equ 0 goto :admin_ok

echo.
echo  [INFO] Requesting administrator privileges...
powershell -Command "Start-Process -FilePath cmd.exe -ArgumentList '/c \"%~dp0deploy.bat\"' -Verb RunAs" >nul 2>&1
if %errorLevel% equ 0 exit /b

echo.
echo  ============================================================
echo  [ERROR] Auto-elevation failed! Please do ONE of these:
echo  ============================================================
echo.
echo  Option 1: Right-click deploy.bat ^> Run as administrator
echo.
echo  Option 2: Open CMD as admin, then type:
echo            "%~f0"
echo  ============================================================
pause
exit /b

:admin_ok
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
if %errorLevel% neq 0 (
    echo.
    echo  [ERROR] PowerShell script exited with error code %errorLevel%
    pause
)
popd
