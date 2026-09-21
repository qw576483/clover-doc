## 这篇文档讲什么？

Clover Engine 从源码编译为生产二进制，并完成部署上线的完整流程。本文档适用于运维人员和开发者将 Clover 部署到生产环境。

## 前置条件

- 已安装 Go 1.25+ 开发环境
- 了解 Clover 的架构和组件
- 具备基本的 Linux/Windows 服务器操作能力
- 已准备生产环境所需的基础设施（MySQL、etcd、NATS、Redis）

## 编译

```bash 编译命令
# 逻辑服（game）—— 入口在你的服务端工程根目录 main.go
cd your-server
go build -o bin/game.exe .

# 网关（gateway）—— 同进程一体启动（server_type: "all" 时）
# Clover 默认网关+逻辑服同进程，无需单独编译 gateway
```

> **注意：** 引擎与业务工程都**没有** `cmd/` 目录；网关与逻辑服由 `server_type` 决定在同进程还是分进程，
> 入口始终是工程根目录的 `main.go`（`app.Run(*cfgPath)`）。

## 依赖服务

部署前需就绪以下基础设施：

| 服务 | 用途 | 生产建议 |
|------|------|----------|
| MySQL | 持久化数据 | 主从 + 定期备份 |
| etcd | 服务注册、分布式锁 | 3 节点集群 |
| NATS | 网关↔逻辑服路由、跨进程同步 | 3 节点集群 |
| Redis | 缓存、状态共享（可选） | 主从 + Sentinel |

## 配置文件

配置位于 `configs/<role>/*.yaml`，典型 `game` 配置：

```yaml game 配置示例
server_type: "game"
logic:
  listen_addr: "127.0.0.1:10001"
  http_listen: "127.0.0.1:10081"
auth:                          # 必填：每次登录都调账号服 /auth/verify（缺失启动即 panic）
  verify_addr: "https://127.0.0.1:8051"   # 账号服默认要求 TLS，故是 https
  verify_timeout: 3s

data:
  tier: "TierRedisMySQL"       # 也可写 "redis_mysql"（解析时忽略大小写与下划线）
  mysql:
    host: "127.0.0.1"
    port: 3306
    user: "user"
    pass: "pass"
    db_name: "clover"          # ★ 键名是 db_name，不是 db
  redis:
    addr: "127.0.0.1:6379"

etcd:
  endpoints:
    - "127.0.0.1:2379"

nats:
  addr: "127.0.0.1:4222"
```

`server_type` 取值为 `game` / `gateway` / `all` / `master` / `log` / `auth`。

**网关的 TLS（gateway 角色 / all 角色都要配）**：

```yaml
gateway:
  tls_cert: "certs/server.pem"    # 与 tls_key 必须成对，只配一个启动即失败
  tls_key: "certs/server-key.pem"
  tcp_tls_disabled: false         # 默认 false：TCP 口也走 TLS（客户端 GameConfig.UseTls 必须与之相反）
```

