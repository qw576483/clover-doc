## 这篇文档讲什么？

本文档列出客户端引擎必须遵守的硬约束，违反这些约束会导致功能异常或兼容性问题。所有业务代码必须遵守这些约束。

## 前置条件

- 已了解 Clover 引擎的基本架构
- 已完成客户端开发环境配置
- 已阅读客户端核心概念文档

## 网络硬约束

> **警告：**   以下是网络相关的强制性约束，违反会导致连接异常或数据丢失。

| 编号 | 约束 | 说明 | 违反后果 |
|------|------|------|----------|
| **N1** | 单一地址配置 | 单一 `addr = ip:port` 配置；启动自动连接，无手动输入 | 连接失败，无法启动 |
| **N2** | 帧格式固定 | `[4B requestID][4B msgID][body]`，requestID==0 表示推送；TCP 外加 `[1B type][4B length]`（type: 0=Data, 1=Ping, 2=Pong, 3=Migrate）、QUIC 流外加 `[4B length]`（**无 type**）防粘包；裸 UDP 首字节 0x55。**帧 / 消息大小上限三条线路统一 10 MiB**（客户端 `ClientFrame.MaxBodySize`（TCP/WS 共用帧体）、`TcpConnection.MaxFramePayload`、`WebSocketConnection.MaxMsgPayload`、`QuicConnection.MaxFrameSize`；与服务端 `max_frame_size` / `maxQUICFrameSize` 对齐），超出本地抛 `ArgumentException` 或直接断线 | 数据解析失败，通信中断 |
| **N3** | EMsg 两端一致 | 消息号由两端各自维护（服务端 `game/def/` ↔ 客户端 `Runtime/Network/EMsg.cs`（引擎段）与 `MsgDef`（业务段）），**常量名与值必须逐字一致**，禁用裸字面量 | 消息号不一致，通信失败 |
| **N4** | 会话恢复 | 重连走 session resume 不重登；次数上限 + 指数退避，超限抛事件停手 | 重复登录，数据丢失 |
| **N5** | UDP 绑定流程 | 服务端经 TCP 下发 `EMsg.UDPBindGrant` → 客户端经 UDP 上报 `EMsg.BindUDP`；每 10 秒重报绑定帧 | UDP 通信失败 |
| **N6** | 传输协议 | QUIC / WebSocket / RawUDP 为 P0 级交付（**WebTransport 未实现**，见工作区根 `客户端待做.md` #2） | 缺少传输协议支持 |
| **N7** | 证书校验 | 全场景禁止自签证书；引擎不提供跳过证书校验的开关 | 安全风险，连接失败 |
| **N8** | Keepalive 处理 | WebTransport keepalive（msgID==0 空包）直接丢弃，不进 Router | 资源浪费，性能下降 |
| **N9** | 多设备被踢 | 清理 UDP → 走 `OnKicked`，不自动重连 | 多设备冲突 |
| **N10** | 平台线路 | Standalone = QUIC → TCP + RawUDP；GL（WebGL）= **当前无可用线路**（WebSocket 与 WebTransport 均需浏览器 jslib 桥接、尚未落地，见 `客户端待做.md` #2；浏览器无 BSD socket，原生家族线路也不可用） | 平台兼容性问题 |
| **N11** | 线路 TLS | `GameConfig.UseTls` 与服务端 `gateway.tcp_tls_disabled` **必须相反**；证书只走系统信任链 | 握手失败，连上就断 |
| **N12** | 排队与通道加密 | 由引擎自动处理（`EMsg.QueuePosition` 位置帧 + 登录时自动协商 AES-GCM）；业务**不得**手填 `ELoginRequest.encrypt`，也不得自行加解密帧 | 收到密钥却解不开 / 帧被丢弃 |

### 网络约束详解

```csharp 标题：N1 - 单一地址配置
// ✅ 正确：单一地址配置
var config = new GameConfig
{
    ServerAddr = "127.0.0.1:8002",  // 单一地址
    // 启动自动连接
};

// ❌ 错误：手动输入地址
// var config = new GameConfig();
// config.AskForAddress();  // 禁止手动输入
```

