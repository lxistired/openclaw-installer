# ============================================================================
# OpenClaw 一键安装脚本 (Windows)
# 面向中国用户 - 支持国产大模型 API + 飞书接入
# ============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 强制 TLS 1.2/1.3（部分 Windows 默认仅启用 TLS 1.0/1.1，导致 HTTPS 握手失败）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# ---------------------------------------------------------------------------
# 全局配置
# ---------------------------------------------------------------------------
$NODEJS_VERSION   = "22.13.1"    # LTS 版本 (OpenClaw 要求 >= 22)
$NODEJS_URL       = "https://npmmirror.com/mirrors/node/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-x64.msi"
$GIT_VERSION      = "2.47.1"
$GIT_URL          = "https://registry.npmmirror.com/-/binary/git-for-windows/v${GIT_VERSION}.windows.1/Git-${GIT_VERSION}-64-bit.exe"
$NPM_MIRROR       = "https://registry.npmmirror.com"
$INSTALL_LOG      = "$env:TEMP\openclaw-install.log"
$OPENCLAW_CONFIG  = "$env:USERPROFILE\.openclaw"

# 获取脚本所在目录（用于定位 guides/ 下的 HTML 教程）
$SCRIPT_DIR = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# 如果从 TEMP 执行，原始目录通过临时文件或环境变量传入
$origDirFile = "$env:TEMP\openclaw-original-dir.txt"
if (Test-Path $origDirFile) {
    $origDir = (Get-Content $origDirFile -Raw).Trim()
    if ($origDir) { $SCRIPT_DIR = $origDir }
} elseif ($env:OPENCLAW_ORIGINAL_DIR) {
    $SCRIPT_DIR = $env:OPENCLAW_ORIGINAL_DIR
}

# AI 提供商配置
$PROVIDERS = @{
    "zhipu" = @{
        Name     = "智谱 GLM"
        BaseURL  = "https://open.bigmodel.cn/api/anthropic"
        RegURL   = "https://open.bigmodel.cn"
        KeyURL   = "https://open.bigmodel.cn/usercenter/apikeys"
        Guide    = "zhipu-setup.html"
        Models   = @(
            @{ Id = "glm-5";         Name = "GLM-5 旗舰";        Context = 202000; MaxTokens = 65536 }
            @{ Id = "glm-4.7";       Name = "GLM-4.7 编程";      Context = 128000; MaxTokens = 32768 }
            @{ Id = "glm-4.7-flash"; Name = "GLM-4.7-Flash 快速"; Context = 128000; MaxTokens = 32768 }
            @{ Id = "glm-4-flash";   Name = "GLM-4-Flash 免费";   Context = 128000; MaxTokens = 4096 }
        )
    }
    "kimi" = @{
        Name     = "Kimi / 月之暗面"
        BaseURL  = "https://api.moonshot.cn/anthropic"
        RegURL   = "https://platform.moonshot.ai"
        KeyURL   = "https://platform.moonshot.ai/console/api-keys"
        Guide    = "kimi-setup.html"
        Models   = @(
            @{ Id = "kimi-k2.5"; Name = "Kimi K2.5 旗舰"; Context = 256000; MaxTokens = 65536 }
        )
    }
    "minimax" = @{
        Name     = "MiniMax"
        BaseURL  = "https://api.minimaxi.com/anthropic"
        RegURL   = "https://platform.minimax.io"
        KeyURL   = "https://platform.minimax.io/user-center/basic-information/interface-key"
        Guide    = "minimax-setup.html"
        Models   = @(
            @{ Id = "MiniMax-M2.5";           Name = "M2.5 旗舰";    Context = 204000; MaxTokens = 65536 }
            @{ Id = "MiniMax-M2.5-highspeed";  Name = "M2.5 高速";    Context = 204000; MaxTokens = 65536 }
            @{ Id = "MiniMax-M2.1";            Name = "M2.1 编程";    Context = 204000; MaxTokens = 32768 }
            @{ Id = "MiniMax-M2.1-highspeed";  Name = "M2.1 编程高速"; Context = 204000; MaxTokens = 32768 }
        )
    }
}

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Add-Content -Path $INSTALL_LOG -Value "[$(Get-Date)] $Message"
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [信息] $Message" -ForegroundColor Green
    Add-Content -Path $INSTALL_LOG -Value "[$(Get-Date)] INFO: $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [警告] $Message" -ForegroundColor Yellow
    Add-Content -Path $INSTALL_LOG -Value "[$(Get-Date)] WARN: $Message"
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [错误] $Message" -ForegroundColor Red
    Add-Content -Path $INSTALL_LOG -Value "[$(Get-Date)] ERROR: $Message"
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"
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

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )
    Write-Info "正在下载 $Description ..."
    Write-Info "下载地址: $Url"

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
        $ProgressPreference = 'Continue'
        Write-Info "$Description 下载完成"
    }
    catch {
        Write-Warn "Invoke-WebRequest 下载失败，尝试使用 WebClient ..."
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutFile)
            Write-Info "$Description 下载完成 (WebClient)"
        }
        catch {
            Write-Err "$Description 下载失败: $_"
            Write-Err "请手动下载: $Url"
            return $false
        }
    }
    return $true
}

