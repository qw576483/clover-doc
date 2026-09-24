## 这篇文档讲什么？

本文档提供客户端引擎核心 API 的快速参考，帮助开发者快速查找和使用 API。文档按照模块组织，包含完整的参数说明和代码示例。

## 前置条件

- 已了解 Clover 引擎的基本架构
- 已完成客户端开发环境配置
- 已阅读客户端核心概念文档

## Game 门面

`Game` 是客户端引擎的唯一入口，业务代码只通过 `Game` 访问各模块。

### 核心属性

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.Launch(config)` | `GameConfig` | `void` | 初始化核心子系统（日志/事件/定时器等），不联网、不登录 | 应用启动时调用一次 |
| `Game.IsRunning` | - | `bool` | 引擎是否已启动 | 检查引擎状态 |
| `Game.Net` | - | `INetwork` | 网络模块入口 | 所有网络操作 |
| `Game.Http` | - | `IWebRequest` | HTTP 模块入口 | HTTP 请求 |
| `Game.Sync` | - | `IWorldSync` | 世界同步 / 数据订阅唯一入口（`OnData` / `OnFullSync` / 实体事件，每个 `On*` 有配对 `Off*`） | 多人同步 |
| `Game.Schema` | - | `ISchemaRegistry` | 数据 Schema 声明入口（**不做订阅**，数据订阅走 `Game.Sync`） | 登记字段结构 |
| `Game.Alert` | - | `IAlert` | 公告推送入口 | 服务端公告分发 |
| `Game.CloverScene` | - | `ICloverScene` | 服务端场景投影入口（逻辑地图 + 分线） | 场景归属、关卡映射 |
| `Game.Map` | - | `IMapData` | 逻辑地图入口：服务端权威地图在客户端的只读投影（`Load` / `LoadFromResource` / `WalkableAt`）。**只回答空间事实**，不含本地预测解算 | 本地碰撞 / 寻路查询 |
| `Game.FrameRoom` | - | `IFrameRoom` | 帧同步房间入口（消息号需 `Configure()` 注入） | 帧同步玩法 |
| `Game.Entity` | - | `IEntityManager` | 实体管理入口 | 实体创建销毁 |
| `Game.Res` | - | `IResourceManager` | 资源管理入口 | 资源加载 |
| `Game.Pool` | - | `IObjectPool` | 对象池入口 | 对象复用 |
| `Game.Input` | - | `IInputManager` | 输入模块入口（需先 `CloverInput.Init()`） | 键鼠/手柄/触摸读取 |
| `Game.Event` | - | `IEventBus` | 事件总线入口 | 模块间通信 |
| `Game.Timer` | - | `ITimer` | 定时器入口 | 延迟/循环任务 |
| `Game.Fsm` | - | `IFsm` | 状态机入口 | 状态管理 |
| `Game.Table` | - | `IDataTable` | 配表管理入口 | 配置表读取 |
| `Game.Setting` | - | `ISetting` | 本地设置入口 | 配置存储 |
| `Game.Localization` | - | `ILocalization` | 多语言入口 | 国际化 |
| `Game.Logger` | - | `ILogger` | 日志入口 | 日志输出 |
| `Game.UI` | - | `IUIManager` | UI 管理入口 | 界面打开/关闭 |
| `Game.Scene` | - | `ISceneManager` | Unity 关卡管理入口 | 加载/切换场景 |
| `Game.Atlas` | - | `ISpriteAtlasManager` | SpriteAtlas 管理入口 | 图集加载/释放 |
| `Game.Anim` | - | `IAnimationManager` | 动画管理入口 | 动画播放控制 |
| `Game.Sound` | - | `ISoundManager` | 音效管理入口 | 音效播放/停止 |
| `Game.Camera` | - | `ICameraManager` | 相机管理入口 | 相机切换/控制 |
| `Game.Quality` | - | `IQualityManager` | 画质/性能入口 | 画质档位、帧率监控 |
| `Game.DeviceId` | - | `IDeviceIdProvider` | 设备唯一标识入口 | 匿名登录、房间寻址 |

### 使用示例

```csharp 标题：初始化引擎
using CloverEngine;

public class GameStartup : MonoBehaviour
{
    void Awake()
    {
        // 配置引擎
        var config = new GameConfig
        {
            ServerAddr = "127.0.0.1:8002",      // 服务器地址
            MaxReconnectCount = 5,              // 最大重连次数
            CallTimeoutSeconds = 10,             // 请求超时（秒）
        };
        
        // 启动引擎
        Game.Launch(config);
        
        Debug.Log("引擎启动完成");
    }
    
    void Update()
    {
        // 检查引擎状态
        if (Game.IsRunning)
        {
            // 引擎运行中，执行业务逻辑
        }
    }
}
```

```csharp 标题：访问各模块
public class ModuleAccessExample : MonoBehaviour
{
    void Start()
    {
        // 网络模块（全量同步推送走 Game.Sync；引擎推送号在保留段、不可经 Game.OnMsg 注册）
        Game.Sync.OnFullSync((data, accountData) =>
        {
            Debug.Log("收到玩家全量同步");
        });
        
        // 事件总线（带参事件必须显式 On<T>，不能靠隐式推断）
        Game.Event.On<object>("player.LevelUp", data =>
        {
            Debug.Log("玩家升级");
        });
        
        // 定时器
        Game.Timer.After(3f, () =>
        {
            Debug.Log("3秒后执行");
        });
    }
}
```

## 网络模块

### 核心 API

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.OnMsg(msgID, handler)` | `uint, MsgHandler` | `void` | 注册消息监听（**唯一入口**，与服务端 `g.OnMsg` 同名） | 监听服务器推送 |
| `Game.OffMsg(msgID)` | `uint` | `void` | 注销该消息号的全部处理器 | 停止监听 |
| `Game.OffMsg(msgID, handler)` | `uint, MsgHandler` | `void` | 注销指定处理器 | 精确移除 |
| `Game.Net.Send(msgID, body)` | `uint, object` | `void` | 可靠发送（TCP） | 重要消息发送 |
| `Game.Net.SendUnreliable(msgID, body)` | `uint, object` | `void` | 非可靠发送（UDP 优先） | 高频位置同步 |
| `Game.Net.Call<T>(msgID, body)` | `uint, object` | `Task<T>` | 请求-回包（async），超时默认 10s。⛔ 泛型约束 **`where T : class`** —— `Call<SomeStruct>(...)` 编译不过，回复体必须是**类** | 需要回复的请求 |
| `Game.Net.IsQueued` / `QueueAhead` / `QueueTotal` | - | `bool` / `int` / `int` | 是否在服务端等候队列中、「前面还有多少人」、队列总人数（来自 `EMsg.QueuePosition`） | 排队等待界面 |
| `Game.Net.IsChannelEncrypted` | - | `bool` | 本次连接是否已启用会话通道加密（AES-256-GCM，引擎自动协商） | 排查 / 状态展示 |

### 参数说明

**`Game.OnMsg`**
- `msgID`: 消息号（`uint`，EMsg 枚举值）
- `handler`: 回调函数，参数为 `NetCtx`
- 返回值: `void`，通过 `OffMsg(msgID)` 取消监听

**`Game.Net.Send`**
- `msgID`: 消息号（EMsg 枚举值）
- `body`: 消息体对象，会被序列化为 JSON
- 特点: 可靠传输，保证顺序

**`Game.Net.SendUnreliable`**
- `msgID`: 消息号（EMsg 枚举值）
- `body`: 消息体对象，会被序列化为 JSON
- 特点: 非可靠传输，可能丢包，适合高频数据

**`Game.Net.Call<T>`**
- `T`: 回包类型
- `msgID`: 请求消息号
- `body`: 请求体对象
- 返回值: `Task<T>`，异步等待回包
- 异常: `CloverCallException`，含 `ServerError`（描述）与 `Code`（机器可读错误码，见 `ErrCode`）

### 使用示例

```csharp 标题：注册推送监听
public class NetworkListener : MonoBehaviour
{
    private Action<Dictionary<string, Dictionary<string, object>>, Dictionary<string, object>> _onFullSync;

    void Start()
    {
        // 注册推送监听（玩家全量同步推送；引擎推送号在保留段、不可经 Game.OnMsg 注册）
        _onFullSync = (data, accountData) =>
        {
            Game.Logger.Info("Net", $"收到全量同步：{data.Count} 个分组");
        };
        Game.Sync.OnFullSync(_onFullSync);
    }
    
    void OnDestroy()
    {
        // 取消监听（注销需传注册时的同一委托引用）
        Game.Sync.OffFullSync(_onFullSync);
    }
}
```

```csharp 标题：发送可靠消息
public class ChatManager : MonoBehaviour
{
    public void SendChatMessage(string content)
    {
        // 创建消息体
        var message = new ChatMessage
        {
            Content = content,
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            TargetPlayerID = 0, // 0 表示全体
        };
        
        // 可靠发送（业务消息号放 MsgDef，不要混进 EMsg）
        Game.Net.Send(MsgDef.ChatMessage, message);
        
        Debug.Log("消息已发送");
    }
}
```

```csharp 标题：发送非可靠消息
public class PositionSync : MonoBehaviour
{
    void Update()
    {
        // 每帧同步位置（非可靠）
        var positionData = new PositionData
        {
            X = transform.position.x,
            Y = transform.position.y,
            Z = transform.position.z,
            Rotation = transform.eulerAngles.y,
            Timestamp = Time.time,
        };
        
        Game.Net.SendUnreliable(MsgDef.PositionSync, positionData);
    }
}
```

```csharp 标题：请求-回包
public class ShopUI : MonoBehaviour
{
    public async void BuyItem(int itemID, int count)
    {
        try
        {
            // 发送请求，等待回复
            var reply = await Game.Net.Call<ShopBuyReply>(
                MsgDef.ShopBuy, 
                new ShopBuyRequest
                {
                    ItemID = itemID,
                    Count = count,
                }
            );
            
            // 处理回复
            Debug.Log($"购买成功! 订单号: {reply.OrderID}");
            Debug.Log($"剩余金币: {reply.GoldRemaining}");
            
            // 更新 UI
            UpdateGoldDisplay(reply.GoldRemaining);
        }
        catch (CloverCallException ex)
        {
            // ex.ServerError = 人类可读描述；ex.Code = 机器可读错误码（见 ErrCode）。
            // 按码分支，不要匹配文案——文案会变，码不会。
            Debug.LogError($"购买失败: {ex.ServerError} (code={ex.Code})");

            switch (ex.Code)
            {
                case ErrCode.Unauthenticated: BackToLogin();               break;  // 回到登录流程
                case ErrCode.Forbidden:       ShowErrorUI(ex.ServerError); break;  // 无权限
                default:                      ShowErrorUI(ex.ServerError); break;
            }
        }
    }
}
```

## Event 事件总线

### 核心 API

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.Event.On(event, handler)` | `string, Action` | `void` | 注册监听（等价 `OnPriority` 的 priority = 0） | 监听事件 |
| `Game.Event.On<T>(event, handler)` | `string, Action<T>` | `void` | 注册类型化监听 | 类型安全监听 |
| `Game.Event.OnPriority(event, priority, handler)` | `string, int, Action` | `void` | 按优先级注册：**priority 越大越先执行**；同优先级内后注册先执行 | 表达执行顺序依赖 |
| `Game.Event.Emit(event)` | `string` | `void` | 发射事件 | 触发事件 |
| `Game.Event.Emit<T>(event, data)` | `string, T` | `void` | 发射类型化事件 | 触发带数据事件 |
| `Game.Event.Off(event, handler)` | `string, Action` | `void` | 取消监听（一次注销干净） | 手动取消监听 |
| `Game.Event.OffAll(event)` | `string` | `void` | 移除该事件的所有监听器 | 批量注销 |
| `Game.Event.OffAll()` | - | `void` | 移除所有事件的所有监听器 | 切场景/拆卸 |
| `Game.Event.Once(event, handler)` | `string, Action` | `void` | 注册一次性监听 | 只触发一次 |

### 参数说明

**`Game.Event.On`**
- `event`: 事件名（精确匹配；也可用 `*` / `**` **通配订阅**——以 `.` 分段，`*` 匹配恰好一段、`**` 匹配一段或多段，如 `Net.*` / `Net.**`）
- `handler`: 回调函数
- 返回值: `void`，需保存 handler 引用，通过 `Off` 取消监听
- 配对与分发语义：同一 handler 重复注册会被**忽略并告警**（一次 `Off` 即注销干净）；
  **分发顺序为精确匹配先、通配订阅后**；`Emit` 分发期间调用 `Off` / `OffAll` **即时生效**（被注销者本帧不再触发）

**`Game.Event.Emit`**
- `event`: 事件名
- `data`: 事件数据，可以是任意对象

### 使用示例

```csharp 标题：注册和触发事件
public class EventSystem : MonoBehaviour
{
    // 保存 handler 引用以便后续 Off
    private Action<LevelUpData> _onLevelUp;

    void Start()
    {
        // 类型化监听
        _onLevelUp = data =>
        {
            Debug.Log($"玩家升级! 新等级: {data.NewLevel}");
            UpdateLevelUI(data.NewLevel);
            PlayLevelUpSound();
        };
        Game.Event.On("player.LevelUp", _onLevelUp);
    }

    // 触发事件
    public void TriggerLevelUp(int newLevel)
    {
        Game.Event.Emit("player.LevelUp", new LevelUpData
        {
            NewLevel = newLevel,
            OldLevel = newLevel - 1,
            Experience = CalculateExperience(newLevel),
        });
    }

    void OnDestroy()
    {
        // 取消监听
        Game.Event.Off("player.LevelUp", _onLevelUp);
    }
}
```

```csharp 标题：事件管理
public class EventManager : MonoBehaviour
{
    // 保存 handler 引用
    private Action _onBuySuccess;
    private Action _onBuyFailed;
    private Action<ShopInfo> _onShopInfoChanged;

    void Start()
    {
        _onBuySuccess = () => { /* ... */ };
        _onBuyFailed = () => { /* ... */ };
        _onShopInfoChanged = info => { /* ... */ };

        Game.Event.On("shop.BuySuccess", _onBuySuccess);
        Game.Event.On("shop.BuyFailed", _onBuyFailed);
        Game.Event.On("shop.InfoChanged", _onShopInfoChanged);
    }

    void OnDestroy()
    {
        Game.Event.Off("shop.BuySuccess", _onBuySuccess);
        Game.Event.Off("shop.BuyFailed", _onBuyFailed);
        Game.Event.Off("shop.InfoChanged", _onShopInfoChanged);
    }
}
```

## Timer 定时器

### 核心 API

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.Timer.After(seconds, action)` | `float, Action` | `long` | 延迟执行，返回定时器 ID | 延迟任务 |
| `Game.Timer.Every(seconds, action)` | `float, Action` | `long` | 循环执行，返回定时器 ID | 循环任务 |
| `Game.Timer.AfterName(name, seconds, action)` | `string, float, Action` | `long` | 命名延迟 | 可取消的延迟任务 |
| `Game.Timer.EveryName(name, seconds, action)` | `string, float, Action` | `long` | 命名循环 | 可取消的循环任务 |
| `Game.Timer.After(seconds, action, scope)` | `float, Action, string` | `long` | 延迟执行（带作用域） | 作用域内延迟任务 |
| `Game.Timer.Every(seconds, action, scope)` | `float, Action, string` | `long` | 循环执行（带作用域） | 作用域内循环任务 |
| `Game.Timer.Stop(id)` | `long` | `void` | 按 ID 停止单个定时器（`After` / `Every` 等的返回值） | 取消单个定时器 |
| `Game.Timer.StopNamed(name)` | `string` | `void` | 按名称停止定时器 | 取消特定任务 |
| `Game.Timer.StopScope(scope)` | `string` | `void` | 停止作用域内定时器 | 批量取消任务 |
| `Game.Timer.StopAll()` | - | `void` | 停止所有 | 清理所有定时器 |
| `Game.Timer.AfterUnscaled(seconds, action)` | `float, Action` | `long` | 延迟执行，**按真实时间推进**（`timeScale = 0` 也触发） | 暂停/结算/GameOver 屏里的延时 |
| `Game.Timer.EveryUnscaled(seconds, action)` | `float, Action` | `long` | 循环执行，按真实时间推进 | 冻结画面里的循环任务 |

### 参数说明

**`Game.Timer.After`**
- `seconds`: 延迟秒数
- `action`: 延迟后执行的回调
- 返回值: `long` 定时器 ID，可用于 `Stop(id)` 取消

**`Game.Timer.Every`**
- `seconds`: 循环间隔秒数
- `action`: 每次循环执行的回调
- 返回值: `long` 定时器 ID，可用于 `Stop(id)` 取消

**`Game.Timer.AfterName` / `EveryName`**
- `name`: 定时器名称，用于后续停止
- `seconds`: 延迟/间隔秒数
- `action`: 回调函数

**`Game.Timer.After` / `Every`（带 scope 重载）**
- `scope`: 作用域字符串名称，用于批量停止

### 使用示例

```csharp 标题：基本定时器使用
public class TimerExample : MonoBehaviour
{
    void Start()
    {
        // 延迟执行
        Game.Timer.After(3f, () =>
        {
            Debug.Log("3秒后执行");
            // 延迟后显示 UI
            ShowDelayedUI();
        });
        
        // 循环执行
        Game.Timer.Every(1f, () =>
        {
            Debug.Log("每秒执行");
            // 每秒检查一次状态
            CheckGameStatus();
        });
        
        // 命名定时器（可取消）
        Game.Timer.AfterName("buff_poison", 5f, () =>
        {
            Debug.Log("毒素效果结束");
            // 移除毒素效果
            RemovePoisonEffect();
        });
        
        // 停止命名定时器
        Game.Timer.StopNamed("buff_poison");
        
        // 循环定时器
        Game.Timer.EveryName("heartbeat", 10f, () =>
        {
            Debug.Log("心跳检测");
            // 发送心跳包
            SendHeartbeat();
        });
    }
}
```

