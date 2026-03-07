# ============================================================================
# OpenClaw 一键卸载脚本 (Windows)
# ============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [信息] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [警告] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [错误] $Message" -ForegroundColor Red
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"
}

# ---------------------------------------------------------------------------
# 确认卸载
# ---------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Red
Write-Host "       OpenClaw 一键卸载工具" -ForegroundColor Red
Write-Host "  ================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  本工具将卸载 OpenClaw 并清理相关配置。" -ForegroundColor White
Write-Host ""
Write-Host "  将执行以下操作:" -ForegroundColor White
Write-Host "    1. 停止 OpenClaw 服务/进程" -ForegroundColor White
Write-Host "    2. 卸载 OpenClaw (npm uninstall)" -ForegroundColor White
Write-Host "    3. 清理配置文件 (可选)" -ForegroundColor White
Write-Host "    4. 卸载 Node.js / Git (可选)" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "  确定要卸载 OpenClaw 吗? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "  卸载已取消。" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  按 Enter 键退出"
    exit 0
}

# ---------------------------------------------------------------------------
# Step 1: 停止 OpenClaw 服务
# ---------------------------------------------------------------------------
Write-Step "步骤 1/4: 停止 OpenClaw 服务"

# 尝试使用 openclaw stop 命令
if (Get-Command "openclaw" -ErrorAction SilentlyContinue) {
    Write-Info "尝试停止 OpenClaw 服务..."
    try {
        & openclaw stop 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Info "OpenClaw 服务已停止"
    } catch {
        Write-Warn "openclaw stop 命令执行失败，尝试终止进程..."
    }
}

# 终止相关进程
$processes = Get-Process -Name "openclaw" -ErrorAction SilentlyContinue
if ($processes) {
    Write-Info "发现 OpenClaw 进程，正在终止..."
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Info "OpenClaw 进程已终止"
} else {
    Write-Info "未发现运行中的 OpenClaw 进程"
}

# ---------------------------------------------------------------------------
# Step 2: 卸载 OpenClaw
# ---------------------------------------------------------------------------
Write-Step "步骤 2/4: 卸载 OpenClaw"

if (Get-Command "npm" -ErrorAction SilentlyContinue) {
    Write-Info "正在通过 npm 卸载 OpenClaw..."
    try {
        & npm uninstall -g openclaw 2>&1 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
        Refresh-Path

        if (-not (Get-Command "openclaw" -ErrorAction SilentlyContinue)) {
            Write-Info "OpenClaw 卸载成功"
        } else {
            Write-Warn "openclaw 命令仍可用，可能需要重启终端"
        }
    } catch {
        Write-Err "OpenClaw 卸载失败: $_"
        Write-Err "请手动运行: npm uninstall -g openclaw"
    }
} else {
    Write-Warn "npm 未找到，跳过 npm 卸载步骤"
}

# ---------------------------------------------------------------------------
# Step 3: 清理配置文件
# ---------------------------------------------------------------------------
Write-Step "步骤 3/4: 清理配置文件"

$openclawConfigDir = "$env:USERPROFILE\.openclaw"
$claudeConfigDir   = "$env:USERPROFILE\.claude"
$claudeJsonFile    = "$env:USERPROFILE\.claude.json"

# OpenClaw 配置
if (Test-Path $openclawConfigDir) {
    $cleanOpenClaw = Read-Host "  是否删除 OpenClaw 配置目录 ($openclawConfigDir)? (y/N)"
    if ($cleanOpenClaw -eq 'y' -or $cleanOpenClaw -eq 'Y') {
        Remove-Item -Path $openclawConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Info "OpenClaw 配置目录已删除"
    } else {
        Write-Info "保留 OpenClaw 配置目录"
    }
} else {
    Write-Info "OpenClaw 配置目录不存在，跳过"
}

# Claude ​Code 兼容配置 — 恢复备份或清理 OpenClaw 相关字段
if (Test-Path $claudeConfigDir) {
    # 查找 OpenClaw 创建的 settings.json 备份（最早的备份 = 安装前原始配置）
    $backupFiles = Get-ChildItem -Path $claudeConfigDir -Filter "settings.json.openclaw-backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
    if ($backupFiles -and $backupFiles.Count -gt 0) {
        $oldestBackup = $backupFiles[0]
        Write-Host ""
        Write-Host "  发现 OpenClaw 安装前的 settings.json 备份:" -ForegroundColor Cyan
        Write-Host "    $($oldestBackup.Name)  ($($oldestBackup.LastWriteTime))" -ForegroundColor White
        Write-Host ""
        $restoreSettings = Read-Host "  是否恢复安装前的 settings.json? (Y/n)"
        if ($restoreSettings -ne 'n' -and $restoreSettings -ne 'N') {
            Copy-Item -Path $oldestBackup.FullName -Destination "$claudeConfigDir\settings.json" -Force
            Write-Info "已恢复 settings.json 到安装前状态"
            # 清理所有备份文件
            $backupFiles | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
            Write-Info "已清理备份文件"
        } else {
            Write-Info "保留当前 settings.json"
        }
    }

    # 恢复 api-key-helper.cmd 备份
    $helperBackup = "$claudeConfigDir\api-key-helper.cmd.openclaw-backup"
    if (Test-Path $helperBackup) {
        Copy-Item -Path $helperBackup -Destination "$claudeConfigDir\api-key-helper.cmd" -Force
        Remove-Item -Path $helperBackup -Force -ErrorAction SilentlyContinue
        Write-Info "已恢复 api-key-helper.cmd"
    } elseif (Test-Path "$claudeConfigDir\api-key-helper.cmd") {
        $cleanHelper = Read-Host "  是否删除 OpenClaw 创建的 api-key-helper.cmd? (y/N)"
        if ($cleanHelper -eq 'y' -or $cleanHelper -eq 'Y') {
            Remove-Item -Path "$claudeConfigDir\api-key-helper.cmd" -Force -ErrorAction SilentlyContinue
            Write-Info "已删除 api-key-helper.cmd"
        }
    }

    # 清理 auth-profiles.json（OpenClaw 创建的 API provider 注册文件）
    $authProfilesPath = "$claudeConfigDir\auth-profiles.json"
    if (Test-Path $authProfilesPath) {
        $cleanAuthProfiles = Read-Host "  是否删除 OpenClaw 创建的 auth-profiles.json? (y/N)"
        if ($cleanAuthProfiles -eq 'y' -or $cleanAuthProfiles -eq 'Y') {
            Remove-Item -Path $authProfilesPath -Force -ErrorAction SilentlyContinue
            Write-Info "已删除 auth-profiles.json"
        }
    }

    # 不再提供删除整个 .claude 目录的选项（可能包含用户的 Claude Code 配置）
    Write-Info "保留 Claude Code 配置目录（可能包含您的其他配置）"
}

