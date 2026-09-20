# 网络与会话

## 这篇文档讲什么？

本指南介绍 Network 模块的完整用法，包括连接管理、消息收发、重连机制和会话管理。

**目标读者**：需要理解 Clover 客户端网络层的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](./quick-start.md)
- 了解基本的网络编程概念

## Network 模块概览

客户端引擎的网络底座，与服务端 `event` 内核同语义。

| 能力 | 说明 |
|------|------|
| Connection | 传输抽象与线路计划：QUIC / TCP / WebSocket / 裸 UDP（**WebTransport 尚未实现**，见工作区根 `客户端待做.md` #2）。原生家族 = QUIC → TCP + RawUDP，Web 家族 = WT → WS（两者均需浏览器 jslib 桥接、**当前均未落地 ⇒ WebGL 无可用线路**），**两家族互斥**；跨家族换线不是「降级」而是换协议家族，引擎禁止 |
| Session | 登录态：account / playerID / token / 线路 / requestID 分配 / 请求-回包配对 |
| Router | `OnMsg(msgID, handler)` 注册派发，推送（requestID==0）走这里 |
| Call 配对 | `Call<T>` 按 requestID 配对，超时默认 10s |
| 会话恢复 | 断线重连后自动发送 `EMsg.ResumeSession`。凭证取自全量同步的 `session_token`；服务端回包**必须带 `owner`**，否则网关不会把重连后的新连接绑回 owner，后续业务消息会被**全量拒为 401** |
| 重连 | 次数上限（默认 5）、指数退避（2^n 秒，封顶 60s） |

## 接入地址与端口（这一步必须搞对）

```csharp
Game.Launch(config);
CloverNet.Init("127.0.0.1:8002", "127.0.0.1:8003");
//                  ↑ TCP 网关       ↑ UDP 端点（不需要不可靠通道就传 null）
```

两个参数与服务端 `server.yaml` 的 `gateway` 段**一一对应**：

| 服务端配置 | 端口 | 谁在用 | 客户端参数 |
|-----------|------|--------|-----------|
| `gateway.listen_tcp` | **8002** | Unity 原生客户端（裸 TCP） | `CloverNet.Init` 第 1 个参数 ← **就是这个** |
| `gateway.listen_udp` | 8003 | 不可靠通道（`SendUnreliable`） | 第 2 个参数，不需要就传 `null` |
| `gateway.listen_ws` | 8001 | 浏览器 / WebGL 客户端（WebSocket） | Unity 客户端**不要用** |

### 线路是否走 TLS

服务端配了 `gateway.tls_cert` 后 **TCP 口默认也被 TLS 包起来**（`tcp_tls_disabled` 默认 `false`）；
客户端用 `GameConfig.UseTls` 匹配（`true` → TCP 走 `SslStream`、WS 走 `wss://`、QUIC/WT 本来就是 TLS 1.3）：

```csharp
Game.Launch(new GameConfig
{
    ServerAddr = "127.0.0.1:8002",
    UseTls = true,          // 与服务端 gateway.tcp_tls_disabled 相反：服务端 false 时这里 true
});
```

- **两个开关必须相反**：`UseTls=true` 连明文网关 = 握手失败（连上就断）；`UseTls=false` 连 TLS 网关 = 同样连不上。
- 证书走**系统信任链**校验，引擎**不提供**跳过校验的开关（硬约束 §N7）；本地开发用 mkcert 根 CA（`mkcert -install` 装进信任库）。
- 服务端 TCP/WS 的 TLS 下限是 **1.2**（`gwcore` 为 TCP/WS 单独放宽，QUIC/WT 仍是 1.3），以兼容只到 TLS 1.2 的原生 `SslStream`。
- 服务端显式设 `tcp_tls_disabled: true` 保留明文入口时，启动日志会打一条告警——那不是默认形态。

> ⚠️ Unity 客户端**必须填 8002**（`gateway.listen_tcp`）。填 8001 是常见错误：
> 8001 是 WebSocket 口，裸 TCP 连上去会出现「TCP 握手成功 → 立刻被断开 → 自动重连 →
> 重连耗尽报被踢 → 之后所有 `Call`（登录 / 建房 / 同步）全部超时」这种极难定位的现象。
> 客户端日志特征：`[Clover][Network] reliable link connected (…)` 紧跟着 `reliable link lost (…)` /
> `reconnecting in …s`（链路日志由 `Game.Logger` 以 `Network` tag 输出，可在 `logs/` 文件日志里检索）。
>
> 另注：`CloverNet.Init` 的第一个参数缺省（null / 空串）时**会回退读取 `GameConfig.ServerAddr`**；
> 两者都未配置且 `WsAddr` 也为空时才报错返回。

## API 对照

