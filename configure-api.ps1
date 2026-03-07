# ============================================================================
# OpenClaw API 配置工具
# 支持切换 智谱 GLM / Kimi / MiniMax 三家提供商
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

# AI 提供商配置
$PROVIDERS = [ordered]@{
    "zhipu" = @{
        Name     = "智谱 GLM"
        BaseURL  = "https://open.bigmodel.cn/api/anthropic"
        KeyURL   = "https://open.bigmodel.cn/usercenter/apikeys"
        Guide    = "zhipu-setup.html"
        Models   = @(
            @{ Id = "glm-5";         Name = "GLM-5 旗舰 (744B MoE)";    Context = 202000; MaxTokens = 65536 }
            @{ Id = "glm-4.7";       Name = "GLM-4.7 编程";              Context = 128000; MaxTokens = 32768 }
            @{ Id = "glm-4.7-flash"; Name = "GLM-4.7-Flash 快速";        Context = 128000; MaxTokens = 32768 }
            @{ Id = "glm-4-flash";   Name = "GLM-4-Flash 免费";          Context = 128000; MaxTokens = 4096 }
        )
    }
    "kimi" = @{
        Name     = "Kimi / 月之暗面"
        BaseURL  = "https://api.moonshot.cn/anthropic"
        KeyURL   = "https://platform.moonshot.ai/console/api-keys"
        Guide    = "kimi-setup.html"
        Models   = @(
            @{ Id = "kimi-k2.5"; Name = "Kimi K2.5 旗舰 (1T MoE, 256K)"; Context = 256000; MaxTokens = 65536 }
        )
    }
    "minimax" = @{
        Name     = "MiniMax"
        BaseURL  = "https://api.minimaxi.com/anthropic"
        KeyURL   = "https://platform.minimax.io/user-center/basic-information/interface-key"
        Guide    = "minimax-setup.html"
        Models   = @(
            @{ Id = "MiniMax-M2.5";           Name = "M2.5 旗舰 (230B MoE)"; Context = 204000; MaxTokens = 65536 }
            @{ Id = "MiniMax-M2.5-highspeed";  Name = "M2.5 高速 (~100tps)";  Context = 204000; MaxTokens = 65536 }
            @{ Id = "MiniMax-M2.1";            Name = "M2.1 编程";            Context = 204000; MaxTokens = 32768 }
            @{ Id = "MiniMax-M2.1-highspeed";  Name = "M2.1 编程高速";        Context = 204000; MaxTokens = 32768 }
        )
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

function Get-CurrentConfig {
    if (-not (Test-Path $CONFIG_FILE)) { return $null }
    try {
        return Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-CurrentProviderInfo {
    $config = Get-CurrentConfig
    if (-not $config -or -not $config.models -or -not $config.models.providers) {
        return @{ Name = "(未配置)"; BaseURL = ""; Model = "" }
    }

    $providers = $config.models.providers
    foreach ($key in @("zhipu", "kimi", "minimax")) {
        $p = $providers.$key
        if ($p) {
            $name = switch ($key) {
                "zhipu"   { "智谱 GLM" }
                "kimi"    { "Kimi / 月之暗面" }
                "minimax" { "MiniMax" }
            }
            $model = if ($p.models -and $p.models.Count -gt 0) { $p.models[0].id } else { "未知" }
            return @{ Name = $name; BaseURL = $p.baseURL; Model = $model; Key = $p.apiKey; ProviderKey = $key }
        }
    }
    return @{ Name = "(未配置)"; BaseURL = ""; Model = "" }
}

function Show-CurrentConfig {
    $info = Get-CurrentProviderInfo

    Write-Host ""
    Write-Host "  当前配置:" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "    AI 提供商 = $($info.Name)" -ForegroundColor White

    if ($info.BaseURL) {
        Write-Host "    API 端点  = $($info.BaseURL)" -ForegroundColor White
    }
    if ($info.Model) {
        Write-Host "    主力模型  = $($info.Model)" -ForegroundColor White
    }
    if ($info.Key) {
        $masked = $info.Key.Substring(0, [Math]::Min(8, $info.Key.Length)) + "****"
        Write-Host "    API Key   = $masked" -ForegroundColor White
    }

    Write-Host "  ────────────────────────────────────────" -ForegroundColor Gray
    Write-Host ""
}

function Set-ProviderConfig {
    param(
        [string]$ProviderKey,
        [string]$ApiKey,
        [array]$Models
    )

    $provider = $PROVIDERS[$ProviderKey]
    $config = Get-CurrentConfig
    if (-not $config) { $config = [ordered]@{} }

    # 构建模型列表
    $modelList = @()
    foreach ($m in $Models) {
        $modelList += [ordered]@{
            id            = $m.Id
            name          = $m.Name
            contextWindow = $m.Context
            maxTokens     = $m.MaxTokens
        }
    }

    # 写入 models.providers 配置
    $providersObj = [ordered]@{
        $ProviderKey = [ordered]@{
            baseURL = $provider.BaseURL
            apiKey  = $ApiKey
            models  = $modelList
        }
    }

    if ($config -is [PSCustomObject]) {
        $config = $config | ConvertTo-Json -Depth 10 | ConvertFrom-Json | ConvertTo-Hashtable
    }
    if (-not $config.Contains("models")) { $config["models"] = [ordered]@{} }
    $config["models"]["providers"] = $providersObj

    # 确保配置目录存在
    if (-not (Test-Path $OPENCLAW_CONFIG)) {
        New-Item -ItemType Directory -Path $OPENCLAW_CONFIG -Force | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($CONFIG_FILE, ($config | ConvertTo-Json -Depth 10), $utf8NoBom)

    # 同步更新 Claude Code 兼容配置（合并模式）
    $claudeConfigDir = "$env:USERPROFILE\.claude"
    if (-not (Test-Path $claudeConfigDir)) {
        New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null
    }

    # 备份并写入 api-key-helper.cmd（转义 CMD 特殊字符）
    $apiKeyHelperPath = "$claudeConfigDir\api-key-helper.cmd"
    if (Test-Path $apiKeyHelperPath) {
        $backupHelper = "$apiKeyHelperPath.openclaw-backup"
        Copy-Item -Path $apiKeyHelperPath -Destination $backupHelper -Force
    }
    $escapedKey = $ApiKey -replace '([&|<>^])', '^$1' -replace '%', '%%'
    "@echo off`necho $escapedKey" | Out-File -FilePath $apiKeyHelperPath -Encoding ASCII -Force

    $opusModel   = $Models[0].Id
    $sonnetModel = if ($Models.Count -ge 2) { $Models[1].Id } else { $Models[0].Id }
    $haikuModel  = if ($Models.Count -ge 3) { $Models[2].Id } else { $Models[-1].Id }

    # 合并 settings.json — 只更新 OpenClaw 所需字段，保留用户其他配置
    $settingsPath = "$claudeConfigDir\settings.json"
    $settingsObj = [ordered]@{}
    if (Test-Path $settingsPath) {
        try {
            $existingContent = Get-Content $settingsPath -Raw
            $settingsObj = $existingContent | ConvertFrom-Json | ConvertTo-Hashtable
            # 备份现有 settings.json
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$settingsPath.openclaw-backup-$timestamp"
            Copy-Item -Path $settingsPath -Destination $backupPath -Force
        } catch {
            $settingsObj = [ordered]@{}
        }
    }

    # 只在没有 apiKeyHelper 或已是 OpenClaw 设置时才覆盖
    if (-not $settingsObj.Contains("apiKeyHelper") -or ($settingsObj["apiKeyHelper"] -and $settingsObj["apiKeyHelper"] -like "*api-key-helper.cmd*")) {
        $settingsObj["apiKeyHelper"] = $apiKeyHelperPath
    }

    # 合并 env 字段：保留用户已有的其他环境变量
    if (-not $settingsObj.Contains("env")) {
        $settingsObj["env"] = [ordered]@{}
    }
    $settingsObj["env"]["ANTHROPIC_BASE_URL"]             = $provider.BaseURL
    $settingsObj["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"]  = $haikuModel
    $settingsObj["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL"] = $sonnetModel
    $settingsObj["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL"]   = $opusModel

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($settingsPath, ($settingsObj | ConvertTo-Json -Depth 5), $utf8NoBom)

    # 写入 auth-profiles.json — 注册 anthropic API provider（解决 "No API provider registered" 错误）
    $authProfilesPath = "$claudeConfigDir\auth-profiles.json"
    $authProfiles = [ordered]@{}
    if (Test-Path $authProfilesPath) {
        try {
            $authProfiles = Get-Content $authProfilesPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        } catch {
            $authProfiles = [ordered]@{}
        }
    }
    $authProfiles["anthropic"] = [ordered]@{
        apiKey  = $ApiKey
        baseURL = $provider.BaseURL
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($authProfilesPath, ($authProfiles | ConvertTo-Json -Depth 5), $utf8NoBom)

    # 跳过登录检查
    $claudeJsonPath = "$env:USERPROFILE\.claude.json"
    $claudeJson = @{}
    if (Test-Path $claudeJsonPath) {
        try { $claudeJson = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable } catch {
            # JSON 解析失败，备份后创建新文件
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            Copy-Item -Path $claudeJsonPath -Destination "$claudeJsonPath.openclaw-backup-$timestamp" -Force
            $claudeJson = @{}
        }
    }
    $claudeJson["hasCompletedOnboarding"] = $true
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($claudeJsonPath, ($claudeJson | ConvertTo-Json -Depth 5), $utf8NoBom)
}

function Test-NetworkReachability {
    param([string]$Url)
    Write-Host "  ── 网络诊断 ──" -ForegroundColor Cyan
    try {
        $uri = [System.Uri]$Url
        $host_ = $uri.Host

        # 1. DNS 解析
        try {
            $addrs = [System.Net.Dns]::GetHostAddresses($host_)
            Write-Host "    DNS 解析 $host_ -> $($addrs -join ', ')" -ForegroundColor Green
        } catch {
            Write-Host "    DNS 解析失败: $host_ — $($_.Exception.Message)" -ForegroundColor Red
        }

        # 2. TCP 443 连通
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcp.BeginConnect($host_, 443, $null, $null)
            $connected = $asyncResult.AsyncWaitHandle.WaitOne(10000, $false)
            if ($connected -and $tcp.Connected) {
                Write-Host "    TCP 443 端口连通: 正常" -ForegroundColor Green
            } else {
                Write-Host "    TCP 443 端口连通: 超时 (10s)" -ForegroundColor Yellow
            }
            $tcp.Close()
        } catch {
            Write-Host "    TCP 443 端口连通失败: $($_.Exception.Message)" -ForegroundColor Red
        }

        # 3. 系统代理
        try {
            $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
            $proxyUri = $proxy.GetProxy($uri)
            if ($proxyUri.Host -ne $host_) {
                Write-Host "    检测到系统代理: $proxyUri" -ForegroundColor Yellow
            } else {
                Write-Host "    系统代理: 无 (直连)" -ForegroundColor Green
            }
        } catch {
            Write-Host "    系统代理: 检测失败" -ForegroundColor Gray
        }
    } catch {
        Write-Host "    网络诊断异常: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "  ── 诊断结束 ──" -ForegroundColor Cyan
}

function Test-ApiConnection {
    $info = Get-CurrentProviderInfo
    if (-not $info.Key) {
        Write-Host "  [错误] 未配置 API Key" -ForegroundColor Red
        return
    }

    Write-Host "  正在测试 API 连接..." -ForegroundColor Cyan
    Write-Host "  请求地址: $($info.BaseURL)/v1/messages" -ForegroundColor Gray
    Write-Host "  使用模型: $($info.Model)" -ForegroundColor Gray

    $testUrl = "$($info.BaseURL)/v1/messages"
    $bodyJson = @{
        model      = $info.Model
        max_tokens = 20
        messages   = @(@{ role = "user"; content = "请回复'连接成功'" })
    } | ConvertTo-Json -Depth 3
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $maxRetries = 3
    $delays = @(0, 10, 20)
    $lastStatusCode = 0

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if ($attempt -gt 1) {
            $waitSec = $delays[$attempt - 1]
            Write-Host "  第 $attempt/$maxRetries 次重试 (等待 ${waitSec}s)..." -ForegroundColor Yellow
            Start-Sleep -Seconds $waitSec
        }

        try {
            $request = [System.Net.HttpWebRequest]::Create($testUrl)
            $request.Method = "POST"
            $request.ContentType = "application/json; charset=utf-8"
            $request.Headers.Add("x-api-key", $info.Key)
            $request.Headers.Add("anthropic-version", "2023-06-01")
            $request.Timeout = 60000
            $request.ReadWriteTimeout = 60000
            $request.ContentLength = $bodyBytes.Length

            $reqStream = $request.GetRequestStream()
            $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $reqStream.Close()

            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $responseText = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()

            $jsonObj = $responseText | ConvertFrom-Json
            if ($jsonObj.content -and $jsonObj.content.Count -gt 0) {
                $reply = $jsonObj.content[0].text
                Write-Host ""
                Write-Host "  [成功] API 连接正常!" -ForegroundColor Green
                Write-Host "  模型回复: $reply" -ForegroundColor Green
                return
            } else {
                Write-Host "  [警告] API 返回了意外的响应格式" -ForegroundColor Yellow
                return
            }
        } catch [System.Net.WebException] {
            $webEx = $_.Exception
            $statusCode = 0
            if ($webEx.Response) {
                $statusCode = [int]$webEx.Response.StatusCode
                $lastStatusCode = $statusCode
                try {
                    $errReader = New-Object System.IO.StreamReader($webEx.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                    $errBody = $errReader.ReadToEnd()
                    $errReader.Close()
                } catch { $errBody = "" }
            }

            switch -Regex ($statusCode.ToString()) {
                "^401$" {
                    Write-Host ""
                    Write-Host "  [错误] API Key 无效 (HTTP 401)" -ForegroundColor Red
                    Write-Host "  请检查 API Key 是否正确" -ForegroundColor Yellow
                    return  # 不重试
                }
                "^403$" {
                    Write-Host ""
                    Write-Host "  [错误] 访问被拒绝 (HTTP 403)" -ForegroundColor Red
                    Write-Host "  请检查账户余额或套餐是否有效" -ForegroundColor Yellow
                    return  # 不重试
                }
                "^429$" {
                    Write-Host "  请求频率限制 (HTTP 429)..." -ForegroundColor Yellow
                    continue  # 重试
                }
                "^5\d{2}$" {
                    Write-Host "  服务器错误 (HTTP $statusCode)..." -ForegroundColor Yellow
                    continue  # 重试
                }
                default {
                    if ($webEx.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
                        Write-Host "  请求超时 (60s)..." -ForegroundColor Yellow
                        continue  # 重试
                    }
                    Write-Host "  连接失败: $($webEx.Message)" -ForegroundColor Red
                    if ($attempt -lt $maxRetries) { continue }
                }
            }
        } catch {
            Write-Host "  连接异常: $($_.Exception.Message)" -ForegroundColor Red
            if ($attempt -lt $maxRetries) { continue }
        }
    }

    # 429 = 服务器验证了身份但限流，Key 本身有效
    if ($lastStatusCode -eq 429) {
        Write-Host ""
        Write-Host "  [成功] API Key 验证有效!" -ForegroundColor Green
        Write-Host "  服务器确认了您的身份，当前触发了频率限制 (429)" -ForegroundColor Yellow
        Write-Host "  这不影响正常使用，稍后会自动恢复" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  [错误] API 测试在 $maxRetries 次尝试后仍失败" -ForegroundColor Red
    Test-NetworkReachability -Url $testUrl
    Write-Host ""
    Write-Host "  请检查:" -ForegroundColor Yellow
    Write-Host "    1. API Key 是否正确" -ForegroundColor Yellow
    Write-Host "    2. 账户是否有余额或套餐" -ForegroundColor Yellow
    Write-Host "    3. 网络是否正常 (参见上方诊断信息)" -ForegroundColor Yellow
}

function Check-OpenClawUpdate {
    Write-Host "  正在检查 OpenClaw 更新..." -ForegroundColor Cyan
    try {
        if (Get-Command "openclaw" -ErrorAction SilentlyContinue) {
            $currentVer = & openclaw --version 2>$null
            Write-Host "  当前版本: $currentVer" -ForegroundColor White
        }

        Write-Host "  正在检查最新版本..." -ForegroundColor Gray
        & npm view openclaw version 2>$null | ForEach-Object {
            Write-Host "  最新版本: $_" -ForegroundColor White
        }

        $doUpdate = Read-Host "  是否更新? (y/N)"
        if ($doUpdate -eq 'y' -or $doUpdate -eq 'Y') {
            Write-Host "  正在更新 OpenClaw..." -ForegroundColor Cyan
            & npm install -g openclaw@latest 2>&1 | ForEach-Object {
                Write-Host "  $_" -ForegroundColor Gray
            }
            Write-Host "  [成功] 更新完成!" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [错误] 检查更新失败: $_" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Magenta
    Write-Host "       OpenClaw - AI 提供商配置工具" -ForegroundColor Magenta
    Write-Host "  ================================================================" -ForegroundColor Magenta

    Show-CurrentConfig

    Write-Host "  操作:" -ForegroundColor White
    Write-Host "    [1] 切换提供商 (智谱/Kimi/MiniMax)" -ForegroundColor White
    Write-Host "    [2] 更换 API Key" -ForegroundColor White
    Write-Host "    [3] 测试 API 连接" -ForegroundColor White
    Write-Host "    [4] 检查 OpenClaw 更新" -ForegroundColor White
    Write-Host "    [Q] 退出" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "  请输入选项"

    if ($choice -eq 'Q' -or $choice -eq 'q') {
        Write-Host ""
        Write-Host "  配置工具已退出。" -ForegroundColor Yellow
        Write-Host ""
        break
    }

    # ── [1] 切换提供商 ──
    if ($choice -eq "1") {
        Write-Host ""
        Write-Host "  请选择 AI 提供商:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    [1] 智谱 GLM   — 国产最强，GLM-5 旗舰 (推荐)" -ForegroundColor White
        Write-Host "    [2] Kimi        — 256K 超长上下文" -ForegroundColor White
        Write-Host "    [3] MiniMax     — 性价比最高" -ForegroundColor White
        Write-Host ""

        $provChoice = Read-Host "  请选择 (1-3)"
        $provKeys = @("zhipu", "kimi", "minimax")

        if ($provChoice -ge "1" -and $provChoice -le "3") {
            $pKey = $provKeys[[int]$provChoice - 1]
            $prov = $PROVIDERS[$pKey]

            Write-Host ""
            Write-Host "  已选择: $($prov.Name)" -ForegroundColor Cyan

            # 打开双窗口引导
            $openBrowser = Read-Host "  是否打开浏览器获取 API Key? (Y/n)"
            if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
                Start-Process $prov.KeyURL
                Open-Guide $prov.Guide
            }

            Write-Host ""
            $apiKey = Read-Host "  请输入 API Key"
            if ([string]::IsNullOrWhiteSpace($apiKey)) {
                Write-Host "  [警告] 未输入 API Key，操作取消" -ForegroundColor Yellow
            } else {
                Set-ProviderConfig -ProviderKey $pKey -ApiKey $apiKey.Trim() -Models $prov.Models
                Write-Host ""
                Write-Host "  [成功] $($prov.Name) 配置完成!" -ForegroundColor Green
                Write-Host "  主力模型: $($prov.Models[0].Id)" -ForegroundColor Green
            }
        } else {
            Write-Host "  无效选项" -ForegroundColor Yellow
        }

        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [2] 更换 API Key ──
    elseif ($choice -eq "2") {
        $info = Get-CurrentProviderInfo
        if (-not $info.ProviderKey) {
            Write-Host "  [错误] 尚未配置提供商，请先选择提供商 (选项 1)" -ForegroundColor Red
        } else {
            Write-Host ""
            Write-Host "  当前提供商: $($info.Name)" -ForegroundColor Cyan
            $newKey = Read-Host "  请输入新的 API Key"
            if (-not [string]::IsNullOrWhiteSpace($newKey)) {
                $prov = $PROVIDERS[$info.ProviderKey]
                Set-ProviderConfig -ProviderKey $info.ProviderKey -ApiKey $newKey.Trim() -Models $prov.Models
                Write-Host "  [成功] API Key 已更新!" -ForegroundColor Green
            } else {
                Write-Host "  [警告] 未输入，操作取消" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [3] 测试连接 ──
    elseif ($choice -eq "3") {
        Write-Host ""
        Test-ApiConnection
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    # ── [4] 检查更新 ──
    elseif ($choice -eq "4") {
        Write-Host ""
        Check-OpenClawUpdate
        Write-Host ""
        Read-Host "  按 Enter 返回主菜单"
    }

    else {
        Write-Host "  无效选项，请重试" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}