function Open-Guide {
    param([string]$GuideFile)
    # 优先从 TEMP 的 openclaw-guides 查找（.bat 复制过去的）
    $tempGuidePath = "$env:TEMP\openclaw-guides\$GuideFile"
    if (Test-Path $tempGuidePath) {
        Start-Process $tempGuidePath
        return
    }
    # 其次从原始目录查找
    $guidePath = Join-Path $SCRIPT_DIR "guides\$GuideFile"
    if (Test-Path $guidePath) {
        Start-Process $guidePath
    } else {
        Write-Warn "教程文件未找到: $GuideFile"
    }
}

function Test-NetworkReachability {
    param([string]$Url)
    Write-Info "── 网络诊断 ──"
    try {
        $uri = [System.Uri]$Url
        $host_ = $uri.Host

        # 1. DNS 解析
        try {
            $addrs = [System.Net.Dns]::GetHostAddresses($host_)
            Write-Info "  DNS 解析 $host_ -> $($addrs -join ', ')"
        } catch {
            Write-Err "  DNS 解析失败: $host_ — $($_.Exception.Message)"
        }

        # 2. TCP 443 连通
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcp.BeginConnect($host_, 443, $null, $null)
            $connected = $asyncResult.AsyncWaitHandle.WaitOne(10000, $false)
            if ($connected -and $tcp.Connected) {
                Write-Info "  TCP 443 端口连通: 正常"
            } else {
                Write-Warn "  TCP 443 端口连通: 超时 (10s)"
            }
            $tcp.Close()
        } catch {
            Write-Err "  TCP 443 端口连通失败: $($_.Exception.Message)"
        }

        # 3. 系统代理
        try {
            $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
            $proxyUri = $proxy.GetProxy($uri)
            if ($proxyUri.Host -ne $host_) {
                Write-Warn "  检测到系统代理: $proxyUri"
            } else {
                Write-Info "  系统代理: 无 (直连)"
            }
        } catch {
            Write-Info "  系统代理: 检测失败"
        }
    } catch {
        Write-Err "  网络诊断异常: $($_.Exception.Message)"
    }
    Write-Info "── 诊断结束 ──"
}