> **注意：** 客户端和服务端的网络 API 语义完全一致，方便前后端逻辑复用。

| 操作 | 服务端 Go | 客户端 C# |
|------|----------|----------|
| 注册监听 | `g.OnMsg(msgID, func(c event.Ctx) error { ... })` | `Game.OnMsg(msgID, ctx => { var r = ctx.Bind<EPlayerFullSyncNotify>(); ... })`（**唯一入口**） |
| 回复 | `g.Reply(c, v)` | - |
| 可靠发送 | - | `Game.Net.Send(EMsg.Xxx, msg)` |
| 请求-回包 | - | `await Game.Net.Call<XxxReply>(EMsg.Xxx, msg)` |
| 非可靠发送 | - | `Game.Net.SendUnreliable(EMsg.Xxx, msg)` |

> **命名一致**：注册监听在两端**同一个名字 `OnMsg`**（服务端 `g.OnMsg` / 客户端 `Game.OnMsg`），
> 且客户端**只有这一个入口**——`INetwork` 不含 `OnMsg/OffMsg`（路由能力独立为 `IRouter`，由 `Game` 门面暴露），
> 所以不存在 `Game.Net.OnMsg` 第二入口，也不存在 `OnPush` 之类的近似名。
> 回包不注册回调——`Call<T>` 按 requestID 自动配对；客户端 router 只会收到推送（回包 msgID 恒为 0，走配对不进 router）。

## 核心 API

### 注册推送监听

```csharp
// 注册监听（唯一入口，与服务端 g.OnMsg 同名）
Game.OnMsg(EMsg.SomeNotify, ctx =>
{
    var msg = ctx.Bind<SomeNotify>();
    Debug.Log($"收到推送: {msg.Data}");
});

// 取消监听
Game.OffMsg(EMsg.SomeNotify, handler);   // 精确移除指定 handler
Game.OffMsg(EMsg.SomeNotify);            // 移除该消息号的全部 handler
```

### 发送消息

```csharp
// 可靠发送（TCP）；业务消息号放 MsgDef，不要混进 EMsg
Game.Net.Send(MsgDef.ChatMessage, new ChatMessage
{
    Content = "你好",
});

// 非可靠发送（UDP 优先）
Game.Net.SendUnreliable(MsgDef.PositionSync, new PositionData
{
    X = transform.position.x,
    Y = transform.position.y,
    Z = transform.position.z,
});
```

### 请求-回包

```csharp
// 异步请求
try
{
    var reply = await Game.Net.Call<ShopBuyReply>(EMsg.ShopBuy, new ShopBuyRequest
    {
        ItemID = 1001,
        Count = 1,
    });
    Debug.Log($"购买成功: {reply.OrderID}");
}
catch (CloverCallException ex)
{
    Debug.LogError($"业务错误: {ex.ServerError}");
}
catch (TimeoutException)
{
    Debug.LogError("请求超时");
}
```

## Ctx 成员

服务端 `event.Ctx` 的客户端子集：

| 成员 | 说明 |
|------|------|
| `MsgID` | 消息号 |
| `RequestID` | 请求配对 ID |
| `TraceID` | 追踪 ID |
| `Body` | 原始消息体 |
| `Bind<T>()` | 反序列化消息体 |

```csharp
Game.OnMsg(EMsg.SomeNotify, ctx =>
{
    Debug.Log($"MsgID={ctx.MsgID}, RequestID={ctx.RequestID}, TraceID={ctx.TraceID}");
    var msg = ctx.Bind<SomeNotify>();
});
```

## UDP 绑定

绑定两步：

```mermaid
sequenceDiagram
    participant 客户端
    participant 服务端
    
    服务端->>客户端: TCP: EMsg.UDPBindGrant (体为令牌原文)
    客户端->>服务端: UDP: EMsg.BindUDP (体为令牌原文)
    
    loop 每 10 秒
        客户端->>服务端: UDP: EMsg.BindUDP (心跳)
    end
```

> **警告：** `UDPBindGrant` 由引擎最高优先拦截，业务**不可占用**该消息号。断线时清理 UDP。
>
> 该帧**不加密**（即便已协商会话通道加密）：网关在 `onUDPFrame` 里按明文读令牌，早于任何解密。

## 排队位置通知

服务器限流 / 满载时会把你放进**等候队列**（而不是直接拒绝），并下发 `EMsg.QueuePosition`（=7，
网关直发帧，`requestID=0`，不经逻辑服）。业务据此显示「您前面还有 N 人」的等待界面：

```csharp
Game.Event.On<EQueuePositionNotify>("Net.QueuePosition", pos =>
{
    // ahead / total / ticket；文本刷新由你自己的面板控件完成（IUIManager 不提供 SetText）
    _queueLabel.text = $"前面还有 {pos.ahead} 人";
});

// 也可以只读状态（引擎会维护，任意时刻可查）
if (Game.Net.IsQueued) Debug.Log($"{Game.Net.QueueAhead}/{Game.Net.QueueTotal}");
```