```csharp 标题：作用域管理
public class SceneManager : MonoBehaviour
{
    private const string SceneScope = "game_scene";
    
    void OnEnable()
    {
        // 场景内定时器（通过 scope 参数归属作用域）
        Game.Timer.Every(0.1f, () =>
        {
            // 场景内每0.1秒执行
            UpdateSceneObjects();
        }, SceneScope);
        
        Game.Timer.AfterName("scene_load", 5f, () =>
        {
            Debug.Log("场景加载完成");
        });
    }
    
    void OnDisable()
    {
        // 离开场景，停止该作用域内所有定时器
        Game.Timer.StopScope(SceneScope);
    }
}
```

## Fsm 有限状态机

### 核心 API

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `fsm.RegisterState(name, onEnter, onTick, onExit)` | `string, Action, Action<float>, Action` | `void` | 注册状态 | 定义状态 |
| `fsm.Transition(toState)` | `string` | `void` | 转换到目标状态 | 手动转换 |
| `fsm.AddTransition(trigger, toState)` | `string, string` | `void` | 注册触发器→目标状态映射 | 条件转换 |
| `fsm.Trigger(trigger)` | `string` | `void` | 触发转换 | 条件转换 |
| `fsm.Force(state)` | `string` | `void` | 强制进入状态 | 强制切换 |
| `fsm.Tick(dt)` | `float` | `void` | 每帧驱动 | 状态更新 |
| `fsm.OnChange(handler)` | `Action<string, string>` | `void` | 注册状态变化回调 | 监听变化 |
| `fsm.OffChange(handler)` | `Action<string, string>` | `void` | 移除状态变化回调 | 取消监听 |
| `fsm.Reset()` | - | `void` | 恢复到「未初始化」：清空状态表 / 触发器表 / `Current`（**不销毁实例**、**不触发** OnExit / OnEnter / OnChange、**保留** `OnChange` 订阅表）；可重复调用 | 每回合重开 / 对象池复用 |
| `Game.NewFsm()` | - | `IFsm` | 取一棵**独立**状态机（每次新实例，绝不返回 `Game.Fsm`）；**`Game.Tick` 不驱动它**，谁创建谁 `Tick(dt)` | 每个 Bot / 单位一棵局部状态机 |
| `fsm.Current` | - | `string` | 获取当前状态名称 | 查询状态 |

### 参数说明

**`fsm.RegisterState`**
- `name`: 状态名称
- `onEnter`: 进入状态时的回调
- `onTick`: 每帧更新的回调（参数为 `float dt`）
- `onExit`: 退出状态时的回调

**`fsm.Transition`**
- `toState`: 目标状态名称

**`fsm.AddTransition`**
- `trigger`: 触发器名称
- `toState`: 目标状态名称（隐含从当前状态转换）

**`fsm.Trigger`**
- `trigger`: 触发器名称

**`fsm.OffChange`**
- `handler`: 要移除的状态变更回调（需传入同一 handler 引用）

**`fsm.Current`**
- 只读属性，返回当前状态名称（未设置状态时返回 null）

### 使用示例

```csharp 标题：状态机基础用法
public class CharacterFSM : MonoBehaviour
{
    void Start()
    {
        // 使用引擎内置状态机（Game.Fsm）
        
        // 注册状态
        Game.Fsm.RegisterState("idle",
            onEnter: () => Debug.Log("进入空闲状态"),
            onTick: dt =>
            {
                // 空闲逻辑：检测输入（必须走 Game.Input，禁止直连 UnityEngine.Input）
                if (Game.Input.GetKeyDown(GameKey.Space))
                {
                    Game.Fsm.Trigger("start_jump");
                }
            },
            onExit: () => Debug.Log("退出空闲状态")
        );
        
        Game.Fsm.RegisterState("jumping",
            onEnter: () => 
            {
                Debug.Log("进入跳跃状态");
                // 执行跳跃动画
                GetComponent<Animator>().SetTrigger("Jump");
            },
            onTick: dt =>
            {
                // 跳跃逻辑
                if (IsGrounded())
                {
                    Game.Fsm.Trigger("land");
                }
            },
            onExit: () => Debug.Log("退出跳跃状态")
        );
        
        // 注册触发器（trigger → toState，隐含从当前状态转换）
        Game.Fsm.AddTransition("start_jump", "jumping");
        Game.Fsm.AddTransition("land", "idle");
        
        // 监听状态变化
        Game.Fsm.OnChange((from, to) =>
        {
            Debug.Log($"状态变化: {from} -> {to}");
            // 更新 UI 显示
            UpdateStateUI(to);
        });
        
        // 强制进入初始状态
        Game.Fsm.Force("idle");
    }
    
    // 注意：`Game.Fsm` 已由 `Game.Tick` 每帧统一驱动，业务无需（也不要）自己调 `Tick`
}
```

> ⚠️ 每个 AI / 单位一棵状态机请用 `Game.NewFsm()`（独立实例，自己按帧 `Tick`）；
> 「注册到 `Game.Fsm` + 状态名加前缀隔离」是**旧绕法**（多实体共用同一个 `Current`，同名状态重复注册还会告警并整体替换回调）。
> 下面这段保留作为对照。

```csharp 标题：AI 状态机示例（旧绕法：Game.Fsm + 状态名加前缀隔离）
public class AIController : MonoBehaviour
{
    private string _prefix; // 用前缀隔离不同 AI 的状态
    
    void Start()
    {
        _prefix = gameObject.GetInstanceID() + "_";
        
        // 巡逻状态
        Game.Fsm.RegisterState(_prefix + "patrol",
            onEnter: () =>
            {
                Debug.Log("开始巡逻");
                SetRandomPatrolPoint();
            },
            onTick: dt =>
            {
                MoveToTarget(patrolPoint);
                if (DetectPlayer())
                {
                    Game.Fsm.Trigger(_prefix + "player_detected");
                }
            }
        );
        
        // 追击状态
        Game.Fsm.RegisterState(_prefix + "chase",
            onEnter: () =>
            {
                Debug.Log("发现玩家，开始追击");
                SetAnimation("Run");
            },
            onTick: dt =>
            {
                MoveToTarget(player.transform.position);
                if (IsInAttackRange())
                {
                    Game.Fsm.Trigger(_prefix + "attack_range");
                }
                if (!DetectPlayer())
                {
                    Game.Fsm.Trigger(_prefix + "player_lost");
                }
            }
        );
        
        // 攻击状态
        Game.Fsm.RegisterState(_prefix + "attack",
            onEnter: () =>
            {
                Debug.Log("进入攻击状态");
                StartCoroutine(AttackCoroutine());
            }
        );
        
        // 注册触发器
        Game.Fsm.AddTransition(_prefix + "player_detected", _prefix + "chase");
        Game.Fsm.AddTransition(_prefix + "attack_range", _prefix + "attack");
        Game.Fsm.AddTransition(_prefix + "player_lost", _prefix + "patrol");
        Game.Fsm.AddTransition(_prefix + "attack_done", _prefix + "chase");
        
        // 开始巡逻
        Game.Fsm.Force(_prefix + "patrol");
    }
    
    private IEnumerator AttackCoroutine()
    {
        yield return new WaitForSeconds(0.5f);
        DealDamage();
        yield return new WaitForSeconds(1f);
        Game.Fsm.Trigger(_prefix + "attack_done");
    }
}
```

## Resource 资源管理

### 核心 API

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.Res.LoadAsset<T>(path, callback)` | `string, Action<T>` | `void` | 异步加载资源（回调式） | 加载预制体、材质等 |
| `Game.Res.LoadAsset<T>(path, progress, callback)` | `string, Action<float>, Action<T>` | `void` | 异步加载资源（带进度） | 大资源加载 |
| `Game.Res.Release(path)` | `string` | `void` | 释放资源引用计数 | 释放不再使用的资源 |
| `Game.Res.Preload(paths, onDone, progress)` | `List<string>, Action, Action<float>` | `void` | 批量预加载 | 场景切换前预加载 |
| `Game.Res.UnloadAll()` | - | `void` | 卸载所有资源 | 清理所有缓存 |
| `Game.Res.TryGet<T>(path)` | `string` | `T` | **同步**取已驻留资源（不触发加载、不阻塞） | 配合 `Preload` 拿"必须立刻要"的资源 |
| `Game.Res.Exists(path)` | `string` | `bool` | **同步**回答"这条路径在不在"（不驻留、不动引用计数；Resources 后端探测一次并按路径缓存） | 决定"占位色 / 缺失分支"，避免 `Image` 停在初始白 |
| `Game.Res.LoadAll<T>(path)` | `string` | `T[]` | **同步批量取**该路径下全部资源（**会加载**；不进缓存/引用计数，⛔ 不要 `Release`） | 条带 / 图集**整条取**（子 sprite 按名取不到时）；后端不支持 ⇒ 空数组 + Warn |


### 参数说明

**`Game.Res.LoadAsset<T>`**
- `T`: 资源类型（`GameObject`, `Material`, `Sprite` 等）
- `path`: 资源路径（相对于 Resources 文件夹）
- `callback`: 加载完成回调
- `progress`: 进度回调（可选）
- 注意: 资源使用完毕后必须调用 Release

**`Game.Res.Release`**
- `path`: 资源路径（与加载时使用的路径一致）
- 注意: 只减少引用计数、**不立即释放**；缓存淘汰由内存水位 + LRU 决定（加载在途时该调用会被忽略）

### 使用示例

```csharp 标题：异步加载资源（回调式）
public class ResourceLoader : MonoBehaviour
{
    void Start()
    {
        // 异步加载预制体（回调式）
        Game.Res.LoadAsset<GameObject>("Prefabs/Enemy", prefab =>
        {
            if (prefab != null)
            {
                Debug.Log("资源加载完成");
                var instance = Instantiate(prefab);
                instance.transform.position = new Vector3(0, 0, 0);
            }
        });
    }
    
    void OnDestroy()
    {
        // 释放资源引用
        Game.Res.Release("Prefabs/Enemy");
    }
}
```

```csharp 标题：资源管理器
public class ResourceManager : MonoBehaviour
{
    private Dictionary<string, GameObject> _cache = new Dictionary<string, GameObject>();
    
    public void GetAsset(string key, Action<GameObject> callback)
    {
        // 检查缓存
        if (_cache.TryGetValue(key, out var cached))
        {
            callback?.Invoke(cached);
            return;
        }
        
        // 异步加载资源（回调式）
        Game.Res.LoadAsset<GameObject>(key, asset =>
        {
            if (asset != null)
            {
                _cache[key] = asset;
            }
            callback?.Invoke(asset);
        });
    }
    
    public void ReleaseAll()
    {
        // 释放所有缓存资源
        foreach (var key in _cache.Keys)
        {
            Game.Res.Release(key);
        }
        _cache.Clear();
    }
}
```

## ObjectPool 对象池

### 核心 API

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.Pool.Spawn(key)` | `string` | `GameObject` | 获取实例 | 创建游戏对象 |
| `Game.Pool.Despawn(go)` | `GameObject` | `void` | 归还实例 | 回收游戏对象 |
| `Game.Pool.Preload(key, count)` | `string, int` | `void` | 预加载 | 场景加载前预热 |
| `Game.Pool.Clear(key)` | `string` | `void` | 清空指定池 | 回收单类对象 |
| `Game.Pool.ClearAll()` | - | `void` | 清空所有池 | 场景切换 |
| `Game.Pool.ClearGroup(group)` | `string` | `void` | 清除指定场景组的所有池 | 按组回收 |
| `Game.Pool.GetActiveCount(key)` / `GetInactiveCount(key)` | `string` | `int` | 活跃 / 非活跃实例数 | 排障 / 监控 |
| `Game.Pool.IdleExpirySeconds` | `float`（属性） | `float` | **空闲过期回收**阈值（秒）：>0 时闲置超时的非活跃对象在下次 `Spawn` / `Despawn` 被销毁；**默认 `0` = 关闭**（负数按 0 处理） | 峰值后回收长期闲置实例 |
| `Game.Pool.TrimIdle()` | - | `void` | 立即按 `IdleExpirySeconds` 清理一次全部池的空闲对象（阈值为 0 时无操作） | 切场景前手动收紧内存 |

### 参数说明

**`Game.Pool.Spawn`**
- `key`: 对象池键名（对应预制体路径）
- 返回值: `GameObject`，可直接使用
- 特点: 自动 `SetActive(true)`；**没有 `OnSpawn` 回调**，取出后的初始化由业务自己调

**`Game.Pool.Despawn`**
- `go`: 要归还的游戏对象
- 特点: 自动 `SetActive(false)` 并挂回池根，归还到对象池；**没有 `OnDespawn` 回调**

**`Game.Pool.Preload`**
- `key`: 对象池键名
- `count`: 预加载数量

**`Game.Pool.Clear`**
- `key`: 要清空的对象池键名

**`Game.Pool.IdleExpirySeconds` / `Game.Pool.TrimIdle()`**
- `IdleExpirySeconds`: 空闲过期回收阈值（秒），**默认 `0` = 关闭**（只按容量上限裁剪）；回收在**主线程**的池操作里惰性执行，不引入额外 Tick
- `TrimIdle()`: 立即清理一次全部池的空闲对象（阈值为 0 时无操作），用于切场景前手动收紧内存

### 使用示例

```csharp 标题：对象池基础用法
public class BulletManager : MonoBehaviour
{
    public void Fire(Vector3 position, Vector3 direction)
    {
        // 从对象池获取子弹
        var bullet = Game.Pool.Spawn("Prefabs/Bullet");
        
        // 设置位置和方向
        bullet.transform.position = position;
        bullet.transform.forward = direction;
        
        // 初始化子弹组件
        var bulletScript = bullet.GetComponent<Bullet>();
        bulletScript.Initialize(direction, 10f, 1f);
    }
    
    public void ReturnBullet(GameObject bullet)
    {
        // 归还到对象池
        Game.Pool.Despawn(bullet);
    }
}
```

```csharp 标题：取出后自行初始化（对象池没有 OnSpawn / OnDespawn 回调）
public class PooledObject : MonoBehaviour
{
    // 引擎不会自动调用任何 OnSpawn / OnDespawn：
    // 取出后的初始化由取出方显式调用，归还前的清理由归还方处理。
    public void OnTaken()
    {
        // 重置状态
        gameObject.SetActive(true);
        GetComponent<Rigidbody>().velocity = Vector3.zero;
        GetComponent<Collider>().enabled = true;
    }
    
    public void OnReturned()
    {
        // 清理状态
        gameObject.SetActive(false);
        GetComponent<Collider>().enabled = false;
    }
    
    void OnCollisionEnter(Collision collision)
    {
        // 碰撞后归还到对象池
        if (collision.gameObject.tag == "Wall")
        {
            OnReturned();                       // 归还前先清理（引擎不会自动做）
            Game.Pool.Despawn(gameObject);
        }
    }
}
```

### ReferencePool 引用池（纯 C# 对象）

`Game.Pool` 管 `GameObject`；**普通托管对象**（每帧产生的输入帧、事件参数、临时 List 等）用 `ReferencePool`：

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `ReferencePool.Acquire<T>()` | - | `T` | 取一个实例（池空则 `new`）。⛔ 约束是 **`where T : class, new()`** —— 必须是**引用类型**且有无参构造函数（`Acquire<SomeStruct>` 编译不过） | 复用短命对象、降低 GC |
| `ReferencePool.Release<T>(item)` | `T` | `void` | 归还实例（传 `null` 静默忽略；同一实例重复归还被忽略并告警） | 用完归还 |
| `ReferencePool.Count<T>()` | - | `int` | 当前池中的空闲实例数 | 调试 / 测试 |
| `ReferencePool.Clear<T>()` | - | `void` | 清空该类型的池 | 单类清理 |
| `ReferencePool.ClearAll()` | - | `void` | 清空全部类型的池 | 切场景 / 引擎拆卸 |

> 对象实现 `IReferencePoolable`（`OnAcquire` / `OnRelease`）时，取出 / 归还会**自动回调**复位；
> 线程模型：**主线程专用**（内部加锁只为"误从后台线程归还"时不破坏栈结构）。

## 数据与通用件（配表 / 存档 / 随机 / 寻路 / 等距 / 日志降频）

> 这一节全是**引擎已下沉的通用能力**。业务侧遇到对应需求**直接用**，
> ⛔ 不要再在 `Assets/Scripts/Core/` 里自己重写一份（那是每个项目都重写一遍的浪费）。

### CloverTable —— 读自家打表工具的产物

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `CloverTable.LoadAll(streamingAssetsDir, dataDir)` | `string, string` | `string` | 加载全部 tsv + 建主键索引；**成功返回 `null`、失败返回可定位错误串**（⛔ 不抛） | 启动期加载配表 |
| `CloverTable.Get<T>(tableName, int\|string key)` | `string, 主键` | `T` | 按主键取一行（**反射填 public 字段**）；取不到 ⇒ `null` + 限频告警 | 按 id 查行 |
| `CloverTable.Dir` / `ResolveDir(...)` / `RequiredTables` | - | - | 实际加载目录 / 目录解析 / 已声明的必需表 | 排障 |

> ⚠️ 引擎旧入口 `CloverData.InitDataTable` 要求行类实现 `IDataRow`、**读不了打表产物** ⇒ 工程侧一律用 `CloverTable`。
> 打表生成的 `Tables.Default.*` 强类型壳（`Get(id)` / `All()`）是**便捷访问层**，可以继续用。

