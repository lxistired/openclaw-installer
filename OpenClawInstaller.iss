; ============================================================================
; OpenClaw 一键安装包 - Inno Setup 打包脚本
; ============================================================================

#define MyAppName "OpenClaw"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "OpenClaw"
#define MyAppURL "https://github.com/openclaw/openclaw"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName} 一键安装包
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={tmp}\OpenClaw-Installer
DisableDirPage=yes
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=OpenClaw-Installer-v{#MyAppVersion}
SetupIconFile=
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
Uninstallable=no
CreateUninstallRegKey=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
; 主脚本
Source: "install.ps1"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion
Source: "configure-api.ps1"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion
Source: "configure-feishu.ps1"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion
Source: "uninstall.ps1"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion

; 批处理启动器
Source: "一键安装.bat"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion
Source: "配置API.bat"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion
Source: "配置飞书.bat"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion
Source: "一键卸载.bat"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion

; HTML 教程
Source: "guides\*"; DestDir: "{tmp}\openclaw-setup\guides"; Flags: ignoreversion recursesubdirs

; 版本信息
Source: "version.json"; DestDir: "{tmp}\openclaw-setup"; Flags: ignoreversion

; 同时复制工具到用户桌面方便后续使用
Source: "configure-api.ps1"; DestDir: "{userdesktop}\OpenClaw"; Flags: ignoreversion
Source: "configure-feishu.ps1"; DestDir: "{userdesktop}\OpenClaw"; Flags: ignoreversion
Source: "uninstall.ps1"; DestDir: "{userdesktop}\OpenClaw"; Flags: ignoreversion
Source: "配置API.bat"; DestDir: "{userdesktop}\OpenClaw"; Flags: ignoreversion
Source: "配置飞书.bat"; DestDir: "{userdesktop}\OpenClaw"; Flags: ignoreversion
Source: "一键卸载.bat"; DestDir: "{userdesktop}\OpenClaw"; Flags: ignoreversion
Source: "guides\*"; DestDir: "{userdesktop}\OpenClaw\guides"; Flags: ignoreversion recursesubdirs

[Run]
; 安装完成后自动运行主安装脚本
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\openclaw-setup\install.ps1"""; \
  WorkingDir: "{tmp}\openclaw-setup"; \
  Flags: runascurrentuser waituntilterminated; \
  StatusMsg: "正在安装 OpenClaw..."

[Messages]
WelcomeLabel1=欢迎使用 OpenClaw 一键安装包
WelcomeLabel2=本安装包将帮助您一键安装 OpenClaw AI 助手框架，并配置国产 AI 提供商（智谱/Kimi/MiniMax）和飞书机器人接入。%n%n点击「下一步」开始安装。
FinishedHeadingLabel=OpenClaw 安装完成
FinishedLabel=OpenClaw 已安装到您的电脑。%n%n桌面上已创建 OpenClaw 工具文件夹，包含配置和卸载工具。%n%n使用方法：打开终端，运行 openclaw gateway 启动服务。