| 项 | 说明 |
|---|---|
| 载体 | `EQueuePositionNotify{ ahead, total, ticket }`（`ahead`=前面还有多少人，0=队首；`ticket`=排队编号，仅展示） |
| 时机 | 入队时下发一次；队列前进后按固定间隔（3s）**只在位置变化时**续发 |
| 放行判据 | 收到**任意回包**即表示已放行（排队中服务端丢弃后续帧、不会有回包）——引擎此时清 `IsQueued` |
| 超时 | 排队期间引擎会顺延未决请求（如登录 `Call`）的超时：服务端还在刷新位置就说明仍在正常排队；**但顺延有总期限**——`MinPendingHardTimeoutSeconds = 60`（实际取 `max(60, CallTimeoutSeconds)`），到点即判超时失败（队列停滞期不下发位置帧时也不会无限挂起，代码自标 E-net-01） |
| 未启用 | 服务端 `gateway.queue_cap=0`（默认不排队）时**不会出现**该帧：超限直接拒绝并断连 |

## 会话通道加密（AES-256-GCM）

登录后客户端与服务端之间的**整帧**可以再套一层会话加密（TCP/WS 之上、TLS 之内的应用层）：

```text
客户端登录（自动声明 encrypt=true）→ 服务端回包带 session_key（明文）
→ 双方此后所有帧 = [12B nonce][ciphertext+tag]（8B 帧头一起加密）
```

| 项 | 说明 |
|---|---|
| 谁开启 | **引擎自动**：`Game.Net.Call<ELoginReply>(EMsg.Login, …)` 时按平台能力自动填 `ELoginRequest.encrypt`，业务不要手填 |
| 平台不支持 | 拿不到 AES-GCM 的平台（如 WebGL）**不声明**加密 → 服务端保持明文，链路安全由 wss/QUIC/WT 的 TLS 承担（不会出现"声明了却解不开"） |
| 状态查询 | `Game.Net.IsChannelEncrypted` |
| 明文例外 | ① 登录回包自身（客户端要靠它拿密钥）；② `EMsg.BindUDP` 绑定帧（网关按明文读令牌） |
| 断线重连 | 新连接是**新会话**：密钥作废、由新的登录回包重新协商（引擎自动清掉旧密钥） |
| 与 TLS 的关系 | 这是「TLS 之上再加一层」，**不是** TLS 的替代——登录回包本身仍是明文下发密钥 |

## 网络帧格式

### TCP 流

> **QUIC 流的分帧不同**：`[4B 大端长度][客户端帧]`（**无 type 字节**，见 `Runtime/Network/Quic/QuicStreamFraming.cs`）；WebTransport 尚未实现，接入后另行说明。

```
+-------------+-------------------+-------------------+-------------------+---------+
| type (1B)   | length (4B)       | requestID (4B)    | msgID (4B)        | body    |
| 传输层帧类型  | 后续数据字节长度     | 请求配对 ID        | 消息号             | 消息体   |
+-------------+-------------------+-------------------+-------------------+---------+
```

| 字段 | 长度 | 说明 |
|------|------|------|
| `type` | 1 字节 | 传输层帧类型：`0`=数据、`1`=ping、`2`=pong、`3`=会话迁移（见 `Connection.cs`） |
| `length` | 4 字节 | 其后的 `[requestID][msgID][body]` 字节长度（不含 `type` 与自身） |
| `requestID` | 4 字节 | 请求配对 ID，0 表示推送 |
| `msgID` | 4 字节 | 消息号（EMsg 枚举） |
| `body` | 可变 | 消息体（JSON / Protobuf / MemoryPack，当前默认 JSON） |

### 裸 UDP

```
+--------+-------------------+-------------------+---------+
| 0x55   | requestID (4B)    | msgID (4B)        | body    |
| 魔数    | 请求配对 ID        | 消息号             | 消息体   |
+--------+-------------------+-------------------+---------+
```

| 字段 | 长度 | 说明 |
|------|------|------|
| `0x55` | 1 字节 | 魔数标识 |
| `requestID` | 4 字节 | 请求配对 ID，0 表示推送 |
| `msgID` | 4 字节 | 消息号（EMsg 枚举） |
| `body` | 可变 | 消息体 |

## WebRequest（HTTP 短连接）

版本检查、公告、CDN 清单、日志/埋点上报等一切 HTTP(S) 请求的统一入口。

| 特性 | 说明 |
|------|------|
| 支持方法 | GET / POST |
| 超时 / 重试 / 并发上限 | **均未实现**（`IWebRequest` 只有 `Get` / `Post` / `Dispose`） |

