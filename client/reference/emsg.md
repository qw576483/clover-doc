## 这篇文档讲什么？

本文档定义消息号（EMsg）的结构、分配规则和使用规范。消息号由**服务端与客户端各自维护**（服务端 `game/def/`，客户端 `Runtime/Network/EMsg.cs`（引擎段）与 `MsgDef`（业务段）），**两端必须逐字一致**。

## 前置条件

- 已了解 Clover 引擎的基本架构
- 已完成客户端开发环境配置
- 已阅读网络通信基础文档

## 消息号结构

### 引擎内置消息号

引擎内置的消息号定义在 `CloverEngine.EMsg` 中：

```csharp 标题：引擎内置消息号定义
public static class EMsg
{
    // 连接与会话
    // 号位 1 原为 Signup（账号注册）：注册已完全移到账号服 HTTP，号位**作废保留不复用**。
    public const uint Login = 2;               // 账号登录（body 只有 token）
    public const uint ResumeSession = 3;       // 断线重连恢复会话
    public const uint RankQuery = 4;           // 排行榜查询
    public const uint BindUDP = 5;             // TCP 上报 UDP 端点
    public const uint UDPBindGrant = 6;        // 网关下发 UDP 绑定令牌
    public const uint QueuePosition = 7;       // 网关直发：排队位置通知（前面还有 N 人）
    
    // 推送消息
    public const uint PushPlayerFullSync = 4001;  // 玩家全量数据推送
    public const uint PushAlert = 4002;           // 公告/警告推送
    public const uint PushDataSync = 4003;        // 数据增量同步推送
    public const uint PushRoomTakeover = 4004;    // 房间接管推送
    public const uint PushSceneInfo = 4005;       // 场景标识推送
    
    // 错误处理
    public const uint Error = 0xFFFFFFFF;         // 统一错误回包
    
    // 引擎消息号上界，业务消息号必须大于该值
    public const uint InternalMsgMax = 10000;
}
```

### 业务扩展消息号

业务消息号定义在客户端 `MsgDef` 类中，与服务端 `game/def/{msg,reply,push}.go` 逐条对齐；类名与引擎内置 `EMsg` 隔离：

```csharp 标题：业务扩展消息号定义
public static class MsgDef
{
    // 角色系统（1000101-1000199）
    public const uint GetPlayerList = 1000101;    // 获取角色列表
    public const uint CreatePlayer = 1000102;     // 创建角色
    public const uint EnterGame = 1000103;        // 进入游戏
    
    // 排行榜系统（1000401-1000499）
    public const uint RankSubmitScore = 1000403;  // 提交分数
    public const uint GetRank = 1000404;          // 获取排行榜
    
    // 帧同步房间（1002001-1002099）
    public const uint FrameRoomCreate = 1002001;  // 创建房间
    public const uint FrameRoomJoin = 1002002;    // 加入房间
    public const uint FrameRoomLeave = 1002003;   // 离开房间
    // ... 从 1000101 起
}
```

### 消息号分类

| 类别 | 前缀 | 范围 | 说明 |
|------|------|------|------|
| 引擎 C2S + 网关直发 | `EMsg` | 1-7 | 引擎核心请求与网关直发帧（登录/会话/UDP 令牌/排队位置） |
| 引擎推送 | `EMsg.Push*` | 4001-4005 | 引擎推送（玩家同步/公告等） |
| 引擎错误 | `EMsg.Error` | 0xFFFFFFFF | 统一错误回包 |
| 业务 C2S | `Msg` | 1000101-1999999 | 客户端→服务器业务消息 |
| 业务回包 | 无前缀 | 不占号段 | 服务器→客户端回包按 requestID 配对（msgID 恒为 0） |
| 业务推送 | `Push` | 3002001-3999999 | 服务器→客户端推送 |

## 两端一致性

消息号是前后端通信的桥梁，**两端必须逐字一致**：

