# ObjectID 与实体对象

## ObjectID

`pkg/domain/object.ObjectID` 是稳定、可比较、可线化的对象身份，由 `Type`（高 16 位）和 `Seq`（低 48 位）组成。引擎提供 `NewObjectID`、`ParseObjectID`、`MarshalUint64` 与 `FromUint64`；不存在服务器/房间/符号位布局。`BasicObject`（仅持有 ObjectID 的极简对象）和 `Manager`（对象管理器）均位于 `pkg/domain/object`，是可用的 pkg API。

```go
id := object.NewObjectID(object.TypePlayer, 42)
text := id.String()       // "1:42"
wire := id.MarshalUint64()
id2 := object.FromUint64(wire)
```

## 对象管理与 MMO

对象管理器 API 位于 `pkg/domain/object`，大世界 AOI API 位于 `pkg/domain/mmo/aoi` 与 `pkg/domain/mmo`。对象系统和 MMO 场景是独立模块；请使用各模块实际导出的 `Manager`、`Scene`、`Grid`、`VisualSystem` 接口，不要调用不存在的 `g.Entities()` 或 `g.AOI()`。

### ObjectManager 事件 API

对象管理器支持双通道事件：

| 方法 | 行为 | 适用场景 |
|------|------|----------|
| `manager.SendEvent` | 并发，handler 可能并行跑 | 只读/通知（零开销） |
| `manager.SendQueueEvent` | 串行，per-object 锁，不同对象仍并行 | 掉血、掉落归属、对象级共享计数 |

```go
import "github.com/qw576483/clover-server-engine/pkg/domain/object"

// 对象类型由业务自定义（引擎内置只有 TypePlayer=1 / TypeScene=2）
const TypeMonster uint16 = 1001

// 注册：(对象类型, 事件名) → handler
g.OnGObjectEvent(TypeMonster, "take_damage", func(ctx context.Context, obj object.Object, eventType string, payload any) error {
    return nil
})

// 发送
g.SendEventToGObject(ctx, bossID, "death", &DeathEvent{...})           // 并发通道
g.SendQueueEventToGObject(ctx, bossID, "take_damage", &Damage{Amount: 90}) // 串行通道
```

场景内对象事件必须通过 `sceneMgr.ObjectManager()` 发送（它与 Game 内置的 `g.ObjectManager()` 是两个不同实例，互不可见）。

### AOI 网格示例

```go
import (
    "github.com/qw576483/clover-server-engine/pkg/domain/mmo"
    "github.com/qw576483/clover-server-engine/pkg/domain/mmo/aoi"
    "github.com/qw576483/clover-server-engine/pkg/domain/object"
)

grid := mmo.NewGrid(10)         // 10 米一格，返回 aoi.Grid
grid.SetObserver(func(watcher, target object.ObjectID, ev aoi.Event) {
    // ev 为 aoi.EnterView / LeaveView
    // 根据 ev 通过 app.Game.PushToPlayer 推送业务消息
})
playerID := object.NewObjectID(object.TypePlayer, 1001)
grid.Enter(playerID, aoi.Position{X: 100, Y: 0, Z: 200})
grid.Watch(playerID, 96)        // 设置视野半径
grid.Move(playerID, aoi.Position{X: 110, Y: 0, Z: 200})
nearby := grid.Around(aoi.Position{X: 110, Y: 0, Z: 200}, 50)
```

具体实体的持久化仍应使用 `app.Game.LoadStruct` / `LoadRecord` 与 `data` schema；ObjectID 只负责身份，不自动创建或落库实体。