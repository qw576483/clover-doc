# Game 门面

## 这篇文档讲什么？

本指南介绍 `Game` 门面的使用方法，这是客户端引擎的唯一入口，业务代码只通过 `Game` 访问各模块。

**目标读者**：所有使用 Clover 客户端引擎的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](../quickstart.md)
- 了解 Unity 基础开发

## 初始化

```csharp
Game.Launch(config);  // 初始化核心子系统（日志→派发→事件→定时→状态机→设置→设备码），不联网、不登录、不进场景
```

> **注意：** `Game.Launch` 只建核心子系统并启驱动器。联网需调用 `CloverNet.Init(addr, udpAddr)`（自动连接）；
> 登录要业务自己发起：`await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest { token })`，
> **首次登录没有推送式事件**。`Net.OnResumed` 是**断线重连**恢复会话成功的事件
> （`Game.Event.On<EResumeSessionReply>("Net.OnResumed", ...)`），不是登录成功信号；登录成功同样没有 `Net.OnLogin` 这类事件。

### GameConfig 参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ServerAddr` | `string` | - | 服务器地址（ip:port） |
| `LogDir` | `string` | `"logs"` | 日志文件存储目录 |
| `SettingDir` | `string` | `"setting"` | 配置与设置文件存储目录 |
| `ResourceRoot` | `string` | - | 资源文件根目录路径 |
| `DataDir` | `string` | - | 表格数据文件存储目录 |
| `HeartbeatIntervalMs` | `int` | 15000 | TCP 心跳间隔（毫秒） |
| `ConnectTimeoutMs` | `int` | 5000 | TCP 连接超时（毫秒） |
| `CallTimeoutSeconds` | `double` | 10 | 请求-响应超时（秒） |
| `MaxReconnectCount` | `int` | 5 | 最大重连次数 |
| `UdpKeepaliveIntervalSeconds` | `double` | 10 | 裸 UDP 通道 NAT 保活周期（秒） |
| `UseTls` | `bool` | `true` | 线路是否走 TLS（TCP→`SslStream`、WS→`wss://`）；必须与服务端 `gateway.tcp_tls_disabled` **相反**。**默认 `true`（默认加密）**：移动端（Android 9+ / iOS ATS）默认拦截明文流量，默认明文等于「默认连不上」，加密才是安全侧默认值；**只在服务端确实未启 TLS 时才手动关**（`gateway.tls_cert` 未配置 / `tcp_tls_disabled=true`），否则握手会失败。证书只走系统信任链，无跳过校验开关（§N7） |

```csharp
var config = new GameConfig
{
    ServerAddr = "127.0.0.1:8002",
    MaxReconnectCount = 5,
    CallTimeoutSeconds = 10,
    UseTls = true,          // 服务端 gateway.tcp_tls_disabled 为 false（默认）时必须为 true
};
Game.Launch(config);
```

## 模块入口

