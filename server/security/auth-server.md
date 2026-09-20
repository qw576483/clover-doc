# 账号服（auth 服）

账号 / 密码的校验与存储**不该长在游戏服里**。本引擎把账号体系拆成一个可独立部署的
**账号服**（`server_type: auth`），**对客户端只暴露 HTTP**；游戏服退化为「只认 token」。
（另有一条**可选的消息通道** `auth.rpc_listen`，供 game 侧 `Game.CallAuth` 发业务消息——
它不承载登录校验，登录固定走 HTTP `/auth/verify`。）

引擎**只有这一种登录模式**：没有内置账号表，也没有本地验签——游戏服每次登录都必须
调账号服的 `/auth/verify` 换取 `owner`。账号服因此是登录链路的**必经依赖**。

## 为什么单独拆一个服务

| 维度 | 放在游戏服 | 独立账号服 |
| --- | --- | --- |
| 扩容 | 跟游戏服一起扩（登录高峰才需要，但游戏服很贵） | 独立扩容，登录是低频请求-响应 |
| 安全面 | 账号表与玩法同一进程，一破全破 | 账号表不出账号服 |
| 外部交互 | 渠道 SDK 服务端校验、运营后台都要挤进长连接进程 | 天然是 HTTP 世界，直接对接 |
| 变更频率 | 改登录流程要重启游戏服 | 独立发版，游戏服不动 |

## 唯一登录链路

登录固定两步，外加游戏服向账号服的一次校验：

```text
① 客户端  ──HTTP──▶  账号服    /auth/login  {account, password} ──▶ JWT
② 客户端  ──长连接─▶  游戏网关  EMsgLogin{token}
③ 游戏服  ──HTTP──▶  账号服    /auth/verify {token} ──▶ owner（网关据此绑定会话）
```

- 游戏服**不碰账号表、不存密码、不持有签名密钥**：`jwt_secret` 只配在账号服。
- ② 走的是**同一条游戏长连接**，只是请求体从 `account/password` 换成 `token`
  （`ELoginRequest` 的 `token` 字段，JSON 键为小写 `token`）。
- ③ 由引擎唯一的内置实现 `RemoteAuthenticator`
  （`internal/domain/auth/client/client.go`）发起：它把客户端带来的 token
  原样递给账号服、把 `owner` 拿回来，自己完全不碰账号表。

为什么不合并在长连接里：登录是**低频请求-响应**，而账号服天然属于 HTTP 世界
（要跟渠道 SDK 服务端、运营后台打交道）。两者挤在一条常驻通道上没有任何好处。

> **账号服是登录链路的必经依赖**：它不可达时无人能登录，且**不会静默放行**。
> 拿到的取舍是「封号即时生效」与「账号表不出账号服」。

## 配置

`auth:` 段**没有 `mode` 字段**——登录模式只有一种。同一个结构在两种角色下各取所需字段：

```yaml
auth:
  # —— 账号服角色（server_type = auth，或 all 内嵌）：listen / jwt_secret 必填 ——
  listen: "127.0.0.1:8051"             # 账号服 HTTPS 监听地址
  jwt_secret: "dev-only-change-me"     # HS256 签名密钥；生产务必用强随机串
  token_ttl: 2h                        # 签发有效期；<=0 用内置默认 2h
  issuer: "clover-auth"                # 签发者（iss 声明）；空=内置默认 "clover-auth"
  tls:                                 # ★ 默认要求 TLS：证书对（只配一个启动即失败）
    cert_file: "certs/server.pem"
    key_file: "certs/server-key.pem"
  # 仅本机 / 完全隔离内网联调才显式放行明文（启动打 Warn）；生产不要用
  # insecure_plaintext: true

  # —— 游戏服角色（server_type = game / gateway / all）：verify_addr 必填 ——
  verify_addr: "https://127.0.0.1:8051" # 游戏服校验登录凭证的账号服地址（明文部署才写 http://）
  verify_timeout: 3s                   # /auth/verify 单次调用超时；<=0 用内置默认 3s
  # verify_ca_file: "certs/ca.pem"     # 账号服用自签 / 内网 CA 时填它（不要用 skip-verify 绕）
```