function Test-ApiKey {
    param(
        [string]$BaseURL,
        [string]$ApiKey,
        [string]$Model
    )
    Write-Info "正在测试 API 连接..."

    $testUrl = "$BaseURL/v1/messages"
    $bodyJson = @{
        model      = $Model
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
            Write-Warn "第 $attempt/$maxRetries 次重试 (等待 ${waitSec}s)..."
            Start-Sleep -Seconds $waitSec
        }

        try {
            $request = [System.Net.HttpWebRequest]::Create($testUrl)
            $request.Method = "POST"
            $request.ContentType = "application/json; charset=utf-8"
            $request.Headers.Add("x-api-key", $ApiKey)
            $request.Headers.Add("anthropic-version", "2023-06-01")
            $request.Timeout = 60000          # 60s
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
                Write-Info "API 连接成功! 模型回复: $reply"
                return $true
            } else {
                Write-Warn "API 返回了意外的响应格式"
                return $false
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
                    Write-Err "API Key 无效 (HTTP 401) — 请检查 Key 是否正确"
                    return $false  # 不重试
                }
                "^403$" {
                    Write-Err "访问被拒绝 (HTTP 403) — 请检查账户余额或套餐是否有效"
                    return $false  # 不重试
                }
                "^429$" {
                    Write-Warn "请求频率限制 (HTTP 429)"
                    continue  # 重试
                }
                "^5\d{2}$" {
                    Write-Warn "服务器错误 (HTTP $statusCode)"
                    continue  # 重试
                }
                default {
                    if ($webEx.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
                        Write-Warn "请求超时 (60s)"
                        continue  # 重试
                    }
                    Write-Err "连接失败: $($webEx.Message)"
                    if ($attempt -lt $maxRetries) { continue }
                }
            }
        } catch {
            Write-Err "API 连接异常: $($_.Exception.Message)"
            if ($attempt -lt $maxRetries) { continue }
        }
    }

    # 429 = 认证通过但被限流，Key 本身是有效的
    if ($lastStatusCode -eq 429) {
        Write-Info "API Key 验证有效（服务器确认了身份），当前被频率限制"
        Write-Info "这不影响正常使用，启动 OpenClaw 后会自动处理限流"
        return $true
    }

    Write-Err "API 测试在 $maxRetries 次尝试后仍失败"
    Test-NetworkReachability -Url $testUrl
    return $false
}

# ---------------------------------------------------------------------------
# 管理员权限检查
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [错误] 本脚本需要以管理员身份运行！" -ForegroundColor Red
    Write-Host ""
    Write-Host "  请右键点击「一键安装.bat」，选择「以管理员身份运行」。" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  按 Enter 键退出"
    exit 1
}

# ---------------------------------------------------------------------------
# 欢迎界面
# ---------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host "       OpenClaw 一键安装工具 (Windows 中国版)" -ForegroundColor Magenta
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  本工具将自动完成以下操作:" -ForegroundColor White
Write-Host "    1. 检查并安装 Node.js >= 22 (使用国内镜像)" -ForegroundColor White
Write-Host "    2. 检查并安装 Git          (使用国内镜像)" -ForegroundColor White
Write-Host "    3. 配置 npm 国内镜像源 + 安装 OpenClaw" -ForegroundColor White
Write-Host "    4. 配置 AI 提供商 (智谱/Kimi/MiniMax)" -ForegroundColor White
Write-Host "    5. 配置飞书机器人" -ForegroundColor White
Write-Host "    6. 写入配置 + 启动 OpenClaw" -ForegroundColor White
Write-Host ""
Write-Host "  注意: 本脚本需要以 管理员身份 运行" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "  按 Enter 继续安装，输入 Q 退出"
if ($confirm -eq 'Q' -or $confirm -eq 'q') {
    Write-Host "  安装已取消。" -ForegroundColor Yellow
    exit 0
}

# 初始化日志
"[$(Get-Date)] OpenClaw 安装开始" | Out-File -FilePath $INSTALL_LOG -Encoding UTF8

# ---------------------------------------------------------------------------
# Step 1/6: 检查/安装 Node.js
# ---------------------------------------------------------------------------
Write-Step "步骤 1/6: 检查 Node.js (>= 22)"

$skipNode = $false
if (Test-CommandExists "node") {
    $nodeVer = & node --version 2>$null
    Write-Info "Node.js 已安装: $nodeVer"

    $majorVersion = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($majorVersion -lt 22) {
        Write-Warn "Node.js 版本过低 (需要 >= 22)，将升级..."
    }
    else {
        Write-Info "Node.js 版本满足要求，跳过安装"
        $skipNode = $true
    }
}

