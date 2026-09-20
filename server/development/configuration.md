# 配置管理

## 这篇文档讲什么？

本文档介绍 Clover 引擎的配置管理系统，包括配置文件结构、配置项说明和环境变量配置。目标读者是想要配置和管理 Clover 服务端的开发者。

## 前置条件

- 了解 Clover 引擎的基本架构
- 熟悉 YAML 配置格式
- 了解部署模式（all 模式、分离模式）

## 配置文件结构

Clover 使用统一的 `server.yaml` 配置文件，通过 `server_type` 字段区分进程角色：

```
configs/
├── all/                    # 单进程模式（推荐开发环境）
│   └── server.yaml         # 网关+逻辑服+master 同进程
├── master/                 # 分离部署：master 协调服
│   └── server.yaml
├── game/                   # 分离部署：逻辑服
│   └── server.yaml
└── gateway/                # 分离部署：网关服
    └── server.yaml
```

## 快速开始

### 1. 创建配置文件

在项目根目录创建 `configs/all/server.yaml`：

```yaml
# Clover 统一配置
# 引擎分层：gateway（网关）→ logic（逻辑服）→ data（存贮）├─ nats（队列）├─ etcd（发现）
# 用法：go run . -config configs/all/server.yaml

# 进程角色：all=网关+逻辑服+master 同进程（master 必须启动成功）
server_type: "all"

# ========== 网关接入（客户端暴露端口 8001-8100） ==========
gateway:
  listen_ws: "127.0.0.1:8001"       # 客户端 WebSocket 接入
  listen_tcp: "127.0.0.1:8002"      # 客户端 TCP 接入
  listen_udp: "127.0.0.1:8003"      # 客户端 UDP 接入

# ========== 逻辑服（内部 TCP 端口 8011-8100） ==========
logic:
  listen_addr: "127.0.0.1:8011"     # TCP 监听
  http_listen: "127.0.0.1:8012"     # HTTP 控制面

# ========== 账号服（登录链路的必经依赖） ==========
# 引擎只有一种登录模式：账号服校验账号密码并签发 JWT，游戏服每次登录都调
# {verify_addr}/auth/verify 换 owner。因此 all 角色会一并启动账号服：
#   ① 客户端 HTTPS 调 {verify_addr}/auth/login 换 token
#   ② 客户端走长连接发 EMsgLogin{token}
#   ③ 游戏服 POST {verify_addr}/auth/verify 换 owner
# listen 是本进程账号服监听的地址，verify_addr 是游戏服实际去连的地址；
# 两者必须能互相连通（同进程部署时填同一个地址，否则会自己连不上自己）。
# ★ 默认安全：账号服**默认要求 TLS**——不配 tls.cert_file/tls.key_file 又没显式
#   insecure_plaintext: true 时**拒绝启动**（口令与 JWT 不能明文上线）。
#   本机联调证书用 clover-server-tools/mkcert 生成（根 CA 已入系统信任库）；
#   老配置升级写法见「配置迁移说明」一节。
auth:
  listen: "127.0.0.1:8051"                # 账号服 HTTPS 监听（auth / all 角色必填）
  jwt_secret: "dev-only-change-me"        # JWT 签名密钥（HS256）；生产务必用强随机串
  token_ttl: 2h                           # 签发 token 有效期；<=0 用内置默认 2h
  issuer: "clover-auth"                   # JWT 签发者（iss 声明）；空=内置默认
  tls:                                    # ★ 账号服证书对（必须成对；只配一个启动即失败）
    cert_file: "certs/server.pem"
    key_file: "certs/server-key.pem"
  # 仅在「本机 / 完全隔离的内网联调」时取消下面这行的注释：显式放行明文（启动会打 Warn），
  # 此时 verify_addr 也可以写回 http://。生产环境不要这么配。
  # insecure_plaintext: true
  verify_addr: "https://127.0.0.1:8051"   # 游戏服校验凭证的账号服地址（game/gateway/all 必填，缺失即 panic）
  verify_timeout: 3s                      # /auth/verify 单次调用超时；<=0 用内置默认 3s

# ========== 通用数据存贮 ==========
data:
  tier: "TierRedisMySQL"           # 存储模式
  auto_create_table: true           # 自动建表
  table: "data"                     # 三元键存贮表名
  sqls_dir: "sqls"                  # SQL 迁移目录
  redis_key_prefix: "clover-a:data"   # Redis 前缀
  cache_ttl: 0                      # 缓存TTL；0=不过期
  redis:
    addr: "127.0.0.1:6379"
    pass: ""
    db: 0
  mysql:
    host: "127.0.0.1"
    port: 3306
    user: "root"
    pass: ""
    db_name: "clover-a"
    charset: "utf8mb4"
    auto_create: true
    parse_time: true

# ========== Master 协调服 ==========
master_listen_addr: "127.0.0.1:8021"
master_http_listen_addr: "127.0.0.1:8022"
master_addr: "127.0.0.1:8021"

# ========== 日志 ==========
log:
  level: "debug"                     # debug/info/warn/error
  format: "console"                  # console=开发 / json=生产
  dir: "./logs"                      # 日志根目录
  stdout: true                       # 同步输出到控制台
```