> **注意：** WebRequest **不走游戏长连接**，与 Network 互不干扰。

```csharp
// GET 请求（回调式）
Game.Http.Get("https://api.example.com/version", response =>
{
    if (response.IsSuccess)
    {
        var data = JsonUtility.FromJson<VersionCheckResponse>(response.Text);
        // 处理结果
    }
});

// POST 请求（回调式，body 为 JSON 字符串）
var body = JsonUtility.ToJson(new LoginRequest { Account = "test", Password = "123456" });
Game.Http.Post("https://api.example.com/login", body, response =>
{
    if (response.IsSuccess)
    {
        var data = JsonUtility.FromJson<LoginResponse>(response.Text);
        // 处理结果
    }
});
```

## 网络事件

| 事件名 | 说明 |
|--------|------|
| `Net.OnConnected` | 连接建立 |
| `Net.OnDisconnected` | 断开，恢复可用时自动重连 |
| `Net.OnConnectFailed` | 从未连上：首次连接失败或地址非法 |
| `Net.OnKicked` | 重连次数耗尽或无恢复凭证 |
| `Net.OnResumed` | 会话已恢复，参数为回包结构 |
| `Net.OnResumeFailed` | 恢复被拒，参数为原因 |
| `Net.QueuePosition` | 服务器排队位置变化（参数为 `EQueuePositionNotify`，见「排队位置通知」） |

```csharp
// 监听连接事件（OnConnected/OnKicked 无参；OnResumed 带参、用显式 On<T>）
Game.Event.On("Net.OnConnected", () =>
{
    Debug.Log("已连接到服务器");
});

Game.Event.On<EResumeSessionReply>("Net.OnResumed", data =>
{
    Debug.Log("会话已恢复");
});

Game.Event.On("Net.OnKicked", () =>
{
    Debug.Log("被踢出，需要重新登录");
});
```

## 网络硬约束

| 编号 | 约束 |
|------|------|
| **N1** | 单一 `addr = ip:port` 配置；启动自动连接，无手动输入 |
| **N2** | 帧格式 `[4B requestID][4B msgID][body]`，requestID==0 推送 |
| **N3** | EMsg 两端一致：常量名与值逐字相同（服务端 `game/def/` ↔ 客户端 `Runtime/Network/EMsg.cs`（引擎段）与 `MsgDef`（业务段）） |
| **N4** | 重连走 session resume 不重登；次数上限 + 指数退避 |
| **N5** | UDP 绑定两步流程，每 10 秒重报绑定帧 |
| **N6** | QUIC / WebSocket / RawUDP 为 P0 级交付（**WebTransport 未实现**，见工作区根 `客户端待做.md` #2） |
| **N7** | 全场景禁止自签证书 |
| **N8** | WebTransport keepalive（msgID==0 空包）直接丢弃 |
| **N9** | 多设备被踢 → 清理 UDP → 走 `OnKicked`，不自动重连 |
| **N10** | 平台线路：Standalone = QUIC → TCP + RawUDP；GL（WebGL）= **当前无可用线路**（WebSocket 与 WebTransport 均需浏览器 jslib 桥接、尚未落地，见 `客户端待做.md` #2；浏览器无 BSD socket，原生家族线路也不可用） |
| **N11** | 线路 TLS 开关与服务端 `gateway.tcp_tls_disabled` **必须相反**；证书只走系统信任链（无跳过开关） |
| **N12** | 会话通道加密由引擎协商（登录时自动填 `ELoginRequest.encrypt`）；业务不得手填该字段，也不得自行加解密帧 |

## 常见问题

### 连接超时

**症状**：`TimeoutException`

**原因**：网络不稳定或服务器负载过高

**解决**：
1. 检查网络连接
2. 增加 `CallTimeoutSeconds` 配置

### 会话恢复失败

**症状**：`Net.OnResumeFailed` 事件触发

**原因**：服务器会话过期或 token 无效

**解决**：
1. 重新登录
2. 检查 token 是否正确

> ⚠️ **另一种「看起来恢复了、其实废了」**：`Net.OnResumed` 正常触发，但紧接着**每条业务请求都返回
> `code=401 unauthenticated`**。这不是网络抖动，而是**网关没把 owner 绑到重连后的新连接**上
> （恢复回包缺 `owner` 字段）。引擎侧已内置修复（`ResumeSessionHandler` 按 playerID 反查账号补 `owner`）；
> 业务侧若遇到，监听 `Net.OnUnauthorized` 回登录流程即可，不要当成弱网重试。

## 下一步

- 了解 [序列化协议](./serialization.md) 和帧格式
- 了解 [Game 门面](./game-facade.md) 和模块入口