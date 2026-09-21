# 快速开始

从一台干净机器，到用调试客户端登录进游戏。

Clover 服务端引擎是**标准 Go module**，不需要克隆引擎源码，`go get` 就能用。真正要准备的是**两块东西**，也是新手最容易漏的两块：

1. **依赖环境** —— etcd / nats / redis / mysql。引擎启动链路的第一步就是连它们，**没起不是"降级"、是直接启动失败**；
2. **配置文件** —— `configs/all/server.yaml`。多个字段**缺失时不报错而是静默降级**，所以每一项都要显式写。

| # | 做什么 | 判据（做完能看到什么） |
|---|---|---|
| 1 | 用 [clover-server-tools](https://github.com/qw576483/clover-server-tools) 的 `windows-env` 一起启动四个中间件 | `env.exe info` 显示四个都「运行中」 |
| 2 | 建工程 → 写 `configs/all/server.yaml` → 启动 | 日志出现 `clover: gateway running (ws=… tcp=… udp=…)` |
| 3 | 用 `msg-client` 连网关、注册 / 登录 | 收到 `ELoginReply` |

## 1. 前置：Go 1.25+

```bash
go version    # 需要 go1.25 或更高
```

## 2. 起依赖环境（windows-env）

### 2.1 为什么这一步不能跳

引擎启动时，master 起来的第一件事就是连 redis 与 mysql。它们没起时日志长这样（真实报错）：

```text
ERROR  server/main.go:26  【all】app start failed (config=configs/all):
svc: master start failed: master: create store: redis ping [127.0.0.1:6379]
(mode=standalone, db=0): dial tcp 127.0.0.1:6379:
connectex: No connection could be made because the target machine actively refused it.
```

这是**本机最常见的第一个坑**：代码写得没错，环境没起。

### 2.2 拿环境

```powershell
git clone https://github.com/qw576483/clover-server-tools.git
cd clover-server-tools/windows-env
```

> **中间件二进制不入库**：`etcd/` `mysql/` `nats/` `redis/` 四个目录合计约 1.8 GB，属第三方发行物，仓库不含。
> 新克隆下来它们是空的，要把官方发行包解压进去（`env.exe` 检测到缺失会直接把下载地址与文件名打出来）。
> `core/env.exe`（环境管理 CLI）**已随仓库提供**，不需要自己编译。

### 2.3 起停

```powershell
core\env.exe start           # 起全部（etcd + nats + redis + mysql）
core\env.exe start mysql     # 只起一个
core\env.exe info            # 看状态（status 是 info 的别名）
core\env.exe stop            # 停全部
```

也可以**双击 `core\env.exe`** 进交互菜单：`1` 启动全部 / `2` 停止全部 / `3` 状态 / `q` 退出。

`env.exe` 退出、终端关掉都不影响服务——四个中间件在后台独立存活。

### 2.4 端口与账号（与引擎默认配置完全对齐）

| 组件 | 端口 | 账号 |
|---|---|---|
| etcd | 2379（client）/ 2380（peer） | 无密码，只监听 `127.0.0.1` |
| nats | 4222 | 无密码 |
| redis | 6379 | 无密码 |
| mysql | 3306 | 用户 `root`，**空密码** |

### 2.5 验证（四条都过才算环境就绪）

```powershell
mysql\bin\mysql.exe -uroot -e "SELECT VERSION();"
redis\redis-cli.exe -p 6379 ping        :: 期望 PONG
etcd\etcdctl.exe endpoint health        :: 期望 healthy
core\env.exe info                       :: 四个服务都「运行中」
```

## 3. 建工程

```bash
mkdir your-server && cd your-server
go mod init your-server
go get github.com/qw576483/clover-server-engine@latest
```

只有**需要改引擎源码**时才克隆引擎，并在 `go.mod` 里用 `replace` 指过去：

```text
replace github.com/qw576483/clover-server-engine => ../clover-server-engine
```

### 3.1 入口 `main.go`

```go
package main

import (
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/foundation/logger"

    _ "your-server/game/logic"        // 业务逻辑包：在 init 里完成挂载
)

func main() {
    if err := app.Run("configs/all"); err != nil {
        logger.Fatal("启动失败", logger.Field("err", err))
    }
}
```

`app.Run(path)` 的参数是**配置目录**（也接受单个 yaml 文件），按配置里的 `server_type` 决定起哪些角色。

### 3.2 挂载业务 `game/logic/logic.go`

```go
package logic

import (
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/transport/event"
)

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(1000101, onGetPlayerList)      // 业务消息号必须 >= 10001
    })
}

// handler 签名固定为 func(event.Ctx) error；返回即自动提交（读 → 改 → 返回）
func onGetPlayerList(c event.Ctx) error { return nil }
```

`app.Mount` 是四个角色**共用的唯一挂载入口**（通常在业务包 `init` 里调用）。fn 签名必须与 role 匹配，不匹配会在**进程启动时立刻 panic**，不会出现"挂错角色、消息永远到不了"的静默失败：

| role | fn 签名 |
|---|---|
| `app.RoleGame` | `func(*app.Game)` |
| `app.RoleMaster` | `func(*app.MasterGame)` |
| `app.RoleLog` | `func(*app.LogGame)` |
| `app.RoleAuth` | `func(*app.AuthGame)` |

### 3.3 目录结构

```text
your-server/
├── main.go
├── configs/
│   └── all/
│       └── server.yaml      # 唯一配置文件
└── game/
    ├── def/                 # 消息号与消息结构（C2S / 回包 / 推送）
    ├── datadef/             # 数据 schema 定义
    ├── logic/               # 业务 handler（app.Mount）
    └── table/               # 打表产物（go:embed）与读表代码
```

### 3.4 消息号约定

- 引擎占 `[1, 10000]`（`proto.InternalMsgMax`）；**业务消息号必须 `>= 10001`**，由 `OnMsg` 在启动期校验（误用直接 panic）；
- 引擎常量用 `EMsg*` / `EPush*`；普通回包 `msgID` 恒为 `0`，客户端按 `requestID` 配对；
- 引擎内建协议号（如 master↔game 房间协议 6001–6004）走内部注册路径，业务侧 `OnMsg` 的硬约束不变。

## 4. 写配置 `configs/all/server.yaml`

**这一节最容易出事**：好几个字段缺失时引擎**不报错**，只是少监听一条线路、或者推送全部丢掉。所以照下面写全，别省。

```yaml
server_type: "all"                 # 必需：game | gateway | all | master | log | auth

gateway:
  listen_ws:  "127.0.0.1:8001"     # WebSocket（浏览器 / WebGL）；空 = 不启用
  ws_path: "/ws"
  listen_tcp: "127.0.0.1:8002"     # TCP（Unity 原生客户端走这个口）；空 = 不启用
  listen_udp: "127.0.0.1:8003"     # UDP（QUIC + 裸 UDP 共享）
  enable_wt: true                  # WebTransport 复用 listen_ws 的端口号（UDP 侧），无独立地址字段
  max_frame_size: 1048576
  tls_cert: "certs/server.pem"     # 主证书：TCP / WS / QUIC 共用（本机证书见文末附录）
  tls_key:  "certs/server-key.pem"
  wt_cert: ""                      # 空 = 网关自动签发并轮换 WebTransport 专用证书
  wt_key:  ""
  wt_pin:  true                    # 本地 true；生产用公共 CA 时 false
  tcp_tls_disabled: true           # 必须与客户端 `server.tls` 相反（见下表）

logic:
  listen_addr: "127.0.0.1:8011"    # 必需：网关的上游；空则网关拨不通逻辑服
  heartbeat: 30s
  frame_timeout: 30s

auth:                              # 账号服：登录链路的必经依赖（all 模式会一并启动）
  listen: "127.0.0.1:8051"
  jwt_secret: "dev-only-change-me"
  token_ttl: 2h
  verify_addr: "http://127.0.0.1:8051"
  insecure_plaintext: true         # 本机联调显式声明明文；不给会因"账号服要求 TLS"而启动失败

data:
  tier: "TierRedisMySQL"           # 禁止 TierMemory（loadConfig 会直接拒绝）
  auto_create_table: true
  table: "data"
  redis:
    addr: "127.0.0.1:6379"
    pass: ""
    db: 0
  mysql:
    host: "127.0.0.1"
    port: 3306
    user: "root"
    pass: ""                       # windows-env 的 mysql root 就是空密码
    db_name: "clover"
    charset: "utf8mb4"
    parse_time: true

master_listen_addr: "127.0.0.1:8021"
master_addr: "127.0.0.1:8021"
log_listen_addr: "127.0.0.1:8031"
log_addr: "127.0.0.1:8031"         # etcd 发现不到 log 实例时的兜底

nats:
  addr: "127.0.0.1:4222"           # 必须非空，理由见下表
nats_subject: "clover.notify"

log:                               # 注意字段名是 log，不是 logging
  level: "debug"
  format: "console"
  dir: "./logs"
  stdout: true

admin:
  listen_addr: "127.0.0.1:8041"    # 空 = 回落固定 8041（不是随机端口）

misc:
  timezone: "Asia/Shanghai"

etcd:
  endpoints: []                    # 空 = 不启用服务发现（单进程 all 够用；多节点必须填）
```

### 字段背后的坑（都踩过）

| 字段 | 写错的后果 | 真相 |
|---|---|---|
| `nats.addr` | **所有 `Push*` 静默返回 `nil`** —— 不报错、不打日志。现象是"客户端连上了、但收不到任何推送，进对局黑屏" | 引擎 `Core.PushToPlayer` 第一行就是 `if co.notifyPub == nil { return nil }`：空值不是"不启用"，是**推送全部丢掉**。实测出处：补上这一行后 35 条端到端断言全 PASS，不补则收到 0 条推送 |
| `logic.listen_addr`、`gateway.listen_*` | 对应线路**静默不启用** | 监听地址缺失**不报错**，所以每个口都必须显式写 |
| `data.tier` | 写 `TierMemory` 会被 `loadConfig` **拒绝**（启动失败） | 本地联调也用 `TierRedisMySQL` —— 反正 windows-env 已经把 mysql/redis 起好了 |
| `auth.insecure_plaintext` | 不给就直接启动失败 | 账号服 HTTP 默认要求 TLS；本机联调显式声明明文，生产必须配证书 |
| `gateway.tcp_tls_disabled` | 与客户端 `server.tls` 配成**同侧** ⇒ 现象是"连上就断" | 二者必须**相反**：`tcp_tls_disabled: true` ⇒ 客户端 `"tls": false` |
| `etcd.endpoints: []` | 单机无影响；多节点时会找不到别人的场景 / 房间 | 空值启动日志会明确 WARN（见下节最后一条） |

## 5. 启动与判据

```bash
go build -o server.exe .
./server.exe -config configs/all
```

**启动成功的判据**（`all` 模式真实日志，按出现顺序）：

```text
INFO  redis/client.go:108   【all】redis connected: mode=standalone addrs=[127.0.0.1:6379] db=0 pool_size=20
INFO  mysql/client.go:78    【all】mysql connected: 127.0.0.1:3306 db=clover max_open=20 max_idle=10
INFO  nats/client.go:119    【all】nats connected: nats://127.0.0.1:4222 (jetstream=false, client=)
INFO  tcp/server.go:52      【all】tcp server listening on 127.0.0.1:8021          # master
INFO  tcp/server.go:52      【all】tcp server listening on 127.0.0.1:8031          # log
INFO  http/server.go:92     【all】http server listening on 127.0.0.1:8051 (tls=false)   # 账号服
INFO  auth_server.go:231    【all】auth: serving /auth/* on 127.0.0.1:8051 (issuer=clover-auth ttl=2h0m0s)
INFO  tcp/server.go:52      【all】tcp server listening on 127.0.0.1:8011          # 逻辑服
INFO  bootstrap.go:541      【all】gateway: TLS certificate loaded cert=certs/server.pem key=certs/server-key.pem
INFO  tcp/server.go:52      【all】tcp server listening on 127.0.0.1:8002
INFO  ws/server.go:98       【all】ws server listening on wss://127.0.0.1:8001/ws
INFO  quic/server.go:132    【all】quic server listening on 127.0.0.1:8003
INFO  bootstrap.go:637      【all】clover: gateway running (ws=127.0.0.1:8001 tcp=127.0.0.1:8002 udp=127.0.0.1:8003)
```

最后一行出现 = 可以连了。`all` 模式各角色占用的端口：

| 角色 | 端口 | 谁连它 |
|---|---|---|
| gateway | `8001` WS / `8002` TCP / `8003` UDP | 客户端（Unity / 浏览器）。UDP 口同时承载 QUIC 与 WebTransport |
| logic | `8011` | 网关（上游） |
| master | `8021` | 逻辑服 |
| log | `8031` | 逻辑服 |
| auth | `8051` HTTP / `8061` RPC | 客户端 HTTP 换 token；逻辑服 verify |
| admin | `8041` | 运维面（drain、切上游等） |

> `configs/all` 是**单进程承载全部角色**，本地开发用这个最省事。要拆进程部署，把 `server_type` 改成对应角色、各自一份配置（见[部署](operations/deployment.md)）。

## 6. 连上去：msg-client

```bash
cd clover-server-tools/msg-client
go build -o client ./cmd/client
./client                      # 首次运行会自动生成默认 config.yaml
```

```yaml
# config.yaml
addr: "127.0.0.1:8003"                    # 网关 UDP（QUIC 优先，失败自动回退 TCP）
tcp_addr: "127.0.0.1:8002"                # 回退用的 TCP 口
auth_addr: "http://127.0.0.1:8051"        # 账号服，**必填**（注册 / 登录都走它）
```

REPL 里：

```text
connect                    # 连网关
signup alice 123456        # 注册（走账号服 HTTP，成功后自动登录）
login alice 123456         # 或者直接登录
ls                         # 列出引擎 + 业务的全部消息
send MsgGetPlayerList      # 按字段名自动组包，发一条业务消息
```

登录链路（**账号密码只发给账号服，永不进入游戏长连接**）：

```text
注册：msg-client ──POST {auth_addr}/auth/signup──▶ 账号服
登录：① msg-client ──POST {auth_addr}/auth/login────▶ 账号服 换 JWT
      ② msg-client ──长连接 EMsgLogin{token}──────▶ 游戏服
      ③ 游戏服     ──POST {auth.verify_addr}/auth/verify──▶ 账号服 换 owner
```

## 7. 常见问题

| 现象 | 原因 / 解法 |
|---|---|
| `app start failed ... redis ping ... actively refused` | 依赖环境没起。`core\env.exe start` 后重试，`core\env.exe info` 看是谁没起 |
| `svc: master start failed: ... mysql` | 同上（MySQL 没起，或 `data.mysql` 的账号密码与实际情况不符） |
| 客户端连上了，但**一条推送都收不到** | 九成是 `nats.addr` 为空 ⇒ 所有 `Push*` 静默返回 `nil`。填上 `127.0.0.1:4222` 重启 |
| 客户端「连上就断」 | `gateway.tcp_tls_disabled` 与客户端 `server.tls` 配成了同侧 |
| `listen tcp ...: bind: address already in use` | 上一轮没停干净：`core\env.exe info` 看端口占用，或 `netstat -ano \| findstr :8002` |
| 日志有 `scene route uses in-memory backend (no etcd)` | **正常** —— 这是 `etcd.endpoints: []` 的预期行为；单机无影响，只是跨节点对象迁移用不了 |
| 客户端配了 `8001` 连不上 | 原生客户端走 **TCP `8002`**；`8001` 是给浏览器 WS / WebTransport 的 |

## 附录：本机证书

`gateway.tls_cert` / `tls_key` 不是可有可无（WS / QUIC / WT 几条线路都要用），但**也不需要买证书**：本机用 [mkcert](https://github.com/qw576483/clover-server-tools/tree/main/mkcert) 生成一张、装进本机信任库即可（`clover-server-tools` 仓库已随附 `mkcert.exe` 与命令）。

> **证书每台机器独立，绝不能跨机器拷贝**：mkcert 的根 CA 是在本机随机生成并装进本机信任库的，A 机器的证书拿到 B 机器必然报 `tls: unknown certificate`。

## 下一步

1. [安装与环境](development/environment.md) — 各依赖的手工安装方式（Linux / macOS）
2. [配置说明](development/configuration.md) — 全部配置字段
3. [Handler 开发](development/handler.md) — 开始写业务逻辑
4. [本地环境工具](tools/windows-env.md) — windows-env 详解
5. [调试客户端](tools/msg-client.md) — msg-client 详解
6. [部署](operations/deployment.md) — 生产环境