### FileSlotStore —— 「一槽一文件」的存档 / 回放 / 草稿

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new FileSlotStore(dir, extension = ".json")` | `string, string` | `FileSlotStore` | 一槽一文件；构造**不抛**（目录不可用 ⇒ 退化为"写失败 + 可定位错误串"） | 存档目录 |
| `Write(key, content, out error)` | `string, string, out string` | `bool` | 原子写（`.tmp` → `File.Replace`）；失败 ⇒ `false` + 错误串（⛔ 不抛） | 存一只角色 |
| `Read(key)` | `string` | `string` | 读回文本；**不存在 / 内容坏了 ⇒ `null`**（坏了会留档 `.corrupt` + 限频告警一次） | 读档 |
| `Exists(key)` / `Delete(key)` / `List()` | `string` | `bool` / `bool` / `List<string>` | 只看文件在不在 / 删除 / **全部槽位（字典序）** | 选角列表 |
| `Dir` / `LastCorruptPath` | - | `string` | 槽位目录 / 最近一次留档的坏文件（没有 ⇒ `null`） | 排障 / 留档判据 |

> ⚠️ **`List()` 是字典序、不是插入序** ⇒ 要"创建先后"（选角屏卡片顺序这类）**自己维护索引键**。
> ⚠️ `Write` / `Read` **都不抛异常**；key 非法（空 / 含 `/` `\`）⇒ 失败 + 错误串，⛔ 也不允许 `../` 逃出槽目录。
> 与 `Game.Setting` **互补**：那个是**单文件 KV**（内存里攒、`Save()` 一次写全），这个**一槽一文件、每次 `Write` 独立落盘、可枚举**。

### Rng —— 注入式可复现随机

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new Rng(seed)` / `Rng.FromTime()` | `int` | `Rng` | `FromTime()` **只在"决定本局 seed"这一处用** | 地图 / 掉落 |
| `Next()` / `Next(max)` / `Next(min, max)` / `NextFloat()` / `Range(min, max)` | - | `int` / `float` | 非法参数**不抛** ⇒ 返回安全值 + 限频告警 | 各类取值 |
| `Chance(p)` / `Pick(list)` / `PickWeighted(weights)` / `Shuffle(list)` / `NextGrid(w, h)` / `Index(size)` | - | `bool` / `T` / `int` / `void` / `Vector2Int` / `int` | `Chance`：`<=0` 恒 `false`、`>=1` 恒 `true`；`Shuffle` **同 seed 同排列** | 掉落 / 洗牌 |
| `Derive(salt)` / `DeriveSeed(salt)` | `int` | `Rng` / `int` | 从本局 seed 派生子系统 seed（**保持可复现**） | 每个子系统独立流 |

> ⛔ **禁止 `UnityEngine.Random`**（全局静态状态 ⇒ 序列不可复现）；由调用方持有实例并**显式传参**。

### AStar / IsoLayout —— 运行时寻路与等距几何

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `AStar.Find(walkable, from, to, ...)` | `Func<Vector2Int,bool>, Vector2Int, Vector2Int` | `List<Vector2Int>` | **回调式**（零业务类型依赖）；不可达 / 入参非法 ⇒ `null` + 限频告警 | 随机地图寻路 |
| `AStar.FindSmoothed` / `Smooth` / `HasLineOfSight` / `Describe` | - | - | 平滑路径 / **视线判定（仅 2D 格网）** / 文字诊断 | 2D 寻路 / 点击移动 |

> ⚠️ **`AStar.HasLineOfSight` 不是 3D 视线判定**：它是 2D 格网上的 Bresenham + 可走回调（`AStar.cs`），只看"这条格线经过的格子是否可走"。它**没有**层高（`y`）、没有受体（角色/物体）过滤、也没有烟雾/遮挡物概念 ⇒ ⛔ **不能**用来做"怪物能不能看见玩家"。
> 需要 3D 视线（视锥 + 物理射线 + 受体层）时，客户端引擎目前**没有**等价件（`Frustum` / `ViewCone` / `CanSee` / `Perception` 全仓 0 命中）；服务端的参考口径在 `collide.Grid3.Raycast` / `NavGrid3`，客户端侧要么自己实现、要么登记为引擎缺口。
| `new IsoLayout(halfW, halfH, sortOrderStep, sortOrderBase)` | `float, float, int, int` | `IsoLayout` | 构造收参数 ⇒ **不绑定任何项目常量**（⛔ 后两个是 **int**：写 `1f, 0f` 编译不过） | 2.5D / 等距 |
| `IsoLayout.GridToWorld / WorldToGrid / ScreenToGrid / SortOrder / GridDistance* / DirectionTo` | - | - | 正逆投影 / 深度排序 / 距离 / 方向 | 坐标换算 |

> ⚠️ 引擎 `MapBake` 是**静态烘焙**（不解决"每局随机生成"）⇒ 运行时格子寻路用 `AStar`。

### LogThrottle —— 日志防刷屏

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `ShouldLog(key, intervalSeconds = 5f)` | `string, float` | `bool` | **时间口径**：同一 key 在间隔内只出第一条；空 key 恒 `false` + 只报一次 Warn | 每帧刷屏的分支 |
| `WarnThrottled / ErrorThrottled / WarnOnce / ErrorOnce(tag, key, message, ...)` | `string, string, string, ...` | `bool` | 直接出日志（`*Once` = `ShouldLog(key, +∞)`） | 兜底分支留痕 |
| `ShouldLogEvery(key, everyN)` / `InfoCounted` / `WarnCounted` / `ErrorCounted` | - | `bool` | **计数口径**：每 key 独立计数、**第 1 次必打**、之后每 N 次一条 | 偶发但一局很多次 |
| `Clock` / `ClockSource` / `Reset()` | - | - | 注入单调秒（离线宿主**必须注入**才有确定性）/ `Injected`/`Unity`/`Process` / 换场景时清限频表 | 确定性 / 测试 |

> ⚠️ **两种口径语义不同、不可互相替换**：时间治"每帧刷屏"、计数治"偶发但一局出现很多次"的打点抽样。

### FrameBank —— 精灵目录抓帧（整目录有序数组 / 帧号寻址 / 统一画布锚点）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new FrameBank(resource = null, fallbackPixelsPerUnit = 100f)` | `IResourceManager, float` | `FrameBank` | 一般传 `null`（回落 `Game.Res`）；`fallbackPixelsPerUnit <= 0.01` 按 `DefaultPixelsPerUnit`（100）处理（⛔ 不抛） | 进图前建一个 |
| `LoadDir(path)` / `LoadDir(path, PivotMode)` | `string` / `string, PivotMode` | `Sprite[]` | **同步**取整目录全部帧 + 按帧号升序排；空路径 / 两级都取不到 ⇒ **长度 0 的数组**（⛔ 不返回 `null`、⛔ 不抛）。降级链：`LoadAll<Sprite>` ⇒ 空则 `LoadAll<Texture2D>` 现场 `Sprite.Create` | 逐帧动画取整目录 |
| `FrameNumberMap(path, mode)` | `string, PivotMode` | `int[]` | `map[帧号]` = 该帧在数组里的**下标**（取不到 = `-1`）；表长 = 最大帧号 + 1；同帧号取首次出现的下标。**恒等 ⇒ Info；非恒等 ⇒ Warn + 前 8 项 `fN→idx` 作证据** | 按帧号寻址取帧 |
| `UnifyCanvasAnchor(frames, cacheKey)` | `Sprite[], string` | `Sprite[]` | 用「全目录 `rect` **并集中心**」当**共用纹理锚点**重建每一帧（`PivotMode.UnifiedCanvasAnchor` 内部即调它）；前提 = 各帧**画布尺寸一致**，不满足 ⇒ **降级保原样 + 限频 Warn**（⛔ 不静默） | 多 Sprite 导入的「贴图抖动」 |
| `ParseFrameIndex(name)` | `string` | `int` | **纯函数**（离线可断言）：帧号 = 名字里**从倒数第二段起往回**找的第一个纯数字段（`frame_000_0→0`、`frame_485_0→485`、`frame_003→3`、`gen_frame_012→12`）；解析不出 ⇒ `-1` | 排序键 / 离线断言 |
| `Cached(path)` | `string` | `Sprite[]` | **已缓存**的帧（`AsImported` 模式；**不触发加载**）；没缓存过 ⇒ 空数组 | 诊断 |
| `WhiteSprite()` | - | `Sprite` | 共享 1×1 白块（`pixelsPerUnit = 1` ⇒ 恰好 1 世界单位），惰性造一次 | 世界空间纯色底块 / 占位块 |
| `Clear()` | - | `void` | 清缓存 + **只销毁名字带 `gen_` 前缀的那些**现造 Sprite（导入 / 引擎那份归资源模块，⛔ 本类不碰）；调用后同名目录会重新加载，且「只报一次」的告警**重新武装** | 出图 / 换场景 |
| `Count` / `GeneratedSpritePrefix` / `DefaultPixelsPerUnit` / `PivotMode.AsImported` / `PivotMode.UnifiedCanvasAnchor` | - | `int` / `string` / `float` / 枚举 | 已缓存目录数 / 现造 Sprite 的名字前缀 `gen_` / 兜底 PPU `100` / 「按导入设置原样」/「全目录共用锚点」 | 诊断 / 常量 |

> ⚠️ **什么时候不要用它**：① **⛔ 战斗热路径里第一次调用** —— `LoadDir` 走 `LoadAll<T>` 是**同步阻塞**（真的加载、不进缓存/引用计数），请在**进图前 / 读条阶段**调；② 只要「随用随取单张、不介意被水位淘汰」⇒ 用同节的 `SpriteSet`（两者方向相反且互补）。
> ⚠️ 帧号 ≠ 下标发生在「一张 PNG 被切成多个子 Sprite」的目录里 ⇒ 一旦发生而无人知晓，表现是「取帧取错」这类**零报错**的静默错误，所以 `FrameNumberMap` 必须断言 + 留痕。
> ⛔ 不要自己再写一份「抓目录 + 排序 + 定锚点」（同形状在各工程里重写过 N 遍）；⛔ `UnifyCanvasAnchor` 的 `Sprite.Create` **`pivot` 口径是相对各自 `rect` 归一化**（不是相对整张贴图）—— 这条是实测出来的，别靠回忆重推。

### RuntimePanelProvider —— 运行时面板供给者（零 prefab）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new RuntimePanelProvider(params Assembly[] panelAssemblies)` / `new RuntimePanelProvider(timer, panelAssemblies)` | `Assembly[]` / `ITimer, Assembly[]` | `RuntimePanelProvider` | 传**面板类型所在的程序集**（`typeof(某面板).Assembly`）；引擎所在程序集里没有业务面板 ⇒ 必须至少给一个 | 纯代码搭 UI 的工程 |
| `Install(bus)` | `IEventBus`（一般 `Game.Event`） | `bool` | 给静态槽 `CloverPresentation.PanelProvider` 装上「按类名反射造面板」的实现（`Game.UI.Open<T>` 从此**不再依赖** `Resources/UI/{类名}.prefab`）；幂等；`bus == null` ⇒ `false` + **Error**（= 调早于 `Game.Launch`）；同一条总线但槽被别人清掉 / 覆盖 ⇒ **自愈重装**并返回 `true` | 启动流程一次性调用 |
| `Uninstall()` | - | `void` | 把槽置回 `null`（= 回到 prefab 路线）+ 清掉兜底残留模板；⛔ 只影响**之后**打开的面板（已开着的归 `UIManager`） | 退出流程 |
| `AddAssembly(assembly)` / `Invalidate()` | `Assembly` | `void` | 追加要扫描的程序集（⛔ 第一次 `Install` 之前加齐）/ 丢掉类型表（改完程序集集合后调） | 模块化工程 |
| `IsInstalled` / `InstalledBus` / `PanelTypeCount` / `PanelTypes` | - | `bool` / `IEventBus` / `int` / `IReadOnlyDictionary<string, Type>` | 是否装着本实例（且总线仍是安装时那条）/ 安装那一刻的总线 / 已登记面板类型数（**会触发扫描**）/ 类型只读快照 | 自检 / 诊断 |

> ⚠️ **什么时候不要用它**：需要在编辑器里调版面 / 面板里挂引用 / 美术要看 prefab ⇒ 保持 `PanelProvider == null` 走 **prefab 路线**（`Editor/PanelPrefabBuilder` 能按 `IUIPanel` 实现批量生成壳 prefab）。两条路线是**同一个函数槽** ⇒ 天然互斥，⛔ 不会两套同时生效。
> ⚠️ **时机**：必须在 `Game.Launch` **之后**、**第一次 `Game.UI.Open` 之前** `Install`（晚装只影响之后打开的面板）。
> ⚠️ **面板必须在 `OnOpen` 里建视觉树**，⛔ 不要放 `Awake` / `Start` —— 模板对象也会走一遍 `Awake`（`AddComponent` 当场触发），在 `Awake` 里建树会让**模板也建一份**（白做 + 多一次加载）。这条引擎挡不住 ⇒ 靠本行约束。
> ⚠️ **IL2CPP 裁剪**：反射扫程序集会被 **managed code stripping** 打掉（面板类型没有任何静态引用）⇒ 用了本件的工程**必须**在 `Assets/link.xml` 里 `preserve` 面板类型（或至少面板所在程序集），否则表现为「面板开不出来且完全静默」。
> ⛔ 不要自己再写一份 `PanelFactory`（同形状曾在工程侧手写过一遍）。

### SnapshotInterpolator —— 低频权威快照 → 高帧率插值（渲染时钟 + 窗口选择）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `SnapshotInterpolatorOptions.Default()` | - | `SnapshotInterpolatorOptions` | 参考工程**实测收敛**的那一组：10 Hz 快照 / 6 格历史 / 落后 2 个间隔 / ±5% 速率 | 起步值 |
| `SnapshotIntervalMs` / `ExpectedRenderFps` / `HistSlots` / `RenderLagIntervals` / `LagSteerGain` / `LagSteerMaxRate` / `CatchUpMaxRate` / `CatchUpThresholdIntervals` / `ServerNowExtrapCapIntervals` / `ClockMaxLeadIntervals` | - | `float` / `int` | **结构体 + 公开字段**（与 `ViewBobConfig` 同形）。换快照频率或渲染帧率**必须**改前两个；`HistSlots` **必须 > `1 + RenderLagIntervals`**，否则时钟一落后就掉出历史 ⇒ `t` 恒为 0（插值静默失效） | 参数化节奏 |
| `TargetLagMs` / `CatchUpThresholdMs` / `ServerNowExtrapCapMs` / `ClockMaxLeadMs` / `HistoryCoverageMs` | - | `float` | 上面几个的**毫秒派生量**（只读） | 诊断 |
| `new SnapshotInterpolator(options = null, clockSeconds = null)` | `SnapshotInterpolatorOptions?, Func<float>` | `SnapshotInterpolator` | `options` 传 `null` 取 `Default()`；非正 / 过小的值被**归一化 + 一条 Warn**（⛔ 不静默、⛔ 不抛）。`clockSeconds` **返回秒**、语义同 `Time.realtimeSinceStartup` ⇒ 离线单测 / 回放灌数据注入它即可完全复现 | 建插值器 |
| `Push(serverMs, payload = null)` | `float, object` | `bool` | 推入一帧权威快照：**只入历史，⛔ 绝不重置渲染时钟、⛔ 绝不换正在渲染的窗口**。`true` = 入了历史；`false` = 被丢弃（`serverMs <= 0` ⇒ 退化按标称周期推定；时间戳没前进 / 乱序 ⇒ **整帧丢**，历史必须按时间戳单调） | 网络回调里推 |
| `Tick()` | - | `float` | **每帧一次**：推进渲染时钟 → 有界比例速率修正 → 按渲染时钟选插值窗口 → 返回 `t ∈ [0,1]`（未就绪 = 返回 `1f`，语义「冻在最后一个已知位置」） | 业务 Tick |
| `Reset()` | - | `void` | 复位到「还没收到任何快照」（换对局 / 重连 / 出图）；「只报一次」的告警**不重置** | 换对局 |
| `HasWindow` / `WindowStartPayload` / `WindowEndPayload` / `InterpRatio` | - | `bool` / `object` / `object` / `float` | 窗口是否可用 / **该插值的那一对载荷**（调用方自己的 `payload`，本件只存**引用**、⛔ 不读不拷贝）/ 上次的 `t`。调用方拿 `prev` / `cur` 自己 Lerp 自己的实体字段 | 渲染实体 |
| `RenderClockMs` / `NewestSnapshotMs` / `RenderLagMs` / `BufferLagMs` / `WindowStartMs` / `WindowEndMs` / `ClockRate` / `SnapshotCount` / `HistoryLength` / `CatchingUp` / `OutOfWindow` / `DroppedOutOfOrderCount` / `Options` | - | `float` / `int` / `bool` / 结构体 | 渲染时钟（服务端时间轴上的哪一毫秒）/ 最新快照时间戳 / 落后最新多少 ms / 缓冲多深 / 窗口两端 / 当前速率 / 计数 / 状态标志 —— **留痕与自检用** | 自检 / 诊断 |
| `static SteerRate(lagErrorMs, options)` / `SteerRate(lagErrorMs)` | `float, SnapshotInterpolatorOptions` | `float` | **纯函数**控制律（离线可断言）：偏差 ≤ 阈值 ⇒ 在 ±`LagSteerMaxRate` 内**按比例**微调；超阈值 ⇒ 放开到 `CatchUpMaxRate` 有界追帧（超前时只放一半） | 离线断言 |