# .claude.json — 不再无条件删除，询问用户
if (Test-Path $claudeJsonFile) {
    $cleanClaudeJson = Read-Host "  是否删除 $claudeJsonFile? (不建议，可能影响 Claude Code) (y/N)"
    if ($cleanClaudeJson -eq 'y' -or $cleanClaudeJson -eq 'Y') {
        Remove-Item -Path $claudeJsonFile -Force -ErrorAction SilentlyContinue
        Write-Info "已清理 $claudeJsonFile"
    } else {
        Write-Info "保留 $claudeJsonFile"
    }
}

# ---------------------------------------------------------------------------
# Step 4: 可选卸载 Node.js / Git
# ---------------------------------------------------------------------------
Write-Step "步骤 4/4: 可选 - 卸载 Node.js / Git"

Write-Host "  以下组件是 OpenClaw 安装时可能安装的：" -ForegroundColor White
Write-Host ""

# Node.js
if (Get-Command "node" -ErrorAction SilentlyContinue) {
    $nodeVer = & node --version 2>$null
    Write-Host "    Node.js $nodeVer — 已安装" -ForegroundColor White

    $uninstallNode = Read-Host "  是否卸载 Node.js? (如果其他程序也在使用则不建议卸载) (y/N)"
    if ($uninstallNode -eq 'y' -or $uninstallNode -eq 'Y') {
        Write-Info "正在卸载 Node.js..."
        # 通过注册表查找 Node.js 卸载命令
        $nodeUninstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "Node.js*" } |
            Select-Object -First 1

        if ($nodeUninstall -and $nodeUninstall.UninstallString) {
            $uninstCmd = $nodeUninstall.UninstallString
            if ($uninstCmd -match "msiexec") {
                # MSI 卸载
                $productCode = if ($uninstCmd -match '\{[^}]+\}') { $Matches[0] } else { "" }
                if ($productCode) {
                    Start-Process "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait
                    Write-Info "Node.js 卸载完成"
                }
            }
        } else {
            Write-Warn "未找到 Node.js 卸载信息，请通过「设置 → 应用」手动卸载"
        }
    }
} else {
    Write-Info "Node.js 未安装，跳过"
}

Write-Host ""

# Git
if (Get-Command "git" -ErrorAction SilentlyContinue) {
    $gitVer = & git --version 2>$null
    Write-Host "    $gitVer — 已安装" -ForegroundColor White

    $uninstallGit = Read-Host "  是否卸载 Git? (如果其他程序也在使用则不建议卸载) (y/N)"
    if ($uninstallGit -eq 'y' -or $uninstallGit -eq 'Y') {
        Write-Info "正在卸载 Git..."
        $gitUninstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "Git*" } |
            Select-Object -First 1

        if ($gitUninstall -and $gitUninstall.UninstallString) {
            $uninstExe = $gitUninstall.UninstallString -replace '"', ''
            if (Test-Path $uninstExe) {
                Start-Process $uninstExe -ArgumentList "/VERYSILENT /NORESTART" -Wait
                Write-Info "Git 卸载完成"
            }
        } else {
            Write-Warn "未找到 Git 卸载信息，请通过「设置 → 应用」手动卸载"
        }
    }
} else {
    Write-Info "Git 未安装，跳过"
}

# ---------------------------------------------------------------------------
# 卸载完成
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Green
Write-Host "       卸载完成!" -ForegroundColor Green
Write-Host "  ================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  卸载汇总:" -ForegroundColor White

# 检查各项状态
Refresh-Path

if (-not (Get-Command "openclaw" -ErrorAction SilentlyContinue)) {
    Write-Host "    [OK] OpenClaw 已卸载" -ForegroundColor Green
} else {
    Write-Host "    [!!] OpenClaw 仍可用 (请重启终端)" -ForegroundColor Yellow
}

if (-not (Test-Path $openclawConfigDir)) {
    Write-Host "    [OK] OpenClaw 配置已清理" -ForegroundColor Green
} else {
    Write-Host "    [--] OpenClaw 配置已保留" -ForegroundColor Gray
}

if (-not (Test-Path $claudeConfigDir)) {
    Write-Host "    [OK] Claude ​Code 配置已清理" -ForegroundColor Green
} else {
    Write-Host "    [--] Claude ​Code 配置已保留" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  如需重新安装，请运行 一键安装.bat" -ForegroundColor Gray
Write-Host ""
Read-Host "  按 Enter 键退出"
