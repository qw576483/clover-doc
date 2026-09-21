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

```csharp 标题：AI 状态机示例（使用 Game.Fsm，状态名加前缀隔离）
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
| `AStar.FindSmoothed` / `Smooth` / `HasLineOfSight` / `Describe` | - | - | 平滑路径 / 视线判定 / 文字诊断 | 怪物 AI / 点击移动 |
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

---

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

