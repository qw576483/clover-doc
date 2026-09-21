# Event / Timer / Fsm

## 这篇文档讲什么？

本指南介绍 Event（事件总线）、Timer（定时器）和 Fsm（有限状态机）的使用方法。

> ⚠️ **处理器内禁止阻塞**：这几类回调都在**主线程**，处理器里任何阻塞（`Thread.Sleep`、同步等待 / IO、大循环）
> 都会卡住整帧。约定与替代做法见 [约束](../reference/constraints.md) 的「约定：处理器内禁止阻塞」。

**目标读者**：需要实现游戏逻辑的 Unity 开发者。

## 前置条件

- 已完成 [快速开始](../quickstart.md)
- 了解 [Game 门面](./game-facade.md)

## Event（事件总线）

进程内事件总线，API 与服务端 `event.Bus` 语义一致。

### API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `Game.Event.On(event, handler)` | `string, Action` | `void` | 注册监听（等价 `OnPriority` 的 priority = 0） |
| `Game.Event.On<T>(event, handler)` | `string, Action<T>` | `void` | 注册类型化监听 |
| `Game.Event.OnPriority(event, priority, handler)` | `string, int, Action` | `void` | 按优先级注册：**priority 越大越先执行**；同优先级内仍是后注册先执行 |
| `Game.Event.Emit(event)` | `string` | `void` | 发射事件 |
| `Game.Event.Emit<T>(event, data)` | `string, T` | `void` | 发射类型化事件 |
| `Game.Event.Off(event, handler)` | `string, Action` | `void` | 取消监听（传入注册时的同一 handler，一次注销干净） |
| `Game.Event.OffAll(event)` | `string` | `void` | 移除该事件的所有监听器 |
| `Game.Event.OffAll()` | - | `void` | 移除所有事件的所有监听器 |
| `Game.Event.Once(event, handler)` | `string, Action` | `void` | 注册一次性监听 |

> **通配订阅（`*` / `**`）**：事件名以 `.` 分段（如 `Net.OnConnected`），订阅名里可用 `*` 匹配**恰好一段**、
> `**` 匹配**一段或多段**（`Net.**` 命中 `Net.OnConnected`；`Net.*` 只命中两段名）。
> 分发顺序：**精确匹配的订阅先执行，通配订阅随后**；退订语义与精确订阅一致——用注册时**同一个订阅名**（含通配符）调 `Off` 即注销。
> 通配订阅同样适用于 `On<T>` / `Once`（`<T1,T2>` 形态亦可用）。
>
> **订阅配对语义**：同一事件上**同一 handler 重复注册会被忽略并告警**（不再叠加多份），因此一次 `Off` 即注销干净、不残留。
> **分发期间修改即时生效**：`Emit` 回调里调用 `Off` / `OffAll`，被注销的 handler 本帧不再触发（未被注销者也不会重复触发）。

### 使用示例

```csharp
// 注册监听
Game.Event.On("player.OnLevelUp", () =>
{
    Debug.Log("升级!");
});

// 类型化监听
Game.Event.On<PlayerLevelUpEvent>("player.OnLevelUp", evt =>
{
    Debug.Log($"升级! level={evt.Level}");
});

// 发射事件
Game.Event.Emit("player.OnLevelUp");
Game.Event.Emit("player.OnLevelUp", new PlayerLevelUpEvent { Level = 5 });

// 取消监听（需传入同一 handler 引用）
Game.Event.Off("player.OnLevelUp", handler);

// 一次性监听（触发一次后自动移除）
Game.Event.Once("player.OnLevelUp", () => { });
```

## Timer（定时器）

API 与服务端 `timer.Scheduler` **完全同名**，实现为主线程 `List<TimerEntry>` 全表线性遍历（**非最小堆**），Update 驱动。

### API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `Game.Timer.After(seconds, action)` | `float, Action` | `long` | 延迟执行，返回定时器 ID |
| `Game.Timer.Every(seconds, action)` | `float, Action` | `long` | 循环执行，返回定时器 ID |
| `Game.Timer.AfterName(name, seconds, action)` | `string, float, Action` | `long` | 命名延迟 |
| `Game.Timer.EveryName(name, seconds, action)` | `string, float, Action` | `long` | 命名循环 |
| `Game.Timer.After(seconds, action, scope)` | `float, Action, string` | `long` | 延迟执行（带作用域） |
| `Game.Timer.Every(seconds, action, scope)` | `float, Action, string` | `long` | 循环执行（带作用域） |
| `Game.Timer.StopNamed(name)` | `string` | `void` | 按名称停止定时器 |
| `Game.Timer.StopScope(scope)` | `string` | `void` | 停止作用域内定时器 |
| `Game.Timer.StopAll()` | - | `void` | 停止所有 |
| `Game.Timer.AfterUnscaled(seconds, action)` | `float, Action` | `long` | 延迟执行，**按真实时间推进**：`timeScale = 0` 时也照常触发 |
| `Game.Timer.EveryUnscaled(seconds, action)` | `float, Action` | `long` | 循环执行，按真实时间推进 |