> ⚠️ **三个已知坑（改之前先读）**：① ⛔ **不要把渲染时钟写成「每帧累加 `Time.deltaTime`」** —— 那个值被 Unity 夹在 `Time.maximumDeltaTime`（默认 1/3 秒），一次卡顿就让时钟**永久落后**（实测 1915~2108 ms）⇒ `t` 恒为 0、单位冻住；② ⛔ 速率修正**必须每帧都调**，不许写成 `|err| > 阈值 ? SteerRate(err) : 1f`（落后量一旦被成批到达的快照推过阈值就**再也回不来**）；③ ⛔ **换窗口必须按时钟跨过时间戳**，不许「按包到达换窗口」（那是抖动的来源：实测速度 cv 0.24~0.28，改成按时钟后 cv 0.000）。
> ⚠️ **分工**：`WorldSync` 是 MMO/AOI 的**逐实体**镜像同步（回答「这个实体怎么平滑到下一格」）；本件只管**时间轴 / 窗口**（对快照内容一无所知，可叠加使用）。也**不是** `FramePacingPolicy` 的重复（那个管帧**交付**节奏，本件管取**哪一时刻**的状态）。
> ⚠️ **代价（明知）**：画面比服务端晚 `RenderLagIntervals` 个间隔 —— 这是「**绝不前跳**」换来的（前跳会瞬间把单位推过头、甚至穿墙）。
> ⛔ 不要自己再写一份「插值比例 + 快照缓冲」（三代失败模式：分母写死 + 每帧重置 ⇒ 前跳；到达驱动换窗口 ⇒ 抖动；本件是第三代）。

### GridUtil —— 矩形 → 整数格遍历

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `GridUtil.TryGetTileRange(r, out xMin, out xMax, out yMin, out yMax, epsilon = EdgeEpsilon)` | `Rect, out int ×4, float` | `bool` | 矩形覆盖到的格**范围**（`xMin/xMax/yMin/yMax` 都**含**端点）；空 / 反向矩形 ⇒ `false`（**静默**，不打日志）；非有限坐标（NaN / ±Inf）⇒ `false` + 限频 Error | 碰撞盒 → 格范围 |
| `GridUtil.ForEach(r, action, epsilon = EdgeEpsilon)` | `Rect, Action<int, int>, float` | `void` | **热路径入口**：`y` 升序外层 / `x` 升序内层（**顺序是契约** —— 回调里 `break` 时「先撞到哪一格」会随顺序变）；委托已缓存时**零分配**；格数离谱 ⇒ 只留痕、**⛔ 不截断**（截断 = 静默丢格 ⇒ 碰撞漏判） | 每帧碰撞查询 |
| `GridUtil.Enumerate(r, epsilon = EdgeEpsilon)` | `Rect, float` | `IEnumerable<Vector2Int>` | ⚠️ **每次调用都会分配**（迭代器状态机 + 装箱枚举器）⇒ 只给冷路径（建关卡 / 工具 / EditMode 测试） | 构建期遍历 |
| `GridUtil.EdgeEpsilon` | - | `float` | `0.0001f`：右 / 上边按**开区间**收边（否则「只在一条零宽边上碰到」的格会被算进来 ⇒ 贴右墙隔空撞墙、多踩一格）；⚠️ 只对 \|坐标\| ≲ 4096 可靠（更大时 ULP > epsilon，等于没减）⇒ 世界更大**显式传更大的 epsilon** | 构造默认值 |

> ⚠️ **世界 → 格必须 `Mathf.FloorToInt`**：`(int)` 强转对**负数向零截断**（x = -0.5 ⇒ 第 0 格）⇒ 表现为「站在坑里也能踩到地」且**不报错**；`RoundToInt` 会把格边界挪到 0.5，与引擎既有口径「格 (gx, gy) 覆盖 [gx, gx+1]」不符。
> ⚠️ 热路径的 `lambda` **一旦捕获局部变量就每次调用分配一个闭包**；方法组转换在 Unity 的 C# 9 下**每次转换也分配** ⇒ 把委托**存进字段**再传。
> ⛔ 不要自己再写一份 `Overlap(Rect)` —— 这个形状在某个工程里被**逐字复制了 4 份**（玩家 / 敌人 / 道具 / 火球），正是本类被下沉的原因。

### ITileWorld / TileWorld —— 2D 瓦片世界的空间事实面

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `ITileWorld` / `new TileWorld()` | - | - | **只回答事实，不给位移解算**（口径同 `Game.Map`）；纯数据、无 MonoBehaviour / 无 GameObject（`TileWorld` = 两个哈希表 + 64 位压缩键，稀疏存储） | 平台 / 俯视关卡的格子事实 |
| `IsSolid(tx, ty)` / `IsSolidAt(x, y)` | `int, int` / `float, float` | `bool` | 该格是否实心；**越界一律 `false`**（⛔ 不抛、不打日志）；`IsSolidAt` 内部走 `Mathf.FloorToInt` | 碰撞 / 可走判定 |
| `SetSolid(tx, ty, solid = true)` | `int, int, bool` | `void` | 置 / 清一个实心格（⛔ 不要用 `bool[宽*高]` 全量数组） | 破坏方块 / 临时阻挡 |
| `TryGetCarrierTop(tx, ty, out topY)` / `SetCarrierTop(tx, ty, topY)` / `ClearCarrierTop(tx, ty)` | `int, int` / `int, int, float` | `bool` / `void` | **移动托台**的小数顶高（世界 y，例如平台顶面在 `3.25`）；查不到 ⇒ `false`（**这是正常查询**，不抛、不打日志）；`SetCarrierTop` 收到非有限值 ⇒ 忽略 + Error | 升降平台 / 电梯 |
| `SetBounds(minX, maxX, groundTopY)` | `float, float, float` | `void` | 给一次世界边界与地面顶高（关卡构建期）；非有限值 ⇒ 忽略 + Error；`minX > maxX` ⇒ 限频 Warn 后**交换**（归一化） | 建关卡 |
| `MinX` / `MaxX` / `GroundTopY` / `HasBounds` | - | `float` / `bool` | 世界左 / 右边界、地面顶高；未 `SetBounds` 前都是 `0` 且 `HasBounds = false` ⇒ ⛔ **0 不代表世界真的到 0**，判之前先看 `HasBounds` | 相机 / 角色边界约束 |
| `Clear()` | - | `void` | 只清**格子数据**（实心 + 托台），**不动**世界边界 / 地面顶高 —— 那是「世界事实」，重进关卡时由 `SetBounds` 重新给 | 换关卡 |
| `SolidCount` / `CarrierCount` | - | `int` | 实心格 / 已登记托台格数量 | 诊断 / 自检 |

> ⚠️ 同类能力别重复造：**格子寻路**用 `AStar`、**等距投影 / 深度排序**用 `IsoLayout`（见上一节）；本件只管「这一格是什么」这条**事实**。
> ⛔ 不要为了「能扫整张地图」去加一个 `bool[宽*高]` 的实现（稀疏存储是接口契约里写着的实现要求）。

### SpriteFrameAnimator —— 逐帧动画器（`Sprite[]` → `SpriteRenderer`）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new SpriteFrameAnimator(target)` | `SpriteRenderer` | `SpriteFrameAnimator` | `target` **允许为 `null`**（离线宿主 / EditMode 只推进内部状态、不写渲染器；⛔ 不会因此报错刷屏） | 逐帧动画 |
| `Play(frames, fps, loop = true)` / `PlayOnce(frames, fps, onComplete = null)` | `Sprite[], float, ...` | `void` | **旧签名（语义逐字不变）**：`fps <= 0` / NaN / ±Inf ⇒ 按 **1 fps** + 限频 Warn；重播 / 换表**从第 0 帧重来**（累计时间归零）；空帧表 ⇒ 不播 + 限频 Warn | 简单的两态动画 |
| `Play(frames, indices, fps, loop = true)` / `PlayOnce(frames, indices, fps, onComplete = null)` | `Sprite[], int[], float, ...` | `void` | **新重载**：`fps == 0` = **静止帧（停播，不是「1 fps 慢慢抖」）**；`indices` = **帧段子集**（可多区间 / 可乱序，顺序即播放顺序），`null` / 空 ⇒ 等价整表按序播（+ 限频 Warn 一次） | 一档动画的帧**不连续**（如 attack = 帧 182-230 ∪ 247-251） |
| `PlayStill(frames, index = 0)` | `Sprite[], int` | `void` | 显示第 `index` 帧并**停住**（`fps = 0` 的等价直白入口，`Advance` 不再推进） | 原版 idle 就是单条静止姿态帧 |
| `SwitchTo(frames, indices, fps, loop = true, force = false)` | `Sprite[], int[], float, bool, bool` | `bool` | **换档（带滞回）**：请求档 == 当前档（帧表 / 切片 / fps / loop 全同）⇒ **什么都不做**（⛔ 绝不从第 0 帧重播）；当前档「播一次且没播完」⇒ **扣住**并返回 `false`，除 `force = true`；其余 ⇒ 正常换（当帧即贴新档首帧） | 服务端瞬时的 `anim` 字段（挥砍只在一 tick 置 attack） |
| `static ExpandRuns(runs, frameCount, out error)` | `int[], int, out string` | `int[]` | 把 `[起始, 长度, …]` 的**段表**展开成下标集合（形状对齐配表里的 `Clip.Runs`）；**严格校验**（表为 null / 空、长度为奇数、某段长度 ≤ 0、某段越界 ⇒ 返回 `null` + `error` 给原因，⛔ **不做静默裁剪**） | 配表里的帧段表 |
| `Advance(dt)` | `float` | `void` | **唯一的时间入口**（由业务 Tick 调）：`dt <= 0` ⇒ 不推进（`0` 是合法的「暂停帧」，负值按 0 + 限频 Warn）；单次推进超过 `MaxAdvanceSteps` 帧 ⇒ 丢弃剩余累计时间 + 限频 Warn（⛔ 不把一帧卡成死循环） | 业务 Tick |
| `Stop()` / `SetFrame(index)` | `int` | `void` | 停止（**保留当前帧的画面**、未触发的完成回调作废）/ 直接定位到第 `index` 帧并立刻推给渲染器（越界**收敛** + 限频 Warn，**不改播放状态**；定位后累计时间归零） | 暂停 / 定帧调试 |
| `Frames` / `ClipIndices` / `ClipLength` / `FrameCount` / `FrameIndex` / `Fps` / `Loop` / `IsPlaying` / `Target` | - | `Sprite[]` / `int[]` / `int` / `float` / `bool` / `SpriteRenderer` | 只读状态；用帧切片时 `FrameIndex` 是**档位位置**（对应的帧下标 = `ClipIndices[FrameIndex]`）；`Fps` 是归一化后的生效值（静止帧档恒为 0） | 自检 / 诊断 |

> ⚠️ **什么时候不要用它**：要「在编辑器里编 State / Clip、有状态混合 / Avatar」⇒ 用 `IAnimationManager`（落地的是一颗 `Animator` + controller 资产）。本件是「`Sprite[]` 进、`SpriteRenderer` 出」—— 平台游戏每套动画的节奏就是**一个 fps**，为 4 张帧图建 controller + clip 是纯负担。
> ⛔ 不要自己再写一份 `_animTimer += dt; if (_animTimer >= 0.11f) { 换帧 }` —— 这个形状在某个工程里被**逐字手写了 5 处以上**（节奏常量散落各 MonoBehaviour）。
> ⚠️ 传入的 `frames` / `indices` **按只读对待**（本类**不克隆** —— 换档是热路径）⇒ 每个档位的切片**缓存起来复用**，不要每次换档现造。
> ⚠️ 本类**不加载任何资源**（帧表由调用方给，谁加载谁 Release）；帧表怎么来见上面的 `FrameBank`。

### SpriteSet —— 批量异步预加载 + 按名同步取

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new SpriteSet(resource = null)` | `IResourceManager` | `SpriteSet` | `null` ⇒ 回落 `Game.Res`（可注入替身做离线自检） | 随用随取的精灵组合 |
| `LoadSet(paths, onDone = null)` | `IEnumerable<string>, Action` | `void` | 批量**异步**预加载；回调**必定被调用一次**（含「清单为空」「资源管理器未挂接」「Preload 抛异常」三种情形 —— 否则调用方永久等待）。每条路径登记**两个名字**：① 全路径原样 ② 末段去扩展名；**短名冲突** ⇒ 保留先注册的 + Warn（此时请改用全路径取）。可多次调用**追加**清单 | 进图前预热一整套精灵 |
| `Get(name)` | `string` | `Sprite` | **纯读缓存：不加载、不阻塞**。取不到（不在清单 / 尚未驻留 / 已被水位淘汰）⇒ `null` + **按名字只报一次 Error**（它会每帧被调用，逐帧刷屏会把日志打爆） | 每帧取图 |
| `IsReady` | - | `bool` | 预加载**流程**是否结束（⛔ 它**不代表**「每一张都拿到」 —— 缺哪张由 `Get` 报） | 读条判定 |
| `Count` | - | `int` | 已登记的名字条数（含全路径与短名） | 诊断 / 自检 |
| `Clear()` | - | `void` | 清名字索引 + `IsReady` 复位（下次 `LoadSet` 是全新一批）；**只清本件的索引** —— 引擎缓存的引用计数不由本件持有，淘汰交给水位 / LRU | 出图 |

> ⚠️ **与 `FrameBank` 的分工**：`SpriteSet` = 「异步 `Preload` 一批 → 按**名**同步 `TryGet` 单张」，**没有**目录级全量数组、条目**可被水位 LRU 淘汰**；`FrameBank` = 「一次拿到**整目录有序数组** + 按**帧号**定位 + 统一锚点」。要「第 N 帧动画」用后者，要「随用随取单张」用前者。
> ⚠️ 忘了把某个动作放进 `LoadSet` 清单的表现是**角色整段隐形、零报错零日志** ⇒ 所以「取不到必须报、且因为每帧都会被调用所以只报一次」。
> ⚠️ 需要**长期常驻**请自行 `Game.Res.LoadAsset` 持有引用（本件不持有引用计数）。

### Screenshot —— 截图落盘

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `Screenshot.CaptureToFile(path, superSize = 1)` | `string, int` | `bool` | 把当前画面**立即**读成像素并写 PNG；传入路径的**父目录不存在时自动递归创建**；空 / `null` 路径、屏幕尺寸非法（0×0）、任何异常 ⇒ **返回 `false` + Error 留痕（⛔ 永不抛）**；`superSize < 1` ⇒ 按 1 处理 + 限频 Warn（放大是**读屏后最近邻**，不是渲染层超采样 —— `ReadPixels` 拿不到比屏幕更高的分辨率） | 自动化验证取证 / 玩家反馈 |

> ⚠️ **必须在「帧末」那一拍调用**：`ReadPixels` 只能主线程、且必须在**渲染完成后同帧内**取 —— Play 模式用 `yield return new WaitForEndOfFrame()`；Editor 菜单 / 自动化脚本直接调。
> ⚠️ 引擎**刻意不替调用方排帧末**（引擎不接管业务 Tick 的生命周期：替业务起协程去等帧末 = 引擎持有一次业务生命周期，`Game.Shutdown` 时那个协程还在等）。⛔ 不要为了「一行截图」在引擎里加协程 wrapper。
> ⚠️ 截图功能的失败是**静默**高发区（调用方以为存了、磁盘上没有文件）⇒ 判据必须看**返回值 + 日志**，⛔ 不要只看目录里有没有图。

### OrderedAsyncResult\<T\> —— 乱序异步结果按下标落位

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new OrderedAsyncResult<T>(count)` | `int` | `OrderedAsyncResult<T>` | `count <= 0` ⇒ **立即视为 complete**（`TryTakeOrdered` 返回空数组 + `true`）+ 限频 Warn（零任务也是「齐了」；否则调用方永远等一个不会到来的交付） | 并行加载 / 逐帧采集 |
| `Put(index, value)` | `int, T` | `void` | 把一个结果落到指定下标（**到达顺序任意**）。越界 ⇒ **忽略** + 限频 Warn（⛔ 不抛：异步回调路径上抛异常会打断调用方的循环）；同一 `index` 重复 ⇒ **覆盖**旧值 + 限频 Warn（后到的算新值；静默覆盖会让「结果错」无从查起） | 并行回调里落位 |
| `TryTakeOrdered(out ordered)` | `out T[]` | `bool` | **仅在 `IsComplete` 时返回 `true`**：`ordered` = 长度 `Count`、**按下标升序**的数组，并**清空自己**（可复用：再 `Put` 一轮即可交付下一次）；未收齐 ⇒ `ordered = null` + `false`（⛔ **不交付半成品**）；`Count == 0` ⇒ 空数组 + `true` | 「齐了才组装」 |
| `Count` / `FilledCount` / `IsComplete` | - | `int` / `bool` | 期待的结果个数 / 已落位的下标个数（重复 `Put` 同一 index **不重复计数**）/ 是否已收齐 | 读条判定 / 自检 |

> ⚠️ **什么时候不要用它**：**非线程安全（主线程使用）** ⇒ 多线程回调请先在各自线程排队、回到主线程再 `Put`。回调本来就有序时也不需要它（直接数组赋值）。
> ⚠️ 它解决的是「异步回调的到达顺序 ≠ 业务需要的顺序」：① 帧序随回调次序抖动（回放不可复现、对比判据随机红）② 结果被「到达即消费」。
> ⛔ 不要自己再攒一层「N 个 boolean + 计数」（同形状在多个项目 / 多个功能里被各自手写过一遍）。