if (-not $skipNode) {
    $nodeMsi = "$env:TEMP\nodejs-installer.msi"
    $downloaded = Download-File -Url $NODEJS_URL -OutFile $nodeMsi -Description "Node.js v${NODEJS_VERSION}"

    if ($downloaded) {
        Write-Info "正在安装 Node.js (静默安装)..."
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$nodeMsi`" /qn /norestart" -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Info "Node.js 安装成功"
        }
        else {
            Write-Err "Node.js 安装失败 (退出代码: $($process.ExitCode))"
            Write-Err "请手动下载安装: https://npmmirror.com/mirrors/node/"
        }
        Remove-Item -Path $nodeMsi -Force -ErrorAction SilentlyContinue
    }

    Refresh-Path
}

# ---------------------------------------------------------------------------
# Step 2/6: 检查/安装 Git
# ---------------------------------------------------------------------------
Write-Step "步骤 2/6: 检查 Git"

if (Test-CommandExists "git") {
    $gitVer = & git --version 2>$null
    Write-Info "Git 已安装: $gitVer"
    Write-Info "跳过 Git 安装"
}
else {
    $gitExe = "$env:TEMP\git-installer.exe"
    $downloaded = Download-File -Url $GIT_URL -OutFile $gitExe -Description "Git v${GIT_VERSION}"

    if ($downloaded) {
        Write-Info "正在安装 Git (静默安装)..."
        $process = Start-Process -FilePath $gitExe -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`"" -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Info "Git 安装成功"
        }
        else {
            Write-Err "Git 安装失败 (退出代码: $($process.ExitCode))"
            Write-Err "请手动下载安装: https://registry.npmmirror.com/binary.html?path=git-for-windows/"
        }
        Remove-Item -Path $gitExe -Force -ErrorAction SilentlyContinue
    }

    Refresh-Path
}

# ---------------------------------------------------------------------------
# Step 3/6: 配置 npm 镜像 + 安装 OpenClaw
# ---------------------------------------------------------------------------
Write-Step "步骤 3/6: 安装 OpenClaw（使用国内镜像）"

if (Test-CommandExists "npm") {
    Write-Info "使用 npm 镜像源: $NPM_MIRROR"

    Write-Info "正在通过 npm 安装 OpenClaw ..."
    Write-Info "（使用国内镜像源，请耐心等待）"

    try {
        & npm install -g openclaw@latest --registry=$NPM_MIRROR 2>&1 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
        Refresh-Path

        if (Test-CommandExists "openclaw") {
            $openclawVer = & openclaw --version 2>$null
            Write-Info "OpenClaw 安装成功: $openclawVer"
        }
        else {
            Write-Warn "openclaw 命令未找到，可能需要重启终端"
            Write-Info "安装完成后请打开新的 PowerShell 窗口运行 'openclaw' 命令"
        }
    }
    catch {
        Write-Err "OpenClaw 安装失败: $_"
        Write-Err "请手动运行: npm install -g openclaw@latest"
    }
}
else {
    Write-Err "npm 未找到，请确保 Node.js 安装成功后重试"
    Write-Err "您可以关闭此窗口，重新以管理员身份运行本安装程序"
}