| 配置项 | 生效角色 | 必填 | 说明 |
| --- | --- | --- | --- |
| `listen` | 账号服（`auth` / `all`） | 是 | 账号服 HTTP 监听地址 |
| `jwt_secret` | 账号服（`auth` / `all`） | 是 | HS256 签名密钥，账号服签发与验签都用它 |
| `token_ttl` | 账号服 | 否 | 签发有效期；`<=0` 用默认 `2h` |
| `issuer` | 账号服 | 否 | JWT 签发者；空=默认 `clover-auth` |
| `verify_addr` | 游戏服（`game` / `gateway` / `all`） | 是 | 游戏服调 `/auth/verify` 的账号服地址（账号服默认 HTTPS，故通常 `https://`） |
| `verify_timeout` | 游戏服 | 否 | `/auth/verify` 单次超时；`<=0` 用默认 `3s` |
| `tls.cert_file` / `tls.key_file` | 账号服 | **是（二者取其一）** | 证书对；配了就以 HTTPS 提供服务 |
| `insecure_plaintext` | 账号服 | **是（二者取其一）** | 显式放行明文（默认 `false`，启动打 Warn），仅限本机 / 隔离内网 |
| `verify_ca_file` / `verify_insecure_skip_verify` | 游戏服 | 否 | 校验账号服证书用的 CA / 跳过校验（后者会让 TLS 只防嗅探、不防中间人） |

- 游戏服缺 `verify_addr` → **启动即 panic**（配置错误，不静默降级）。
- 账号服缺 `listen` / `jwt_secret` → 启动报错返回。
- ⚠️ **账号服默认要求 TLS**：既不配 `tls.cert_file` + `tls.key_file`，又不显式
  `insecure_plaintext: true` ⇒ **拒绝启动**（`AuthConfig.ValidateAuthServer`）。
  口令与 JWT 不能明文上线；证书只配一半同样报错，不回落明文。
- **`server_type: all` 包含账号服**：启动顺序为 `master → log → auth → logic → gateway`；
  `server_type: auth` 仍可独立部署。
- 配置文件加载是 viper **非严格**模式，老配置里残留的 `mode:` 会被忽略，不会报错。

## HTTP 接口

账号服对客户端**只开 HTTP(S)**（默认 HTTPS，见 `auth.tls`），不接游戏长连接——game↔auth 的登录校验是 HTTP
请求-响应，不是长连接。另可经 `auth.rpc_listen` 开一条消息通道给业务使用
（`Game.CallAuth` ↔ `AuthGame.OnMsg`），与 master / log 对称。全部 JSON：

| 方法与路径 | 请求体 | 响应体 | 状态码 |
| --- | --- | --- | --- |
| `POST /auth/signup` | `{account, password}` | `{success, owner, token, exp, err}` | `200` / `409` 账号已存在 / `400` 参数错 |
| `POST /auth/login` | `{account, password}` | `{success, owner, token, exp, err}` | `200` / `401` 账号或密码错误 / `429` 尝试次数过多 |
| `POST /auth/verify` | `{token}` | `{valid, owner, exp, err}` | **恒 `200`**（无效时 `valid=false`，不是 5xx） |
| `GET /auth/health` | — | `{ok, service, time}` | `200` |

- 注册成功**即签发 token**（注册即登录），客户端无需再调一次 login。
- `/auth/verify` **已从「运维排查用」升级为游戏服的正式依赖接口**：每次登录都会调它。
- `/auth/verify` 把「token 无效」（过期 / 签名不符 / 伪造）表达为 `200` + `valid=false`，
  便于游戏服统一解析；`5xx` 只留给账号服自身故障。
- 业务失败用响应体里的 `success=false` + `err` 表达；链路失败才是 HTTP 5xx / 连不上。
  客户端据此区分「密码不对」和「账号服没起来」。
- 请求体上限 4 KiB（只有两个短字段，超长一律视为异常）。

## 撞库防护

权威防护点在账号服 `/auth/login`（凭证校验发生在这里），按账号计失败次数：

- **连续 10 次失败 → 锁定 5 分钟**，锁定期内返回 **HTTP `429`**
  「尝试次数过多，请稍后再试」；锁定期内继续尝试**不延长**锁定。
- 防护状态在账号服**进程内**（`internal/domain/auth/state/guard.go` 的 `loginGuard`）：
  账号服多实例横扩时**各实例各算各的**；需要全局一致时把该实现换成共享后端即可。
- **游戏服不做任何失败计数**：它只转发 token、拿不到账号名。按空串计数会让所有玩家
  共用同一个计数器（10 次失败即全员被锁），比不做防护更糟——这是「防护点在账号服」的根本原因。
- **账号服不可达（`ErrAuthUnavailable`）不计入失败次数**——服务端抖动不是玩家在撞库，
  不能把玩家锁死 5 分钟。

## 错误文案（客户端可见）

| 情况 | 回包 `err` |
| --- | --- |
| 凭证无效 | `authentication failed` |
| 账号服不可达（连不上 / 超时） | `账号服务不可用，请稍后重试` |
| 没带 token | `token 不能为空`（参数类，原样透传） |

> 服务端日志里同时会打出可定位信息：账号服不可达时是
> `auth: verify unavailable (url=…)`，凭证不通过时是 `auth: verify rejected token`。

