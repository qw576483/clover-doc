
## 这篇文档讲什么？

`msg-client` 是 clover 网关的**命令行调试客户端**：连上网关，交互式收发消息，用于联调登录与业务消息。

> **关于历史页面的说明**：文档里曾出现的 `clover-cli`、`msg-test-tcp`、`msg-test-ws`
> 在本仓库中**都不存在**（`clover-server-tools/` 下现有 `gmt`、`manager`、`mkcert`、`msg-client`、`msg-web`、`robot`、`windows-env`；`table` 在 `clover-tools`）。
> 它们已被 `msg-client` 取代（权限点更全：QUIC/TCP 双传输 + proto 自动解析 + 交互式 REPL + 账号服登录流程），
> 相关页面已下线。本文以 [`clover-server-tools/msg-client/`](https://github.com/qw576483/clover-server-tools/blob/main/msg-client/README.md) 源码为准。

## 能力

- **双传输**：QUIC 优先，失败自动回退 TCP；收到 `ping` 自动回 `pong`
- **proto 自动解析**：启动时递归扫描 Go 源码，提取 `const MsgXxx / EMsgXxx` 消息号与带 `json` tag 的结构体，自动按 Request / Reply / Notify 分类
- **加消息无需改工具**：引擎或 demo 新增消息/结构体，CLI 下次启动即自动识别
- **交互式 REPL**：`ls` 列全部消息，`send` 按字段名自动组包
- **登录 / 注册内置**：账号服 HTTP 换取 token → 长连接 `EMsgLogin{token}`

## 线协议（与 clover-server-engine 对齐）

| 层 | 结构 |
| --- | --- |
| 传输层帧 | `[1B 帧类型][4B 大端长度][payload]`；帧类型 `0`=数据、`1`=ping、`2`=pong |
| 客户端帧 | `[4B 大端 requestID][4B 大端 msgID][body]`，body 为 JSON |

- `requestID != 0` → 请求 / 回包，客户端按 `requestID` 配对；普通回包 `msgID` 恒为 `0`
- `requestID == 0` → 推送，客户端按 `msgID` 路由
- 错误回包使用特殊值 `EMsgError = 0xFFFFFFFF`

**消息号区间**：引擎占 `[1, 10000]`（`InternalMsgMax = 10000`），业务消息从 `10001` 起。
关键 opcode：`EMsgLogin=2`、`EMsgResumeSession=3`、`EMsgUDPBindGrant=6`、`EMsgQueuePosition=7`（网关直发：
排队位置，服务端开 `queue_cap` 且需要排队时才出现）、`EPushPlayerFullSync=4001`、`EPushAlert=4002`、`EPushDataSync=4003`。

> 1 号原为 `EMsgSignup`：注册已完全移到账号服 HTTP，号位**作废保留不复用**。

## 编译与运行

```bash
cd clover-server-tools/msg-client

# 产物落在当前目录（Windows 下为 client.exe）
go build -o client ./cmd/client

# 首次运行会自动生成默认 config.yaml
./client
# 指定配置 / 覆盖网关地址
./client -config my.yaml -addr 127.0.0.1:8003
```

## 配置（config.yaml）

```yaml
# ⛔ msg-client 的 Default() **三项全为空串**：addr / tcp_addr / auth_addr 都**必填**，空则启动即 os.Exit(1)。
#    （8003/8002/8051 那组"默认值"是 **robot** 的，不是本工具的。）下面填的是示例值。
addr: "127.0.0.1:8003"                # 网关 QUIC/UDP 地址（必填；启动 -addr 可覆盖）
tcp_addr: "127.0.0.1:8002"            # QUIC 不可用时的 TCP 回退地址（必填；两个端口不同）
                                      # 网关 TCP 口若走 TLS（tcp_tls_disabled=false，默认），
                                      # 本工具会在进程内首次连接时自动判定并复用（TLS 优先 → 明文回退）
auth_addr: "http://127.0.0.1:8051"    # 账号服 HTTP 地址（必填；默认值即 http://127.0.0.1:8051）

proto:
  business: []                        # 业务 proto 目录（相对配置文件），可多个
```

- 路径相对**配置文件所在目录**解析
- `auth_addr` 是**必填项**：登录 / 注册都走账号服 HTTP，游戏服不接收账号密码；缺失时启动即报错退出

## 交互命令

| 命令 | 说明 |
| --- | --- |
| `help` / `?` | 显示帮助 |
| `connect [addr]` | 连接网关（缺省用启动 `-addr`；会先断开旧连接） |
| `disconnect` | 断开当前连接 |
| `login <account> <password>` | 一键登录：先 HTTP 换 token，再发 `EMsgLogin{token}` |
| `signup <account> <password>` | 注册（走账号服 HTTP，成功后自动登录） |
| `ls` / `list` | 列出全部已加载消息（方向 + req/reply/notify 字段） |
| `about <MsgName\|id>` | 查看单条消息的说明与字段 |
| `types [Name]` | 列出全部 Request/Reply/Notify 结构体；带参数时查该结构体字段 |
| `send <MsgName\|id> [k=v ...]` | 按消息名或消息号**自动绑定字段**组 JSON 包发送 |
| `send <id> <raw-json>` | 兜底：索引里没有该消息时直接发原始 JSON |
| `send_pos ...` | 位置同步类消息的快捷发送 |
| `reload` | 重新扫描 proto 目录 |
| `quit` / `exit` | 断开并退出 |

连上网关后，服务端下发的每一帧会自动打印：

```text
<<< [ELoginReply]
{
  "owner": "alice",
  "token": "tok-xyz",
  "success": true
}
```

## 登录与注册（唯一链路）

```text
注册：msg-client ──POST {auth_addr}/auth/signup──▶ 账号服        （游戏服不参与）
登录：① msg-client ──POST {auth_addr}/auth/login──▶ 账号服 换 JWT
      ② msg-client ──长连接 EMsgLogin{token}────▶ 游戏服
      ③ 游戏服     ──POST {auth.verify_addr}/auth/verify──▶ 账号服 换 owner
```

账号密码**只发给账号服**，永不进入游戏长连接；游戏服只认 token，不碰账号表。

## 与 msg-web 的分工

| | `msg-client` | `msg-web` |
| --- | --- | --- |
| 形态 | 终端 REPL | 浏览器 Web GUI |
| 适用 | 快速联调、可脚本化试消息 | 可视化翻查消息与字段、多人共用 |
| 账号服接入 | 直连 | 经本工具代理 `/api/auth/*`（规避跨域） |

### msg-web 配置（[`clover-server-tools/msg-web/config.yaml`](https://github.com/qw576483/clover-server-tools/blob/main/msg-web/config.yaml)）

| 键 | 说明 | 取值 |
| --- | --- | --- |
| `addr` | 引擎**网关**地址（页面直连；WS 与 WebTransport 复用同一端口号，协议由页面自动选择） | 默认 `127.0.0.1:8001` |
| `web_port` | 本工具页面监听端口 | 默认 `3020` |
| `auth_addr` | 账号服 HTTP 地址；页面登录 / 注册都经本工具代理 `/api/auth/*`（规避跨域） | **必填**，缺失启动即失败 |
| `tls_cert` / `tls_key` | 页面 HTTPS 证书（PEM）；两项**都非空**才启用 HTTPS，页面据此派生 `wss://` | 留空=明文 HTTP |
| `proto.business` | 业务 def 目录（引擎消息已内置，不需配引擎源码路径） | 如 `../../your-server/game/def` |

> **页面协议必须与网关一致**：网关开了 TLS（`gateway.tls_cert`）时页面也要配证书；
> 若把网关证书清空退回明文，这两行也要注释掉、或启动加 `-http`，否则浏览器 WS 与 WebTransport 两条通道都连不上。

## 下一步

1. [打表工具](table-tools.md) —— 策划表转换与代码生成
2. [本地环境](windows-env.md) —— etcd / nats / redis / mysql 一键起停
3. [AI Skill](../../ai/skill.md) —— 开发范式与模板