# ---------------------------------------------------------------------------
# 检测现有 Claude Code 配置
# ---------------------------------------------------------------------------
$claudeSettingsCheck = "$env:USERPROFILE\.claude\settings.json"
if (Test-Path $claudeSettingsCheck) {
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  检测到已有 Claude Code 配置                            │" -ForegroundColor Yellow
    Write-Host "  │                                                          │" -ForegroundColor Yellow
    Write-Host "  │  安装将以兼容模式运行：                                  │" -ForegroundColor Yellow
    Write-Host "  │    - 保留您的 web search、allowedTools 等配置            │" -ForegroundColor Yellow
    Write-Host "  │    - 自动备份现有 settings.json                          │" -ForegroundColor Yellow
    Write-Host "  │    - 卸载时可恢复原始配置                                │" -ForegroundColor Yellow
    Write-Host "  └──────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    $continueInstall = Read-Host "  继续安装? (Y/n)"
    if ($continueInstall -eq 'n' -or $continueInstall -eq 'N') {
        Write-Host "  安装已取消。" -ForegroundColor Yellow
        Read-Host "  按 Enter 键退出"
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Step 4/6: 配置 AI 提供商（双窗口引导）
# ---------------------------------------------------------------------------
Write-Step "步骤 4/6: 配置 AI 提供商"

Write-Host ""
Write-Host "  请选择 AI 提供商:" -ForegroundColor Yellow
Write-Host ""
Write-Host "    [1] 智谱 GLM   — 国产最强开源，GLM-5 旗舰 (推荐)" -ForegroundColor White
Write-Host "    [2] Kimi        — 256K 超长上下文，kimi-k2.5 旗舰" -ForegroundColor White
Write-Host "    [3] MiniMax     — 性价比最高，$0.15/M input" -ForegroundColor White
Write-Host "    [S] 跳过，稍后配置" -ForegroundColor Gray
Write-Host ""

$providerChoice = Read-Host "  请输入选项编号 (1-3/S)"

# 存储选择的提供商信息
$selectedProvider = $null
$selectedApiKey   = $null
$selectedModels   = $null

if ($providerChoice -ge "1" -and $providerChoice -le "3") {
    $providerKeys = @("zhipu", "kimi", "minimax")
    $providerKey  = $providerKeys[[int]$providerChoice - 1]
    $provider     = $PROVIDERS[$providerKey]

    Write-Host ""
    Write-Host "  已选择: $($provider.Name)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  即将打开两个浏览器窗口:" -ForegroundColor White
    Write-Host "    1. $($provider.Name) 注册/API Key 页面" -ForegroundColor White
    Write-Host "    2. 本地教程（手把手引导）" -ForegroundColor White
    Write-Host ""

    $openBrowser = Read-Host "  是否打开浏览器? (Y/n)"
    if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
        # 双窗口引导：打开实际平台 + 本地 HTML 教程
        Start-Process $provider.KeyURL
        Open-Guide $provider.Guide
        Write-Info "已打开浏览器窗口，请跟随教程操作"
    }

    Write-Host ""
    Write-Host "  请跟随教程完成注册，获取 API Key 后回到此窗口" -ForegroundColor Yellow
    Write-Host ""

    $apiKey = Read-Host "  请粘贴您的 API Key"

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Warn "未输入 API Key，跳过 API 配置"
        Write-Warn "您可以稍后运行 configure-api.ps1 进行配置"
    }
    else {
        $selectedApiKey   = $apiKey.Trim()
        $selectedProvider = $provider
        $selectedModels   = $provider.Models

        # 测试 API 连接
        $testModel = $selectedModels[0].Id
        $testResult = Test-ApiKey -BaseURL $provider.BaseURL -ApiKey $selectedApiKey -Model $testModel
        if (-not $testResult) {
            Write-Warn "API 测试未通过，但配置将继续写入。您可以稍后检查。"
        }
    }
}
else {
    Write-Info "跳过 AI 配置，您可以稍后运行 配置API.bat 进行配置"
}

# ---------------------------------------------------------------------------
# Step 5/6: 配置飞书机器人（双窗口引导）
# ---------------------------------------------------------------------------
Write-Step "步骤 5/6: 配置飞书机器人"

$feishuAppId     = $null
$feishuAppSecret = $null
$feishuBotName   = $null

Write-Host ""
Write-Host "  OpenClaw 通过飞书应用机器人接入，使用 WebSocket 连接，" -ForegroundColor White
Write-Host "  无需公网 IP 或域名。" -ForegroundColor White
Write-Host ""
Write-Host "  任何飞书账号均可操作（个人账号在开放平台创建一个团队即可，" -ForegroundColor White
Write-Host "  随便填个名字，无需企业认证）。" -ForegroundColor White
Write-Host ""
Write-Host "  即将打开两个浏览器窗口:" -ForegroundColor White
Write-Host "    1. 飞书开放平台（创建应用）" -ForegroundColor White
Write-Host "    2. 本地教程（手把手引导）" -ForegroundColor White
Write-Host ""
Write-Host "  [C] 继续配置飞书" -ForegroundColor White
Write-Host "  [S] 跳过，稍后配置" -ForegroundColor Gray
Write-Host ""