### FramePacingPolicy —— 帧节奏（帧率上限 / 垂直同步）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `FramePacingPolicy.Recommend(out targetFrameRate, out vSyncCount, out refreshHz)` | `out int, out int, out float` | `bool` | 由**显示器刷新率**给推荐档位；返回 `false` = 刷新率读不到（此时按兜底口径：`DefaultTargetFrameRate` / `DefaultVSyncCount`） | 启动期定帧节奏 |
| `FramePacingPolicy.Pin(targetFrameRate, vSyncCount, out readBackFps, out readBackVSync, out error)` | `int, int, out int, out int, out string` | `bool` | 写 `Application.targetFrameRate` + `QualitySettings.vSyncCount` 并**读回校验**（原生 API 可能被平台改写）。`true` = 写入且读回一致；`false` = 抛异常（`error` 给原因）**或**读回值 ≠ 目标（`out` 给出**实际**读回值，调用方据此判「未生效」） | 钉死帧节奏 |
| `FramePacingPolicy.TryRead(out fps, out vSyncCount, out error)` | `out int, out int, out string` | `bool` | **只读**当前帧节奏（不改任何值）；离线宿主里这两个原生 API 会抛 `UnityException` ⇒ `false` + 原因（「宿主里失败」是正常现象，不是崩溃） | `Pin` 前后对比 / 自检 |
| `FramePacingPolicy.Describe(targetFrameRate, vSyncCount, reason, beforeFps, beforeVSync)` | `int, int, string, int, int` | `string` | 生效口径的**单行文本**（⛔ 不含日志级别、不含业务文案 —— 业务在自己那层加前缀） | 日志留痕 |
| `RecommendVSyncCount(refreshHz)` / `TryReadRefreshHz()` | `float` | `int` / `float` | **纯函数**（离线可断言）：刷新率可读（> 0）⇒ **1**（帧交付锁到刷新率 ⇒ 帧间隔恒定，100 Hz 面板 ⇒ 10.0 ms）；读不到（无头 / 离线宿主 / 平台不提供）⇒ `0` | 档位计算 / 显示刷新率 |
| `DefaultTargetFrameRate` / `DefaultVSyncCount` | - | `int` | 兜底帧率上限 `60` / 兜底垂直同步档位 `0`（**只在刷新率读不到时使用**） | - |

> ⚠️ **什么时候不要用它**：**画质内容**（阴影 / 分辨率缩放 / LOD / 贴图限制）属 `Quality`（`Game.Quality.SetLevel`）—— 本件**只碰**帧率上限与垂直同步这两件「帧交付节奏」的事。
> ⚠️ **口径（调用方要抄）**：① `vSyncCount > 0` 时平台会**忽略** `targetFrameRate` ⇒ 两个必须**一起写**；② `QualitySettings.SetQualityLevel` 会**按档位重置 `vSyncCount`** ⇒ **每次改画质档位之后都要重新 `Pin`**。
> ⚠️ **为什么必须与显示器对齐（真机 A/B 实测）**：位置是 `f(t)` 的光滑函数（按 `dt` 积分）⇒ **帧间隔不匀直接变成画面推进不匀**。实测（100 Hz 显示器 + 配置 60/0）：`dt` 8.5~62.6 ms（sd 5.0 ms），相机世界滚动**每帧推进量 sd = 2.97 px**（速度 sd ÷ 标称 = 31%），且 `corr(纵向偏差, dt − 均值) = 0.923` ⇒ **不匀就是帧时间造成的**（不是代码）；跟拍链路本身已干净（横向 sd 0.19 px）。⇒ 帧节奏必须与显示器对齐，而刷新率只有引擎能可靠读到 ⇒ 策略放这里。
> ⛔ 不要在业务侧再写一处 `Application.targetFrameRate =`（这就是它被下沉的原因）；`vSync` 开启时平台忽略 `targetFrameRate` **属预期**，⛔ 别当 bug 修。

### UI 通用小件（品牌署名行 / 飘字 / 静音状态）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `UIWidgets.CreateCreditLabel(parent, font = null, fontSize = 14, bottomOffset = 16f, text = "by clover-engine")` | `Transform, Font, int, float, string` | `Text` | **品牌署名行**：底部锚点居中（`anchorMin = anchorMax = (0.5, 0)` / `pivot = (0.5, 0)` / `anchoredPosition.y = bottomOffset`）+ 小字号 + 低调色。建 Text 一律走 `CreateText`（保证 `TextHooks` 挂钩不被绕过）、贴底一律走 `AnchoredBottom`，⛔ 本方法不新建第三套定位 / 建文本工具 | 首页画面底部的 `by clover-engine` |
| `Game.UI.FloatText(worldPos, text, color = null, duration = 1.2f, riseWorld = 0f, fade = true)` | `Vector3, string, Color?, float, float, bool` | `void` | 世界坐标飘字；`riseWorld` = 上升高度（世界单位）；`fade = false` = **不淡出**（用于「原版不淡出」的飘字，例如分数：0.5s 直线上升、动画剪辑里没有 alpha 曲线） | 伤害 / 分数飘字 |
| `Game.Sound.IsMuted(group)` | `SoundGroup` | `bool` | 该音频分组**当前是否静音** —— 画面上的静音图标状态要查它，⛔ 不要自己再记一份镜像状态 | 设置面板 / 静音按钮图标 |

> ⚠️ `CreateCreditLabel` 的 `font = null` ⇒ 回落引擎内置字体并**限频 Warn 一次**：**像素 / 点阵字体常常只有大写字形 ⇒ 小写会被静默渲染成全大写（`BY CLOVER-ENGINE`）**，这是真实发生过的事故 ⇒ 要保证小写请**显式传入带小写字形的字体**。判据 = **实机截图 / 运行时那个标签的实际文本 + 实际字体**，⛔ 不是 grep 源码字符串（源码对 ≠ 画面上对）。
> ⚠️ `text` 的默认值**逐字** = `by clover-engine`（首字母小写，⛔ 不要改大小写）。
> ⚠️ `bottomOffset` 用**底部锚点**而不是「y = 常量」的原因：`CanvasScaler`（match=0.5）的真实画布高度随窗口变化（1600×900 时只有约 972），y 一旦超过画布高度元素就**整体掉到屏幕外**（节点 active、文本正确，但一个像素都看不见，只有实机截图才发现）。

### UnitFacingMap —— 朝向档 → 视角号 + 是否镜像（多视角 2D sprite）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new UnitFacingMap(stepToView, flipFromStep = 0)` | `int[], int` | `UnitFacingMap` | 档位 → 视角号（下标 = 档位号，长度即 `StepCount`）；⛔ 表**按只读对待**（本类不克隆、热路径直接索引）。`flipFromStep <= 0` ⇒ 自动取 `StepCount/2 + 1`（16 档 ⇒ 9）；显式给了越界值 ⇒ 收敛到自动值 + 限频 Warn。表为空 ⇒ **抛 `ArgumentException`**（唯一会抛的入口，构造期错就是错） | 16 / 32 向素材的视角选择 |
| `UnitFacingMap.Default` | - | `UnitFacingMap` | 标准 16 档 / 9 视角（共用实例，只读使用） | 直接用标准表 |
| `ViewForHeading(headingDeg, out view, out flip)` | `float, out int, out bool` | `void` | **热路径推荐这个**（一次取全，省一次取模）：档位由 `round((90° − φ) / (360°/StepCount))` 再取模求出，`view` ≥ 1、`flip` = 是否水平镜像 | 每帧更新朝向 |
| `StepForHeading(headingDeg)` | `float` | `int` | 朝向极角（度）→ 档位号 `[0, StepCount)`；取整用 `Math.Round` 的**中点取偶**（换成"四舍五入远离零"会在恰好落档边界时差一档 ⇒ 偶发"朝向跳一格"）；非有限值 ⇒ 按 0° + 限频 Warn | 单要档位 |
| `ViewForStep(step)` / `StepFlip(step)` / `Wrap(step)` | `int` | `int` / `bool` / `int` | 由档位取视角号（`<= 0` 返回 0）/ 该档是否镜像（`step >= FlipFromStep`）/ 把任意档位折回 `[0, StepCount)`（负数也折回正区间） | 按档位驱动表现 |
| `StepCount` / `FlipFromStep` | - | `int` | 档位数（= 表长）/ 镜像起始档位 | 诊断 |
| `DefaultStepCount` / `HeadingOffsetDeg` / `Standard16StepToView` | - | `int` / `float` / `int[]` | `16`（= 360° ÷ 22.5°）/ `90f`（档位 0 = 远离镜头的**约定原点**）/ `{1,2,3,4,5,6,7,8,9,8,7,6,5,4,3,2}` | 常量 / 换表基线 |

> ⚠️ **什么时候不要用它**：**滞回**与**噪声门槛**是调用方策略，⛔ 引擎不替它定死（来源工程取 `0.25 档` 滞回 / `0.01 格` 位移门槛）。朝向极角**必须由插值窗口两端快照之差**求，⛔ 不能用逐帧位移：服务端位置是毫格量化的，站立单位会被 ±2 毫格噪声把方向翻 180°（实测某 id 的步进片段 `[4,12,12,12,4]` 而同期逐帧位移仅 `-0.002 格`）。
> ⚠️ **档位 / 视角搞反不会报错**，只会"人物朝向看着别扭" ⇒ 这张表**只能靠断言 + 负控**保证，肉眼判不了（`Standard16StepToView` 逐字搬自来源工程的权威副本，改动必须同步改表并重跑其断言 + `--corrupt` 负控）。
> ⚠️ 本件**只回答「该选哪一个视角」**，⛔ 不负责 clip 内容 —— 「每档只取一个视角」是调用方（帧段表）的约束。旧事故：把 9 个视角的 clip **取并集**再依次播 ⇒ 现象 =「1 秒 9 次视角、走路原地打转 / 抽搐」。
> ⛔ 不要自己再写一份「`step > 8` ⇒ 镜像」的散装判断（原项目里它只是项目专有数据表上的四个静态成员，别的项目要用就得整张表一起抄）。

### TextFit —— 可变长文本的单行截断

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `TextFit.Clamp(label, raw)` / `Clamp(label, raw, ellipsis)` | `Text, string` / `Text, string, string` | `string` | 装得下 ⇒ **原样写入**（⛔ 不无端加省略号）；装不下 ⇒ **二分找最长可行前缀 + 省略号**，写入并返回实际文本。`label == null` ⇒ 原样返回（调用方不必判空）；`rect.width <= 1`（布局还没算 / 未挂画布）或空串 ⇒ 原样写入、**不裁**（那时判定依据不存在，裁只会裁错）；空的 `ellipsis` 按 `Ellipsis` 处理 | 玩家昵称 / 卡名等**长度由数据决定**且必须单行的标签 |
| `TextFit.ClampSelf(label)` | `Text` | `void` | 把标签**当前**文本按同规则裁一次（用于已在别处赋过值的标签） | 复用处 / 编辑器脚本 |
| `TextFit.Measure(label, text)` | `Text, string` | `float` | 量一串文本在**不受矩形约束**时的单行像素宽（口径 = uGUI `Text.preferredWidth`：`TextGenerator.GetPreferredWidth(text, GetGenerationSettings(Vector2.zero)) / pixelsPerUnit`）。**⛔ 必须自建 `TextGenerator`，不许读 `label.preferredWidth`** | 调用方断言 / 判据 |
| `TextFit.Ellipsis` / `TextFit.Tag` | - | `string` | 默认省略号 `"\u2026"`（U+2026；⛔ 不用三个 ASCII 点 —— CJK 字体下宽度不一致）/ 日志标签 | 常量 |

> ⚠️ **为什么要自建 `TextGenerator`（这条必须留，否则后人一定"顺手优化"回去）**：uGUI 的 `preferredWidth` 走的是**缓存**的布局用生成器 —— 刚 `label.text = 新值` 之后，同一帧里读到的还是**上一串文本**的宽度（原件实测：3 字串 `rectW=58 / preferredW=44` 却被判超宽、截成 1 字 + 省略号，就是读到了旧值）。
> ⚠️ **为什么必须"显式调用"而不是把引擎的文本创建点全局改成截断**：一旦全局截断，**多行说明文案**（规则两行、加载提示）也会被裁成一行 —— 那是另一类破坏。截断只对「内容长度由数据决定、且必须单行显示」的标签成立 ⇒ 由各面板在"把数据写进标签"的那一处调一次。
> ⛔ **不许用改字号来"糊过去"**（会让同一列标签字号不一致，且仍然可能溢出）；⛔ 本件不换行、不裁剪多行文案。uGUI 的 `HorizontalWrapMode` **只有 `Wrap` / `Overflow`**，不存在 `horizontalOverflow = Truncate` ⇒ 横向截断只能自己把**字符串**裁短（这就是它被下沉的原因）。
> ⚠️ 二分之后**仍要向前退到确实装得下为止**（宽度随长度"单调不减"在换行点上有轻微非单调，由那一步兜住）；`Clamp` 之后 `preferredW <= rectW` 恒成立，可直接拿它做断言。