```csharp 标题：N3 - EMsg 两端一致
// 用具名常量，不用裸字面量
await Game.Net.Call<ELoginReply>(EMsg.Login, loginRequest);   // 引擎内置（回包类型是 ELoginReply）
await Game.Net.Call<XxxReply>(MsgDef.Xxx, request);          // 业务：与服务端 game/def/ 同名同值
```

```csharp 标题：N4 - 会话恢复
// ✅ 正确：重连走 session resume
Game.Event.On<EResumeSessionReply>("Net.OnResumed", data =>
{
    // 引擎自动处理 session resume
    Debug.Log("已重连，会话已恢复");
});

// ❌ 错误：重连后重新登录
// Game.Event.On("Net.OnResumed", async data =>
// {
//     await Game.Net.Call<ELoginReply>(EMsg.Login, loginRequest);  // 禁止重新登录
// });
```

## 通用硬约束

> **警告：**   以下是通用的强制性约束，违反会导致功能异常或代码混乱。

| 编号 | 约束 | 说明 | 违反后果 |
|------|------|------|----------|
| **G1** | 模块封装 | 对外只暴露接口/纯数据/枚举/工厂；实现类 `internal`；工厂返回接口 | 封装破坏，维护困难 |
| **G2** | 主线程约束 | 所有业务回调（OnMsg/Timer/Event/动画事件）必须在主线程；公开 API 仅主线程可调（**引擎未内置主线程断言**，靠约定与评审保障） | 线程安全问题，崩溃 |
| **G3** | Entity 与 View | Entity 不继承 MonoBehaviour；View 异步绑定 | 架构混乱，性能问题 |
| **G4** | 客户端不权威 | 不跑权威数值逻辑；重连后以服务器快照覆盖本地 | 数据不一致，作弊漏洞 |
| **G5** | 资源池化 | 战斗内 GameObject 一律走对象池；资源一律走 Resource 模块异步加载 | 内存泄漏，性能下降 |
| **G6** | 场景管理 | 场景切换一律走 Scene 模块；业务禁止直调 Unity `SceneManager` | 场景管理混乱 |
| **G7** | 代码生成 | **配表**由打表工具生成（源表 → tsv + 代码）；消息号、动画参数常量、多语言 key 手工维护，但两端 / 多处必须一致 | 数据不一致，维护困难 |
| **G8** | 跨边界传递 | 引用类型**跨程序集**传递不得让渡可变状态：或返回**拷贝快照**，或返回**只读契约 / 不可变对象**（判据与四处复核结论见 [`clover-client-unity-engine/结构规则.md`](https://github.com/qw576483/clover-client-unity-engine/blob/main/结构规则.md) §5.3） | 外部改坏内部状态，数据竞争 |
| **G9** | 空值处理 | 返回接口的方法判 `null` 后再返回，避免 typed-null 等价问题 | 空引用异常 |
| **G10** | 注释规范 | 函数注释不写冗余函数名 | 代码冗余，维护困难 |
| **G11** | UI 数据流 | UI 只订阅数据事件，不直连网络、不改数据 | 数据流混乱，难以维护 |
| **G12** | 冻结画面的定时器 | `Time.timeScale = 0` 期间要触发的延时**必须**用 `Game.Timer.AfterUnscaled` / `EveryUnscaled`；普通 `After` / `Every` 一律不触发 | **界面永久卡死，且零报错零日志**（暂停菜单/结算屏/GameOver 常见） |
| **G13** | 资源一律经 `Game.Res` | 不许用 `Resources.Load` / `AssetBundle.*` 等**绕开资源模块**自己取资源；需要"立刻拿到"就**先 `Preload`、后 `TryGet<T>`** | 缓存 / LRU / 根前缀 / 热更后端**全部失效**，换后端时**静默不跟着变** |

### 通用约束详解

```csharp 标题：G2 - 主线程约束
public class ThreadSafeExample : MonoBehaviour
{
    // ✅ 正确：在主线程执行
    void Start()
    {
        // 所有业务回调在主线程
        Game.OnMsg(EMsg.SomeMsg, ctx =>
        {
            // 这里是主线程
            Debug.Log("主线程执行");
        });
        
        Game.Timer.After(1f, () =>
        {
            // 这里是主线程
            Debug.Log("主线程执行");
        });
        
        Game.Event.On<object>("some.event", data =>
        {
            // 这里是主线程
            Debug.Log("主线程执行");
        });
    }
    
    // ❌ 错误：在后台线程调用
    async void WrongExample()
    {
        await Task.Run(() =>
        {
            // 这里是后台线程
            Game.Net.Send(EMsg.SomeMsg, data);  // 错误！
        });
    }
    
    // ✅ 正确：切回主线程
    async void CorrectExample()
    {
        await Task.Run(() =>
        {
            // 后台线程处理
            var result = ProcessData();
            
            // 切回主线程（引擎唯一入口：Game.Dispatcher.Post）
            Game.Dispatcher.Post(() =>
            {
                Game.Net.Send(EMsg.SomeMsg, result);
            });
        });
    }
}
```

```csharp 标题：G5 - 资源池化
public class ResourcePooling : MonoBehaviour
{
    // ❌ 错误：裸 Instantiate
    public void WrongWay()
    {
        var go = Instantiate(prefab);  // 禁止！
        // 使用后直接 Destroy(go);  // 内存泄漏
    }
    
    // ✅ 正确：使用对象池
    public void CorrectWay()
    {
        var go = Game.Pool.Spawn("Prefabs/Bullet");
        // 使用后
        Game.Pool.Despawn(go);
    }
    
    // ❌ 错误：直接加载资源
    public void WrongResourceLoading()
    {
        var prefab = Resources.Load<GameObject>("Prefabs/Enemy");  // 禁止！
        Instantiate(prefab);
    }
    
    // ✅ 正确：使用 Resource 模块（回调式）
    public void CorrectResourceLoading()
    {
        Game.Res.LoadAsset<GameObject>("Prefabs/Enemy", prefab =>
        {
            var go = Game.Pool.Spawn("Prefabs/Enemy");
            // 使用后
            Game.Pool.Despawn(go);
            Game.Res.Release("Prefabs/Enemy");
        });
    }
}
```

```csharp 标题：G11 - UI 数据流
// ❌ 错误：UI 直连网络
public class WrongShopUI : MonoBehaviour
{
    void Start()
    {
        // UI 直接监听网络消息
        Game.OnMsg(EMsg.ShopInfo, ctx =>
        {
            var info = ctx.Bind<ShopInfo>();
            UpdateUI(info);  // 直接更新 UI
        });
    }
}

// ✅ 正确：UI 订阅数据事件
public class CorrectShopUI : MonoBehaviour
{
    void Start()
    {
        // UI 订阅数据事件（带参事件用显式 On<T>）
        Game.Event.On<ShopInfo>("shop.InfoChanged", info =>
        {
            UpdateUI(info);
        });
    }
}

// 数据层
public class ShopData
{
    private ShopInfo _info;
    
    public void UpdateInfo(ShopInfo newInfo)
    {
        _info = newInfo;
        
        // 触发数据事件
        Game.Event.Emit("shop.InfoChanged", _info);
    }
}
```

## 常见违规示例

> **警告：**   以下是常见的违规写法，务必避免：

```csharp 标题：违规示例集合
public class BadExamples : MonoBehaviour
{
    // ❌ 违反 G5：裸 Instantiate
    public void BadInstantiate()
    {
        var go = Instantiate(prefab);
        // 使用后忘记 Destroy，内存泄漏
    }
    
    // ❌ 违反 G6：直调 SceneManager
    public void BadSceneManager()
    {
        UnityEngine.SceneManagement.SceneManager.LoadScene("GameScene");
    }
    
    // ❌ 违反 G11：UI 直连网络
    public class BadShopUI : MonoBehaviour
    {
        void Start()
        {
            Game.OnMsg(EMsg.ShopInfo, ctx => { /* 刷新 UI */ });
        }
    }
    
    // ❌ 违反 G2：后台线程调用
    public async void BadThreadUsage()
    {
        await Task.Run(() =>
        {
            Game.Net.Send(EMsg.SomeMsg, data);  // 错误！
        });
    }
    
    // ❌ 违反 G8：跨边界传递
    public void BadBoundaryPassing()
    {
        var data = new SharedData();
        // 直接赋值让渡所有权
        otherObject.Data = data;  // 禁止！
        // 之后 data 可能被修改
    }
}
```

```csharp 标题：正确示例集合
public class GoodExamples : MonoBehaviour
{
    // ✅ 正确：使用对象池
    public void GoodInstantiate()
    {
        var go = Game.Pool.Spawn("Prefabs/Bullet");
        // 使用后
        Game.Pool.Despawn(go);
    }
    
    // ✅ 正确：使用 Game.Scene（随 Launch 自动挂载）
    public void GoodSceneManager()
    {
        Game.Scene.Load("GameScene");
    }
    
    // ✅ 正确：UI 订阅数据事件
    public class GoodShopUI : MonoBehaviour
    {
        void Start()
        {
            Game.Event.On<object>("shop.InfoChanged", data => { /* 刷新 UI */ });
        }
    }
    
    // ✅ 正确：主线程调用
    public async void GoodThreadUsage()
    {
        await Task.Run(() =>
        {
            // 后台处理
            var result = ProcessData();
            
            // 切回主线程（引擎唯一入口：Game.Dispatcher.Post）
            Game.Dispatcher.Post(() =>
            {
                Game.Net.Send(EMsg.SomeMsg, result);
            });
        });
    }
    
    // ✅ 正确：跨边界传递
    public void GoodBoundaryPassing()
    {
        var data = new SharedData();
        // 必须新建实例（拷贝构造），不能让对方直接持有你的对象
        otherObject.Data = new SharedData(data);
    }
}
```

## 约定：处理器内禁止阻塞（业务侧）

`OnMsg` / `Timer` / `Event` / 动画事件回调**全部运行在主线程**（G2），因此处理器里**任何阻塞都会卡住整帧**：
`Thread.Sleep`、同步等待（`Wait()` / `.Result`）、同步文件或网络 IO、大循环、逐帧同步加载资源。

正确做法：

| 你要做的事 | 不要 | 应该 |
|---|---|---|
| 等一段时间 / 等条件 | 原地阻塞等 | `Game.Timer.After` / `Game.Timer.AfterUnscaled`（后者用于 `timeScale=0`，G12）或状态机推进 |
| 一段重计算 | 在主线程硬算 | 后台线程算完，**回主线程**（G2）抛结果事件 |
| 加载资源 | 同步 `Load` | `Game.Res` 异步加载（G5） |
| 等网络回包 | 处理器里等回包 | 一律走消息，回包在另一个 `OnMsg` 里处理 |

> 这是**约定**（不占 G 编号）："公开 API 仅主线程可调"与"处理器里别阻塞"一样靠**约定 + 评审**保障
> （**引擎未内置主线程断言**）—— 违反后的表现是掉帧、卡死、被系统判无响应（或线程安全问题），而不是自解释的报错。

## 约束检查清单

### 开发前检查

- [ ] 业务消息号是否与服务端 `game/def/` 同名同值？
- [ ] 是否在主线程调用 API？
- [ ] 处理器（`OnMsg` / `Timer` / `Event`）里是否有阻塞操作？
- [ ] 是否使用对象池管理 GameObject？
- [ ] 是否使用 Scene 模块管理场景？
- [ ] UI 是否只订阅数据事件？

### 代码审查检查

- [ ] 是否有裸 `Instantiate` 调用？
- [ ] 是否有直调 `SceneManager`？
- [ ] 是否有后台线程调用引擎 API？
- [ ] 是否有 UI 直连网络？
- [ ] 是否有 `Thread.Sleep` / 同步等待 / 同步 IO 出现在业务回调里？
- [ ] 跨程序集返回的可变对象，是否已改为**只读契约**或**拷贝快照**？（G8，判据见 `结构规则.md` §5.3）

### 性能检查

- [ ] 是否频繁创建销毁 GameObject？
- [ ] 是否有内存泄漏（未释放资源）？
- [ ] 是否有线程安全问题？
- [ ] 是否有不必要的主线程阻塞？

## 下一步

-   了解约束背后的设计理念
-   了解模块划分和依赖关系