
## 这篇文档讲什么？

Clover 引擎的认证流程、Token 设计、会话管理和权限控制机制。

## 认证流程

```text
客户端                    Gateway                          Game
  │                         │                              │
  │  1. 注册 / 登录请求      │                              │
  │ ───────────────────────> │  2. 转发（本连接尚未绑定）     │
  │                         │ ───────────────────────────> │  3. 校验 token（调账号服 /auth/verify 换 owner）
  │                         │                              │  4. 回 ELoginReply{owner,...}
  │                         │  5. 提取 owner 并绑定会话 ◀─── │
  │  6. 回 ELoginReply       │     idIndex["a:"+owner]       │
  │ <─────────────────────── │                              │
  │                         │                              │
  │  7. 后续业务消息          │                              │
  │    （不再携带 token）      │  8. 本连接已绑定 owner？      │
  │ ───────────────────────> │     未绑定且非白名单 → 直接拒绝 │
  │                         │     已绑定 → 信封带 Owner 转发 │
  │                         │ ───────────────────────────> │  9. Ctx.account = Owner
  │                         │                              │     （网关填，不可伪造）
```

**关键点：登录是「连接级会话状态」，不是「每包携带凭证」。**

游戏服务器是长连接，登录成功那一刻网关就把 `连接 ↔ owner` 绑定下来（`idIndex`
双 key 索引：`a:账号` 与 `p:角色ID`），后续请求靠这条绑定识别身份，既不重复传 token，
也不逐包查库。这与 Web 的「每请求验 token」是本质区别。

身份进入逻辑服后落到 `Ctx.account`（直接取自网关信封的 `Owner` 字段），
业务侧 `c.Account()` 拿到的就是它——**由网关按会话状态填充，客户端无法伪造**。

## Token 设计

引擎涉及两种 Token：

- **登录凭证（JWT）**：由**账号服**签发与校验，客户端经 `EMsgLogin{token}` 带来，
  游戏服调账号服 `/auth/verify` 换 `owner`（见 [账号服](/server/security/auth-server)）。
- **会话凭证（session token）**：游戏服自己管理，用于断线重连恢复会话。

### JWT Token（账号服签发）

```json
{
  "header": {
    "alg": "HS256",
    "typ": "JWT"
  },
  "payload": {
    "sub": "player_12345",
    "iss": "clover-auth",
    "exp": 1735689600
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `sub` | 对象标识（owner），通常是账号名 |
| `iss` | 签发者（`auth.issuer`，默认 `clover-auth`）；不参与验签，仅供排查 |
| `exp` | 过期时间（Unix 秒）；`Verify` 强制校验，`0` 视为立即过期 |

### 自定义 Token

引擎的 session token 是字符串（由 `sessiontoken.Store` 管理），不是结构体。
业务通过以下 API 管理会话：

```go
// 生成新 session token
token, err := g.NewSessionToken(playerID)

// 验证 session token
ok := g.ValidateSessionToken(playerID, token)

// 删除 session token（登出时）
g.DeleteSessionToken(playerID)
```

## 会话管理

### 踢下线

```go
// 当玩家在其他设备登录时，踢掉旧连接
// 引擎自动处理多端互踢：新登录会触发旧连接的 KickConn
func onLogin(c event.Ctx) error {
    // 通过 connID 踢掉旧连接（引擎内置机制）
    // 业务可通过 OnKick 事件监听被踢下线
    // g.KickConn(connID) —— 仅支持按 connID 踢下线
    // ...
}
```

### 断线保留

断线宽限期通过 `gateway.reconnect_grace` 配置（引擎默认 `0`，即关闭，需显式配置，如 30s）：

```yaml
gateway:
  reconnect_grace: 30s  # 断线后保留 30 秒允许重连
```

## 登录门禁（默认开启）

网关在转发前检查本连接是否已绑定对象标识；**未绑定的连接只放行免登录白名单**，
其余消息直接回 `EErrorReply{code:401}` 拒绝，不占用逻辑服资源。

默认白名单（`gwcore.DefaultAuthExemptMsgIDs`）：

| 消息号 | 常量 | 说明 |
| --- | --- | --- |
| 1 | （已作废） | 原 `EMsgSignup`：注册已移到账号服 HTTP，号位保留不复用（发该号会被登录门禁挡下） |
| 2 | `EMsgLogin` | 登录 |
| 3 | `EMsgResumeSession` | 断线重连恢复会话 |

配置项（`config.yaml` 的 `gateway` 段）：

```yaml
gateway:
  auth_disabled: false      # 关闭门禁；仅开发/本地调试用，生产保持 false（零值即开启）
  auth_exempt_msg_ids: []   # 免登录消息号白名单；留空=用引擎默认（注册/登录/恢复会话）