| 项 | 服务端 | 客户端 |
|------|------|------|
| 消息号常量 | `server/game/def/msg.go` | 引擎段 `Runtime/Network/EMsg.cs`；业务段 `Assets/Scripts/Def/MsgDef.cs`（业务工程内手工维护） |
| 协议结构体 | `server/game/def/{reply,push}.go` | 引擎段 `Runtime/Network/Protocol.cs`；业务段 `Assets/Scripts/Def/ProtoDef.cs` |

**约束**：

- 新增消息号时**两端同时改**。只改一端不会有编译错误，只会在运行期表现为「消息发出去没有反应」或「handler 不触发」；
- 两端**常量名与值必须完全一致**（含大小写）；
- 客户端协议结构体的字段名用 **snake_case**，与服务端 `json:"..."` tag 对齐。

> 建议在 CI 里加一个「两端消息号比对」脚本：分别解析两边的常量名与值，不一致就让构建失败。
> 这类问题比编译错误难查得多，值得用自动化挡住。

## 使用示例

### 发送消息

```csharp 标题：使用内置消息号
public class LoginManager : MonoBehaviour
{
    public async void Login(string account, string password)
    {
        try
        {
            // 唯一登录路径：账号密码只发给账号服（HTTP）换 token，再以 token 走长连接。
            var token = await CloverAuth.LoginAsync(account, password);
            var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest { token = token });

            Debug.Log($"登录成功! owner: {reply.owner}");
            
            // 保存登录信息
            PlayerPrefs.SetString("Token", reply.token);
            PlayerPrefs.Save();
        }
        catch (CloverCallException ex)
        {
            Debug.LogError($"登录失败: {ex.ServerError}");
        }
    }
}
```

```csharp 标题：使用业务消息号
public class ShopManager : MonoBehaviour
{
    public async void BuyItem(int itemID, int count)
    {
        try
        {
            // 使用业务消息号
            var reply = await Game.Net.Call<ShopBuyReply>(
                MsgDef.ShopBuy, 
                new ShopBuyRequest
                {
                    ItemID = itemID,
                    Count = count,
                }
            );
            
            Debug.Log($"购买成功! 订单号: {reply.OrderID}");
            
            // 更新本地数据
            UpdateLocalShopData(reply);
            
            // 触发事件
            Game.Event.Emit("shop.BuySuccess", new { ItemID = itemID, Count = count });
        }
        catch (CloverCallException ex)
        {
            Debug.LogError($"购买失败: {ex.ServerError}");
            
            // 显示错误提示
            ShowErrorUI(ex.ServerError);
        }
    }
}
```

### 注册监听

```csharp 标题：监听推送消息
public class NetworkListener : MonoBehaviour
{
    void Start()
    {
        // 监听玩家全量数据推送：引擎推送号（4001）落在保留段 [1,10000] 内，不可经 Game.OnMsg 注册；
        // 正确入口是 Game.Sync.OnFullSync（或 Game.Event 的 Net.PlayerFullSync 事件）。
        _onFullSync = (data, accountData) => ProcessPlayerData(data);
        Game.Sync.OnFullSync(_onFullSync);
    }

    private Action<Dictionary<string, Dictionary<string, object>>, Dictionary<string, object>> _onFullSync;

    void OnDestroy()
    {
        // 取消监听：注销需传注册时的同一委托引用
        Game.Sync.OffFullSync(_onFullSync);
    }
}
```

```csharp 标题：监听业务消息
public class ShopListener : MonoBehaviour
{
    void Start()
    {
        // 监听业务消息
        Game.OnMsg(MsgDef.ShopBuyReply, ctx =>
        {
            var reply = ctx.Bind<ShopBuyReply>();
            Debug.Log($"购买成功: {reply.OrderID}");
            
            // 更新 UI
            UpdateShopUI(reply);
        });
        
        // 监听推送消息
        Game.OnMsg(MsgDef.ShopInfoPush, ctx =>
        {
            var push = ctx.Bind<ShopInfoPush>();
            Debug.Log($"商店信息更新: {push.Items.Count} 个商品");
            
            // 刷新商店界面
            RefreshShop(push.Items);
        });
    }
}
```

