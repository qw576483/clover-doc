# 事件系统

## 核心概念

Clover 引擎提供三层事件通道，适用于不同的并发需求：

| 通道 | 适用场景 | 并发保证 |
|------|----------|----------|
| **客户端消息** (`g.OnMsg`) | 玩家请求处理 | 同玩家串行，跨玩家并行 |
| **玩家领域事件** (`g.SendEventToPlayer` / `g.SendQueueEventToPlayer`) | 跨节点事件分发 | SendEvent 并行，SendQueueEvent 同玩家串行 FIFO |
| **场景/对象事件** (`Scene` / `ObjectManager`) | 场景状态、对象状态 | 双通道：`SendEvent` 并行，`SendQueueEvent` 同目标串行（两通道之间不互斥） |

---

## 一、客户端消息 Handler

Clover 的业务 handler 类型是 `event.Handler`，即 `func(c event.Ctx) error`。

```go
func onMessage(c event.Ctx) error {
    var req LoginRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    return nil
}
```

### 注册

业务通常在 `init` 中通过 `app.Mount(app.RoleGame, ...)` 注册；消息号从业务 `def` 包引用（业务号必须大于引擎保留区间）。

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgLogin, onMessage)
    })
}
```

`g.OnMsg(msgID, handler, priority...)` 支持可选优先级。handler 返回非 nil 错误时框架自动按错误协议回包；返回 nil 且未写入回包时可作为 fire-and-forget。`Ctx.SetNoAutoReply()` 可显式抑制自动回包。

### Ctx 常用 API

| API | 说明 |
|---|---|
| `c.BindMsg(&req)` | 将请求体 JSON 绑定到业务结构体 |
| `c.PlayerID()` / `c.Account()` | 当前角色 ID / 账号 |
| `c.RequestID()` / `c.MsgID()` / `c.ConnID()` | 请求、消息、连接标识 |
| `c.TraceID()` / `c.SpanID()` | 链路追踪标识 |
| `c.ConnValue(key)` / `c.SetConnValue(key, value)` | 连接级 KV |
| `c.SetPlayerID(id)` | 设置当前连接角色 |
| `c.SetNoAutoReply()` / `c.SetNoPush()` | 关闭自动回包 / 数据变更自动推送 |

回包和主动推送通过 `app.Game` 完成：

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgLogin, func(c event.Ctx) error {
        var req LoginRequest
        if err := c.BindMsg(&req); err != nil { return err }
        g.Reply(c, &LoginReply{PlayerID: c.PlayerID()})
        return nil
    })
})
```

主动推送 API 为 `g.PushToPlayer`、`g.PushToScene`、`g.PushToAll`（以及对应 `Raw` 版本）。旧式 `c.Reply`、`c.Push`、`c.Data()`、`c.Game()` 不属于当前公开 `Ctx` API。

---

## 二、玩家领域事件

### 并发通道：`SendEventToPlayer`

```go
// 注册：业务领域事件
g.OnEvent("player.created", func(c event.Ctx) error {
    // 处理逻辑
    return nil
})

// 发送：向指定玩家投递（并行，不保证顺序）
g.SendEventToPlayer(c, playerID, "player.created", &PlayerCreatedData{...})
```

适合只读 / 纯通知类事件，零串行开销。

> **跨节点读数据的唯一姿势就是"发事件过去取"**：`SendEventToPlayer` 已具备跨节点寻址
> （经 master 定位 → 目标节点 `OnEvent` 里读 → 回投一个 event 给请求方）。
> 引擎**不提供**通用的 `CallNode` RPC —— 保持"事件派发"这一套模型，不引入第二种跨节点交互形态。
> 另有两条边界记牢：① **在线**玩家的数据只在 owner 节点内存，别处 `Load` 拿到的是 Redis/MySQL 的旧值；
> ② 已有的镜像广播（`publishMirror` → `ReceiveMirror`）是**单向全广播、无寻址、只在写提交时触发**（读不触发）。

### 串行通道：`SendQueueEventToPlayer`

```go
// 同一玩家的事件严格 FIFO，避免并发竞态
g.SendQueueEventToPlayer(c, playerID, "battle.damage", &DamageData{Amount: 90})
```

需要原子读-改-写玩家状态时用这个。handler 内禁止对同一玩家再调 `SendQueueEventToPlayer`（自我死锁），嵌套投递用 `SendEventToPlayer`。

---

## 三、场景事件（Scene）

场景是 MMO 世界的基本单元，场景事件用于多玩家共享的场景状态。

### 注册与发送

```go
import "github.com/qw576483/clover-server-engine/pkg/domain/mmo"

// 注册场景事件处理器
// ⛔ `s` 是**接口** mmo.Scene（SceneFacade，只有方法集）—— 取 `s.progress` **编译不过**
//    （那是 internal 实现里的未导出字段，接口值没有字段可读）。
//    要记进度请放在**业务自己的** map/结构里（按场景 id 或 objID 索引），⛔ 不要试图改引擎内部状态。
scene.OnEvent("capture.tick", func(ctx context.Context, s mmo.Scene, eventType string, payload any) error {
    data, ok := payload.(*CaptureData)
    if !ok {
        return nil
    }
    // captureProgress 是业务侧的表：captureProgress[sceneID] += data.Value
    _ = data
    return nil
})
```