> ⚠️ **`timeScale = 0` 时普通 `After` / `Every` 永不触发**（引擎用 `Time.deltaTime` 推进；`deltaTime` 恒为 0）。
> 暂停菜单、结算屏、GameOver 这类**画面冻结但仍要"几秒后做点什么"**的场景，**一律用 `*Unscaled`** ——
> 否则表现为那张屏永久卡住，**且不报错、不打日志**（详见下方「常见问题」）。
>
> **精度边界**：`*Unscaled` 按 `Time.unscaledDeltaTime` 累加，**编辑器失焦时会明显不准**（实测偏慢/偏快都出现过）。
> 玩家体验不受影响，但**别拿它当秒表**；需要严格墙钟时间请自行用 `Time.realtimeSinceStartup`。

### 使用示例

```csharp
// 延迟执行
Game.Timer.After(3f, () => { /* 3秒后执行 */ });

// 循环执行
Game.Timer.Every(1f, () => { /* 每秒执行 */ });

// 命名定时器
Game.Timer.AfterName("buff_poison", 5f, () => { /* 5秒后执行 */ });
Game.Timer.StopNamed("buff_poison");

// 作用域（场景切换时批量停止）
Game.Timer.Every(1f, () => { /* 场景内循环 */ }, sceneID);
// 离开场景时批量停止
Game.Timer.StopScope(sceneID);

// 停止所有
Game.Timer.StopAll();
```

## Fsm（有限状态机）

游戏流程用它（**房间帧同步走 `Game.FrameRoom`，不使用 Fsm**）。服务端 `fsm.Machine` 使用 `Transition(from, to, event)` 签名，客户端简化为 `Transition(toState)` 和 `AddTransition(trigger, toState)`。

### API 参考

| API | 参数 | 返回值 | 说明 |
|-----|------|--------|------|
| `fsm.RegisterState(name, onEnter, onTick, onExit)` | `string, Action, Action<float>, Action` | `void` | 注册状态 |
| `fsm.Transition(toState)` | `string` | `void` | 转换到目标状态 |
| `fsm.AddTransition(trigger, toState)` | `string, string` | `void` | 注册触发器→目标状态映射 |
| `fsm.Trigger(trigger)` | `string` | `void` | 触发转换 |
| `fsm.Force(state)` | `string` | `void` | 强制进入状态 |
| `fsm.Tick(dt)` | `float` | `void` | 每帧驱动 |
| `fsm.OnChange(handler)` | `Action<string, string>` | `void` | 注册状态变化回调 |
| `fsm.OffChange(handler)` | `Action<string, string>` | `void` | 移除状态变化回调 |
| `fsm.Current` | - | `string` | 获取当前状态名称 |

### 使用示例

```csharp
// 注册状态
// 使用 Game.Fsm（引擎内置状态机），不建议 new Fsm()
fsm.RegisterState("idle",
    onEnter: () => { },
    onTick: dt => { },
    onExit: () => { }
);
fsm.RegisterState("battle",
    onEnter: () => { },
    onTick: dt => { },
    onExit: () => { }
);

// 转换到目标状态
fsm.Transition("battle");

// 强制触发
fsm.Force("battle");

// 每帧驱动
fsm.Tick(Time.deltaTime);

// 状态变化监听
fsm.OnChange((from, to) => { });
```

## 与服务端对齐点

| 模块 | 客户端 C# | 服务端 Go |
|------|----------|----------|
| Event | `Game.Event.On/Emit` | `event.Bus` |
| Timer | `Game.Timer.After/Every/...` | `timer.Scheduler` |
| Fsm | `Game.Fsm.RegisterState/...` | `fsm.Machine` |

> **注意：** 客户端和服务端的 Event/Timer/Fsm 设计理念一致，但具体 API 签名有差异（如客户端 Timer 使用 `float` 秒数而非 `time.Duration`，Event `On` 返回 `void` 而非 `IDisposable`）。业务逻辑可复用，但代码不能直接搬运。

## 常见问题

### 事件监听未触发

**症状**：`Game.Event.On()` 注册后未收到事件

**原因**：事件名称错误或事件未发射

**解决**：
1. 检查事件名称是否匹配
2. 确认 `Game.Event.Emit()` 调用

### 定时器未执行

**症状**：`Game.Timer.After()` 未执行

**原因**：定时器被停止或作用域已结束

**解决**：
1. 检查定时器是否被 `StopNamed()` 停止
2. 确认作用域未结束

### 暂停 / 结算界面的定时器永远不执行

**症状**：把 `Time.timeScale` 设成 0 之后（暂停菜单、结算屏、GameOver 屏），
`Game.Timer.After(4f, …)` 里的回调**再也不触发**，界面永久停在那儿；**没有任何报错或日志**。

**原因**：Timer 靠每帧传进来的 `dt` 累加推进，而 `dt` 来自 `Time.deltaTime` ——
`timeScale = 0` 时它恒为 **0**，于是任何定时器都不再前进。

**解决**：改用 `Game.Timer.AfterUnscaled(...)` / `EveryUnscaled(...)`（按 `Time.unscaledDeltaTime` 推进）。

```csharp
// ❌ 冻结画面里永远不会触发
Time.timeScale = 0f;
Game.Timer.After(4f, () => Game.Fsm.Transition("Menu"));

// ✅ 用真实时间
Game.Timer.AfterUnscaled(4f, () => Game.Fsm.Transition("Menu"));
```

### 状态机转换失败

**症状**：`fsm.Transition()` 未生效

**原因**：状态未注册或转换条件不满足

**解决**：
1. 确认状态已注册
2. 检查转换条件

## 下一步

- 了解 [Game 门面](./game-facade.md) 和模块入口
- 了解 [网络与会话](./network.md) 完整用法