### DragGestureRouter —— 「拖拽 vs 滚动」手势仲裁

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new DragGestureRouter(dragThresholdPx = 12f, allowScroll = true)` | `float, bool` | `DragGestureRouter` | `<= 0` ⇒ 用 `DefaultDragThresholdPx`；`allowScroll = false` ⇒ 所有越阈值手势都归拖拽（例如已选中那一行不允许滚动） | ScrollRect 里放可拖出的格子 |
| `Begin(pointer)` | `Vector2` | `void` | 按下：开一段新手势（归 `Undecided`）并**清掉上一段可能残留的"压点击"标记** | `OnBeginDrag` / `OnPointerDown` |
| `Move(pointer, escapedScrollRegion)` | `Vector2, bool` | `Step` | 指针移动一拍，返回调用方该做的事（见下「让位规则」）。`escapedScrollRegion` = 指针是否已**离开滚动区**，由调用方算（几何属调用方的画布结构）—— ⛔ 不要偷懒传 `false`，那正是"格子拖不出来"的成因 | `OnDrag` |
| `End()` | - | `Step` | 抬起：返回 `EndScroll` / `EndContent` / `None`，并**在这里一并清掉"压点击"标记**（`ReleaseMouse` 是**先 click 后 endDrag**，此刻清既不影响本次尾巴，又避免残留标记吞掉下一次正常点击） | `OnEndDrag` |
| `ConsumeClickSuppressed()` | - | `bool` | 读一次并清掉"压点击"标记：业务的点击处理**第一行**调它，`true` = "这次点击是拖动的尾巴，忽略" | `Button.onClick` 首行 |
| `DragThresholdPx` / `AllowScroll` | `float` / `bool` | - | 判"拖动而不是点击"的位移阈值（像素）/ 是否允许"纵向占优 ⇒ 归滚动" | 手感配置 |
| `Current` / `LastGestureName` / `ClickSuppressed` | - | `Gesture` / `string` / `bool` | 当前归属（`Undecided`/`Scroll`/`Content`）/ **最近一次实际走的分支名**（自检 / 驱动脚本读它，避免"只看日志"）/ 本手势是否已"真的拖动过" | 自检 / 诊断 |
| `Gesture` / `Step`（枚举） | - | - | `Gesture`：`Undecided` / `Scroll` / `Content`。`Step`：`None` / `BeginScroll` / `MoveScroll` / `EndScroll` / `BeginContent` / `MoveContent` / `EndContent` / `EscalateToContent` | 驱动转发 |

> **让位规则（优先级从高到低，一段手势只有一个归属）**：① 指针已拖到**滚动区之外**（`escapedScrollRegion`）⇒ 归**拖拽**（**必须优先于方向判定**：列表在下方、目标槽位在上方时，"把格子拖到槽位"的主方向恰恰是纵向，只按方向判会把它当滚动 —— 实测拖向槽位 `Δ=(62.8, +251.3)` 被判成 scroll，格子一个都没动）；② 否则**纵向占优**（`|dy| > |dx|`）⇒ 归滚动、**横向占优** ⇒ 归拖拽；③ 一旦定为拖拽就**不再改主意**；滚动中的手势若拖出滚动区仍会**升格**为拖拽（真实手势一定是"先在列表里、再拖出去"）⇒ 返回 `EscalateToContent`。**升格时必须先给滚动收尾**（调用方转 `ScrollRect.OnEndDrag`），否则它会一直停在"拖动中"，残留的速度 / 惯性会在下一帧继续挪内容。
> ⚠️ **为什么是"返回 `Step` 让调用方去转发"而不是本件自己搬 content**：`ScrollRect.OnBeginDrag/OnDrag/OnEndDrag` 是 `public virtual` 的正式事件入口，转发后惯性 / 回弹 / 边界全走既有实现（⛔ 不重造轮子）；而且它是在**转发那一刻**才记 `m_PointerStartLocalCursor` / `m_StartPosition` ⇒ 从手指中段接管**不会跳一下**。本件**不引用** `ScrollRect` / `EventSystem` / `PointerEventData`。
> ⚠️ **为什么必须有它（两条 uGUI 机制）**：① uGUI 把 `pointerDrag` 判给**最靠前（最深层）**的 `IDragHandler` ⇒ 格子上的本件拿到事件后**必须自己决定**归谁，否则"纵向拖动 = 滚动列表"和"把格子拖出来"会在同一个 GameObject 上互相抢；② uGUI **只在** `pointerPress != pointerDrag` 时才清 `eligibleForClick` ⇒ 把 `Button` 与本件挂在**同一个 GameObject** 上时两者相等 ⇒ 拖完**仍会**触发 `Button.onClick`（现象 = "拖动换位之后又顺手点了这张卡"）。
> ⚠️ 阈值小于 `EventSystem.pixelDragThreshold`（默认 10）**也没用**（轮不到本件）⇒ 别把阈值调到比引擎那道还小。

### SortingLayers —— 2D `sortingOrder` 层级预算 + 深度序 + 同序次级键

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `new SortingLayers(fieldHeightTiles, depthLevelsPerTile = 16, tiebreakMod = 256, tiebreakStep = 1e-4f)` | `float, int, int, float` | `SortingLayers` | `fieldHeightTiles` **必给**（世界尺寸属业务，⛔ 引擎不替它定死；`<= 0` / Inf ⇒ 按 1 格 + 限频 Warn）；**一层一实例**（同进程里横版 / 竖版或两个不同尺寸的世界各持一份） | 俯视 2D 的层级分配 |
| `DepthOrder(worldY)` | `float` | `int` | 角色层在给定世界 y 处的 `sortingOrder` = `Actor + round((FieldHeightTiles/2 − worldY) × DepthLevelsPerTile)` —— **y 越小（越靠屏幕下方）order 越大（后画 ⇒ 挡在前面）** | 角色写 `renderer.sortingOrder` |
| `TiebreakOffset(id)` | `int` | `float` | 同 `sortingOrder` 下的**确定性次级键**：只由实体 id 决定的微小 **z** 偏移（格）。⛔ 只允许用**逐帧不变**的量（id）—— 用帧号 / lerp 进度会让次序来回翻，等于没修 | 同格堆叠写 `transform.localPosition.z` |
| `ValidateBudget()` | - | `bool` | 检查层级预算，不自洽 ⇒ 限频 Warn + `false`（建好配置后调一次即可） | 启动期自检 |
| `BudgetValid` | - | `bool` | `ActorOrderMin > Structure`（角色不压在建筑下）且 `ActorOrderMax < Overlay`（血条不被角色盖）且 `Overlay < Effect` | 判据 |
| `ActorOrderMin` / `ActorOrderMax` | - | `int` | 角色层可能取到的最小 / 最大 order（= 场地最上 / 最下端，由 `DepthOrder` 在同端点上求，⛔ 不另写一份公式） | 预算计算 |
| `Ground` / `Decoration` / `Structure` / `Indicator` / `Actor` / `Overlay` / `Effect` | `int` | - | **层级预算表**（默认 `0 / 10 / 50 / 200 / 1000 / 2000 / 3000`，与原项目取值一致）—— ⛔ 每项都可覆盖 | 分层 |
| `FieldHeightTiles` / `DepthLevelsPerTile` / `TiebreakMod` / `TiebreakStep` | `float` / `int` / `int` / `float` | - | 场地纵向格数 / 深度分辨率（级/格，默认 16）/ 次级键取模基数（默认 256 = 可区分的同格堆叠上限）/ 次级键步长（默认 1e-4 格） | 参数化 |
| `DefaultDepthLevelsPerTile` / `DefaultTiebreakMod` / `DefaultTiebreakStep` | - | `int` / `float` | `16` / `256` / `1e-4f` | 常量 |

> ⚠️ **同序为什么必须有确定性次级键（Unity 官方手册「2D 渲染顺序」）**：排序层 → 层内顺序 → 渲染队列 → **距离** → 排序组 → 材质；「距离」条目明写"正交：Unity 使用从相机平面到游戏对象中心的距离，**要控制渲染顺序，请增加或减少 z 位置**"，同页又写明"若两个游戏对象上述值都相同，Unity 用内部渲染队列顺序决定先后 —— **此顺序是不固定的，您无法控制**"。⇒ 位置**完全重合**的单位（一次 6 只落在同一格）必然拿到同一个 `sortingOrder`，谁盖谁就回到枚举顺序 ⇒ **每帧可能不同**（实测 `frame=5907 pos=(-5.5,2.5) n=3 order=[1216,1216,1216]`）⇒ 两张不同动画帧的贴图在同像素上互相翻盖。
> ⚠️ **次级键用 z 而不是再细分 `sortingOrder`**：`sortingOrder` 是 int，再细分就会撞穿层级预算（角色层上界要 **< 血条层**）；z 是**同一 `sortingOrder` 内**的次级排序键，不占 int 预算。
> ⚠️ **两个必查口径**：① 预算**必须逐段检查**（`ValidateBudget`）—— 角色层最大 order 一旦 ≥ 血条层，症状是"血条被自己单位的精灵盖住"（很显眼但很难猜是层级算错），也可能是"站在建筑前面的兵被建筑盖住"；② **深度序的方向不能反**（写反不会报错，只会"后面的兵盖住前面的兵"）。③ 次级键的 `TiebreakStep × TiebreakMod`（默认 `1e-4 × 256 = 0.0256`）**必须小于 1 个 order 级**（1/16 格 = 0.0625 格），否则 z 会把本该在前的单位压到后面。
> ⛔ 不要把 `sortingOrder` 的取值散落在各 `MonoBehaviour` 里（原项目散在视图类 + 它的嵌套静态类里，别的项目要照抄一遍，连同"忘了留预算"的坑）。

### ScreenPointUtil —— 屏幕点 ↔ 画布矩形 / 世界点换算（+ 正交「屏幕 → 地面」）

| API | 入参 | 返回 | 说明 | 典型场景 |
| --- | --- | --- | --- | --- |
| `ScreenPointUtil.CameraForCanvas(canvas)` | `Canvas` | `Camera` | **按画布模式取相机**（本件的核心口径）：`ScreenSpaceOverlay` ⇒ **`null`**（它的世界坐标**就是屏幕像素**，不能再投一次）；否则 ⇒ 画布自己的 `worldCamera`；`canvas == null` ⇒ `null` | 换算前取相机 |
| `ScreenPointUtil.CameraForUi(context)` | `Component` | `Camera` | 同上，从 `context` 用 `GetComponentInParent<Canvas>()` 向上找画布；`context == null`（面板还没挂到画布上）⇒ 取不到画布 ⇒ 按 Overlay 处理（`null`） | 面板内取相机 |
| `TryScreenToWorldInRect(rect, screen, cam, out world)` / `(…, context, out world)` | `RectTransform, Vector2, Camera / Component, out Vector3` | `bool` | 屏幕点 → 矩形所在平面上的**世界点**（拖幽灵体 / 定位子节点）；`rect == null` ⇒ `false` + 限频 Warn（⛔ 不返回"成功 + 零向量"，那会让调用方把元素摆到原点）。`context` 重载按画布模式自动取相机 | 拖拽幽灵体定位 |
| `TryScreenToLocalInRect(rect, screen, cam, out local)` / `(…, context, out local)` | `RectTransform, Vector2, Camera / Component, out Vector2` | `bool` | 屏幕点 → 矩形内的**局部点**（命中测试 / 列表内定位）；口径随锚点轴心，⛔ 别自己拿 `anchoredPosition` 凑 | 列表内定位 |
| `ContainsScreenPoint(rect, screen, cam)` / `(…, context)` | `RectTransform, Vector2, Camera / Component` | `bool` | 屏幕点是否落在矩形的**屏幕矩形**内（命中测试）；⛔ **相机必须按画布模式取**（见下方根因）。`rect == null` ⇒ `false` + 限频 Warn | 手牌命中测试 / "拖出列表上沿"判定 |
| `TryScreenToGround(cam, screen, out world, fallbackDepth = 10f)` | `Camera, Vector2, out Vector3, float` | `bool` | 屏幕点 → **地面（z = 0）世界点**（正交相机）。契约：`depth = -cam.transform.position.z`；`Mathf.Approximately(depth, 0)` ⇒ **退化为固定值** `fallbackDepth`（否则 `ScreenToWorldPoint` 恒返回同一点，表现为"点击位置不随鼠标移动"）。相机为 `null` ⇒ `false` + 限频 Warn（⛔ 不返回 `(0,0,0)` 当成功）；相机非正交 ⇒ 限频 Warn 后照算 | 点击落点格换算 |
| `DefaultFallbackDepth` / `Tag` | - | `float` / `string` | `10f` / 日志标签 | 常量 |

> **★ 根因（照抄来源工程的实机读数，2026-09-22）**：常驻画布 `canvas.renderMode = ScreenSpaceOverlay`（引擎 `Runtime/Presentation/UI.cs:49`），其世界坐标**就是屏幕像素**。实测（1080×1920 画布 + 正交半高 16 的场地相机，相机在 `(0,0,-10)`）：某 UI 元素中心的真屏幕点 `=(214,221)`，`RectangleContainsScreenPoint(rect, (214,221), mainCam) = False`、传 `null` 时为 `True` ⇒ 命中测试返回 -1 ⇒ **按下根本不进入拖拽链**（症状 = "卡牌拖不动 / 放不上战场"）。⇒ **⛔ 所以相机必须按画布模式取，不是"取一台相机就完事"**：Overlay ⇒ `null`；`ScreenSpaceCamera` / `WorldSpace` 才用画布自己的 `worldCamera`。**⚠️ 与之相反的一条别混**：竞技场那边"屏幕 → 格"要的**正是**相机的投影，仍用 `UIFactory.UICamera()`（引擎给 UI 侧取世界相机的官方入口）—— 两件事，⛔ 不要互换。
> **★ 裁决（2026-09-24，本次下沉评审）**：`TryScreenToGround` 与 `IsoLayout.ScreenToWorldOnGround` **两份保持两份、不收敛**。理由与前提：· 「正交 → 地面」是同一条规则的两份实现 —— 本件 fallback **参数化**、只出**世界点**（面向 UI / 输入侧）；`IsoLayout` 那份 fallback **写死 `10`**、顺带产出**格**坐标（面向格子的调用点）。· ⛔ **将来若要收敛，前提是先给 `IsoLayout` 补 static 入口** —— 否则调用方（UI / 输入侧）为了拿一个世界点，得先 `new IsoLayout(...)` 填齐 4 个它根本用不到的构造参（格宽 / 格高 / 排序基准 / 步长）。即：收敛的**前置条件**是 `IsoLayout` 自己先提供一个不需要实例的等价入口，⛔ 而不是把调用方赶去填 4 个用不到的参数。
> ⚠️ **越界代价（这就是它被下沉的原因）**：`RectTransformUtility` 收**非空**相机时会把屏幕点当成"相机视锥里的一个方向"再投到画布平面 ⇒ 与 Overlay 画布（世界坐标 = 屏幕像素）相差一次相机投影。三份逐字重复的实现各自把这条写了一遍注释（说明它**每处都要重新踩一次**）。
> ⚠️ 画布模式取错**不会抛异常**，只会让命中**恒为 `false`**（"点了没反应"）或让元素整体偏一次投影；所有 `Try*` 入口失败返回 `false` 并把 `out` 置零、**不抛异常**（拖拽链路上"抛出去"会打断 uGUI 事件派发）。
> ⛔ **唯一真相包的边界**：面向**格坐标**的换算请用 `IsoLayout.ScreenToWorldOnGround` / `ScreenToGrid`；本件只做「屏幕 ↔ 画布矩形 / 世界点」与「正交屏幕 → 地面世界点（退化值可参数化）」。

### HitShape —— 命中判定几何（正面扇形 / 矩形走廊 / 线段通畅）

**含义**：攻击判定形状的**唯一实现**（纯函数静态工具，无状态）。
两个形状**必须同时成立**才算"在攻击形状内"：① 正面扇形（夹角余弦 ≥ `cosMin`）② 矩形走廊（沿轴 ∈ `[0, reach]` 且 `|垂距| ≤ halfWidth`）；
`LineClear` 是**独立的一关**（近战与远程都要过）。⛔ 引擎不预设 60° / 1.2 格这类题材数值 —— `cosMin` / `reach` / `halfWidth` 全部由调用方传。

| API | 入参 | 返回 | 说明 |
| --- | --- | --- | --- |
| `HitShape.ToUnit(dx, dy, out fx, out fy)` | `int, int, out float, out float` | `bool` | 朝向的**格增量** → **单位向量**。`false` = 零向量（出参置 0）⇒ 调用方据此**拒绝**本次攻击并留痕 |
| `HitShape.InFrontCone(fx, fy, dx, dy, cosMin)` | `float ×5` | `bool` | 目标偏移与朝向单位向量的夹角余弦 ≥ `cosMin`；**零偏移（与攻击者同格）恒 `true`** |
| `HitShape.InMeleeRect(fx, fy, dx, dy, reach, halfWidth)` | `float ×6` | `bool` | 以朝向为轴的矩形走廊：`along = (dx,dy)·朝向 ∈ [0, reach]` 且 `\|perp\| ≤ halfWidth`（正后方恒不命中） |
| `HitShape.LineClear(walkable, from, to, maxSteps = MaxLineSteps)` | `Func<Vector2Int,bool>, Vector2Int, Vector2Int, int` | `bool` | Bresenham 线上**除两端点外**每格都要可走；`from == to` ⇒ 恒 `true` |
| `HitShape.MaxLineSteps` | - | `int` | `1024`（线段遍历的格步数上限） |

```csharp
// 朝向的格增量一律走引擎权威表（本件不自己写 Dir8 → 增量映射表）
var delta = iso.DirectionDelta(dir);
if (!HitShape.ToUnit(delta.x, delta.y, out var fx, out var fy)) return;   // 零向量 ⇒ 拒绝本次攻击
var inShape = HitShape.InFrontCone(fx, fy, tdx, tdy, cosMin)      // tdx/tdy = 目标相对攻击者的格偏移
           && HitShape.InMeleeRect(fx, fy, tdx, tdy, reach, halfWidth);
var clear   = HitShape.LineClear(walkable, attackerCell, targetCell);     // 独立的一关
```

> ⚠️ **同格（零偏移）在扇形里恒命中**：原版的近战触及是**距离 / 外接框**口径（`Weapons.txt` 的 `rangeadder`、`MonStats2.txt` 的 `MeleeRng` 都是**格数**）⇒ `0 ≤ reach` 恒真，"同格"本该命中。⛔ 别改成"同格不命中"，也 ⛔ 别把扇形放宽成圆形（只补这一个退化点）。
> ⚠️ `walkable == null`（地图未接入）⇒ `LineClear` **放行（返回 `true`）** + 降频 Warn —— ⛔ 不把"拿不到地图"变成"打不到"。
> ⚠️ 格步数超过 `maxSteps` ⇒ 返回 `false`（按"不通"处理 + 降频 Warn）：那是**入参异常**（坐标 / 半径算错）的防御分支，不是正常路径。
> ⚠️ 格坐标一律 `Mathf.FloorToInt`；⛔ 不要用 `(int)` 强转（负数向零截断会让格错半格，且**不报错**）。
> ⛔ 不要自己再写一份「扇形 + 走廊 + 线段通畅」（三份逐字重复的实现各自把同一条边界重新踩过一遍）。

### GridGraph / GridBitSet —— 格子图算法底座 + 格集合位图编解码

**含义**：`GridGraph` 是**格子图的通用算法底座**（8 邻接 BFS 连通性 / 未达标目标计数 / 封闭不可达口袋 / 边界环封 / 可走格索引与 O(1) 抽样 / 批量绘制回调）；
`GridBitSet` 是**「格集合 ↔ base64 位图」编解码**（小地图已探索格这类大集合的落盘格式：逐格幂等 + 越界丢弃 + 坏串不抛）。
矩形 → 整数格遍历见上文 `GridUtil` 一节（同一族的第三个件）。

| API | 入参 | 返回 | 说明 |
| --- | --- | --- | --- |
| `GridGraph.FloodFill(isWalkable, width, height, from, visited)` | `Func<Vector2Int,bool>, int, int, Vector2Int, bool[,]` | `int` | 8 邻接 BFS，可达格在 `visited` 里标 `true`。**对角步要求两侧格都可走**（否则会"贴着墙角穿过去"）。起点不可走 / `visited` 尺寸不符 ⇒ 0 |
| `GridGraph.CountUnreachableTargets(isWalkable, width, height, from, targets, out reachedCount, out firstUnreachable)` | `…, IReadOnlyList<Vector2Int>, out int, out Vector2Int` | `int` | 数出 `targets` 里**不可达**的目标数（随机撒点用了它才敢保证"掉落拿得到 / 怪物打得到"）。内部自己跑一次 BFS |
| `GridGraph.FillUnreachablePockets(isWalkable, width, height, visited, isRequired, fill, out keptProtected)` | `…, bool[,], Func<Vector2Int,bool>, Action<int,int>, out int` | `int` | 把**走不到的孤立可走口袋**逐格交给 `fill`；`isRequired` 返回 `true` 的格**不填**（留给连通性自检判失败）。`visited` 必须先由 `FloodFill` 填好 |
| `GridGraph.SealBorderRing(width, height, n, isWalkable, seal)` | `int, int, int, Func<Vector2Int,bool>, Action<int,int>` | `int` | 把**边界环**（距任一地图边 < `n` 格）里现在还可走的格逐格交给 `seal` 封掉；`n <= 0` ⇒ 0 且不写任何格 |
| `GridGraph.WalkableIndex.Rebuild(isWalkable, width, height)` / `.Pick(index)` | `Func<Vector2Int,bool>, int, int` / `int` | `int` / `Vector2Int` | 可走格列表索引：`Rebuild` 一次，之后 `Pick` 是 **O(1)**。填充顺序是契约（`x` 外层升序、`y` 内层升序） |
| `GridGraph.Fill / FillRect / LineH / LineV / FillDisk / SetOnWalkable` | `…, Action<int,int> write` | `void` / `bool` | 批量绘制**回调式**写格 |
| `GridBitSet.Encode(indices, w, h, maxCells = MaxCells)` | `IEnumerable<int>, int, int, int` | `string` | 格索引集合 → base64 位图（行优先，`i = y*w + x`，低位在前）。越界索引**丢弃**；尺寸非法 / 超上限 ⇒ **空串** |
| `GridBitSet.Decode(cells, w, h, into, maxCells = MaxCells)` | `string, int, int, List<int>, int` | `int` | 位图 → 格索引（**只并入、不清空** `into`），返回本次并入格数。`base64` 非法（旧档 / 手改）/ 尺寸非法 ⇒ `0` 且**不抛**；短串 ⇒ 后面的格视为未探索 |
| `GridBitSet.IndexOf(x, y, w, h)` / `ToCell(index, w, h, out x, out y)` | - | `int` / `bool` | 坐标 ↔ 索引互转（越界 ⇒ `-1` / `false`） |
| `GridBitSet.MaxCells` | - | `int` | `1 << 20` = 1,048,576 格（防坏档里的超大 `w*h` 吃掉几百 MB） |

```csharp
// 连通性三件：数不可达 → 封不可达口袋 → 封边界环
var unreachable = GridGraph.CountUnreachableTargets(walkable, w, h, start, targets,
                                                    out var reached, out var firstBad);