### 2. 启动服务

```bash
# 开发环境启动
go run . -config configs/all/server.yaml

# 生产环境启动
./clover-server -config configs/all/server.yaml
```

## 配置项详解

### 网关配置

```yaml
gateway:
  listen_ws: "127.0.0.1:8001"       # WebSocket 监听地址
  ws_path: "/ws"                    # WebSocket 路径
  ws_allow_all_origins: true        # 允许跨域 WS
  listen_tcp: "127.0.0.1:8002"      # TCP 监听地址
  listen_udp: "127.0.0.1:8003"      # UDP 监听地址
  enable_wt: true                   # 启用 WebTransport
  max_frame_size: 10485760          # 单帧上限（10MB，引擎默认值；与客户端帧上限常量同值）
  reconnect_grace: 30s              # 重连宽限期
  disconnect_grace: 30s             # 断线宽限期
  tls_cert: "certs/server.pem"      # TLS 证书路径
  tls_key: "certs/server-key.pem"   # TLS 私钥路径
  tcp_tls_disabled: false           # TCP/WS 是否各自绕过 TLS；默认 false（TCP 也走 TLS）
  wt_cert: ""                       # WebTransport 证书（留空=自动生成）
  wt_key: ""                        # WebTransport 私钥
  wt_pin: true                      # 是否对 WebTransport 启用证书固定
```

**配置说明：**
- `listen_ws`：WebSocket 服务监听地址，客户端通过此地址连接
- `listen_tcp`：TCP 服务监听地址，用于原生客户端连接
- `listen_udp`：UDP 服务监听地址，用于 QUIC 和裸 UDP 连接
- `enable_wt`：在 WS 端口号上启用 WebTransport（UDP 侧）
- `tls_cert/tls_key`：TLS 证书配置，生产环境可换成 Let's Encrypt 证书
- `tcp_tls_disabled`：配了证书后 **TCP 口默认也被 TLS 包起来**（新部署的推荐形态）；
  客户端用 `GameConfig.UseTls` 匹配（**两者必须相反**）。TCP/WS 的 TLS 下限是 **1.2**
  （QUIC/WT 仍是 1.3），以兼容只到 1.2 的原生 `SslStream`。设回 `true` 会保留明文 TCP 入口，
  启动日志会打一条告警——那是显式降级，不是默认。
- `reconnect_grace` / `disconnect_grace`：引擎默认均为 `0`（**关闭重连宽限 / 立即触发硬掉线**），
  需显式配置才生效；上例的 30s 为业务取值，不是引擎默认。

### 逻辑服配置

```yaml
logic:
  listen_addr: "127.0.0.1:8011"     # TCP 监听（网关拨号此地址）
  http_listen: "127.0.0.1:8012"     # HTTP 控制面；空=不启用
  heartbeat: 30s                    # 心跳间隔
  frame_timeout: 30s                # 单帧处理上限
  reconnect_grace: 30s              # 重连宽限
```

**配置说明：**
- `listen_addr`：逻辑服 TCP 监听地址，网关通过此地址连接逻辑服
- `http_listen`：HTTP 控制面地址，用于监控和管理接口
- `heartbeat`：心跳间隔，支持时间单位：s(秒) m(分) h(时) ms(毫秒)

### 数据存储配置

```yaml
data:
  tier: "TierRedisMySQL"           # 存储模式
  auto_create_table: true           # 自动建表
  table: "data"                     # 三元键存贮表名
  sqls_dir: "sqls"                  # SQL 迁移目录
  redis_key_prefix: "clover-a:data"   # Redis 前缀
  cache_ttl: 0                      # 缓存TTL；0=不过期
  redis:
    addr: "127.0.0.1:6379"
    pass: ""
    db: 0
  mysql:
    host: "127.0.0.1"
    port: 3306
    user: "root"
    pass: ""
    db_name: "clover-a"
    charset: "utf8mb4"
    auto_create: true
    parse_time: true
```

**存储模式说明：**
- `TierMemory`：纯内存模式，适合开发测试
- `TierRedisMySQL`：Redis 缓存 + MySQL 持久化，适合生产环境
- `TierSnapshot`：内存 + MySQL 快照，适合大数据量场景

### Master 协调服配置

