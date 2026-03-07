@echo off
title OpenClaw 一键安装

echo.
echo  ================================================================
echo       OpenClaw 一键安装程序
echo  ================================================================
echo.

:: Step 1: Copy files to TEMP (avoids Chinese/Unicode path issues)
set "DST=%TEMP%\openclaw-install.ps1"
copy /Y "%~dp0install.ps1" "%DST%" >nul 2>&1

if not exist "%DST%" (
    echo  [错误] 找不到 install.ps1
    echo  [错误] 请确保 install.ps1 与此 bat 文件在同一目录下。
    pause
    exit /b 1
)

:: Copy guides directory to TEMP
if exist "%~dp0guides" (
    xcopy /Y /E /I "%~dp0guides" "%TEMP%\openclaw-guides\" >nul 2>&1
)

:: Write original directory to temp file for ps1 to read
echo %~dp0> "%TEMP%\openclaw-original-dir.txt"

:: Step 2: Check if already admin (use goto to avoid stale %errorLevel% in if blocks)
net session >nul 2>&1
if %errorLevel% == 0 goto :run_as_admin
goto :elevate

:run_as_admin
echo  [OK] 已以管理员身份运行
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DST%"
if %errorLevel% NEQ 0 (
    echo.
    echo  [错误] 脚本执行出错，请查看上方提示信息。
    echo.
    pause
)
del /f /q "%DST%" >nul 2>&1
del /f /q "%TEMP%\openclaw-original-dir.txt" >nul 2>&1
echo.
timeout /t 3
goto :eof

:elevate
:: Not admin - request elevation via temp file approach
echo  [..] 正在请求管理员权限...
echo.

set "LAUNCHER=%TEMP%\openclaw-elevate.ps1"
> "%LAUNCHER%" echo $target = '%DST%'
>> "%LAUNCHER%" echo try {
>> "%LAUNCHER%" echo     $p = Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "%DST%"' -Verb RunAs -Wait -PassThru
>> "%LAUNCHER%" echo     if ($p.ExitCode -ne 0) {
>> "%LAUNCHER%" echo         Write-Host '  [ERROR] Script exited with error.' -ForegroundColor Red
>> "%LAUNCHER%" echo         Read-Host '  Press Enter to close'
>> "%LAUNCHER%" echo     }
>> "%LAUNCHER%" echo } catch {
>> "%LAUNCHER%" echo     Write-Host '  [ERROR] Administrator privileges required.' -ForegroundColor Red
>> "%LAUNCHER%" echo     Read-Host '  Press Enter'
>> "%LAUNCHER%" echo }

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"

del /f /q "%LAUNCHER%" >nul 2>&1
del /f /q "%DST%" >nul 2>&1
del /f /q "%TEMP%\openclaw-original-dir.txt" >nul 2>&1

echo.
echo  [OK] 完成，可以关闭此窗口。
timeout /t 3