if (reached == 0) { /* 起点就不可走 ⇒ 整体失败，提前返回 */ }
GridGraph.FillUnreachablePockets(walkable, w, h, visited, isRequired: null, fill: SetWall, out _);
GridGraph.SealBorderRing(w, h, 1, walkable, seal: SetWall);

// O(1) 随机取一个可走格（掉落 / 刷怪）
var index = new GridGraph.WalkableIndex();
index.Rebuild(walkable, w, h);
var cell = index.Pick(rng.Next(index.Count));

// 大格集合落盘 / 读回（小地图已探索格这类）
var cells = GridBitSet.Encode(explored, w, h);     // 同集合 ⇒ 同串（确定性）
var n     = GridBitSet.Decode(cells, w, h, into);  // 坏串 / 旧档 ⇒ 0，into 不变
```

> ⚠️ `GridGraph` 的 `isWalkable` **必须对"图外"返回 `false`**（BFS / 口袋填充都按这条判边界）。
> ⚠️ `CountUnreachableTargets` 在 `reachedCount == 0` 时**仍会数**（结果 = 全部目标不可达）⇒ 调用方必须先判 `reachedCount == 0` 并当作整体失败。
> ⚠️ `visited` 是调用方按 `[width, height]` 分配、初值全 `false` 的数组；尺寸不符 ⇒ 引擎**拒答**（返回 0 / 不填充）+ 留痕 —— 拿错数组会把可走区**整片填掉**，且不报错。
> ⚠️ `GridBitSet` 的位图口径（行优先 `i = y*w + x`、低位在前）是**格式契约**：改了就读不了旧档（"同集合恒得同串"是它的自证判据）。
> ⛔ 不要自己再写一份「格集合 ↔ base64」或「BFS 连通性」。

### PathFollower —— 沿 A* 逐格路径推进 + 朝向

**含义**：把 `AStar.Find` 产出的**逐格路径**变成"每 tick 走多远 + 朝向哪边"（纯逻辑类：不继承 `MonoBehaviour`、不持有 `GameObject` ⇒ 可在离线宿主里逐帧复算）。
**分工**：`AStar.Find` 负责寻路，`PathFollower` **只沿路走** —— ⛔ 本件不寻路、不判可走性、不认识任何地图类型。速度 / 重寻路间隔由**构造参数**传入；方向判定走**注入的** `IsoLayout.DirectionTo`。

| API | 入参 | 返回 | 说明 |
| --- | --- | --- | --- |
| `new PathFollower(iso, minMoveSpeed, repathIntervalSeconds)` | `IsoLayout, float, float` | `PathFollower` | `iso` 传 `null` ⇒ **Error 留痕**（朝向更新被跳过，`Pos` / 路径推进仍可用）；两个 `float` ≤ 0 按 0 处理 |
| `SnapTo(grid)` | `Vector2Int` | `void` | 落到该格中心并清空路径与路径目标（进图 / 刷怪 / 复活） |
| `SetPath(path, target)` | `List<Vector2Int>, Vector2Int` | `void` | 喂 `AStar.Find` 的结果（**含起点** ⇒ 本件跳过第 0 个）；`null` / ≤ 1 点 ⇒ 判为"无路径"。同时写入 `RepathTimer` |
| `Advance(tilesPerSecond, dt)` | `float, float` | `bool` | 沿路径推进（**每 tick 一次**）；`true` = 路径已走完（或本来就没有路径） |
| `StepToward(target, tilesPerSecond, dt)` | `Vector2, float, float` | `bool` | 朝某点**直线**走一步（逃跑 / 紧急脱身，⛔ 不做寻路）；`true` = 已到达（距离 < 0.05 格） |
| `Pos` / `Dir` / `Grid` / `Path` / `PathIndex` / `PathTarget` / `HasPathTarget` / `RepathTimer` / `HasRemainingPath` | - | `Vector2` / `Dir8` / `Vector2Int` / … | 连续格坐标（**格中心制**：格 `(gx,gy)` 的中心是 `(gx+0.5, gy+0.5)`）/ 当前朝向（**按格变化**更新）/ 当前格 / 剩余路径 / 下一个路点下标 / 上次寻路目标格 / 重寻路冷却计时 / 是否还有剩余路点 |
| `PathFollower.Center(grid)` | `Vector2Int` | `Vector2` | 格中心的连续坐标（静态纯函数） |
| `MinMoveSpeed` / `RepathIntervalSeconds` | - | `float` | 构造时给的两个参数（只读） |

```csharp
var f = new PathFollower(iso, MonsterTuning.MinMoveSpeed, MonsterTuning.RepathIntervalSeconds);
f.SnapTo(spawnGrid);                        // 进图 / 刷怪 / 复活
f.SetPath(AStar.Find(IsWalkable, f.Grid, goal), goal);
f.Advance(speedTilesPerSecond, dt);         // 每 tick 一次；随后把 f.Dir / f.Pos 同步给视图
if (f.HasPathTarget && f.RepathTimer <= 0f) { f.SetPath(AStar.Find(IsWalkable, f.Grid, goal), goal); }
f.StepToward(targetPos, speed, dt);         // 逃跑：直线走一步
```

> ⚠️ **取格一律 `FloorToInt`**（`Grid` 属性内部就是），⛔ 别用 `(int)` 强转。
> ⚠️ `Advance` / `StepToward` 的入参速度低于 `MinMoveSpeed` ⇒ **按 `MinMoveSpeed` 处理**（配表 0 / 负值不至于原地卡死）；传入合法值时这条一行不生效。
> ⚠️ 朝向**只在格发生变化时**更新（零增量不调 `IsoLayout.DirectionTo` —— 那个会打限频日志，而"这一步没跨格"是正常情形）。
> ⚠️ `RepathTimer` 只是**存好的冷却秒数**，本件**不递减它** —— 由调用方自己 `-= dt` 再判。
> ⛔ 不要自己再写一份"沿路走 + 转向"（各怪各抄一份就是平行再起一套）。

### 瓦片族 —— 池化 / 渲染状态 / 渲染内核 / 程序化生成 / 分块规划

> 同一张 2D 地图上的五个件，分工：`TilemapGenUtil` 造地图数据 → `TileWorld`（见上文「ITileWorld / TileWorld」一节）持有空间事实 →
> `TileRenderer` 把「一格一层」算成渲染状态 → `TileNodePool` 借还节点 → `TileRenderState` 保证"复用与新建逐项相同"；
> `ChunkedTilePlanner` 按块 + 每帧预算决定本轮铺哪些块。

| API | 入参 | 返回 | 说明 |
| --- | --- | --- | --- |
| `new TileNodePool(root)` | `Transform` | `TileNodePool` | `root` = 归还节点的挂载根（挂在业务的地图层根下 ⇒ 随场景销毁），允许 `null`（归还时只失活、不换父） |
| `Take(parent)` / `Return(sr)` / `Clear()` | `Transform` / `SpriteRenderer` | `SpriteRenderer` / `void` | **只有 `Take` 会把节点真建出来**（`new GameObject` + `SpriteRenderer`）；取出即 `SetActive(true)`、归还即 `SetActive(false)`（**严格配对**）；`Clear()` 只销毁**空闲**节点，**不影响已取出的** |
| `SplitDemand(freeCount, demand, out fromFree, out create)` | `int, int, out int, out int` | `void` | **纯函数**：池够 ⇒ 新建 0，不够 ⇒ 只补差额（离线宿主用它做池化收益的算术断言，不必真建 `GameObject`） |
| `CreatedCount` / `ReusedCount` / `FreeCount` | - | `int` | 累计新建 / 累计复用 / **当前空闲数**（⛔ "池里现在几个"看 `FreeCount`，不是 `CreatedCount`；两个计数只增不减，`Clear()` 也不清零） |
| `new TileRenderState(sprite, color, localScale, position, sortingOrder)` | `Sprite, Color, Vector3, Vector3, int` | `TileRenderState` | 一格瓦片的**不可变**渲染状态（5 字段 / 11 标量，全 `readonly`）。⛔ 不许用 `default(TileRenderState)` 当"空状态"（那是全 0，**不是**合法的一格画面） |
| `TileRenderState.SameAs(other)` | `TileRenderState` | `bool` | 5 个字段**逐项逐位**相等（`Sprite` 比引用；不用 `Vector3.Equals` 的 epsilon 语义 —— 判据是"逐位相同"不是"差不多"） |
| `new TileRenderer(iso, pixelsPerUnit, tilePixelsPerUnit)` | `IsoLayout, float, float` | `TileRenderer` | `PixelsPerUnit` = 业务画布口径；`TilePixelsPerUnit` = 一格纹理的像素口径 |
| `StateOf(cell, layer, sprite, placeholderColor, sortOffset, sortBias = 0)` | `Vector2Int, TileLayer, Sprite, Color, int, int` | `TileRenderState` | 把「一格一层」算成一个完整渲染状态（摆位 / 缩放 / 颜色 / 排序号）。层只决定**对齐方式**：`TileLayer.Ground` = 地砖式（贴图顶边贴格中心上方半格）、`Object` / `Overlay` = 墙 / 物件式 |
| `Apply(sr, parent, state)` / `Build(takeNode, parent, state)` / `ApplyPlan(plan, cell, …)` | `SpriteRenderer, Transform, TileRenderState` / … | `void` / `SpriteRenderer` / `int` | **无条件写全** 5 个渲染字段（+ `enabled = true`）；`Build` = 取节点 + 写全一步到位。输入值类型为 `TileCellPlan`（计划）与 `TileLayerParams`（该层排序偏移 / 偏置 / 占位色） |
| `TilemapGenUtil.TryBuildSlotMaze(rng, slotsX, slotsY, loopsMin, loopsMax, …)` | `Rng, int, int, int, int, …` | `bool` | **块级迷宫**生成（全连通 + 环路）；配套 `ConnectSlots` / `TryVerifySlotConnectivity`（连通性自检） |
| `TilemapGenUtil.TryPickByEdges(rng, pieces, group, …)` / `StampPiece(…)` | `Rng, IReadOnlyList<EdgePiece>, int, …` | `bool` / `int` | 按**四边开口**（`PieceEdges` / `Dir4Mask`）挑拼块并盖章（支持翻转 —— `EffectiveEdges` 会同步换算边） |
| `new ChunkedTilePlanner(chunkSize, maxNodesPerFrame)` | `int, int` | `ChunkedTilePlanner` | 块划分 + **每帧节点预算** + 双缓冲换块 |
| `BeginFrame()` / `TryAccept(nodeCost)` / `RequestRebuild()` / `ConsumeRebuild()` | - / `int` | `void` / `bool` | 每帧先 `BeginFrame` 复位计数，再逐个 `TryAccept`（超预算 ⇒ `false`，**不截断已接受的**）；`RequestRebuild` / `ConsumeRebuild` 管"有待重建"标志 |
| `ChunkRangeOf(…)` / `EnumerateChunks(…)` / `ChunkCount(…)` / `FloorDiv(v)` | `int, …` | `void` / `int` | 格范围 → 块范围 / 枚举可见块 / 块计数 / 向下取整除法（负格口径） |
| `AcceptedThisFrame` / `RejectedThisFrame` / `RebuildPending` / `FrontBuffer` / `BackBuffer` | - | `int` / `bool` | 本轮接受 / 拒绝的节点数、"有待重建"标志、双缓冲下标 |

```csharp
// ① 一格一层的完整渲染状态：由纯函数算出
var st = tileRenderer.StateOf(cell, TileLayer.Ground, groundSprite, placeholderColor,
                             sortOffset: layers.Ground);

// ② 取节点 + 无条件写全 5 个字段（+ enabled）
var sr = pool.Take(layerRoot);
tileRenderer.Apply(sr, layerRoot, st);

// ③ 退场：归还（失活 + 挂回池根），⛔ 不是 Destroy
pool.Return(sr);

// ④ 每帧预算 + 分块规划
planner.BeginFrame();
foreach (var chunk in visibleChunks)
{
    if (!planner.TryAccept(chunkNodeCount)) break;   // 超预算 ⇒ 本轮不铺，下一帧继续
    BuildChunk(chunk);
}
```

> ⚠️ **池化最典型的静默失效**：复用出来的节点如果"记得就重设、漏了就继承上一次"，画面会带着**上一格的贴图 / 颜色 / 排序号**出现 —— 不报错、只有看图才发现。所以渲染字段**无条件写全**（`TileRenderState` 就是这件事的结构性保证）。
> ⚠️ `TileNodePool` 的 `Take` / `Return` 必须**严格配对**：`Return` **不查重**（重复归还会让同一节点被压两次 ⇒ `FreeCount` 偏大 + `Take` 可能拿到同一个节点两次）。
> ⚠️ `TileNodePool` ≠ `Game.Pool`：`Game.Pool` 是 **GameObject 级**池（key / 预制体 / 工厂 / 归还时归零变换 / `DontDestroyOnLoad` 池根）；`TileNodePool` 只池化一种东西、**故意不归零变换**（渲染字段由调用方写全）、池根随场景销毁。两者可并存。
> ⚠️ `TileRenderState` ⛔ **只放渲染状态**：业务字段（tile kind / 块号 / 是否已探索…）塞进来会让池化路径开始"继承上一次的残留业务状态"。
> ⚠️ `ChunkedTilePlanner.TryAccept` 超预算返回 `false` ⇒ **本轮不铺这一块、下一帧继续**（不是截断已经接受的那些）。
> ⛔ 不要自己再写一份「节点池 + 逐格渲染」（同形状在各工程里重写过 N 遍，每次都要重新踩一遍"复用不写全"）。

### SceneScaffold —— 最小可运行场景脚手架（编辑器）

**含义**：把**每个工程开工都要写一遍**的三件事收进引擎的 `Editor` 程序集：
① 生成（覆盖）一个最小可运行场景（主相机正交 + `MainCamera` tag + `AudioListener` + 可选 URP 2D 灯光 + 命名根节点 + 入口脚本）；
② **幂等**写 `EditorBuildSettings`；③ **幂等**设 Play 起始场景。
⛔ 引擎侧**一个业务取值都不带**：场景名 / 相机参数 / 根节点名 / 入口类型全由调用方给。

| API | 入参 | 返回 | 说明 |
| --- | --- | --- | --- |
| `SceneScaffold.Create(scenePath, options, out error)` | `string, SceneScaffoldOptions, out string` | `bool` | 生成并保存场景；`false` ⇒ `error` 是可定位原因（`scenePath` 为空 / 保存失败 / **入口脚本类型找不到**）。随后按选项写 Build Settings / Play 起始场景 |
| `SceneScaffoldOptions` | 结构体（公开字段） | - | `OrthoSize` / `CameraZ` / `MapRootName` / `EntityRootName` / `EntryTypeName` / `Create2DLight` / `SolidColorBackground` / `ClearColor` / `NearClip` / `FarClip` / `AddUrpCameraData` / `AdditiveMode` / `CloseAfterSave` / `ApplyBuildSettings` / `SetPlayModeStartScene` |
| `SceneScaffold.ApplyBuildSettings(scenePaths, replace = false)` | `IList<string>, bool` | `bool` | **幂等**：给定场景按序在最前（`replace` ⇒ 结果只有它们）；**返回是否真的发生了写入**（已正确 ⇒ `false` 且不写） |
| `SceneScaffold.SetPlayModeStartScene(scenePath, onlyIfNull = false)` | `string, bool` | `bool` | 设为 Play 起始场景（幂等），返回是否写入；找不到场景资产 ⇒ 限频告警 + `false`（保持原值，**不抛**） |
| `SceneScaffold.FindTypeByName(fullName)` / `FindTypeBySimpleName(simpleName)` | `string` | `Type` | **反射**解析业务类型（Editor 工具不依赖业务程序集 ⇒ 业务程序集编译失败时仍能给诊断）。简名命中多个 ⇒ 取第一个 + 限频告警 |
| 菜单 / 批处理入口 | - | - | 菜单 `Clover/场景脚手架/生成最小可运行场景…`；批处理 `-executeMethod CloverEngine.Editor.SceneScaffold.ExecuteFromCommandLine -scene <path>`（可加 `-ortho` / `-cameraZ` / `-mapRoot` / `-entityRoot` / `-entry`；**失败在批处理下 `Exit(1)`**） |

```csharp
// 代码路径（编辑器脚本 / 自己的工程生成器里调）
var ok = SceneScaffold.Create(
    "Assets/Scenes/Boot.unity",
    new SceneScaffoldOptions
    {
        OrthoSize = 5f,
        CameraZ = -10f,
        MapRootName = "MapRoot",
        EntityRootName = "EntityRoot",
        EntryTypeName = "MyGame.GameMain",
        Create2DLight = true,
        ApplyBuildSettings = true,
        SetPlayModeStartScene = true,
    },
    out var err);