```

| 字段 | 说明 |
| --- | --- |
| `auth_disabled` | 关闭门禁。**仅开发 / 本地调试**；生产保持 `false` |
| `auth_exempt_msg_ids` | 自定义白名单，**完全覆盖**默认值（不是追加）。仅当确有「登录前必须可达」的消息时才配 |

> **为什么用 `Disabled` 反向命名**：与 `HTTPAuthDisabled` 一致——零值即开启门禁（fail-safe）。
> 漏配只会把功能挡住，不会放行越权。

> 业务侧**默认不需要任何配置**：门禁自动生效，登录即可用。只有「登录前就要能发」的消息
> 才需要在 `auth_exempt_msg_ids` 里显式登记。

`EMsgBindUDP`（UDP 端点绑定）不走本门禁：它在网关 `onUDPFrame` 层凭一次性令牌鉴权，
不进入通用转发路径。

**为什么放在网关而不是逻辑服**：这是**连接级**判断（"你是谁"），与具体消息无关。
放在离客户端最近的一跳，无效流量根本到不了逻辑服。逻辑服负责的是**消息级**权限
（"你能不能做这个"），见下节。

## 会话通道加密（AES-256-GCM）

登录成功后网关可对**该连接的所有帧**做整帧加解密（`[12B nonce][ciphertext||tag]`），
与 TLS 是两层、互不替代：

| 环节 | 谁做 | 要点 |
|---|---|---|
| 声明 | 客户端 | `ELoginRequest.encrypt = true`（Unity 引擎按平台能力自动填；不支持 AES-GCM 的平台如 WebGL **不声明**，退回明文交给 TLS） |
| 生成密钥 | 逻辑服 `auth.Handler` | `req.Encrypt` 为真时 `session.NewKey()` 生成 32B 随机密钥；**生成失败明确报错**，不静默退化明文 |
| 下发 | 逻辑服 → 客户端 | `ELoginReply.session_key`（base64，**该帧自身明文**——客户端要靠它才能解密后续帧） |
| 启用 | 网关 | `bootstrap` 注册 `WithCryptoKeyExtractor(auth.ExtractSessionKey())`：按回包 `session_key` 字段解析（与 opcode 解耦），命中即为该会话启用 AES-GCM |
| 例外帧 | — | `EMsgBindUDP`（网关按明文读令牌）、携带密钥的登录回包自身 |

**未声明即明文**：老客户端 / `robot` / `msg-client` / 网页工具都不声明，行为与加此能力前一致——
这样"不支持"等价于"不加密"，而不是"登录后被踢"。

> 安全边界：密钥本身经登录回包明文下发，因此**只有链路已有 TLS（或 QUIC/WT）时才安全**；
> 反过来，裸 TCP + 本层加密 = 中间人可读到密钥并伪造连接。两层的关系是"TLS 打底、应用层再加一层"。

## 权限控制（消息级）

### 统一挂载点：OnBeforeDispatch

引擎不内置 RBAC，但提供**统一挂载点**——业务横切逻辑（鉴权 / 审计 / 前置条件）
不必散落在每个 handler 里：

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    // 引擎内置横切逻辑（停机检查 / 灰度迁移 / 连接 KV 与身份恢复 / token 续期）之后执行。
    // 任一钩子返回 error 即拒绝本次派发，错误以 EErrorReply 回包。
    g.OnBeforeDispatch(func(c event.Ctx) error {
        // 例：房间类消息要求已进入游戏（注意 PlayerID 是角色 ID，不是登录态）
        if isRoomMsg(c.MsgID()) && c.PlayerID() == "" {
            return proto.Forbidden("请先创建角色")
        }
        return nil
    })
})
```

**分层职责**（对齐主流做法）：

| 层 | 负责 | 挂载点 |
| --- | --- | --- |
| 网关 | 「你是谁」：登录门禁（连接级） | `gateway.auth_disabled` |
| 逻辑服 | 「你能不能做这个」：业务权限（消息级） | `g.OnBeforeDispatch` |

钩子返回 `*proto.BizError` 时，错误回包会带上 `Code`（如 `401` / `403`），
客户端据此做统一处理，无需匹配错误文案。

> **注意**：`c.PlayerID()` 是**角色 ID**（创角 / 进入游戏后才有值），
> **不是登录态**。判断"有没有登录"要用 `c.Account()`；门禁本身只要求登录，不要求创角。

### 三种角色

| 角色 | 说明 | 典型权限 |
| --- | --- | --- |
| owner | 游戏所有者 | 全部权限 |
| gm | 游戏管理员 | 封号、发道具、查看数据 |
| player | 普通玩家 | 基本游戏操作 |

### 权限校验

> ⚠️ **引擎不内置 RBAC**：`Game` 上没有 `HasPermission` / `GetPlayerRole` 之类的方法（只有
> `g.KickConn(connID string) bool` 用于按连接踢人）。角色 / 权限体系需要业务自行实现，
> 建议存成 `data` 里的玩家维度数据，并在**统一钩子**里校验（见下节 `OnBeforeDispatch`）。

```go
// 业务自建的权限校验示例（示意，非引擎 API）
func (l *gameLogic) requireGM(c event.Ctx, perm string) error {
    var roles RoleData
    if err := l.g.LoadStruct(c, datadef.RoleSchema, c.PlayerID(), &roles); err != nil {
        return errors.New("no permission")
    }
    if !roles.Has(perm) {
        return errors.New("no permission")
    }
    return nil
}
```

## 安全边界

> **警告：** 以下数据永远不要信任客户端传入的值，必须由服务端计算：


| 数据 | 客户端传入 | 服务端校验 |
| --- | --- | --- |
| 伤害值 | 请求攻击 | 服务端计算实际伤害 |
| 货币数量 | 请求扣款 | 服务端计算余额 |
| 经验值 | 请求升级 | 服务端计算等级 |
| 时间戳 | 请求定时 | 服务端校验时间合法性 |

## 下一步


**相关链接：**

- [输入校验](/server/security/input-validation) - 详细的输入校验指南

- [反作弊](/server/security/anti-cheat) - 游戏反作弊策略

- [Handler 开发](/server/development/handler) - Handler 中的认证实践


