# ============================================================================
# OpenClaw 飞书配置工具
# 管理飞书机器人接入配置
# ============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 强制 TLS 1.2/1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 获取脚本所在目录
$SCRIPT_DIR = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# 如果从 TEMP 执行，原始目录通过临时文件或环境变量传入
$origDirFile = "$env:TEMP\openclaw-original-dir.txt"
if (Test-Path $origDirFile) {
    $origDir = (Get-Content $origDirFile -Raw).Trim()
    if ($origDir) { $SCRIPT_DIR = $origDir }
} elseif ($env:OPENCLAW_ORIGINAL_DIR) {
    $SCRIPT_DIR = $env:OPENCLAW_ORIGINAL_DIR
}

$OPENCLAW_CONFIG = "$env:USERPROFILE\.openclaw"
$CONFIG_FILE     = Join-Path $OPENCLAW_CONFIG "openclaw.json"

function Get-CurrentConfig {
    if (-not (Test-Path $CONFIG_FILE)) { return $null }
    try {
        return Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-FeishuInfo {
    $config = Get-CurrentConfig
    if (-not $config -or -not $config.channels -or -not $config.channels.feishu) {
        return @{ AppId = ""; AppSecret = ""; BotName = ""; Configured = $false }
    }
    $feishu = $config.channels.feishu
    $main   = $feishu.accounts.main
    return @{
        AppId      = if ($main.appId) { $main.appId } else { "" }
        AppSecret  = if ($main.appSecret) { $main.appSecret } else { "" }
        BotName    = if ($main.botName) { $main.botName } else { "" }
        Configured = [bool]$main.appId
    }
}

function Show-CurrentConfig {
    $info = Get-FeishuInfo

    Write-Host ""
    Write-Host "  当前配置:" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────" -ForegroundColor Gray

    if ($info.Configured) {
        Write-Host "    App ID   = $($info.AppId)" -ForegroundColor White
        if ($info.AppSecret) {
            $masked = $info.AppSecret.Substring(0, [Math]::Min(8, $info.AppSecret.Length)) + "****"
            Write-Host "    Secret   = $masked" -ForegroundColor White
        }
        Write-Host "    机器人名 = $($info.BotName)" -ForegroundColor White

        # 检查 openclaw 进程是否在运行
        $running = Get-Process -Name "openclaw" -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host "    状态     = 运行中" -ForegroundColor Green
        } else {
            Write-Host "    状态     = 未运行" -ForegroundColor Gray
        }
    } else {
        Write-Host "    (尚未配置飞书)" -ForegroundColor DarkGray
    }

    Write-Host "  ────────────────────────────────────────" -ForegroundColor Gray
    Write-Host ""
}

function Set-FeishuConfig {
    param(
        [string]$AppId,
        [string]$AppSecret,
        [string]$BotName
    )

    # 确保配置目录存在
    if (-not (Test-Path $OPENCLAW_CONFIG)) {
        New-Item -ItemType Directory -Path $OPENCLAW_CONFIG -Force | Out-Null
    }

    # 读取现有配置或创建新的
    $config = $null
    if (Test-Path $CONFIG_FILE) {
        try {
            $config = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        } catch {
            $config = @{}
        }
    }
    if (-not $config) { $config = @{} }

    # 写入飞书配置
    $config["channels"] = [ordered]@{
        feishu = [ordered]@{
            enabled  = $true
            accounts = [ordered]@{
                main = [ordered]@{
                    appId     = $AppId
                    appSecret = $AppSecret
                    botName   = $BotName
                }
            }
            typingIndicator    = $true
            resolveSenderNames = $true
            streaming          = $true
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($CONFIG_FILE, ($config | ConvertTo-Json -Depth 10), $utf8NoBom)
}

function Test-FeishuConnection {
    Write-Host "  ── 飞书连接诊断 ──────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    $info = Get-FeishuInfo
    if (-not $info.Configured) {
        Write-Host "  [错误] 飞书未配置" -ForegroundColor Red
        return
    }

    $allPassed = $true

    # ── 1. 凭证验证：获取 tenant_access_token ──
    Write-Host "  [1/5] 凭证验证..." -ForegroundColor White
    $token = $null
    try {
        $body = @{
            app_id     = $info.AppId
            app_secret = $info.AppSecret
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" `
            -Method POST -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 15

        if ($response.code -eq 0) {
            $token = $response.tenant_access_token
            Write-Host "    [OK] Tenant Access Token 获取成功" -ForegroundColor Green
        } else {
            Write-Host "    [失败] 错误码 $($response.code): $($response.msg)" -ForegroundColor Red
            $allPassed = $false
            Write-Host ""
            Write-Host "  凭证验证失败，后续检查无法进行。" -ForegroundColor Red
            Write-Host "  请确认 App ID 和 App Secret 是否正确。" -ForegroundColor Yellow
            return
        }
    } catch {
        Write-Host "    [失败] 连接错误: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
        return
    }

    # ── 2. 机器人能力检查 ──
    Write-Host "  [2/5] 机器人能力检查..." -ForegroundColor White
    try {
        $headers = @{ "Authorization" = "Bearer $token" }
        $appResp = Invoke-RestMethod -Uri "https://open.feishu.cn/open-apis/bot/v3/info" `
            -Method GET -Headers $headers -TimeoutSec 15

        if ($appResp.code -eq 0 -and $appResp.bot) {
            Write-Host "    [OK] 机器人能力已启用 — $($appResp.bot.app_name)" -ForegroundColor Green
        } elseif ($appResp.code -eq 0) {
            Write-Host "    [OK] 接口可访问（请确认已添加机器人能力）" -ForegroundColor Green
        } else {
            Write-Host "    [警告] 接口返回错误码 $($appResp.code): $($appResp.msg)" -ForegroundColor Yellow
            Write-Host "    请在飞书开放平台「应用能力」中添加「机器人」能力" -ForegroundColor Yellow
            $allPassed = $false
        }
    } catch {
        Write-Host "    [警告] 无法检查机器人能力: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "    请手动确认已在「应用能力」中添加了「机器人」" -ForegroundColor Yellow
        $allPassed = $false
    }

    # ── 3. 权限提示 ──
    Write-Host "  [3/5] 必需权限清单..." -ForegroundColor White
    Write-Host "    请确认以下权限已全部开通：" -ForegroundColor White
    $permissions = @(
        "contact:user.employee_id:readonly",
        "contact:user.base:readonly",
        "im:chat.access_event.bot_p2p_chat:read",
        "im:chat.members:bot_access",
        "im:message",
        "im:message.group_at_msg:readonly",
        "im:message.p2p_msg:readonly",
        "im:message:readonly",
        "im:message:send_as_bot",
        "im:message.reactions:read",
        "im:resource"
    )
    foreach ($p in $permissions) {
        Write-Host "      - $p" -ForegroundColor Gray
    }
    Write-Host "    [提示] 可在「权限管理」中使用 JSON 批量导入（见教程步骤 2）" -ForegroundColor Cyan

    # ── 4. 发布状态检查 ──
    Write-Host "  [4/5] 应用发布状态..." -ForegroundColor White
    try {
        $headers = @{ "Authorization" = "Bearer $token" }
        $botInfoResp = Invoke-RestMethod -Uri "https://open.feishu.cn/open-apis/bot/v3/info" `
            -Method GET -Headers $headers -TimeoutSec 15

        if ($botInfoResp.code -eq 0 -and $botInfoResp.bot) {
            $openId = $botInfoResp.bot.open_id
            if ($openId) {
                Write-Host "    [OK] 应用已发布 (Bot Open ID: $openId)" -ForegroundColor Green
            } else {
                Write-Host "    [警告] 应用可能未发布或未审批通过" -ForegroundColor Yellow
                $allPassed = $false
            }
        } else {
            Write-Host "    [警告] 无法确认发布状态 — 请确认应用已在「版本管理与发布」中发布并审批通过" -ForegroundColor Yellow
            $allPassed = $false
        }
    } catch {
        Write-Host "    [警告] 无法检查发布状态: $($_.Exception.Message)" -ForegroundColor Yellow
        $allPassed = $false
    }

    # ── 5. 手动确认提示 ──
    Write-Host "  [5/5] 事件订阅配置（需手动确认）..." -ForegroundColor White
    Write-Host "    请在飞书开放平台确认以下配置：" -ForegroundColor White
    Write-Host "      1. 事件订阅方式 = 「使用长连接接收事件」(WebSocket)" -ForegroundColor White
    Write-Host "      2. 已添加事件 = im.message.receive_v1（接收消息）" -ForegroundColor White
    Write-Host "    ⚠ 这两项无法通过 API 检测，请务必手动确认！" -ForegroundColor Yellow

    # ── 总结 ──
    Write-Host ""
    if ($allPassed) {
        Write-Host "  ══ 诊断结果：全部通过 ══" -ForegroundColor Green
        Write-Host "  如果机器人仍无响应，请检查事件订阅和 Pairing 配对（菜单选项 5）。" -ForegroundColor White
    } else {
        Write-Host "  ══ 诊断结果：存在问题（见上方黄色/红色提示）══" -ForegroundColor Yellow
    }
}

function Open-Guide {
    param([string]$GuideFile)
    # 优先从 TEMP 的 openclaw-guides 查找
    $tempGuidePath = "$env:TEMP\openclaw-guides\$GuideFile"
    if (Test-Path $tempGuidePath) {
        Start-Process $tempGuidePath
        return
    }
    $guidePath = Join-Path $SCRIPT_DIR "guides\$GuideFile"
    if (Test-Path $guidePath) {
        Start-Process $guidePath
    } else {
        Write-Host "  [警告] 教程文件未找到: $GuideFile" -ForegroundColor Yellow
    }
}

function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -isnot [Array] -and $InputObject.GetType().Name -eq 'PSCustomObject') {
            $hash = [ordered]@{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
            }
            return $hash
        }
        if ($InputObject -is [Array]) {
            $arr = @()
            foreach ($item in $InputObject) {
                $arr += ,(ConvertTo-Hashtable $item)
            }
            return ,$arr
        }
        return $InputObject
    }
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Magenta
    Write-Host "       OpenClaw - 飞书配置工具" -ForegroundColor Magenta
    Write-Host "  ================================================================" -ForegroundColor Magenta

    Show-CurrentConfig

    Write-Host "  操作:" -ForegroundColor White
    Write-Host "    [1] 重新配置飞书凭证" -ForegroundColor White
    Write-Host "    [2] 修改机器人名称" -ForegroundColor White
    Write-Host "    [3] 测试飞书连接 (全面诊断)" -ForegroundColor White
    Write-Host "    [4] 查看飞书教程" -ForegroundColor White
    Write-Host "    [5] 配对设备 (Pairing)" -ForegroundColor White
    Write-Host "    [Q] 退出" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "  请输入选项"

    if ($choice -eq 'Q' -or $choice -eq 'q') {
        Write-Host ""
        Write-Host "  配置工具已退出。" -ForegroundColor Yellow
        Write-Host ""
        break
    }

    # ── [1] 重新配置飞书凭证 ──
    if ($choice -eq "1") {
        Write-Host ""
        Write-Host "  ── 配置飞书机器人 ──────────────────────────" -ForegroundColor Cyan
        Write-Host ""

        $openBrowser = Read-Host "  是否打开浏览器和教程? (Y/n)"
        if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
            Start-Process "https://open.feishu.cn/app"
            Open-Guide "feishu-setup.html"
        }

        Write-Host ""
        $appId = Read-Host "  请输入飞书 App ID (格式: cli_xxx)"
        if ([string]::IsNullOrWhiteSpace($appId)) {
            Write-Host "  [警告] 未输入 App ID，操作取消" -ForegroundColor Yellow
            Read-Host "  按 Enter 返回主菜单"
            continue
        }

        $appSecret = Read-Host "  请输入飞书 App Secret"
        if ([string]::IsNullOrWhiteSpace($appSecret)) {
            Write-Host "  [警告] 未输入 App Secret，操作取消" -ForegroundColor Yellow
            Read-Host "  按 Enter 返回主菜单"
            continue
        }

        $botNameInput = Read-Host "  请输入机器人名称 (默认: 我的AI助手)"
        $botName = if ([string]::IsNullOrWhiteSpace($botNameInput)) { "我的AI助手" } else { $botNameInput.Trim() }

        Set-FeishuConfig -AppId $appId.Trim() -AppSecret $appSecret.Trim() -BotName $botName

        Write-Host ""
        Write-Host "  [成功] 飞书配置完成!" -ForegroundColor Green
        Write-Host "  App ID:    $($appId.Trim())" -ForegroundColor Green
        Write-Host "  机器人名:  $botName" -ForegroundColor Green
        Write-Host ""

        # 自动测试
        $doTest = Read-Host "  是否立即测试连接? (Y/n)"
        if ($doTest -ne 'n' -and $doTest -ne 'N') {
            Test-FeishuConnection
        }

        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [2] 修改机器人名称 ──
    elseif ($choice -eq "2") {
        $info = Get-FeishuInfo
        if (-not $info.Configured) {
            Write-Host "  [错误] 飞书未配置，请先配置凭证 (选项 1)" -ForegroundColor Red
        } else {
            Write-Host ""
            Write-Host "  当前机器人名称: $($info.BotName)" -ForegroundColor Cyan
            $newName = Read-Host "  请输入新的机器人名称"
            if (-not [string]::IsNullOrWhiteSpace($newName)) {
                Set-FeishuConfig -AppId $info.AppId -AppSecret $info.AppSecret -BotName $newName.Trim()
                Write-Host "  [成功] 机器人名称已更新为: $($newName.Trim())" -ForegroundColor Green
            } else {
                Write-Host "  [警告] 未输入，操作取消" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [3] 测试飞书连接 ──
    elseif ($choice -eq "3") {
        Write-Host ""
        Test-FeishuConnection
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [4] 查看飞书教程 ──
    elseif ($choice -eq "4") {
        Open-Guide "feishu-setup.html"
        Write-Host "  已打开飞书教程" -ForegroundColor Green
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [5] 配对设备 (Pairing) ──
    elseif ($choice -eq "5") {
        Write-Host ""
        Write-Host "  ── 配对设备 (Pairing) ─────────────────────" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  首次启动 OpenClaw Gateway 后，飞书机器人可能需要完成设备配对。" -ForegroundColor White
        Write-Host ""
        Write-Host "  操作步骤：" -ForegroundColor White
        Write-Host "    1. 先启动 OpenClaw Gateway:  openclaw gateway" -ForegroundColor White
        Write-Host "    2. 在飞书中找到你的机器人，发送任意消息" -ForegroundColor White
        Write-Host "    3. 机器人会回复一个 6 位数的配对码 (Pairing Code)" -ForegroundColor White
        Write-Host "    4. 在终端中运行以下命令完成配对：" -ForegroundColor White
        Write-Host ""
        Write-Host "       openclaw pairing approve feishu <配对码>" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  示例: openclaw pairing approve feishu 123456" -ForegroundColor Gray
        Write-Host ""

        $pairingCode = Read-Host "  如已获取配对码，请输入 (或按 Enter 跳过)"
        if (-not [string]::IsNullOrWhiteSpace($pairingCode)) {
            $code = $pairingCode.Trim()
            Write-Host ""
            Write-Host "  正在执行配对..." -ForegroundColor Cyan
            try {
                & openclaw pairing approve feishu $code 2>&1 | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Gray
                }
                Write-Host ""
                Write-Host "  [成功] 配对命令已执行，请查看上方输出确认结果" -ForegroundColor Green
            } catch {
                Write-Host "  [错误] 配对失败: $_" -ForegroundColor Red
                Write-Host "  请确认 openclaw 已安装并且 gateway 正在运行" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    else {
        Write-Host "  无效选项，请重试" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}
