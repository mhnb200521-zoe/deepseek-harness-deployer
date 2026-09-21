@echo off
REM ============================================================
REM  DeepSeek Harness One-Click Installer - Windows 入口 (L0)
REM  双击本文件即可开始安装。
REM  作用: 极薄封装,以 Bypass 执行策略调用 install-windows.ps1
REM ============================================================
setlocal
title DeepSeek Harness Installer

echo.
echo   正在启动 DeepSeek Harness 安装程序...
echo.

REM 定位与本文件同目录的 PowerShell 脚本
set "PS1=%~dp0install-windows.ps1"

if not exist "%PS1%" (
  echo   [FAIL] 未找到 install-windows.ps1,请确认文件完整。 ^(DSH-E010^)
  echo.
  pause
  exit /b 1
)

REM 仅对本进程放开执行策略,不修改系统设置
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo   安装流程结束。
) else (
  echo   安装未成功完成 ^(exit %RC%^)。请查看上方 Error ID 与日志。
)
echo.
pause
endlocal
exit /b %RC%