### 双通道

```go
// 通道1：并发（SendEvent）—— 不互斥，handler 可能并发执行
scene.SendEvent(ctx, "boss.spawn", &BossData{...})

// 通道2：串行（SendQueueEvent）—— 同一场景上的事件严格互斥
scene.SendQueueEvent(ctx, "capture.tick", &CaptureData{...})
```

| 方法 | 行为 | 适用场景 |
|------|------|----------|
| `scene.SendEvent` | 并发，handler 可能并行跑 | 只读/广播/通知（零开销） |
| `scene.SendQueueEvent` | 串行，后到者排队 | 占领进度、活动状态、多玩家同时修改的共享状态 |

handler 内禁止对同一场景再调 `SendQueueEvent`（自我死锁），嵌套投递用 `SendEvent`。

### Tick 与 handler 并发保证（scene.Sync）

`Scene.Tick` 由业务定时器驱动，与 handler 在不同 goroutine。直接在 Tick 里修改场景共享状态会与 handler 并发覆盖。用 `scene.Sync` 包住 Tick 内的状态读写：

```go
import "github.com/qw576483/clover-server-engine/pkg/domain/mmo"

beat := mmo.NewSceneBeat(50*time.Millisecond, 0)
beat.Add(mmo.TierFast, func(dt time.Duration) {
    scene.Sync(func() {
        progress -= dt.Seconds() * decayRate
    })
})
scene.AttachBeat(beat)
```

`Sync` 与 `SendQueueEvent` 共用同一把锁 `evtExecMu`，Tick 与**串行通道 handler** 严格互斥，等价于单线程场景服。

> 注意：`SendEvent`（并发通道）不持该锁，与 `Sync` / `SendQueueEvent` **不互斥**。用它修改场景共享状态仍会与串行 handler 竞态——修改共享状态一律走 `SendQueueEvent`。

---

## 四、GObject 对象事件

GObject 事件作用于独立的游戏对象（怪物、NPC、掉落物等），粒度比场景更细。

### 注册与发送

```go
import "github.com/qw576483/clover-server-engine/pkg/domain/object"

// 对象类型由业务自定义（引擎内置只有 TypePlayer=1 / TypeScene=2）
const TypeMonster uint16 = 1001

// 注册：(对象类型, 事件名) → handler
g.OnGObjectEvent(TypeMonster, "take_damage", func(ctx context.Context, obj object.Object, eventType string, payload any) error {
    // payload 是 Damage{Amount: 90}
    return nil
})
```

### 双通道

```go
// 通道1：并发（SendEventToGObject）
g.SendEventToGObject(ctx, bossID, "death", &DeathEvent{Killer: playerID})

// 通道2：串行（SendQueueEventToGObject）—— 同一对象上的事件互斥
g.SendQueueEventToGObject(ctx, bossID, "take_damage", &Damage{Amount: 90})
```

| 方法 | 行为 | 适用场景 |
|------|------|----------|
| `g.SendEventToGObject` | 并发 | 只读/广播（死亡通知、属性同步） |
| `g.SendQueueEventToGObject` | 串行，per-object 锁 | 怪物掉血、掉落归属、对象级共享计数 |

`SendQueueEventToGObject` 用 per-object `sync.Mutex`，不同对象之间仍然并行，只有同一对象串行。

handler 内禁止对同一对象再调 `SendQueueEventToGObject`（自我死锁），嵌套投递用 `SendEventToGObject`。

### ObjectManager

`object.Manager` 由 `NewSceneManager` 内部自动创建，业务无需手动实例化。通过 `sceneMgr.ObjectManager()` 获取：

```go
// 场景内对象事件走场景的 Manager（不是 Game 内置的那个）
objMgr := sceneMgr.ObjectManager()
objMgr.SendEvent(ctx, bossID, "death", &DeathEvent{...})
```

> **注意**：Game 内置 `g.ObjectManager()` 和 `SceneManager.ObjectManager()` 是两个不同实例，互不可见。场景内对象注册在 `SceneManager.ObjectManager()`，用 `g.SendEventToGObject` 需要传入 `WithObjectManager(g.ObjectManager())` 选项让 SceneManager 复用同一个 Manager。

---

## 五、SendEvent vs SendQueueEvent 选择指南

```
                        ┌─────────────────────────────────┐
                        │  这个操作会修改共享状态吗？       │
                        └───────────────┬─────────────────┘
                                        │
                          ┌─────────────┴─────────────┐
                          │ Yes                        │ No
                          ▼                            ▼
              ┌───────────────────────┐    ┌───────────────────────┐
              │ SendQueueEvent        │    │ SendEvent             │
              │ （串行，后到者排队）    │    │ （并发，零开销）        │
              │ 占领进度、掉血、归属    │    │ 广播、通知、只读        │
              └───────────────────────┘    └───────────────────────┘
```

---

## 六、错误处理与生命周期

handler 只应返回业务错误或底层错误，不要在 handler 中自行启动 goroutine 修改同一领域对象；需要异步任务时使用 `g.Timer`/`pkg/runtime/timer`，并按生命周期取消 timer。数据修改通过 `g.LoadStruct` 或 `g.LoadRecord` 完成，handler 返回后由引擎提交。