$feishuChoice = Read-Host "  请输入选项 (C/S)"

if ($feishuChoice -ne 'S' -and $feishuChoice -ne 's') {
    $openBrowser = Read-Host "  是否打开浏览器? (Y/n)"
    if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
        Start-Process "https://open.feishu.cn/app"
        Open-Guide "feishu-setup.html"
        Write-Info "已打开浏览器窗口，请跟随教程创建飞书应用"
    }

    Write-Host ""
    Write-Host "  请跟随教程创建飞书应用，获取 App ID 和 App Secret 后回到此窗口" -ForegroundColor Yellow
    Write-Host ""

    $feishuAppId = Read-Host "  请输入飞书 App ID (格式: cli_xxx)"

    if ([string]::IsNullOrWhiteSpace($feishuAppId)) {
        Write-Warn "未输入 App ID，跳过飞书配置"
        Write-Warn "您可以稍后运行 配置飞书.bat 进行配置"
        $feishuAppId = $null
    }
    else {
        $feishuAppId = $feishuAppId.Trim()

        $feishuAppSecret = Read-Host "  请输入飞书 App Secret"
        if ([string]::IsNullOrWhiteSpace($feishuAppSecret)) {
            Write-Warn "未输入 App Secret，跳过飞书配置"
            $feishuAppId = $null
        }
        else {
            $feishuAppSecret = $feishuAppSecret.Trim()
            $botNameInput = Read-Host "  请输入机器人名称 (默认: 我的AI助手)"
            if ([string]::IsNullOrWhiteSpace($botNameInput)) {
                $feishuBotName = "我的AI助手"
            } else {
                $feishuBotName = $botNameInput.Trim()
            }
            Write-Info "飞书配置信息已记录"

            # 提示首次配对
            Write-Host ""
            Write-Host "  ┌──────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
            Write-Host "  │  提示：首次启动可能需要 Pairing 配对                     │" -ForegroundColor Cyan
            Write-Host "  │                                                          │" -ForegroundColor Cyan
            Write-Host "  │  1. 启动 openclaw gateway 后                             │" -ForegroundColor Cyan
            Write-Host "  │  2. 在飞书中给机器人发消息 → 收到 6 位配对码              │" -ForegroundColor Cyan
            Write-Host "  │  3. 在终端执行:                                          │" -ForegroundColor Cyan
            Write-Host "  │     openclaw pairing approve feishu <配对码>              │" -ForegroundColor Yellow
            Write-Host "  │                                                          │" -ForegroundColor Cyan
            Write-Host "  │  配对后续即可正常使用，也可通过 配置飞书.bat → 选项 5 操作 │" -ForegroundColor Cyan
            Write-Host "  └──────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
            Write-Host ""
        }
    }
}
else {
    Write-Info "跳过飞书配置，您可以稍后运行 配置飞书.bat 进行配置"
}

# ---------------------------------------------------------------------------
# Step 6/6: 写入配置 + 启动 OpenClaw
# ---------------------------------------------------------------------------
Write-Step "步骤 6/6: 写入配置 + 启动 OpenClaw"

# 创建 OpenClaw 配置目录
if (-not (Test-Path $OPENCLAW_CONFIG)) {
    New-Item -ItemType Directory -Path $OPENCLAW_CONFIG -Force | Out-Null
    Write-Info "已创建配置目录: $OPENCLAW_CONFIG"
}

# 构建 openclaw.json 配置（JSON5 格式，但用标准 JSON 兼容写入）
$config = [ordered]@{}