## 消息号分配表

### 引擎内置（1-10000）

| 消息号 | 用途 | 说明 |
|--------|------|------|
| 1 | （已作废） | 原 `EMsg.Signup`：注册改走账号服 HTTP（`CloverAuth.SignupAsync`），号位保留不复用 |
| 2 | `EMsg.Login` | 账号登录 |
| 3 | `EMsg.ResumeSession` | 断线重连恢复会话 |
| 4 | `EMsg.RankQuery` | 排行榜查询 |
| 5 | `EMsg.BindUDP` | TCP 上报 UDP 端点 |
| 6 | `EMsg.UDPBindGrant` | 网关下发 UDP 绑定令牌 |
| 7 | `EMsg.QueuePosition` | 网关直发：排队位置通知（载体 `EQueuePositionNotify`，`ahead`/`total`/`ticket`；服务端限流/满载时连入等候队列才出现） |
| 4001 | `EMsg.PushPlayerFullSync` | 玩家全量数据推送 |
| 4002 | `EMsg.PushAlert` | 公告/警告推送 |
| 4003 | `EMsg.PushDataSync` | 数据增量同步推送 |
| 4004 | `EMsg.PushRoomTakeover` | 房间接管推送（载体 `ERoomTakeoverNotify`，动态 `recovery` 由 MiniJson 解析） |
| 4005 | `EMsg.PushSceneInfo` | 场景标识推送 |
| 0xFFFFFFFF | `EMsg.Error` | 统一错误回包 |

### 业务扩展（1000101+）

业务 C2S 消息号必须 >= `InternalMsgMax + 1`（即 >= 10001），实际 demo 从 1000101 起。回包通过 requestID 配对（msgID=0），业务推送从 3002001 起。

| 范围 | 用途 | 示例 |
|------|------|------|
| 1000101-1000199 | 角色系统 | `MsgGetPlayerList = 1000101` |
| 1000201-1000299 | 道具系统 | `MsgGiveItem = 1000201` |
| 1000401-1000499 | 排行榜 | `MsgRankSubmitScore = 1000403` |
| 1000501-1000599 | 公告系统 | `MsgSetAnnounce = 1000501` |
| 1002001-1002099 | 帧同步房间 | `MsgFrameRoomCreate = 1002001` |
| 1004201-1004299 | MMO 演示 | `MsgDemoMMOBase = 1004201` |

### 推送消息（3002001+）

| 范围 | 用途 | 示例 |
|------|------|------|
| 3002001-3002099 | 帧同步推送 | `PushFrameRoomSync = 3002001` |
| 3003001-3003099 | 通用广播 | `PushDemoBroadcast = 3003001` |

> **注意：** 引擎内置推送（4001-4005）与网关直发帧（6/7）由引擎自动处理，业务无需定义、也**不可占用**这些号位。

## 维护方式

消息号**手工维护**（两端各写一份），流程：

1. 服务端：在 `game/def/msg.go` 加常量，在 `reply.go` / `push.go` 加对应结构体；
2. 客户端：在 `Assets/Scripts/Def/MsgDef.cs` 加**同名同值**常量，在 `Assets/Scripts/Def/ProtoDef.cs` 加对应字段（snake_case）；
3. 跑一次 CI 的两端比对脚本，确认一致。

> 引擎的**自动生成只覆盖配表**（见打表工具：源表 → tsv + 强类型代码）。
> 消息号目前没有生成器，「两端同时改 + CI 比对」就是当前的正式流程。

## 最佳实践

### 1. 消息号命名规范

