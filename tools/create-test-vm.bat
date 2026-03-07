@echo off
chcp 65001 >nul
title OpenClaw 测试虚拟机 - 自动创建工具

echo.
echo  ================================================================
echo       OpenClaw 测试虚拟机创建工具
echo  ================================================================
echo.

:: 检查 VirtualBox
set "VBOX=C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if not exist "%VBOX%" (
    echo  [错误] 未检测到 VirtualBox
    echo  请先安装 VirtualBox: C:\Users\lxxxxxx\Downloads\VirtualBox-7.2.6-Win.exe
    echo.
    pause
    exit /b 1
)

echo  [OK] VirtualBox 已安装
"%VBOX%" --version

:: 检查 ISO
set "ISO_PATH="
echo.
echo  请将 Win11 ISO 文件拖到此窗口（或粘贴完整路径），然后按 Enter：
echo.
set /p ISO_PATH="  ISO 路径: "

:: 去掉可能的引号
set "ISO_PATH=%ISO_PATH:"=%"

if not exist "%ISO_PATH%" (
    echo.
    echo  [错误] 文件不存在: %ISO_PATH%
    echo.
    pause
    exit /b 1
)

echo  [OK] ISO 文件: %ISO_PATH%
echo.

:: 虚拟机参数
set "VM_NAME=OpenClaw-Test"
set "VM_DIR=%USERPROFILE%\VirtualBox VMs\%VM_NAME%"
set "VM_DISK=%VM_DIR%\%VM_NAME%.vdi"
set "SHARED_FOLDER=%~dp0.."

echo  即将创建虚拟机:
echo    名称: %VM_NAME%
echo    内存: 4096 MB
echo    CPU:  2 核
echo    磁盘: 60 GB (动态扩展)
echo    共享: %SHARED_FOLDER% -^> openclaw
echo.
echo  按任意键开始创建...
pause >nul

:: 如果同名虚拟机已存在，先删除
"%VBOX%" showvminfo "%VM_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo  检测到同名虚拟机，正在删除旧虚拟机...
    "%VBOX%" unregistervm "%VM_NAME%" --delete 2>nul
)

:: 创建虚拟机
echo  [1/8] 创建虚拟机...
"%VBOX%" createvm --name "%VM_NAME%" --ostype "Windows11_64" --register
if %errorlevel% neq 0 (
    echo  [错误] 创建虚拟机失败
    pause
    exit /b 1
)

:: 配置内存和 CPU
echo  [2/8] 配置硬件...
"%VBOX%" modifyvm "%VM_NAME%" --memory 4096 --cpus 2 --vram 128

:: 启用 EFI（Win11 需要）
echo  [3/8] 启用 EFI + TPM 2.0...
"%VBOX%" modifyvm "%VM_NAME%" --firmware efi
"%VBOX%" modifyvm "%VM_NAME%" --tpm-type 2.0

:: 创建硬盘
echo  [4/8] 创建虚拟硬盘 (60GB 动态)...
"%VBOX%" createmedium disk --filename "%VM_DISK%" --size 61440 --format VDI --variant Standard

:: 添加存储控制器
echo  [5/8] 配置存储...
"%VBOX%" storagectl "%VM_NAME%" --name "SATA" --add sata --controller IntelAhci --portcount 2
"%VBOX%" storageattach "%VM_NAME%" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "%VM_DISK%"
"%VBOX%" storageattach "%VM_NAME%" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "%ISO_PATH%"

:: 网络（NAT，可上网）
echo  [6/8] 配置网络...
"%VBOX%" modifyvm "%VM_NAME%" --nic1 nat

:: 共享文件夹（自动挂载）
echo  [7/8] 配置共享文件夹...
"%VBOX%" sharedfolder add "%VM_NAME%" --name "openclaw" --hostpath "%SHARED_FOLDER%" --automount --auto-mount-point "D:\openclaw"

:: 启动虚拟机
echo  [8/8] 启动虚拟机...
echo.
"%VBOX%" startvm "%VM_NAME%" --type gui

echo.
echo  ================================================================
echo   虚拟机已启动！
echo  ================================================================
echo.
echo  接下来：
echo    1. 按照 Win11 安装向导完成系统安装
echo    2. 安装完成后，在 VirtualBox 菜单栏选择:
echo       设备 -^> 安装增强功能 (Guest Additions)
echo    3. 重启虚拟机后，共享文件夹自动挂载到 D:\openclaw
echo    4. 双击 D:\openclaw\一键安装.bat 开始测试
echo.
echo  测试完成后，可直接删除虚拟机，宿主环境零污染。
echo.
pause
