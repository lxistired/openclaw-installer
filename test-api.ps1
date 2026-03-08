[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-Api {
    param([string]$Name, [string]$Url, [string]$Key, [string]$Model, [string]$AuthType)

    Write-Host ""
    Write-Host "  [$Name] $AuthType 认证 -> $Url" -ForegroundColor Cyan
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        if ($AuthType -eq "x-api-key") {
            $req.Headers.Add("x-api-key", $Key)
        } else {
            $req.Headers.Add("Authorization", "Bearer $Key")
        }
        $req.Headers.Add("anthropic-version", "2023-06-01")
        $req.Timeout = 30000
        $req.ReadWriteTimeout = 30000
        $body = '{"model":"' + $Model + '","max_tokens":20,"messages":[{"role":"user","content":"hi"}]}'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream()
        $s.Write($bytes, 0, $bytes.Length)
        $s.Close()
        $resp = $req.GetResponse()
        $rd = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $text = $rd.ReadToEnd()
        $rd.Close()
        $resp.Close()
        Write-Host "  HTTP 200 OK" -ForegroundColor Green
        Write-Host "  $text" -ForegroundColor Gray
    } catch [System.Net.WebException] {
        $ex = $_.Exception
        if ($ex.Response) {
            $code = [int]$ex.Response.StatusCode
            try {
                $rd = New-Object System.IO.StreamReader($ex.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                $errBody = $rd.ReadToEnd()
                $rd.Close()
            } catch { $errBody = "" }
            if ($code -eq 429) {
                Write-Host "  HTTP 429 (Key有效,限流中)" -ForegroundColor Yellow
            } elseif ($code -eq 401) {
                Write-Host "  HTTP 401 (认证失败)" -ForegroundColor Red
            } else {
                Write-Host "  HTTP $code" -ForegroundColor Red
            }
            Write-Host "  $errBody" -ForegroundColor Gray
        } else {
            Write-Host "  连接失败: $($ex.Message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  异常: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor White
Write-Host "  OpenClaw API 诊断工具" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White

# ===== 智谱 GLM =====
$zhipuKey = "823a730756b14d8bb400c8c915be3b1d.Pmc7UXgWBlO8Cb9I"
$zhipuUrl = "https://open.bigmodel.cn/api/anthropic/v1/messages"

Write-Host ""
Write-Host "======== 智谱 GLM ========" -ForegroundColor Yellow
Test-Api -Name "智谱" -Url $zhipuUrl -Key $zhipuKey -Model "glm-4-flash" -AuthType "x-api-key"
Test-Api -Name "智谱" -Url $zhipuUrl -Key $zhipuKey -Model "glm-4-flash" -AuthType "Bearer"

# ===== MiniMax 国内 =====
$mmKey = "sk-api-OpQE9ytyzCfYz9xbG8xqLFrm9oDmghDQA1mdlsOBfIQni0Aa_i2EQJUrDHF8z35NJTor7cfXFR3J8LwDHpFeLBBM0WzZLo63T6PO6j9N62GxoCgOdhqU3fA"
$mmUrlCN = "https://api.minimaxi.com/anthropic/v1/messages"

Write-Host ""
Write-Host "======== MiniMax 国内 (minimaxi.com) ========" -ForegroundColor Yellow
Test-Api -Name "MiniMax-CN" -Url $mmUrlCN -Key $mmKey -Model "MiniMax-M2.5" -AuthType "x-api-key"
Test-Api -Name "MiniMax-CN" -Url $mmUrlCN -Key $mmKey -Model "MiniMax-M2.5" -AuthType "Bearer"

# ===== MiniMax 国际 =====
$mmUrlIO = "https://api.minimax.io/anthropic/v1/messages"

Write-Host ""
Write-Host "======== MiniMax 国际 (minimax.io) ========" -ForegroundColor Yellow
Test-Api -Name "MiniMax-IO" -Url $mmUrlIO -Key $mmKey -Model "MiniMax-M2.5" -AuthType "x-api-key"
Test-Api -Name "MiniMax-IO" -Url $mmUrlIO -Key $mmKey -Model "MiniMax-M2.5" -AuthType "Bearer"

Write-Host ""
Write-Host "============================================" -ForegroundColor White
Write-Host "  诊断完成" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host ""