```yaml
master_listen_addr: "127.0.0.1:8021"      # master 监听地址（内部 RPC）
master_http_listen_addr: "127.0.0.1:8022" # master HTTP 控制面
master_addr: "127.0.0.1:8021"             # game 连接 master 地址
master_token: ""                          # 内部 RPC 共享密钥；非回环地址时**必填**（见下）
```

**配置说明：**
- `master_listen_addr`：master 协调服监听地址，game 通过此地址连接 master
- `master_http_listen_addr`：master HTTP 控制面地址，用于管理接口
- `master_addr`：game 连接 master 的地址，通常与 `master_listen_addr` 相同
- `master_token`：master 内部 RPC 的共享密钥；非空时每条连接首帧必须完成 `MsgAuth` 握手，
  game 侧的 `master_token` 必须填同一个值
- ⚠️ **`master_listen_addr` 非回环时 `master_token` 必填**：这条通道上挂着 `MsgSessionNew` /
  `MsgSessionValidate` / `MsgPlayerRegister` / `MsgRank*` 等**无调用方身份校验**的写接口，
  `internal/app/master_server.go` 的 `validateMasterListen` 把「非回环 + 无 token」判为不安全配置，
  构造期直接报错、**启动被拒**（不静默改写地址）。要跨机部署就必须同时配内网地址与 `master_token`。

### 日志配置

```yaml
log:
  level: "debug"                     # debug/info/warn/error
  format: "console"                  # console=开发 / json=生产
  dir: "./logs"                      # 日志根目录；空=仅控制台
  stdout: true                       # 同步输出到控制台
```

**配置说明：**
- `level`：日志级别，生产环境建议使用 `info` 或 `warn`
- `format`：日志格式，开发环境使用 `console`，生产环境使用 `json`
- `dir`：日志目录，按 `{dir}/{YYYY-MM-DD}-{service}.log` 按天滚动落盘

## 高级配置

### 自定义日志落盘后端

业务日志默认落 MySQL。量级上来后要换 ClickHouse / 自建服务时，**不需要改引擎代码**——
实现 `logstore.Backend` 后注册，改配置即可切换：

```go
// your-server/logic/logbackend.go
func init() {
    app.RegisterLogBackend("clickhouse", func(raw map[string]any) (logstore.Backend, error) {
        return newClickHouseBackend(raw) // raw = log_backend_config
    })
}
```

```yaml
# server_type=log 的配置
log_backend: "clickhouse"
log_backend_config:
  dsn: "clickhouse://127.0.0.1:9000"
  table: "biz_log"
```

**配置说明：**
- `log_backend`：空 = 内置 `mysql`（读 `data.mysql`）；填注册过的名字则用对应后端。
  名字未知、工厂报错、或工厂返回 nil 都**启动即失败**——不静默降级，避免悄悄丢日志。
