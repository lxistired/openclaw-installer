@echo off
chcp 65001 >nul 2>&1
title OpenClaw - 启用 Windows Sandbox (Win11 Home)

:: ============================================================================
:: 在 Windows 11 Home 上启用 Windows Sandbox
:: Windows 11 Home 默认不包含 Sandbox，需通过 DISM 手动启用相关组件
:: 启用后需重启电脑，重启后可在开始菜单搜索 "Windows Sandbox" 打开
:: ============================================================================

:: 检查管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   [错误] 本脚本需要以管理员身份运行！
    echo.
    echo   请右键点击此文件，选择「以管理员身份运行」。
    echo.
    pause
    exit /b 1
)

echo.
echo   ================================================================
echo       OpenClaw - 启用 Windows Sandbox (Win11 Home)
echo   ================================================================
echo.
echo   本脚本将在 Windows 11 Home 上启用 Windows Sandbox 功能。
echo   启用后需要重启电脑。
echo.
echo   用途：在沙盒中测试 OpenClaw 安装包，不影响宿主系统。
echo.

set /p confirm="  按 Enter 继续，输入 Q 退出: "
if /i "%confirm%"=="Q" (
    echo   已取消。
    exit /b 0
)

echo.
echo   [1/2] 正在启用 Containers-DisposableClientVM (Sandbox 核心)...
dism /online /enable-feature /featurename:Containers-DisposableClientVM /all /norestart
if %errorlevel% neq 0 (
    echo.
    echo   [警告] Containers-DisposableClientVM 启用失败。
    echo   可能的原因：
    echo     - 当前 Windows 版本不支持（需要 Win10 1903+ 或 Win11）
    echo     - BIOS 中未启用虚拟化 (VT-x / AMD-V)
    echo.
)

echo.
echo   [2/2] 正在启用 VirtualMachinePlatform (虚拟化平台)...
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
if %errorlevel% neq 0 (
    echo.
    echo   [警告] VirtualMachinePlatform 启用失败。
    echo   请确认 BIOS 中已启用虚拟化功能。
    echo.
)

echo.
echo   ================================================================
echo       组件启用完成！
echo   ================================================================
echo.
echo   请重启电脑使更改生效。
echo   重启后，在开始菜单搜索 "Windows Sandbox" 即可打开沙盒。
echo.
echo   重启后，双击 tools\openclaw-sandbox.wsb 可直接启动
echo   带有 OpenClaw 安装包的沙盒环境。
echo.

set /p reboot="  是否立即重启? (y/N): "
if /i "%reboot%"=="y" (
    shutdown /r /t 10 /c "OpenClaw: 正在重启以启用 Windows Sandbox"
    echo   电脑将在 10 秒后重启...
) else (
    echo   请稍后手动重启电脑。
)

pause
