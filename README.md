# OpenClaw 一键安装包 (Windows 中国版)

面向中国用户的 OpenClaw 一键安装包，提供傻瓜式安装体验。

## 功能

- **一键安装** Node.js、Git、OpenClaw（全部使用国内镜像）
- **三家国产 AI 提供商**：智谱 GLM、Kimi（月之暗面）、MiniMax
- **飞书机器人接入**：WebSocket 模式，无需公网服务器
- **双窗口引导**：打开教程页面 + 实际平台页面，手把手指导
- **配置管理工具**：随时切换 AI 提供商、更新飞书配置

## 快速开始

### 方式一：直接运行

1. 双击 `一键安装.bat`
2. 跟随提示完成 6 步安装
3. 安装完成后，打开终端运行 `openclaw gateway`

### 方式二：Inno Setup 打包

1. 安装 [Inno Setup](https://jrsoftware.org/isinfo.php)
2. 打开 `OpenClawInstaller.iss`
3. 编译生成 `.exe` 安装包

## 文件说明

| 文件 | 说明 |
|------|------|
| `一键安装.bat` | 安装入口（UAC 提权） |
| `install.ps1` | 主安装脚本（6步） |
| `配置API.bat` | API 配置工具启动器 |
| `configure-api.ps1` | AI 提供商配置/管理 |
| `配置飞书.bat` | 飞书配置工具启动器 |
| `configure-feishu.ps1` | 飞书机器人配置/管理 |
| `一键卸载.bat` | 卸载启动器 |
| `uninstall.ps1` | 卸载脚本 |
| `guides/` | HTML 教程页面 |
| `version.json` | 版本信息 |
| `OpenClawInstaller.iss` | Inno Setup 打包脚本 |

## 支持的 AI 提供商

| 提供商 | 旗舰模型 | 特点 |
|--------|----------|------|
| 智谱 GLM | glm-5 (744B MoE) | 国产最强开源，推荐 |
| Kimi | kimi-k2.5 (1T MoE) | 256K 超长上下文 |
| MiniMax | MiniMax-M2.5 (230B MoE) | 性价比最高 |

三家均支持 Anthropic 兼容 API，无需代理。

## 安装流程

```
Step 1/6 → 检查/安装 Node.js (>= 22)
Step 2/6 → 检查/安装 Git
Step 3/6 → 配置 npm 国内镜像 + 安装 OpenClaw
Step 4/6 → 配置 AI 提供商（双窗口引导）
Step 5/6 → 配置飞书机器人（双窗口引导）
Step 6/6 → 写入配置 + 启动 OpenClaw
```

## 飞书接入

OpenClaw 使用飞书**应用机器人**（非 Webhook），通过 WebSocket 连接，无需公网 IP。

配置步骤：
1. 在 [飞书开放平台](https://open.feishu.cn/app) 创建企业自建应用
2. 获取 App ID 和 App Secret
3. 启用机器人能力
4. 添加权限：`im:message`、`im:message.receive_v1`
5. 发布应用并等待审批

详细教程参见 `guides/feishu-setup.html`。

## 相关链接

- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw 文档](https://docs.openclaw.ai/)
- [飞书接入文档](https://docs.openclaw.ai/channels/feishu)
- [飞书开放平台](https://open.feishu.cn/app)