- `log_backend_config`：原样交给后端工厂，结构由后端自己定义，引擎不解释。
- 后端契约：`logstore.Backend`（`WriteBatch(source, entries) (int, error)` + `Close() error`），
  真身见 [`clover-server-engine/pkg/foundation/logstore`](https://github.com/qw576483/clover-server-engine/tree/main/pkg/foundation/logstore)。
- 后端只需负责「把一批日志存下去」；**攒批、按片分发到多实例、失败重连**由引擎在 `logbuf` 侧完成。

### 跨机对象迁移（MMO 切场景）

多 game 节点之间迁移对象（跨服切场景 / 跨图）需要两个前提：

```yaml
node_id: 1          # 本节点在集群内的唯一数字标识（每个 game 节点不同）
etcd:
  endpoints: ["127.0.0.1:2379"]   # scene→node 路由表存在全局 KV 上，跨机必须配
```

**配置说明：**
- `node_id`：**数字**标识而不是地址 —— 定向投递用的 NATS subject 是
  `mmo.transfer.remote.<node_id>`，而 NATS subject 不允许地址里的 `:`。
  多 game 节点必须互不相同；**不配即不启用**跨机迁移（`TransferRemote` 返回 `ErrNoRoute`），单机部署无需配置。
- **全局 KV**：scene→node 路由表建在全局 KV 上。配了 `etcd.endpoints` 时用 etcd 后端（跨机共享）；
  否则退化为内存后端（仅本进程可见，跨机**查不到别的节点**的场景）。

业务侧接线（引擎不自动装配 MMO 模块，需显式创建并注入）：

```go
sm := mmo.NewSceneManager(
    mmo.WithStore(store), mmo.WithPublisher(pub),
    mmo.WithClusterRoute(g.SceneRoute(), g.NodeID()),
    mmo.WithRemoteTransferSubscriber(g.SceneSubscriber()),
)
```

> 注入后 `CreateScene` / `DestroyScene` 自动登记 / 注销路由，`Run` 期间自动续期
> （TTL 30s，续期间隔 10s）；`TransferRemote` 会先查路由定位目标节点再**定向**投递。
> 上面两个选项（`WithClusterRoute` / `WithRemoteTransferSubscriber`）是 `pkg/domain/mmo` 暴露的全部接线入口；
> `internal/domain/mmo` 的 `NewModule` / `WithClusterTransfer` **不对外暴露**，业务侧写不出来。

### Master 节点健康探测

```yaml
master_health:
  heartbeat_interval: 3s            # 节点上报心跳周期；默认 3s
  suspect_timeout: 9s               # 静默超过此值标记 Suspect；默认 9s（必须 < dead_timeout）
  dead_timeout: 15s                 # 静默超过此值标记 Dead 并摘除；默认 15s
  probe_interval: 1s                # 探测器扫描节点表周期；默认 1s
```

### Master session token 存储后端

```yaml
master_session_token:
  backend: "redis"                  # memory=仅进程内（master 重启即失效，需重新登录）| redis=Redis TTL 持久化
  ttl: 24h                          # token 有效期；0=默认 24h；负值（如 -1）永不过期
  key_prefix: "session:token:"      # [仅 redis] key 前缀；多游戏服共用 Redis 时覆盖以隔离
```

### 服务发现（etcd）配置

```yaml
etcd:
  endpoints: ["127.0.0.1:2379"]       # 空=不启用服务发现
  username: ""
  password: ""
  register_ttl: 10s                   # 服务注册租约 TTL；<=0 使用默认 10s
  dial_timeout: 5s                    # 连接超时；<=0 使用默认 5s
  config_key: ""                      # 业务配置在 etcd 中的存储 key 路径（远程配置源用）
  tls:                                # 双向认证；整段省略=不启用 TLS
    cert_file: ""
    key_file: ""
    ca_file: ""
```

**配置说明：**
- `endpoints`：etcd 集群地址；**为空表示不启用服务发现**，各角色退化为使用静态地址（单实例可正常运行）。
- key 约定：`clover/services/<角色>/<角色>-<主机>-<PID>`，值为该实例的可调用地址；`<角色>` 为
  `logic`（网关上游）/ `auth`（账号服消息通道）/ `log`（日志服：同步 RPC `CallLog` 与日志管道
  `AddLog` 共用）。前缀 + 唯一 key 保证多实例互不覆盖，实例崩溃后由租约到期自动摘除。
- `register_ttl`：注册租约续租周期；过短会因网络抖动误摘除，过长会让崩溃实例残留更久，默认 10s。
- 解析顺序**按角色不同**：`logic`（网关上游）静态优先——配了 `logic.listen_addr` 就直接用、不查 etcd；
  `auth` / `log`（消息通道与日志管道）发现优先——etcd 上有实例就轮询使用，列表为空才回退
  `auth.rpc_addr` / `log_addr`。

### 跨节点事件可靠投递配置

```yaml
reliable:
  enabled: true                       # false=退回裸 Publish
  ack_timeout: 3s                     # 单次投递等待 ACK 超时
  max_attempts: 5                     # 最大投递次数
  base_delay: 100ms                   # 重投基础退避
  max_delay: 10s                      # 重投退避上限
  multiplier: 2                       # 退避倍率
  jitter: 0.2                         # 退避抖动比例
  pending_limit: 100000               # 在途投递表容量上限
  async: true                         # true=Send 立即返回、后台重试
  dedup_enabled: true                 # 接收侧幂等去重
  dedup_capacity: 10000               # 本地去重缓存容量
  dedup_ttl: 10m                      # 去重记录有效期
  redis_dedup_prefix: "clover:evt:dedup:"  # 跨节点去重的 Redis key 前缀
  dlq_capacity: 1000                  # 内存死信队列容量
```

### NATS 消息队列配置

```yaml
nats:
  addr: "nats://127.0.0.1:4222"     # 空=不启用 NATS 下行推送
  client_name: "clover-a"
nats_subject: "clover.notify"       # 下行推送 subject
```

### Admin 运维控制面配置

```yaml
admin:
  disable: false                     # true=完全不启动 admin HTTP 服务
  listen_addr: "127.0.0.1:8041"      # 监听地址；留空回落到 127.0.0.1:8041（不是随机端口）
  token: ""                          # 控制面鉴权令牌；空=不启用鉴权，此时 listen_addr 必须是回环
  shutdown_timeout: 5s               # 关停时等待在途请求的上限
  pprof: false                       # true=额外注册 /debug/pprof/*
```

> ⚠️ **`listen_addr` 非回环时 `token` 必填**：`AdminConfig.Normalize` 把「非回环 + 无 token」
> 判为不安全配置，构造期直接报错、**启动被拒**（不会静默改写地址）。要跨机运维 admin，
> 必须同时配内网 `listen_addr` 与 `token`。

**Admin 接口说明**（注册于 `internal/app/admin.go`）：
- `GET /ping`：admin 自身存活 + 已注册路由列表
- `GET /routes`：列出已注册路由
- `GET /metrics`：Prometheus 指标抓取（含自动采集的运行时 / 进程指标，见 [监控](../operations/monitoring.md)）
- `GET /watchdog`：看门狗（进程内周期巡检）的规则状态快照与告警丢弃计数（注册规则与告警出口见 [监控](../operations/monitoring.md)）
- `GET /log/level`：查看当前日志级别
- `PUT /log/level`：热调整日志级别，body `{"level":"debug"}` 或 `?level=debug`
- `/deadletter/dlq`、`/deadletter/dlq/retry`、`/deadletter/dlq/remove`、`/deadletter/pending`：
  跨服死信队列人工介入（列出 / 重投 / 删除 / 在途查询）
- `admin.pprof: true` 时额外注册 `/debug/pprof/*`

> **鉴权**：配了 `admin.token` 后，`/admin/*`、`/deadletter`、`/log/level`、`/debug/pprof`
> 一律要求请求带同一令牌（`X-Admin-Token` 或 `Authorization: Bearer`）；
> `/ping`、`/routes`、`/metrics` 不设门禁（探针与指标抓取）。

> ⚠️ admin 端口上**没有** `/health` 与 `/ready`。存活性/就绪性探针由**逻辑服**提供：
> `GET /healthz` 与 `GET /ready`（`internal/transport/event/logic.go`），端口是 `logic.http_listen`（默认 `127.0.0.1:8012`）。

## 配置加载

### 代码中加载配置

```go
func main() {
    if err := app.Run("configs/all"); err != nil {
        logger.Fatal("启动失败", logger.Field("err", err))
    }
}
```

### 环境变量覆盖

> ⚠️ **引擎当前不支持用环境变量覆盖配置。**
> 配置加载器（`internal/foundation/config/loader.go`）使用 `viper.New()` 且**未**调用
> `AutomaticEnv` / `SetEnvPrefix` / `BindEnv`，因此不存在 `CLOVER_*` 之类的环境变量注入机制。
> 需要按环境区分时，请使用不同的配置文件（如 `configs/dev/server.yaml`、`configs/prod/server.yaml`），
> 或用 `app.Run(<配置路径>)` / `-config` 指定路径。

## 最佳实践

### 开发环境配置

```yaml
server_type: "all"
gateway:
  listen_ws: "127.0.0.1:8001"
  listen_tcp: "127.0.0.1:8002"
  listen_udp: "127.0.0.1:8003"
logic:
  listen_addr: "127.0.0.1:8011"
  http_listen: "127.0.0.1:8012"
auth:
  listen: "127.0.0.1:8051"
  jwt_secret: "dev-only-change-me"     # 生产务必换强随机串
  # 账号服默认要求 TLS：本机联调用 mkcert 自签证书（根 CA 已入系统信任库）
  tls:
    cert_file: "certs/server.pem"
    key_file: "certs/server-key.pem"
  verify_addr: "https://127.0.0.1:8051" # 必填：缺失启动即 panic（明文部署才写 http://）
data:
  tier: "TierRedisMySQL"  # ⚠️ 不要写 TierMemory：该值写在 yaml 里会被 loadConfig 拒绝
  auto_create_table: true
  redis:
    addr: "127.0.0.1:6379"
  mysql:
    host: "127.0.0.1"
    port: 3306
    user: "root"
    db_name: "clover"
log:
  level: "debug"
  format: "console"
  stdout: true
```

> `tier` 合法值：`TierRedis`（纯 Redis）/ `TierRedisMySQL`（Redis 缓存 + MySQL）/ `TierSnapshot`（内存 + MySQL 快照）。
> 纯内存档位**只允许在代码里构造**，配置文件中写 `TierMemory` 会被拒绝。

### 生产环境配置

```yaml
server_type: "all"
gateway:
  listen_ws: "0.0.0.0:8001"
  listen_tcp: "0.0.0.0:8002"
  listen_udp: "0.0.0.0:8003"
  tls_cert: "certs/server.pem"
  tls_key: "certs/server-key.pem"     # 必须与 tls_cert 成对，只配一个启动即失败
logic:
  listen_addr: "0.0.0.0:8011"
  http_listen: "0.0.0.0:8012"
auth:
  listen: "0.0.0.0:8051"                        # 对外暴露 ⇒ 必须配证书（否则启动被拒）
  jwt_secret: "<强随机串，从密钥管理服务注入>"   # 必填
  token_ttl: 2h
  tls:                                          # ★ 账号服证书对；生产请用公共 CA 证书
    cert_file: "certs/auth.pem"
    key_file: "certs/auth-key.pem"
  verify_addr: "https://127.0.0.1:8051"         # 与逻辑服同机填回环；跨机填内网地址
  # verify_ca_file: "certs/ca.pem"              # 账号服用自签 / 内网 CA 时填它（别用 skip-verify）
# 运维控制面：默认只绑回环；跨机运维才改成内网地址（此时 token 必填，否则启动被拒）
admin:
  listen_addr: "127.0.0.1:8041"
  token: ""                                     # 非回环 listen_addr 时必填
data:
  tier: "TierRedisMySQL"
  auto_create_table: false  # 生产环境建议手动管理表结构
  redis:
    addr: "redis-server:6379"
    pass: "your_redis_password"
  mysql:
    host: "mysql-server"
    port: 3306
    user: "clover_user"
    pass: "your_mysql_password"
    db_name: "clover_production"
log:
  level: "info"
  format: "json"
  dir: "/var/log/clover"
  stdout: false
master_health:
  heartbeat_interval: 3s
  suspect_timeout: 9s
  dead_timeout: 15s
master_session_token:
  backend: "redis"                  # 生产建议 redis：master 重启后玩家 token 不失效
  ttl: 24h
```

## 配置迁移说明

引擎的安全默认值已收紧为「**不安全配置直接拒绝启动**」（fail-fast；不静默降级、不静默改写地址）。
老配置升级后若启动失败，多半是下面三处之一 —— 逐条改即可：

| 面 | 新默认（安全形态） | 违反时 | 对外暴露 / 明文的口 |
| --- | --- | --- | --- |
| admin 控制面 `admin.listen_addr` | 只绑回环 `127.0.0.1:8041` | 非回环 + `admin.token` 为空 ⇒ **拒绝启动**（`AdminConfig.Normalize`，`pkg/app/types`） | 跨机运维：内网地址 **且** 配 `token` 两个一起配（该端口挂着 `/admin/shutdown`、`/admin/gateway/upstream`） |
| master 内部 RPC `master_listen_addr` | 只绑回环 `127.0.0.1:8021` | 非回环 + `master_token` 为空 ⇒ **拒绝启动**（`internal/app/master_server.go` 的 `validateMasterListen`） | 跨机部署：内网地址 **且** 配 `master_token`（game 侧填同一个值；该通道上挂着无身份校验的 session/player/rank 写接口） |
| 账号服 HTTP `auth.listen` | **默认要求 TLS**：`auth.tls.cert_file` + `auth.tls.key_file` 成对 | 没有证书对且 `auth.insecure_plaintext` 不为 `true` ⇒ **拒绝启动**（`AuthConfig.ValidateAuthServer`） | 本机 / 完全隔离内网联调：显式 `insecure_plaintext: true`（启动打一条 Warn），此时 `verify_addr` 才可写 `http://` |

- 三处都是**构造期硬错误**，原因写在启动错误里（master / admin 侧还有一条带处置建议的日志），
  **不会静默回落**——静默回落正是「运维以为已按配置生效、其实没生效」的事故来源。
- 证书**只配一半**（只有 `cert_file` 或只有 `key_file`）同样报错，不回落明文。
- 相关键的完整说明见上文「Admin 运维控制面配置」「Master 协调服配置」与
  [账号服（auth 服）](../security/auth-server.md)。

### 旧 → 新 对照

**① admin 控制面**

```yaml
# 旧（非回环 + 无 token ⇒ 启动被拒）
admin:
  listen_addr: "0.0.0.0:8041"

# 新（二选一）
admin:
  listen_addr: "127.0.0.1:8041"     # A. 只本机运维：绑回环，不必配 token
# 或
admin:
  listen_addr: "10.0.0.5:8041"      # B. 跨机运维：内网地址与 token 必须一起配
  token: "<强随机串，从密钥管理服务注入>"
```

**② master 内部 RPC**

```yaml
# 旧（非回环 + 无 master_token ⇒ 启动被拒）
master_listen_addr: "0.0.0.0:8021"

# 新（二选一）
master_listen_addr: "127.0.0.1:8021"   # A. 单机：绑回环
# 或
master_listen_addr: "10.0.0.5:8021"    # B. 跨机：内网地址 + 共享密钥
master_token: "<强随机串>"              #    game 侧必须填同一个值
```

**③ 账号服链路**

```yaml
# 旧（未配证书且未显式放行明文 ⇒ 启动被拒）
auth:
  listen: "127.0.0.1:8051"
  verify_addr: "http://127.0.0.1:8051"

# 新（二选一；A 是默认安全形态）
auth:
  listen: "127.0.0.1:8051"
  tls:                                    # A. 配证书 ⇒ 以 HTTPS 提供服务
    cert_file: "certs/server.pem"         #    本地用 clover-server-tools/mkcert 生成
    key_file: "certs/server-key.pem"      #    （根 CA 已入系统信任库，客户端只走系统信任链）
  verify_addr: "https://127.0.0.1:8051"   #    ★ 协议头同步改成 https://
# 或
auth:
  listen: "127.0.0.1:8051"
  insecure_plaintext: true                # B. 本机联调：显式放行明文（启动打 Warn）
  verify_addr: "http://127.0.0.1:8051"

# 账号服跨机且用自签 / 内网 CA 时，游戏服侧补 CA（**不要**用 skip-verify 绕）：
auth:
  verify_addr: "https://10.0.0.6:8051"
  verify_ca_file: "certs/ca.pem"
```

> 客户端与工具侧的 `auth_addr`（`config.json` 的 `server.auth_addr`、robot / msg-client 的
> `auth_addr`）也要跟着改 `https://`：账号服默认只提供 HTTPS，写成 `http://` 会直接连不上。

## 故障排除

### 常见问题

1. **端口冲突**
   - 错误信息：`bind: address already in use`
   - 解决方案：检查端口占用，修改配置文件中的端口号

2. **配置文件找不到**
   - 错误信息：`config file not found`
   - 解决方案：检查配置文件路径是否正确，确保使用绝对路径或相对路径正确

3. **数据库连接失败**
   - 错误信息：`dial tcp: connect: connection refused`
   - 解决方案：检查数据库服务是否启动，配置信息是否正确

4. **NATS 连接失败**
   - 错误信息：`nats: no servers available`
   - 解决方案：检查 NATS 服务是否启动，配置的地址是否正确

### 调试技巧

1. **启用详细日志**
   ```yaml
   log:
     level: "debug"
     format: "console"
     stdout: true
   ```

2. **检查配置加载**
   ```go
   logger.Infof("Loaded config: %+v", config)
   ```

3. **使用 Admin 接口**
   ```bash
   # admin 自身存活 + 已注册路由列表（注意：admin 端口上没有 /health、/ready）
   curl http://127.0.0.1:8041/ping

   # 查看当前日志级别（配了 admin.token 时需加 -H "X-Admin-Token: <token>"，否则 401）
   curl http://127.0.0.1:8041/log/level

   # 调整日志级别
   curl -X PUT http://127.0.0.1:8041/log/level -d '{"level":"debug"}'

   # 存活性 / 就绪性探针在【逻辑服】端口（logic.http_listen，默认 8012）
   curl http://127.0.0.1:8012/healthz
   curl http://127.0.0.1:8012/ready
   ```

## 完整键表（上文未展开的键）

以下键此前未在本文档展开，生产部署（哨兵 Redis / 连接池 / NATS JetStream 与 TLS / 网关排队）会用到。
**引擎默认值指"字段留空时引擎回落到的值"**，与「demo 示例里填的值」不是一回事。

### `gateway`（连接层限流 / 排队 / TLS）

| 键 | 说明 | 引擎默认 |
| --- | --- | --- |
| `max_conns` | 连接总数上限（活跃会话数） | `0` 不限制 |
| `max_conns_per_sec` | 每秒**新建连接数**上限（连接建立限流） | `0` 不限制 |
| `queue_cap` | 等候队列容量；`>0` 启用排队（限流/满载时缓冲而非直接拒，并向客户端下发排队位置 `EMsgQueuePosition`） | `0` 不排队 |
| `queue_release_per_sec` | 排队每秒放行数 | `0` 尽快放行 |
| `queue_timeout` | 排队最长时间（超时关闭连接） | `0` 不限时 |
| `tcp_tls_disabled` | `true`=TCP 接入**不加密**（显式保留明文入口，启动会告警）；默认 `false` 时 TCP 也走 TLS | `false` 跟随 `tls_cert` |
| `wt_cert` / `wt_key` | WebTransport 专用证书 / 私钥 | 空=自动生成 |
| `wt_pin` | WebTransport 证书固定 | 空 |
| `auth_disabled` | 关闭登录门禁（**仅本地调试**） | `false`（零值即开启门禁，fail-safe） |
| `auth_exempt_msg_ids` | 免登录消息号白名单 | 空=用内置 `EMsgLogin`/`EMsgResumeSession`；**配置即完全覆盖，非追加** |

`tls_cert` 与 `tls_key` **必须成对**，只配一个启动即失败。

### `data`

| 键 | 说明 | 引擎默认 |
| --- | --- | --- |
| `shard_count` | 内存储存 / 脏标记分片数（向上取 2 的幂） | `64` |
| `flush_interval` | 周期落库间隔；`<=0` 只在进程 Close 时终落；内存模式忽略 | `30s` |
| `max_memory` | 最大驻留条目数；`>0` 启用 LRU 淘汰（`TierSnapshot` 淘汰前先落库） | `0` 不限 |

### `data.redis`（完整）

`mode`（`standalone`/`cluster`/`sentinel`，空则按 `master_name`/`addrs` 自动推断）、`addr`（单实例，也可逗号分隔多节点）、
`addrs`（cluster 各节点 / sentinel 哨兵列表，**优先于 `addr`**）、`master_name`（非空即视为哨兵）、
`user`（Redis 6+ ACL）、`pass`、`sentinel_pass`、`db`（cluster 忽略，默认 `0`）、
`pool_size`（默认 `20`）、`min_idle_conns`（默认 `5`）、`max_retries`（默认 `3`）、
`dial_timeout`（默认 `5s`）、`read_timeout`（默认 `3s`）、`write_timeout`（默认 `3s`）。

> `TierRedisMySQL` / `TierRedis` / `TierSnapshot` 下 `data.redis` 为必填，缺失启动失败。

### `data.mysql`（完整）

**必填**：`host` / `user` / `db_name`（`validate:"required"`，缺失启动失败）。
其余：`pass`、`charset`（默认 `utf8mb4`）、`parse_time`（解析 DATETIME/DATE 为 `time.Time`）、
`loc`（时区，默认 `Local`）、`auto_create`（启动自动 `CREATE DATABASE IF NOT EXISTS`，仅开发建议开）、
`port`（默认 `3306`）、`max_open_conns`（默认 `20`）、`max_idle_conns`（默认 `10`，且自动收敛到 `<= max_open_conns`）、
`conn_max_lifetime`（默认 `1h`）、`conn_max_idle_time`（默认 `30m`）、`dial_timeout`（默认 `5s`）、
`read_timeout`（默认 `3s`）、`write_timeout`（默认 `3s`）。

> `server_type: log` / `all` 的业务日志落盘**只支持 MySQL**，缺 `data.mysql` 启动即失败。

### `nats`（完整）

`addr`（多地址逗号分隔）、`user`/`pass`（空=匿名）、`client_name`（日志区分实例）、
`max_reconnect`（默认 `-1` 无限）、`reconnect_delay`（默认 `1s`）、`dial_timeout`（默认 `2s`）、
`msg_timeout`（同步 Request 应答超时，默认 `500ms`）。

| 子键 | 说明 | 默认 |
| --- | --- | --- |
| `jetstream.enable` | 游戏必须开启持久化，防消息丢失（需显式开启） | `false` |

> `jetstream` 目前**只有 `enable` 一个字段**：`storage_type` / `max_msg_age` 已从 `JetStreamConfig` 移除
> （见 `internal/transport/nats/config.go:34`），配了也不生效。
| `tls.cert_file` / `tls.key_file` / `tls.ca_file` | 客户端证书 / 私钥 / 验证服务端的 CA | 空=不启用 TLS |

### 其余顶层 / 小组

| 键 | 说明 |
| --- | --- |
| `log.service` | 服务名（`dir` 模式作为文件名后缀 `{dir}/{YYYY-MM-DD}-{service}.log`） |
| `log.env` | 运行环境：`dev` / `test` / `prod` |
| `log_listen_addr` / `log_http_listen_addr` / `log_addr` | log 服 TCP 监听 / HTTP 控制面 / game 连接地址（解析顺序见「服务发现」小节） |
| `log_backend` | 日志**落盘后端**名；空 = 内置 `mysql`。填业务注册的名字可换成自有后端，见「自定义日志落盘后端」 |
| `log_backend_config` | 自定义后端的参数（原始子节点，引擎不解释、原样交给后端工厂） |
| `misc.timezone` | 时区（如 `Asia/Shanghai`）；空=系统本地时区 |
| `node_id` | 本节点数字标识（跨机对象迁移的路由键）；未配 = 不启用，见「跨机对象迁移（MMO 切场景）」 |
| `tags` | 顶层标签（多环境/多集群标记用） |
| `master_health.*` | 心跳 / 疑似超时 / 死亡超时 / 探测间隔，见生产示例 |
| `master_session_token.*` | `backend`（`memory`/`redis`）/ `ttl` / `key_prefix` |
| `reliable.*` | 跨节点可靠投递（`enabled`/`ack_timeout`/`max_attempts`/退避参数/`dedup_*`/`dlq_capacity` 等 14 键） |

## 相关文档

- [快速开始](../getting-started.md)
- [网络拓扑](../concepts/network-topology.md)
- [应用游戏架构](../concepts/app-game.md)
- [数据持久化](persistence.md)
- [错误处理](error-handling.md)