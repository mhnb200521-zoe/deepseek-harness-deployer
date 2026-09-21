@echo off
REM ============================================================
REM  DeepSeek Harness Runtime Launcher Template (L4)
REM  真实安装后优先使用 <installRoot>\launcher\start-dsh.cmd。
REM  本模板用于交付包中从常见安装位置转发到实际启动器。
REM ============================================================
setlocal
title DeepSeek Harness

set "TARGET="

REM 兼容“模板被放到安装根目录\windows”或相邻目录的场景
if exist "%~dp0..\launcher\start-dsh.cmd" set "TARGET=%~dp0..\launcher\start-dsh.cmd"
if not defined TARGET if exist "D:\DeepSeekHarness\launcher\start-dsh.cmd" set "TARGET=D:\DeepSeekHarness\launcher\start-dsh.cmd"
if not defined TARGET if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\DeepSeekHarness\launcher\start-dsh.cmd" set "TARGET=%LOCALAPPDATA%\DeepSeekHarness\launcher\start-dsh.cmd"

if not defined TARGET (
  echo   [FAIL] 未找到已安装的 DeepSeek Harness 启动器。^(DSH-E010^)
  echo   请先运行 install-windows.cmd。
  echo.
  pause
  exit /b 1
)

call "%TARGET%" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