## 还能接任意登录方式吗（微信 / QQ / Steam）

**能，扩展点在账号服，不在游戏服。** 游戏服侧没有任何登录注入点——登录链路唯一
（`RemoteAuthenticator` → `/auth/verify`）。这是刻意的：账号体系的扩展能力该长在账号体系里，
否则「账号服必须在线」这条不变量就会出现例外。

引擎已把整条渠道登录链路做好，业务只需实现**一个**接口：

```go
// main.go（须在 app.Run 之前）
app.RegisterChannelVerifier(wechatVerifier{appID: "...", secret: "..."})
```

```go
type wechatVerifier struct{ appID, secret string }

// Verify 只回答一个问题：这张票据对应渠道里的谁。
func (v wechatVerifier) Verify(ctx context.Context, channel, ticket string) (string, error) {
    // 调渠道 SDK / HTTP 换 openid（各渠道协议不同，这正是必须由业务实现的部分）
    return openid, nil
}
```

随后账号服即可支持：

```bash
POST /auth/login  {"channel":"wechat","ticket":"<客户端拿到的 code>"}
```

| 环节 | 谁做 |
| --- | --- |
| 票据 → 渠道账号（openid） | **业务**（`ChannelVerifier`；各渠道协议差异大，引擎无法内置） |
| 渠道账号 → 主账号 | 引擎（查 `account_channel` 反查） |
| 首次登录：建号 + 绑定（注册即登录） | 引擎（账号名 = `{channel}_{channelAccount}_{短哈希}`，见 `internal/domain/auth/state/state.go` 的 `channelAccountName`） |
| 签发 JWT | 引擎 |

**已定的行为**（都是刻意的，改前请先确认影响）：

- 未注册校验器时 `/auth/login {channel,...}` 返回 **501** +「账号服未接入该渠道」——
  与「票据错误(401)」明确区分，否则业务会去查渠道 SDK，而问题其实在服务端没接渠道。
- 校验器返回**空**渠道账号 → **500** 且**不建号**；票据校验失败 → **401**，同样不留账号。
- 渠道账号没有可用密码：首次建号用随机占位密码，密码登录路径事实上无法命中它。
- 渠道登录**不做**撞库防护：票据由渠道签发、无法枚举。
- 并发首登（同一用户两个请求同时到达）靠 `account_channel` 唯一键收敛，不会建出两个号。
- 渠道表依赖 MySQL：注册了校验器却没渠道表时**启动即失败**，不留到运行期 500。

> 注册函数位于 **`pkg/app`**（业务可导入）。引擎曾提供 `pkg/transport/auth` +
> `app.RegisterAuthenticator`，但注册函数定义在 `internal/app`，业务模块受 Go internal
> 规则限制根本调不到——属「只能实现、无法挂载」的半成品，已删除。渠道登录刻意避开这个坑。
>
> 实现见 `internal/domain/auth/state/channel.go` 与 `state.go`（链路）、`pkg/app/channel.go`（注册入口）。

## 支付回调 / 订单归谁（已定：账号服）

**订单归属账号服**，与渠道登录同构：公网 HTTP 只有账号服有（`/auth/*` 前缀放行），
渠道的异步支付回调天然落在这一层；账号是全局身份，充值记录也应挂在账号侧。

已定的形态：

```text
① 客户端  ──长连接─▶  游戏服   请求下单
② 游戏服  ──CallAuth──▶ 账号服  建单（带 playerID / serverID）  ← 已有通道
③ 账号服  建单 → orderID            （orders 表 + 三段状态机）
④ 账号服  ──CallAuth 应答──▶ 游戏服  orderID
⑤ 游戏服  ──长连接─▶  客户端    orderID
⑥ 客户端  拉起渠道支付（orderID = 商户订单号）
⑦ 渠道    ──HTTP──▶  账号服    /auth/pay/notify（验签 → MarkPaid → MarkDone）
⑧ 游戏服  ──CallAuth──▶ 账号服  查「这单付了吗」（客户端回报触发；另有定时兜底）← 已有通道
⑨ 游戏服  SendQueueEventToPlayer(playerID, "order.paid") → 发道具
```

| 环节 | 谁做 |
| --- | --- |
| 渠道回调验签 / 换取渠道订单状态 | **业务**（各渠道协议差异大，引擎无法内置） |
| 建单 / 状态流转（`orders` 表） | 引擎（`pkg/domain/data/order` 的 `Store`） |
| 支付回调 HTTP 入口 | 引擎（账号服 `AuthGame.OnHTTP`，业务挂 `/auth/pay/notify`） |
| 发货（加道具 / 货币） | **游戏服**（在线角色数据只在 owner 节点内存） |

**当前状态**：