- 客户端只走**系统信任链**校验，引擎没有"跳过校验"的开关 → 生产用公共 CA 证书（Let's Encrypt 等），
  别把自签证书发给玩家；本地开发用 [`clover-server-tools/mkcert`](https://github.com/qw576483/clover-server-tools/blob/main/mkcert/README.md)（根 CA 已入信任库）。
- TCP/WS 的 TLS 下限是 **1.2**（兼容只到 1.2 的原生 `SslStream`），QUIC/WT 仍是 1.3。
- 显式设 `tcp_tls_disabled: true` 会保留明文 TCP 入口，启动日志会打一条告警——那是降级形态。

## 目录结构

```text 部署目录结构
/opt/clover/
├── bin/
│   ├── gateway
│   └── game
├── configs/
│   ├── gateway/config.yaml
│   └── game/config.yaml
├── logs/
└── tables/          # 策划 TSV 产物
```

## 启动顺序

```bash 启动命令
# 1. 启动依赖（MySQL → etcd → NATS → Redis）
# 2. 启动网关
./bin/gateway -config configs/gateway/config.yaml

# 3. 启动逻辑服（可启动多个）
./bin/game -config configs/game/config.yaml
```

> **警告：** 必须先启动 etcd 和 NATS，否则逻辑服注册会失败。

## 多逻辑服分区分服

- 每个 `game` 进程承载一个或多个场景/地图
- 网关根据消息中的 `server_id` 或目标 room/zone 路由到对应逻辑服
- **服务发现（etcd）**：每个实例启动时按 `clover/services/<角色>/<角色>-<主机>-<PID>` 注册自己的
  可调用地址（租约 + 自动续租，进程崩溃后 etcd 自动摘除，不留僵尸节点）；调用方列出前缀下
  全部实例并轮询选一个。角色前缀：`logic`（网关上游）、`auth`（账号服消息通道，`Game.CallAuth`）、
  `log`（日志服：同步 RPC `Game.CallLog` 与业务日志管道 `Game.AddLog` 共用）。注册时效由
  `etcd.register_ttl` 控制（默认 10s）。
- 网关在**启动时**从 `logic` 前缀解析出一个上游并固定使用（不随实例增删切换）；要按分区固定上游时
  直接配静态 `logic.listen_addr`。
- **静态地址与发现的优先级按角色不同**：
  - `logic`（网关上游）：**静态优先**——配了 `logic.listen_addr` 就直接用，不查 etcd；
  - `auth` / `log`（消息通道与日志管道）：**发现优先**——etcd 上有实例就轮询使用，列表为空才回退
    配置里的 `auth.rpc_addr` / `log_addr`。
  `etcd.endpoints` 为空则完全不启用发现，各角色退化为静态地址（单实例仍可运行）。

## 跨进程 MMO

| 步骤 | 行为 |
|------|------|
| 进程启动 | 在 etcd 注册，网关按玩家定位表路由 |
| 同机迁移 | `Transfer` 本地调用 |
| 异机迁移 | NATS 发指令 → 对端 `EnterOwnerType` → 本机 `Leave` |
| 事件投递 | `SendEventToPlayer`（单播）/ `SendEventToAll`（广播） |

不做 zone 跨节点调度，所有事件按玩家或全服粒度投递。

## 监控与日志

- 日志输出到**标准输出**（`Config.Stdout=true` 时写 `os.Stdout`；stderr 只用于日切失败这类兜底打印），由采集器收集 —— 采集配置按 stdout 接
- 逻辑服**内置** `/healthz`（存活）与 `/ready`（就绪），仅在业务未注册同名路由时自动响应（`internal/transport/event/logic.go:573`）
- admin 服务的探针是 `/ping` / `/routes` / `/metrics`（`internal/app/admin.go:106`），业务自定义探针经 `g.OnAdminHTTP` 注册
- 关键指标：连接数、消息 QPS、定时任务数、Store flush 延迟、etcd/NATS 连接状态

## 高可用建议

| 组件 | 策略 |
|------|------|
| 网关 | ≥2 实例 + L4 负载均衡（**不要求会话粘性**；裸 UDP 例外，见下） |
| 逻辑服 | 按功能/地图分区，避免单进程过载 |
| Master | **单点**：无内置多节点 / 故障转移，多开互不共享状态；靠重启快 + 玩家重连容忍 |
| MySQL | 主从 + 定时备份 |
| etcd / NATS | 3 节点集群 |
| 配置 | HTTP 控制面 `/reload` 热加载（需自行实现） |

### 网关多实例的负载均衡约束

客户端**静态配置网关地址、不走服务发现**，因此多网关必须由外部 LB 提供单一入口。约束如下：

- **可靠通道（TCP / WS / QUIC / WT）不要求会话粘性。** 重连落到任意网关都可行：`EMsgResumeSession`
  由逻辑服验 token 并回带 owner，网关据 owner 重绑（`gwcore/session.go`）；加密会话、上游连接、
  owner 绑定等连接级状态都随连接销毁而重建。副作用仅是重连被当作「首次连接」走一次 resume。
  （TLS 会话与会话通道加密密钥同样是**连接级**的，因此不影响本条约束。）
- **启用裸 UDP 时必须做源亲和。** 绑定令牌（`udpTokens`）与端点表（`udpEndpoints`）都是
  **网关进程本地**的：令牌只在签发它的进程内有效，换网关即被拒。因此必须把**同一玩家的 TCP 连接
  与其 UDP 包**汇聚到同一网关进程，两种做法二选一：
  ① LB 按**源 IP 一致性哈希**；② UDP 地址**静态指向固定网关**（客户端单独指定 UDP 目标）。
- **LB 用 L4 而非 L7。** 客户端与网关之间是长连接 + 私有二进制协议，L7 网关无法解析。
- **网关之间无需互通**，跨节点协作经 NATS。

## 回滚与灰度

```text 回滚策略
回滚：替换二进制 → 重启进程
数据迁移：版本号管理，启动时自动执行 migrations
灰度：按 server_id 或用户 ID 哈希分批次切换网关路由
```

## 常见问题

### 启动失败：etcd 连接超时

**症状**：`connection refused to etcd at 127.0.0.1:2379`

**原因**：etcd 服务未启动或配置错误

**解决**：
1. 确认 etcd 服务已启动：`etcdctl endpoint health`
2. 检查配置文件中的 etcd endpoints
3. 确认网络连通性

### 启动失败：NATS 连接失败

**症状**：`nats: connection closed`

**原因**：NATS 服务未启动或认证失败

**解决**：
1. 确认 NATS 服务已启动：`nats server check`
2. 检查 NATS 配置和认证信息
3. 确认端口未被占用

## 下一步

1. [Kubernetes 部署](kubernetes.md) —— K8s 部署详解
2. [扩缩容](scaling.md) —— 扩缩容策略
3. [监控与告警](monitoring.md) —— 监控体系建设
4. [备份与恢复](backup-recovery.md) —— 备份恢复策略

