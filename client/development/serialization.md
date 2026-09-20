# 序列化与协议

## 这篇文档讲什么？

本指南介绍客户端与服务器之间的序列化协议和网络帧格式，帮助开发者理解消息传输的底层细节。

**目标读者**：需要深入理解网络协议的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](./quick-start.md)
- 了解基本的网络编程概念
- 了解 [网络与会话](./network.md)

## 网络帧格式

### TCP / QUIC 流

**客户端帧**（payload）两种线路相同：`[4B requestID][4B msgID][body]`（全大端）。传输层包装不同：

- **TCP**：`[1B type][4B length][客户端帧]`；
- **QUIC 流**：`[4B length][客户端帧]` —— **没有 `type` 字节**，与服务端 `internal/transport/net/quic/conn.go` 严格对应。

TCP 传输层帧展开：

```
+-------------+-------------------+-------------------+-------------------+---------+
| type (1B)   | length (4B)       | requestID (4B)    | msgID (4B)        | body    |
| 帧类型       | 后续数据字节长度     | 请求配对 ID        | 消息号             | 消息体   |
+-------------+-------------------+-------------------+-------------------+---------+
```

| 字段 | 长度 | 说明 |
|------|------|------|
| `type` | 1 字节 | 帧类型（0=Data，引擎另有控制帧；见 `internal/transport/net/tcp/codec.go`） |
| `length` | 4 字节 | 后续数据的字节长度（不含自身） |
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

## EMsg 消息号

消息号由两端各自维护（服务端 `game/def/`、客户端 `Runtime/Network/EMsg.cs`（引擎段）与 `MsgDef`（业务段）），**常量名与值必须逐字一致**。

```csharp
// 引擎内置消息号（与 pkg/shared/proto 对齐）
public static class EMsg
{
    // 号位 1 原为 Signup（账号注册）：注册已完全移到账号服 HTTP，号位**作废保留不复用**。
    public const uint Login = 2;
    public const uint ResumeSession = 3;
    public const uint RankQuery = 4;
    public const uint BindUDP = 5;
    public const uint UDPBindGrant = 6;
    public const uint QueuePosition = 7;
    public const uint PushPlayerFullSync = 4001;
    public const uint PushAlert = 4002;
    public const uint PushDataSync = 4003;
    public const uint PushRoomTakeover = 4004;
    public const uint PushSceneInfo = 4005;
    public const uint Error = 0xFFFFFFFF;
    public const uint InternalMsgMax = 10000;
}

// 业务扩展消息号（类名与引擎内置 EMsg 隔离）
public static class MsgDef
{
    public const uint GetPlayerList = 1000101;
    public const uint CreatePlayer = 1000102;
}
```

> **注意：** 业务消息号约定从 1000101 起；消息号**手工维护、没有生成器**（不存在「自动跳过重名/重值项」的机制，需两端自行核对）。回包不携带独立消息号（msgID 恒为 0），通过 requestID 配对。

## Call 回包配对

```csharp
var reply = await Game.Net.Call<XxxReply>(EMsg.Xxx, request);
```

| 特性 | 说明 |
|------|------|
| 配对机制 | 按 requestID 配对，回包 msgID 恒为 0 |
| 错误处理 | 服务端统一错误回包 msgID = `EMsg.Error`（body = `EErrorReply{err}`） |
| 异常类型 | 业务错误以 `CloverCallException` 结束 |
| 超时处理 | 超时以 `TimeoutException` 结束（默认 10s，`GameConfig.CallTimeoutSeconds` 可配） |

```csharp
// 请求-回包示例
try
{
    // 账号密码只发给账号服（HTTP）换 token；ELoginRequest 只有 token 字段。
    var token = await CloverAuth.LoginAsync("test", "123456");
    var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest
    {
        token = token,
    });
    Debug.Log($"登录成功: owner={reply.owner}");
}
catch (CloverCallException ex)
{
    // 业务错误（账号不存在、密码错误等）
    Game.Logger?.Error("Net", $"业务错误: {ex.ServerError}");
}
catch (TimeoutException)
{
    // 请求超时
    Game.Logger?.Error("Net", "请求超时，请检查网络");
}
```

## 序列化选型

| 选项 | 状态 | 说明 |
|------|------|------|
| **JSON** | 当前默认 | 跟服务端线格式一致，易于调试 |
| **Protobuf** | 后续可选 | 高性能二进制序列化 |
| **MemoryPack** | 后续可选 | Unity 友好的高性能序列化 |

> **JSON 序列化加固（本轮）**：`MiniJson.Dump` 现带**循环引用 + 深度保护**（自引用对象 / 深度 > 128 直接抛
> `FormatException`，旧实现会一路递归到不可捕获的 `StackOverflowException`）；`float` 按自身最短可往返格式输出
> （不再先提升成 double）；整数值的 `double`（如 `1.0`）**保型**输出为 `1.0`（`Parse` 回来仍是 double）；
> `enum` / `DateTime` / `DateTimeOffset` / `TimeSpan` 统一**按字符串加引号**输出（旧的裸文本是非法 JSON）；
> 对象键按 `StringComparer.Ordinal` **排序**后输出（同一份数据每次结果一致、内容哈希稳定）。
> 解析侧（`MiniJson.Parse`）的嵌套深度上限同样是 128。

> **已定（2026-09-15）：协议字段名保持 snake_case**，不引入 Newtonsoft / `[JsonProperty]`。
> 理由：字段名即 JSON 键，与服务端 `game/def/` **逐字对齐**，联调时肉眼可比；引入第三方序列化器要额外处理
> IL2CPP + 代码裁剪下的反射/AOT 风险，收益只是"命名整齐"。
> **明确接受的代价**：协议字段名不受 C# 命名规范约束，拼错要到联调期才暴露 —— 由 `MsgIdGuardTests` / `ProtocolTests`
> 这类契约测试兜住。（原先登记为待决策项，现结案。）

> **注意：** Router API 不随序列化格式变化而变化，业务代码无需修改。

## 常见问题

### 消息反序列化失败

**症状**：`Bind<T>()` 返回空对象

**原因**：消息体格式与预期不符

**解决**：
1. 检查消息号是否正确
2. 确认序列化格式一致

### 请求超时

**症状**：`TimeoutException`

**原因**：网络延迟或服务器处理时间过长

**解决**：
1. 增加 `CallTimeoutSeconds` 配置
2. 优化服务器处理逻辑

## 下一步

- 了解 [网络与会话](./network.md) 完整用法
- 了解 [Game 门面](./game-facade.md) 和模块入口