```csharp 标题：命名规范示例
// ✅ 正确：清晰的命名
public static class MsgDef
{
    // C2S 请求（业务消息号 >= 10001）
    public const uint GetPlayerList = 1000101;    // 获取角色列表
    public const uint CreatePlayer = 1000102;     // 创建角色
    public const uint EnterGame = 1000103;        // 进入游戏

    // 推送消息（业务推送 >= 3002001）
    public const uint FrameRoomSync = 3002001;    // 帧同步数据
    
    // 错误码（可选，0xFFFFFFFF 已被引擎占用）
    public const int ShopError = 90001;           // 业务错误码（错误码是 int，与引擎 ErrCode 一致）
}

// ❌ 错误：模糊的命名
public static class MsgDef
{
    public const uint Msg1 = 1000101;             // 不清晰
    public const uint Data = 1000102;             // 不清晰
}
```

### 2. 消息号分组

```csharp 标题：分组示例
public static class MsgDef
{
    // 角色系统（1000101-1000199）
    public const uint GetPlayerList = 1000101;
    public const uint CreatePlayer = 1000102;
    public const uint EnterGame = 1000103;
    
    // 道具系统（1000201-1000299）
    public const uint GiveItem = 1000201;
    public const uint CostItem = 1000202;
    public const uint CostAll = 1000203;
    
    // 排行榜（1000401-1000499）
    public const uint RankSubmitScore = 1000403;
    public const uint GetRank = 1000404;
    
    // 帧同步房间（1002001-1002099）
    public const uint FrameRoomCreate = 1002001;
    public const uint FrameRoomJoin = 1002002;
    public const uint FrameRoomLeave = 1002003;
}
```

### 3. 错误处理

```csharp 标题：错误处理示例
public class ErrorHandler : MonoBehaviour
{
    void Start()
    {
        // 推荐：订阅引擎归一化后的「未认证」事件。
        // 网关登录门禁拒绝（未登录就发业务消息）与逻辑服返回 401 都会触发它。
        Game.Event.On<EErrorReply>("Net.OnUnauthorized", e =>
        {
            Game.Logger.Warn("Net", $"未认证（code={e.code}）: {e.err}");
            BackToLogin();
        });

        // 需要按错误码分流更多分支时，直接监听统一错误回包。
        // 注意：这类回包已被引擎按 requestID 配对并结束对应的 Call，
        // 这里属于旁路观察（同一个错误在 Call 侧还会以 CloverCallException 抛出）。
        Game.OnMsg(EMsg.Error, ctx =>
        {
            var error = ctx.Bind<EErrorReply>();

            // error.err  = 人类可读描述（不要拿它做逻辑分支，文案会变）
            // error.code = 机器可读错误码（见 ErrCode），0 表示未分类
            switch (error.code)
            {
                case ErrCode.Unauthenticated: BackToLogin();               break;
                case ErrCode.Forbidden:       ShowNoPermission(error.err); break;
                default:                      ShowGenericError(error.err); break;
            }
        });
    }
}
```

> `EErrorReply` 同时含 `err`（描述）与 `code`（错误码）。错误码取值见
> `Runtime/Network/ErrCode.cs`，与服务端 `pkg/shared/proto` 是同一套数字契约。

## 常见问题

### 消息号冲突

**症状**：发送消息后收到错误回复

**原因**：消息号与内置消息号冲突

**解决**：
1. 检查消息号是否在 [1, 10000] 范围内（该段被引擎保留，`Game.OnMsg` 会拒绝注册）
2. 业务消息号放 `MsgDef`，不要混进 `EMsg`
3. 确认两端常量值一致

### 消息号未找到

**症状**：编译错误 "The name 'MsgDef' does not exist"

**原因**：客户端缺少业务消息号定义，或命名空间未引入

**解决**：
1. 检查 `Assets/Scripts/Def/MsgDef.cs` 是否存在
2. 检查业务脚本是否 `using` 了该文件所在的命名空间
3. 检查与服务端 `game/def/` 的常量名是否一致

### 消息体序列化错误

**症状**：发送消息后服务器解析失败

**原因**：消息体格式与服务器不匹配

**解决**：
1. 检查消息体字段类型
2. 检查消息号是否正确
3. 使用相同的协议定义文件

## 下一步

- 了解 [帧结构和传输协议](frame-format.md)
- 了解 [网络模块](../development/network.md) 完整用法