1. ✅ 账号服**已持有订单存储**：`AuthGame.OrderStore()`（`pkg/app` 对业务开放），
   回调里可直接建单 / 流转状态（`Create` / `MarkPaid` / `MarkDone`）。
2. ✅ 支付结果**不新增回推通道**：由 game 侧收到「支付完成」→ 既有 `CallAuth` 查单 →
   game 自己 `SendQueueEventToPlayer(c, playerID, "order.paid", …)` 投给玩家（同一玩家
   FIFO，天然只在 owner 节点执行）。走的是引擎**已有的按玩家寻址事件通道**，**不需要**
   给账号服接 NATS / master（那会扩大账号服的部署依赖）；回调丢失由 game 侧
   `Timer.Every` 轮询兜底。

**部署前提**：本方案建立在**单库部署**上——auth 与 game 共用同一份 `data.mysql`，
`orders` 表同库可达。若要按区服分库，则需另做跨库 / 跨进程设计：`server_id` 是玩家侧
概念、**不是分库标识**（逻辑服配置里不含它），且 `player` 表的 `uk_player_id` 要求
`player_id` 全局唯一。

## 客户端两步登录

见 [账号服登录（CloverAuth）](../../client/development/auth.md)。要点：

- 客户端先 HTTP 调账号服换 JWT，再经游戏长连接发 `EMsgLogin{token}`。
- `CloverAuth.AuthAddr` 是**必填配置**：为空即未配置，调用登录 / 注册会抛异常。

## 部署

```yaml
# ① 账号服（独立进程，对外只暴露 HTTP(S)；需 MySQL 账号表）
server_type: auth
auth:
  listen: "127.0.0.1:8051"
  jwt_secret: "<强随机串>"
  token_ttl: 2h
  issuer: "clover-auth"
  tls:                                 # ★ 默认要求 TLS；本机联调用 mkcert 自签证书
    cert_file: "certs/server.pem"
    key_file: "certs/server-key.pem"
  # 不配证书时的唯一出口（本机 / 隔离内网联调）：insecure_plaintext: true

# ② 游戏服（game / gateway）
server_type: game
auth:
  verify_addr: "https://127.0.0.1:8051"   # 账号服默认 HTTPS，协议头别漏改
  verify_timeout: 3s
```

- 单进程全功能（含账号服）：`server_type: all`，把上面两组的字段都写上，
  且 `listen` 与 `verify_addr` 指向同一地址（否则游戏服会连不上自己内嵌的账号服）。
- 账号服跨机 + 自签 / 内网 CA 时，游戏服侧补 `verify_ca_file: "certs/ca.pem"`。
- 账号表依赖 MySQL（`data.tier` 为 `redis_mysql` / `snapshot`），建库建表由引擎自动完成。

## 排查清单

| 现象 | 原因 |
| --- | --- |
| 启动报 `auth.listen is required when server_type=auth` | 账号服角色（`auth` / `all`）没配监听地址 |
| 启动报 `auth.jwt_secret is required` | 账号服角色（`auth` / `all`）没配签名密钥 |
| 启动 panic `auth.verify_addr is required` | 游戏服角色（`game` / `gateway` / `all`）没配账号服地址 |
| 启动报 `auth: 账号服 HTTP 默认要求 TLS：请配置 auth.tls.cert_file / auth.tls.key_file` | 账号服角色没配证书对，也没显式 `auth.insecure_plaintext: true`（**默认拒绝启动**） |
| 启动报 `auth: TLS 配置不完整：tls.cert_file 与 tls.key_file 必须成对配置` | 证书只配了一半（不回落明文） |
| 客户端 / 游戏服连账号服报 TLS 校验失败 | `verify_addr` 用 `https://` 而账号服是自签证书：补 `auth.verify_ca_file`（不要用 skip-verify 绕） |
| 登录一直报「账号服务不可用」而账号服日志正常 | `verify_addr` 协议头写错（账号服默认 HTTPS，写成 `http://` 会连不上） |
| 启动报 `account store unavailable` | `server_type=auth` 但 `data.tier` 不是 MySQL 系 |
| 登录报「账号服务不可用，请稍后重试」 | `verify_addr` 填错 / 账号服没起 / 网络不通（服务端日志有 `auth: verify unavailable`） |
| 登录报「尝试次数过多，请稍后再试」（HTTP 429） | 触发账号服撞库门禁（连续 10 次失败锁 5 分钟） |
| 登录报 `authentication failed` | token 无效（过期 / 伪造），让客户端重新走 `/auth/login` |
| 客户端报「HTTP 模块未初始化」 | 没调 `CloverNet.Init`（HTTP 随它一并挂接） |
| 客户端报「账号服无响应」 | `auth_addr` 填错 / 账号服未启动 |