# AI 模型配置
if ($selectedProvider -and $selectedApiKey) {
    $providerKey = switch ($selectedProvider.Name) {
        { $_ -match "智谱" }   { "zhipu" }
        { $_ -match "Kimi" }   { "kimi" }
        { $_ -match "MiniMax" } { "minimax" }
    }

    $modelList = @()
    foreach ($m in $selectedModels) {
        $modelList += [ordered]@{
            id            = $m.Id
            name          = $m.Name
            contextWindow = $m.Context
            maxTokens     = $m.MaxTokens
        }
    }

    $config["models"] = [ordered]@{
        providers = [ordered]@{
            $providerKey = [ordered]@{
                baseUrl = $selectedProvider.BaseURL
                apiKey  = $selectedApiKey
                models  = $modelList
            }
        }
    }

    Write-Info "AI 提供商配置: $($selectedProvider.Name)"
}

# 飞书渠道配置
if ($feishuAppId -and $feishuAppSecret) {
    $config["channels"] = [ordered]@{
        feishu = [ordered]@{
            enabled  = $true
            accounts = [ordered]@{
                main = [ordered]@{
                    appId     = $feishuAppId
                    appSecret = $feishuAppSecret
                    botName   = $feishuBotName
                }
            }
            typingIndicator    = $true
            resolveSenderNames = $true
            streaming          = $true
        }
    }

    Write-Info "飞书配置: App ID = $feishuAppId, 机器人名 = $feishuBotName"
}

# 写入配置文件
$configPath = Join-Path $OPENCLAW_CONFIG "openclaw.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 10), $utf8NoBom)
Write-Info "配置文件已写入: $configPath"

# 同时写入 Claude Code 兼容配置（apiKeyHelper 方式）
if ($selectedApiKey -and $selectedProvider) {
    $claudeConfigDir = "$env:USERPROFILE\.claude"
    if (-not (Test-Path $claudeConfigDir)) {
        New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null
    }

    # 备份并写入 api-key-helper.cmd（转义 CMD 特殊字符）
    $apiKeyHelperPath = "$claudeConfigDir\api-key-helper.cmd"
    if (Test-Path $apiKeyHelperPath) {
        $backupHelper = "$apiKeyHelperPath.openclaw-backup"
        Copy-Item -Path $apiKeyHelperPath -Destination $backupHelper -Force
        Write-Info "已备份 api-key-helper.cmd"
    }
    $escapedKey = $selectedApiKey -replace '([&|<>^])', '^$1' -replace '%', '%%'
    "@echo off`necho $escapedKey" | Out-File -FilePath $apiKeyHelperPath -Encoding ASCII -Force

    $opusModel   = $selectedModels[0].Id
    $sonnetModel = if ($selectedModels.Count -ge 2) { $selectedModels[1].Id } else { $selectedModels[0].Id }
    $haikuModel  = if ($selectedModels.Count -ge 3) { $selectedModels[2].Id } else { $selectedModels[-1].Id }

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
            Write-Info "已备份 settings.json -> $backupPath"
        } catch {
            Write-Warn "settings.json 解析失败，将创建新配置"
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
    $settingsObj["env"]["ANTHROPIC_BASE_URL"]             = $selectedProvider.BaseURL
    $settingsObj["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"]  = $haikuModel
    $settingsObj["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL"] = $sonnetModel
    $settingsObj["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL"]   = $opusModel

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($settingsPath, ($settingsObj | ConvertTo-Json -Depth 5), $utf8NoBom)
    Write-Info "Claude Code 兼容配置已写入（合并模式）: $settingsPath"

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
        apiKey  = $selectedApiKey
        baseUrl = $selectedProvider.BaseURL
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($authProfilesPath, ($authProfiles | ConvertTo-Json -Depth 5), $utf8NoBom)
    Write-Info "API Provider 已注册: $authProfilesPath"
}

# 跳过 OpenClaw 强制登录检查
$claudeJsonPath = "$env:USERPROFILE\.claude.json"
$claudeJson = @{}
if (Test-Path $claudeJsonPath) {
    try {
        $claudeJson = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
    } catch {
        # JSON 解析失败，备份后创建新文件
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupJsonPath = "$claudeJsonPath.openclaw-backup-$timestamp"
        Copy-Item -Path $claudeJsonPath -Destination $backupJsonPath -Force
        Write-Warn ".claude.json 解析失败，已备份到 $backupJsonPath"
        $claudeJson = @{}
    }
}
$claudeJson["hasCompletedOnboarding"] = $true
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($claudeJsonPath, ($claudeJson | ConvertTo-Json -Depth 5), $utf8NoBom)
Write-Info "已跳过登录检查"