| 模块 | API | 说明 |
|------|-----|------|
| **网络** | `Game.Net` / `Game.Http` | 网络域入口（连接/收发/请求-回包）；消息路由唯一入口：`Game.OnMsg(msgID, handler)` / `Game.OffMsg` |
| **世界同步** | `Game.Sync` | 世界镜像入口（原始事件流） |
| **数据 Schema** | `Game.Schema` | Schema 声明表（登记字段结构，`ISchemaRegistry`）；**数据订阅走 `Game.Sync`** |
| **公告推送** | `Game.Alert` | 消费 `EMsg.PushAlert`，把服务端公告分发给业务（`IAlert`） |
| **服务端场景** | `Game.CloverScene` | 服务端场景投影（逻辑地图 + 分线），与 `Game.Scene` 不同义 |
| **帧同步房间** | `Game.FrameRoom` | 帧同步房间生命周期；消息号由业务 `Configure()` 注入 |
| **场景** | `Game.Scene` | Unity 关卡管理（异步加载/卸载 + 加载门控） |
| **逻辑地图** | `Game.Map` | 服务端权威地图在客户端的**只读投影**（本地碰撞 / 寻路查询）：`Load(byte[] data, out string error)` / `LoadFromResource(path)` / `WalkableAt(x,z)` / `Clear()`。数据是服务端加载的**同一份字节**（CloverMap 二进制，契约见 [`clover-server-engine/pkg/domain/mmo/mapdata/README.md`](https://github.com/qw576483/clover-server-engine/blob/main/pkg/domain/mmo/mapdata/README.md)）。⚠️ 与 `Game.Scene`（Unity 关卡）、`Game.CloverScene`（服务端场景）三者语义不同 |
| **实体** | `Game.Entity` | 实体管理 |
| **资源** | `Game.Res` | 资源管理 |
| **对象池** | `Game.Pool` | 对象池 |
| **输入** | `Game.Input`（需先 `CloverInput.Init()`） | 键鼠/手柄/触摸，后端无关 |
| **UI** | `Game.UI` | UI 管理（窗口栈 / 层级 / 遮罩） |
| **图集** | `Game.Atlas` | 图集加载/释放，Sprite 异步获取 |
| **动画** | `Game.Anim` | **仅封装 Unity `Animator`**（播放 / 交叉淡入 / 参数 / 完成回调）；**不含骨骼动画**，Spine / 龙骨由业务自接 SDK |
| **声音** | `Game.Sound` | BGM / 音效 / 人声，分组音量与静音 |
| **相机** | `Game.Camera` | 相机跟随、震屏、边界约束 |
| **画质** | `Game.Quality` | 画质档位、质量配置、帧率监控与自动降级 |
| **设备码** | `Game.DeviceId` | 设备唯一标识（跨会话稳定），用于匿名登录 / 房间寻址 |
| **事件** | `Game.Event` | 事件总线 |
| **定时器** | `Game.Timer` | 定时器 |
| **状态机** | `Game.Fsm` | 状态机 |
| **配表** | `Game.Table` | 配表管理 |
| **本地化** | `Game.Localization` | 本地化管理 |
| **主线程派发** | `Game.Dispatcher` | 主线程消息派发器 |
| **设置** | `Game.Setting` | 本地设置（**单文件 KV**） |
| **本地存档 / 槽位存储** | `CloverEngine.FileSlotStore` | **一槽一文件**的原子写 + 损坏留档 + 枚举—— "一只角色一个文件 / 一局回放一个文件 / 一章关卡草稿一个文件"用它，⛔ 别再自己写「`.tmp` + `File.Replace` + 坏文件留档 + 目录枚举」；与 `Game.Setting` **互补** |
| **日志** | `Game.Logger` | 日志 |

### 使用示例

```csharp
// 访问各模块
Game.Net.Send(EMsg.Xxx, msg);
Game.Event.On("xxx", handler);
Game.Timer.After(3f, () => { });
Game.Res.LoadAsset<GameObject>("xxx", prefab => { });
Game.Pool.Spawn("xxx");

// 推送监听：顶层便利写法与服务端 g.OnMsg 同名
Game.OnMsg(MsgDef.PushDemoBroadcast, ctx => { var n = ctx.Bind<DemoBroadcastNotify>(); });

// 请求-回包：按 requestID 配对，无需注册回调
var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, req);

// 服务端场景投影（与 Game.Scene 不同义）
Game.CloverScene.OnChanged(s => Debug.Log($"scene={s.SceneID} instance={s.InstanceID}"));
```

## 流程状态机

游戏流程（启动 → 热更检查 → 登录 → 主城 → 战斗 …）用 `Fsm` 实现；**Fsm 与 Scene 模块无内置联动**——流程推进、切场景由业务在各状态回调里自行驱动（如 `onEnter` 里调 `Game.Scene.Load`）。

```csharp
// 使用 Game.Fsm（引擎内置状态机，已预注册 Launching/Logging/MainCity/Battle 等状态）

// 注册自定义状态（也可直接使用内置状态）
Game.Fsm.RegisterState("custom_state",
    onEnter: () =>
    {
        // 进入状态逻辑
    },
    onTick: (dt) =>
    {
        // 每帧更新
    },
    onExit: () =>
    {
        // 退出状态逻辑
    }
);

// 通过触发器切换状态（需先 AddTransition）
Game.Fsm.AddTransition("MyTrigger", "custom_state");
Game.Fsm.Trigger("MyTrigger");

// 直接切换状态
Game.Fsm.Transition("custom_state");

// 给内置状态补充进入回调（与内置同名注册 = 覆盖该状态的注册信息）
Game.Fsm.RegisterState("MainCity",
    onEnter: () =>
    {
        // 进入主城（Game.Scene 随 Launch 自动挂载）
        Game.Scene.Load("MainCity");
    }
);

// 启动流程（内置初始状态名是 "Launching"；未注册的状态名只会打 Error 并原地不动）
Game.Fsm.Force("Launching");
```

## 生命周期事件

通过 `Game.Event` 发布，事件名带 `Net.` 前缀，回调均在主线程：

| 事件名 | 说明 |
|--------|------|
| `Net.OnConnected` | 连接建立 |
| `Net.OnDisconnected` | 断开，恢复可用时自动重连 |
| `Net.OnConnectFailed` | 从未连上：首次连接失败或地址非法 |
| `Net.OnKicked` | 重连次数耗尽或无恢复凭证 |
| `Net.OnResumed` | 会话已恢复，参数为回包结构 |
| `Net.OnResumeFailed` | 恢复被拒，参数为原因 |
| `Net.PlayerFullSync` | 全量同步推送，参数为解析后的字典 |
| `Net.Alert` | 公告推送（`EMsg.PushAlert`），参数为 `EAlertNotify` |
| `Net.SceneChanged` | 服务端场景标识变更，参数为 `ICloverScene` |
| `Net.QueuePosition` | 服务端排队位置变化（`EMsg.QueuePosition`），参数为 `EQueuePositionNotify`；也可读 `Game.Net.IsQueued / QueueAhead` |

> 数据同步（增量/全量）**不经事件总线**，唯一入口是 `Game.Sync.OnData` / `Game.Sync.OnFullSync`（见 [世界同步](./worldsync.md)）。

```csharp
// 监听生命周期事件（OnConnected/OnDisconnected/OnKicked 无参，用零参委托；OnResumed 带参，用显式 On<T>）
Game.Event.On("Net.OnConnected", () =>
{
    Game.Logger?.Info("Net", "已连接到服务器");
});

Game.Event.On("Net.OnDisconnected", () =>
{
    Game.Logger?.Info("Net", "连接断开，正在重连...");
});

Game.Event.On<EResumeSessionReply>("Net.OnResumed", data =>
{
    Game.Logger?.Info("Net", "会话已恢复");
});

Game.Event.On("Net.OnKicked", () =>
{
    Game.Logger?.Warn("Net", "被踢出，需要重新登录");
    // 清理本地状态，返回登录界面
});
```

## 最佳实践

> **警告：** 以下是 Game 门面使用的最佳实践：

1. **单一入口**：所有模块访问都通过 `Game` 门面
2. **初始化顺序**：先 `Game.Launch`，再使用各模块
3. **事件驱动**：通过事件监听网络状态变化
4. **流程管理**：使用 Fsm 管理游戏流程

## 常见问题

### 引擎未初始化

**症状**：`Game.XXX` 调用失败

**原因**：未调用 `Game.Launch()`

**解决**：
1. 确保在 `Start()` 中调用 `Game.Launch()`
2. 检查初始化顺序

### 模块访问失败

**症状**：`Game.Net` 等模块为 null

**原因**：初始化未完成或配置错误

**解决**：
1. 等待初始化完成
2. 检查 `GameConfig` 配置

## 下一步

1. 了解 [网络与会话](./network.md) 完整用法
2. 了解 [Event / Timer / Fsm](./event-timer-fsm.md) 详细用法

