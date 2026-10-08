@echo off
setlocal
title DeepSeek Harness Desktop Installer
rem Keep Windows PowerShell 5.1 module loading isolated from PowerShell 7 paths.
set "PSModulePath="
set "INSTALLER=%~dp0install-desktop-windows.ps1"
if not exist "%INSTALLER%" (
  echo [FAIL] Missing install-desktop-windows.ps1
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Installation was not completed. Check the Error ID above.
pause
exit /b %RESULT%