# 运行 openclaw doctor（如果可用）
if (Test-CommandExists "openclaw") {
    Write-Info "运行 openclaw doctor 检查配置..."
    try {
        & openclaw doctor 2>&1 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
    } catch {
        Write-Warn "openclaw doctor 运行失败: $_"
    }
}

# ---------------------------------------------------------------------------
# 安装完成
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Green
Write-Host "       OpenClaw 安装完成!" -ForegroundColor Green
Write-Host "  ================================================================" -ForegroundColor Green
Write-Host ""

# 安装状态检测
Write-Host "  安装状态检测:" -ForegroundColor White
Refresh-Path

if (Test-CommandExists "node") {
    Write-Host "    [OK] Node.js $(& node --version 2>$null)" -ForegroundColor Green
} else {
    Write-Host "    [!!] Node.js 未检测到 (请重启终端后再试)" -ForegroundColor Red
}

if (Test-CommandExists "git") {
    Write-Host "    [OK] $(& git --version 2>$null)" -ForegroundColor Green
} else {
    Write-Host "    [!!] Git 未检测到 (请重启终端后再试)" -ForegroundColor Red
}

if (Test-CommandExists "openclaw") {
    Write-Host "    [OK] OpenClaw 已安装" -ForegroundColor Green
} else {
    Write-Host "    [!!] OpenClaw 未检测到 (请重启终端后运行 'openclaw')" -ForegroundColor Yellow
}

if ($selectedProvider) {
    Write-Host "    [OK] AI 提供商: $($selectedProvider.Name)" -ForegroundColor Green
} else {
    Write-Host "    [!!] AI 提供商未配置 (请运行 配置API.bat)" -ForegroundColor Yellow
}

if ($feishuAppId) {
    Write-Host "    [OK] 飞书: App ID = $feishuAppId" -ForegroundColor Green
} else {
    Write-Host "    [!!] 飞书未配置 (请运行 配置飞书.bat)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  使用方法:" -ForegroundColor White
Write-Host "    1. 打开一个新的 PowerShell 或 CMD 窗口" -ForegroundColor White
Write-Host "    2. 运行命令: openclaw gateway" -ForegroundColor White
Write-Host ""

if ($feishuAppId) {
    Write-Host "  飞书使用:" -ForegroundColor White
    Write-Host "    启动 openclaw gateway 后，在飞书中找到你的机器人" -ForegroundColor White
    Write-Host "    发送一条消息试试！" -ForegroundColor White
    Write-Host ""
}

Write-Host "  管理工具:" -ForegroundColor White
Write-Host "    配置API.bat    — 切换 AI 提供商、更换 API Key" -ForegroundColor Gray
Write-Host "    配置飞书.bat   — 重新配置飞书机器人" -ForegroundColor Gray
Write-Host "    一键卸载.bat   — 卸载 OpenClaw" -ForegroundColor Gray
Write-Host ""
Write-Host "  安装日志: $INSTALL_LOG" -ForegroundColor Gray
Write-Host ""

# 询问是否立即启动
if ($feishuAppId -and $selectedProvider) {
    $startNow = Read-Host "  是否立即启动 OpenClaw Gateway? (Y/n)"
    if ($startNow -ne 'n' -and $startNow -ne 'N') {
        if (Test-CommandExists "openclaw") {
            Write-Info "正在启动 OpenClaw Gateway..."
            Write-Info "按 Ctrl+C 可停止运行"
            Write-Host ""
            & openclaw gateway
        } else {
            Write-Warn "openclaw 命令未找到，请打开新终端后运行: openclaw gateway"
        }
    }
} else {
    Read-Host "  按 Enter 键退出安装程序"
}
