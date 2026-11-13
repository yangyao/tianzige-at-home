# OpenClaw 部署与 Telegram 代理配置记录

*记录 Mac mini 上 OpenClaw 的完整部署形态，重点是国内网络下 Telegram 渠道的代理链路。配置时间：2026-11-13。*

## 整体架构

一台 Mac mini 跑 OpenClaw 网关，同时接入 QQ 和 Telegram 两个渠道；QQ 直连，Telegram 借道本家庭另一台 Mac 的代理出国：

```
QQ 服务器 ◄────WebSocket────┐
                            │
                      Mac mini (192.168.2.123)
                      openclaw gateway (LaunchAgent 常驻, 端口 18789)
                            │
                            │ channels.telegram.proxy = http://127.0.0.1:1082
                            ▼
                 SSH 反向隧道 (R 1082)
                            │
                            ▼
        另一台 Mac (192.168.2.200) 的代理客户端 MacPacketTunnel
        监听 127.0.0.1:1082 (仅回环) ────► api.telegram.org
```

作业上传链路与代理无关：机器人收到作业图后直接调内网的 homework-server（`http://192.168.2.196:18086/api/ingest`），不经过代理。

## 各组件与配置位置

| 组件 | 位置 | 说明 |
| --- | --- | --- |
| OpenClaw 网关 | Mac mini，LaunchAgent `ai.openclaw.gateway` | 常驻服务，日志在 `~/Library/Logs/openclaw/gateway.log` |
| OpenClaw 主配置 | Mac mini `~/.openclaw/openclaw.json` | 渠道、模型提供商、代理都在这里 |
| 机器人行为规则 | Mac mini `~/.openclaw/workspace/AGENTS.md` | 作业上传规则，源头在仓库 `skills/openclaw-qqbot-homework/` |
| QQ Bot | QQ 开放平台 AppID `1906395801` | qqbot 插件，WebSocket 直连，**不需要代理** |
| Telegram Bot | `@corporate_slave_bot` | dmPolicy 配对模式，所有者 `telegram:308297308` |
| Telegram 代理隧道 | 192.168.2.200 这台 Mac，LaunchAgent `ai.openclaw.tg-proxy-tunnel` | 见下文 |

## Telegram 代理链路（重点）

### 为什么需要

Mac mini 直连 `api.telegram.org` 超时（网络封锁），OpenClaw 日志会反复出现：

```
[fetch-timeout] fetch timeout after 14999ms ... url=https://api.telegram.org/bot***/getMe
[telegram] fetch fallback: primary connection path failed; trying alternative Telegram API IP
[telegram] deleteWebhook failed ... ETIMEDOUT
```

QQ 渠道不受影响（`api.sgroup.qq.com` 直连正常）。

### 链路怎么搭的

192.168.2.200 那台 Mac 上有代理客户端（`MacPacketTunnel`），HTTP 代理监听在 `127.0.0.1:1082`——**只绑回环，局域网内其他机器用不了**。所以用 SSH 反向隧道把它"借"出来：

```bash
# 在 192.168.2.200 上运行（已做成 LaunchAgent，无需手动）
ssh -N -R 1082:127.0.0.1:1082 yangyao@192.168.2.123
```

这条命令把 192.168.2.200 的 `127.0.0.1:1082` 反向映射为 Mac mini 的 `127.0.0.1:1082`。然后 OpenClaw 配置里声明代理：

```json5
// ~/.openclaw/openclaw.json
{
  channels: {
    telegram: {
      proxy: "http://127.0.0.1:1082"
    }
  }
}
```

改完 `openclaw gateway restart`（或等热重载），日志出现 `starting provider (@corporate_slave_bot)` 和 `isolated polling ingress started` 即为成功。

### 隧道的自启与保活

192.168.2.200 上注册了 LaunchAgent：`~/Library/LaunchAgents/ai.openclaw.tg-proxy-tunnel.plist`

- `RunAtLoad` + `KeepAlive`：开机自启，进程退出自动拉起
- `ServerAliveInterval=30` + `ExitOnForwardFailure=yes`：断网/远端端口被占时自动重连

管理命令：

```bash
launchctl kickstart -k gui/$(id -u)/ai.openclaw.tg-proxy-tunnel   # 重启隧道
launchctl print gui/$(id -u)/ai.openclaw.tg-proxy-tunnel          # 查看状态
```

### 验证链路是否通

在 **Mac mini** 上执行（注意 -x 走隧道里的代理）：

```bash
curl -s -x http://127.0.0.1:1082 --connect-timeout 8 https://api.telegram.org/ -o /dev/null -w "%{http_code}\n"
# 期望输出 302；超时或 000 说明隧道/代理断了
```

## 已知限制与坑

1. **Telegram 依赖 192.168.2.200 这台 Mac 在线**。它关机或代理客户端退出，Telegram 掉线；QQ 不受影响。Mac mini 侧会自动重试，代理恢复后自行重连，无需手动干预。
2. **反向端口冲突**：如果手动又开了一条 `-R 1082` 的隧道，远端绑定会失败（`ExitOnForwardFailure` 会让新连接退出）。查隧道进程：`pgrep -fl "ssh.*1082"`。
3. **代理端口 1082 是 HTTP 代理**。OpenClaw 的 `channels.telegram.proxy` 也支持 `socks5://` 格式，如果以后换代理客户端，两种都可以。
4. **OpenClaw 升级/重装后**记得确认 `channels.telegram.proxy` 还在（`openclaw doctor --fix` 有时会动配置，改前 `openclaw.json.bak.*` 有备份）。
5. Telegram 配对码 1 小时过期；新设备配对用 `openclaw pairing list telegram` / `openclaw pairing approve telegram <CODE>`。

## 快速排障清单

```bash
# Mac mini：渠道状态
openclaw channels status | grep -i telegram

# Mac mini：看实时日志
tail -f ~/Library/Logs/openclaw/gateway.log

# Mac mini：验证代理链路
curl -s -x http://127.0.0.1:1082 https://api.telegram.org/ -o /dev/null -w "%{http_code}\n"

# 192.168.2.200：隧道进程在不在
launchctl print gui/$(id -u)/ai.openclaw.tg-proxy-tunnel | grep state
```