```

```
# 批处理路径（CI / 命令行）
unity -batchmode -projectPath <client> \
  -executeMethod CloverEngine.Editor.SceneScaffold.ExecuteFromCommandLine -scene Assets/Scenes/Boot.unity
```

> ⚠️ **场景必须在 Build Settings 里** —— `Game.Scene.Load(name)` 走 Unity 场景加载，不在表里就加载不到。
> ⚠️ `AdditiveMode = true` ⇒ 新场景**按叠加方式**建（不替换用户当前打开的场景、不弹保存框）；配合 `CloseAfterSave = true` 存完立刻关掉临时场景。代码里 `new GameObject(...)` 会落进**当前活动场景** ⇒ `AdditiveMode` 下本件会主动 `MoveGameObjectToScene`。
> ⚠️ URP 2D 灯光与 `UniversalAdditionalCameraData` 走**反射可选接入**（拿不到 `Light2D` 类型就跳过 + 留一行日志）：Editor 程序集只引用引擎自己的程序集，硬引用 URP 会让没装 URP 的工程**编不过**。
> ⛔ 不要自己再写一份场景生成器 / Build Settings 写入（同形状曾每个工程重写一遍）；`ApplyBuildSettings` / `SetPlayModeStartScene` 的**返回值**就是"有没有写"的判据。
> 另有启动自愈体检：Build Settings **为空**时只发一条 Warn（正常工程零日志），因为那会让 `Game.Scene.Load` 必失败。

### ClientConfig（`ConfigSectionLoader<T>` / `ConfigSource`） —— 带默认值的配置段加载链

**含义**：把「**按顺序试 N 个配置来源 → 任一来源读不出 / 解析不了就退到下一个 → 全坏就用内置默认值 → 改完文件能 `Reload`**」这段控制流收进引擎。
⛔ 本件**不写盘、不认识键、不做类型转换** —— "值从哪来"由调用方注入；**字段类型（泛型 `T`）、具体来源、具体默认值全留调用方**。
分工（⛔ 别当第二套 `Setting` 用）：`Setting` = **可写的单文件 KV 存储**（`Set` / `Get` / `Save`）；`FileSlotStore` = **一槽一文件**的文本存储（存档 / 回放 / 草稿）；本件 = **只读的配置来源链**。

| API | 入参 | 返回 | 说明 |
| --- | --- | --- | --- |
| `new ConfigSource(name, readText, logLabel = null)` | `string, Func<string>, string` | `ConfigSource` | 一条来源：显示名（命中它时会成为 `Source` 的取值）+ 读文本的委托 + 解析/日志标签（空 ⇒ 用 `name`） |
| `new ConfigSectionLoader<T>(tag, sources, parse, createDefault, normalize = null)` | `string, IEnumerable<ConfigSource>, Func<string,string,T>, Func<T>, Action<T,string>` | `ConfigSectionLoader<T>` | `T` 是**引用类型**（`where T : class`）；`sources` **按顺序**试（`null` / 空 ⇒ 直接走默认值）；`parse` 返回 `null` = 本来源解析失败；`createDefault` 是**默认值的唯一出处** |
| `Value` | - | `T` | 配置对象（**惰性**：首次访问触发一次加载，之后返回缓存值直到 `Reload()`） |
| `Source` / `Loaded` / `LoadCount` | - | `string` / `bool` / `int` | 当前命中的来源显示名（`"默认值"` / `"(未加载)"`）/ 是否加载过 / 已执行过几次加载。**读 `Source` 不会触发加载** |
| `Reload()` / `Load()` | - | `T` | 重跑整条来源链（热改）返回新值 / 显式加载一次（调用方通常只用 `Value` + `Reload`） |
| `ConfigSectionLoader<T>.DefaultSourceName` / `NotLoadedSourceName` | - | `string` | `"默认值"` / `"(未加载)"`（判据常量） |

```csharp
var loader = new ConfigSectionLoader<MyRoot>(
    "Cfg",
    new[]
    {
        new ConfigSource("Resources/Configs/config", () => AssetText()),
        new ConfigSource("文件:" + path,              () => ReadFileText(path), path),
    },
    parse: (json, from) => Parse(json, from),      // 返回 null = 本来源解析失败（解析器自己留痕）
    createDefault: () => new MyRoot(),             // 默认值的唯一出处
    normalize: (root, from) => Clamp(root, from)); // 可选：逐字段兜底 / 裁剪 / 越界告警

var cfg = loader.Value;      // 惰性：首次访问触发一次加载
loader.Reload();             // 热改（重跑整条链）
var log = loader.Source;     // "Resources/…" / "文件:…" / "默认值" / "(未加载)"
```

> ⚠️ **`ReadText` 的两种"坏"语义不同**：返回 `null` / 空串 / **纯空白** = 「本来源**没有内容**」⇒ 引擎**静默跳过**（不打日志）；**抛异常** = 「本来源读取失败」⇒ 引擎记一条 Warn 后改试下一个来源（⛔ **不向上抛**）。
> ⚠️ `parse` 返回 `null` = 本来源解析失败（引擎补一条来源级跳过日志后改试下一个）；`parse` 抛异常按"解析失败"处理。
> ⚠️ `normalize` 抛异常 ⇒ **该来源整体不可用**（拿它继续跑等于把坏值交给业务）⇒ 引擎改试下一个来源。它收到的第二参就是该来源的 `LogLabel`，便于点名是哪份配置越界。
> ⚠️ 全部来源都不可用 ⇒ `Source = "默认值"`、`Value = createDefault()`（+ 一条 Warn）；⛔ **绝不抛异常**（配置问题不该让游戏起不来）。
> ⚠️ 非线程安全（主线程使用，与 `Setting` / `FileSlotStore` 一致）；本件不依赖 `UnityEngine`（只用 `System`）⇒ 离线自检宿主可直接链进工程跑。
> ⚠️ **与 `Setting` 的分工**：要"存下来 / 改一改"用 `Game.Setting`；要"读一份配置、坏了就回默认"用本件。
> ⛔ 不要自己再写一份"多来源回退 + 容错解析 + Reload"（那是每个工程重写一遍的控制流；项目侧只剩"这项目的 config.json 长什么样"）。参考实现见 `clover-ai-skill/patterns/client/config.md`。

---

## 局域网寻服（LanBrowser / ILanResponder）

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.LanBrowser.Scan(options)` | `LanScanOptions` | `void` | 开始一轮扫描（`null` = 全默认：端口 `47777` / 窗口 1500ms / 回环 + 广播 + 子网广播） | 进「找服」界面 |
| `Game.LanBrowser.Stop()` | - | `void` | 提前结束本轮（保留已发现结果）；未扫描时幂等空操作 | 玩家取消 |
| `Game.LanBrowser.Hosts` | - | `IReadOnlyList<LanHostInfo>` | 最近一轮只读快照（上限 64，同 gateway 去重） | 列表 UI |
| `Game.LanBrowser.State` / `IsSupported` / `UnsupportedReason` | - | `LanBrowserState` / `bool` / `string` | 扫描状态 / 平台是否可用 / 不可用原因 | 禁用按钮 + 提示 |
| `Game.LanBrowser.OnHostFound` / `OnScanFinished` | `Action<LanHostInfo>` / `Action` | - | 发现一台 / 一轮结束（主线程；等价事件 `Net.LanHostFound` / `Net.LanScanFinished`） | 增量刷列表 |
| `CloverLan.CreateResponder()` | - | `ILanResponder` | 取应答端（**不经 `Game` 门面**，调用方负责 `Dispose()`） | 玩家当主机 |
| `responder.Start(self, options)` | `LanHostInfo, LanRespondOptions` | `bool` | 开始应答（幂等；`self.Host` 留空 = 自动取本机 IPv4）；失败看 `LastError`，**不抛** | 开主机 |
| `responder.Stop()` / `responder.Dispose()` | - | `void` | 停止 / 释放（都幂等） | 退出主机 |
| `responder.QueryCount` / `ReplyCount` / `DroppedCount` / `ListeningPort` / `LastError` | - | `long` / `int` / `string` | 计数与状态（判据用：`QueryCount > 0` = 确实有人在找服） | 诊断面板 |
| `responder.OnQuery` | `Action<string>` | - | 每收到一次合法查询触发（主线程，参数 = 来源 `ip:port`） | 留痕 / 计数 |

> 协议：UDP `47777`，查询 `CLOVER-LAN-QUERY/1|<nonce>` → **单播**回应答 `CLOVER-LAN-REPLY/1|{json}`，单包 ≤ 512 字节。
> **旁路**：不占 EMsg 消息号、不进 Router、不走线路族（N13）；仅原生平台可用。完整用法见 [网络与会话](../development/network.md) 的「局域网寻服」。

## 第一人称 rig（CloverFirstPersonCamera）

**纯逻辑类**（非 `MonoBehaviour`，不经 `Game.Camera` 门面）：帧步长由调用方经 `Tick(dt)` 注入。

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `new CloverFirstPersonCamera()` | - | - | 直接 `new`（引擎不给门面入口） | 进关卡前建 rig |
| `rig.Bind()` / `rig.Bind(camera)` / `rig.Unbind()` | `Camera` | `bool` / `void` | 绑 `Game.Camera.Main` / 绑指定相机 / 解绑 | 进图 / 回菜单 |
| `rig.Tick(dt)` | `float` | `void` | 每帧推进（**每帧只许调一次**；`dt <= 0` 不推进任何状态） | 业务 Update |
| `rig.ApplyLookDelta(dx, dy)` | `float, float` | `void` | 原始鼠标位移 → 按灵敏度 / 反转 / 限位累加（回放 / 观战接管 / 离线断言走它） | 设备无关注入 |
| `rig.SetRecoil(pitch, yaw)` / `rig.ClearRecoil()` | `float, float` | `void` | 喂**权威**后坐力（表现跟随，⛔ 不累加第二份）/ 立即清 | 开火 / 换目标 |
| `rig.AddShake(amp, dur)` / `rig.ClearShake()` | `float, float` | `bool` / `void` | 注入摇晃（幅度**线性**衰减）/ 立即结束（参数非正 ⇒ `false`） | 受击 / 爆炸 / 落地 |
| `rig.SetView(yaw, pitch)` | `float, float` | `void` | 直接对齐视角（出生 / 接管 / 观战，不做平滑） | 出生 / 切换视角 |
| `rig.Yaw` / `rig.Pitch` / `rig.AimDirection` / `rig.EyePosition` | - | `float` / `Vector3` | 朝向**合量**（= Look + 后坐力 + 摇晃）/ 视线方向 / 射线起点（不含 `ViewOffset`） | 射线 / 命中判定 |
| `rig.Look` | - | `LookAccumulator` | **不含**后坐力 / 摇晃的输入视角（喂给移动方向解算） | 移动解算 |
| `rig.ViewOffset` / `rig.ViewRoll` | `Vector3` / `float` | - | 业务塞进来的视点晃动（典型 = `ViewBob` 输出） | 走路颠簸 |
| `rig.FovX` / `rig.VerticalFieldOfView` | `float` | - | 水平 FOV（开镜改它）/ 本帧实际下发的**垂直** FOV | 开镜 |
| `rig.SensitivityX` / `rig.SensitivityY` / `rig.SeparateAxes` / `rig.InvertY` / `rig.PitchLimit` / `rig.EyeAnchor` / `rig.EyeOffset` / `rig.EyeSmoothTau` / `rig.RecoilRiseTau` / `rig.RecoilFallTau` / `rig.ShakeRng` / `rig.ShakeRollScale` | - | - | 全部为公开字段：引擎**不内置任何手感数值**，由业务从设置与手感表填 | 手感配置 |
| `rig.ControlEnabled` / `rig.SetControlEnabled(on)` / `rig.LockInput()` / `rig.UnlockInput()` | `bool` | `bool` / `void` | 鼠标读取开关 / 加锁 / 解锁（只解**本 rig 加的**那把锁） | 弹窗 / 死亡 / 过场 |

## Separation2D（角色间水平推开）

`Runtime/Core` 的**纯函数静态工具**（与 `Game.Camera` 无关）：只保证任意两圆圆心距 ≥ 两半径之和（+ `Skin`）。

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Separation2D.TryResolve(circles, count, result)` | `Circle[], int, Vector2[]` | `bool` | 一次解开**一整组**（各退一半），结果写进 `result`（不改输入、热路径零分配） | 回合开始 / 传送落点 / 一次性归一化 |
| `Separation2D.TryResolveOne(pos, radius, others, count, out result)` | `Vector2, float, Circle[], int, out Vector2` | `bool` | 只推**一个**申请位置（`others` 视作不动障碍、退全部） | 每帧角色推进 |
| `Separation2D.Circle` | `Vector2 Position` / `float Radius` | - | 水平圆（`Radius <= 0` 按 0 处理） | 构造输入 |
| `Separation2D.MaxIterations` / `Separation2D.Skin` | - | `int` / `float` | 迭代上限 `8` / 缝隙 `0.001f` | - |

> `false` = 迭代上限内仍有重叠（挤成一堆）或缓冲长度不够，**不抛异常**。确定性：不调 `UnityEngine.Random`、不读时钟，遍历顺序 = 数组下标序。
> 推开结果须再由调用方的墙体判定钳一次（⛔ 别把人推进墙里）；不做寻路 / 不做碰撞检测 / 不做时间积分 / 不处理竖直分层。

## 地图命名标记点（Game.Map）

| API | 参数 | 返回值 | 说明 | 使用场景 |
|-----|------|--------|------|----------|
| `Game.Map.Points` | - | `IReadOnlyList<MapPoint>` | **全部**标记点（顺序 = 文件顺序；文件无该段时是空列表） | 遍历全部锚点 |
| `Game.Map.GetPoints(name)` | `string` | `IReadOnlyList<Vector3>` | 该名字下**全部**坐标（同名多点：一组出生点 / 一条路线）；名字**大小写敏感** | 出生点组 / 路线点 |
| `Game.Map.TryGetPoint(name, out pos)` | `string, out Vector3` | `bool` | 取第 0 个；取不到 ⇒ `false` + `Vector3.zero` | 单点锚点 |

> 标记点由导出端产（`MapBakeOptions.MarkerRootName` 指定根对象，「对象名 = 标记名、世界坐标 = 点位」）；
> **旧 `.bytes` 不含该段（flags bit2）⇒ 必须用支持标记段的导出端重新烘焙**（见 [约束](./constraints.md) G14）。

## UI 构件（UIFactory）

**用代码搭 uGUI** 时的脚手架（对业务公开）。**不要再自己写一套锚点 / 铺满 / 文本的工具类**
——那类重复实现是踩坑高发区（详见 [UI 系统 · 用代码搭 UI](../development/ui-system.md)）。

| API | 参数 | 返回值 | 说明 | 典型用途 |
|-----|------|--------|------|----------|
| `UIFactory.CreateNode(name, parent)` | `string, Transform` | `RectTransform` | 新建节点，**已铺满父节点** | 面板根 / 整层容器 |
| `UIFactory.Stretch(rt)` | `RectTransform` | `void` | 把已有节点设为铺满父节点 | 修正没铺满的节点 |
| `UIFactory.CreateCentered(name, parent, size, pos)` | `string, Transform, Vector2, Vector2` | `RectTransform` | 居中锚点 + 定尺 + 相对父层中心定位 | 标题 / 定尺控件 |
| `UIFactory.CreatePanel(name, parent, color, raycastTarget)` | `string, Transform, Color, bool` | `Image` | 铺满的纯色面板 | 背景 / 遮罩 / 按钮底板 |
| `UIFactory.CreateText(name, parent, content, fontSize, alignment, color, raycastTarget)` | `string, Transform, string, int, TextAnchor, Color, bool` | `Text` | 文本节点（**引擎内置字体**） | 普通文字 |
| `UIFactory.CreateButton(name, parent, label, size, pos, bg, onClick)` | `string, Transform, string, Vector2, Vector2, Color, Action` | `Image` | 底板 + 居中标签（`Button` 已挂好） | 通用按钮 |
| `UIFactory.DefaultFont()` | - | `Font` | 引擎内置字体（取不到时回退系统字体） | 字体回落 |
| `TextHooks.Current` | `ITextHook` | - | **文字渲染挂钩**：引擎通用件每建一个 `Text` 都会问它；`null` = 用引擎内置字体（现状） | 像素风项目要把引擎自带提示（Toast / Loading / Confirm / Guide / 飘字）也换成自己的字模 |
| `ITextHook.OnTextCreated(text)` | `UI.Text` | `void` | 引擎刚创建 `Text` 时回调（业务可把 `Text` 降级成数据持有者 + 挂自己的字模渲染器）。⛔ 不许抛异常（引擎吞掉并只 Warn 一次）；⛔ 不许在回调里再调 `UIFactory.CreateText` 造成递归 | 接入原版中文位图字体 |
| `UIFactory.UICamera()` | - | `Camera` | 世界坐标 → 屏幕坐标换算用 | 飘字 / 定位 |

> ⚠️ **`DefaultFont()` 给的是引擎内置字体**：像素风项目要用自己的像素字体（字号常需按字体规格取整），
> 那层包装由业务自己写。通用件（Toast / 飘字 / Loading / 确认框 / 引导）走 `Game.UI`，
> **不要**直接碰底层 Layer 实现（它们仍是 `internal`）。

## 下一步

1. 深入了解 [网络模块 API](../development/network.md)
2. 了解 [事件 / 定时器 / 状态机](../development/event-timer-fsm.md) 等基础模块详细用法
3. 查看 [完整示例代码](../examples/login-flow.md)

