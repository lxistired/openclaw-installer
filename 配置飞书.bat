@echo off
title OpenClaw - 飞书配置

echo.
echo  ================================================================
echo       OpenClaw - 飞书机器人配置工具
echo  ================================================================
echo.

:: Copy ps1 to TEMP to avoid Chinese path issues
set "DST=%TEMP%\openclaw-configure-feishu.ps1"
copy /Y "%~dp0configure-feishu.ps1" "%DST%" >nul 2>&1

if not exist "%DST%" (
    echo  [错误] 找不到 configure-feishu.ps1
    echo  [错误] 请确保 configure-feishu.ps1 与此 bat 文件在同一目录下。
    pause
    exit /b 1
)

:: Write original directory to temp file for ps1 to read
echo %~dp0> "%TEMP%\openclaw-original-dir.txt"

:: Copy guides directory to TEMP
if exist "%~dp0guides" (
    xcopy /Y /E /I "%~dp0guides" "%TEMP%\openclaw-guides\" >nul 2>&1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%DST%"
del /f /q "%DST%" >nul 2>&1
del /f /q "%TEMP%\openclaw-original-dir.txt" >nul 2>&1
echo.
pause
