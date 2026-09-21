
背包用 **RecordSchema 记录集**建模（一行一件道具），读写遵循 Load-Modify-Return。引擎在 handler 返回时自动 Commit 并增量广播给客户端。

## 完整流程

### 定义 RecordSchema

```go game/datadef/bag.go
var BagRec = data.RecordSchema{
    Type:     "bag",
    OwnerType: data.OwnerPlayer, // 玩家维度：改动只广播该玩家
    ColTypes: []object.Type{object.TypeString, object.TypeInt},
    Cols:     []string{"item_id", "count"},
}

func init() {
    data.RegisterTypeBySchema(BagRec)
}
```

### 增删改查

```go game/logic/item.go
package logic

import (
    "your-game/server/game/datadef"
    "your-game/server/game/def"
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/transport/event"
    "github.com/qw576483/clover-server-engine/pkg/domain/object"
    "github.com/qw576483/clover-server-engine/pkg/shared/proto"
)

var GItem *itemLogic

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        GItem = &itemLogic{g: g}
        g.OnMsg(def.MsgGiveItem, GItem.onMsgGiveItem)
        g.OnMsg(def.MsgCostItem, GItem.onMsgCostItem)
    })
}

type itemLogic struct {
    g *app.Game
}

// AddItem 给玩家加/扣道具（count 为负即扣除）
func (l *itemLogic) AddItem(c event.Ctx, itemID string, count int) error {
    bag, err := l.g.LoadRecord(c, datadef.BagRec, c.PlayerID())
    if err != nil {
        return err
    }

    if row := bag.Find("item_id", object.NewString(itemID)); row >= 0 {
        cur := bag.GetCell(row, 1).Int()
        bag.SetCell(row, 1, object.NewInt(cur+int64(count)))
    } else {
        bag.AddRowValues([]object.Value{
            object.NewString(itemID),
            object.NewInt(int64(count)),
        })
    }
    return nil // 返回后自动 Commit + 增量广播
}

func (l *itemLogic) onMsgGiveItem(c event.Ctx) error {
    var req def.GiveItemRequest
    if err := c.BindMsg(&req); err != nil {
        l.g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "请检查参数"})
        return nil
    }
    return GItem.AddItem(c, req.ItemID, 10)
}

func (l *itemLogic) onMsgCostItem(c event.Ctx) error {
    var req def.CostItemRequest
    if err := c.BindMsg(&req); err != nil {
        l.g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "请检查参数"})
        return nil
    }
    return GItem.AddItem(c, req.ItemID, -10)
}
```

### 事件驱动初始化

玩家创建后经 `EvtPlayerCreated` 事件发放初始道具：

```go
func (l *itemLogic) onEventPlayerCreated(c event.Ctx) error {
    var evt def.EvtPlayerCreatedData
    if err := c.BindEvent(&evt); err != nil {
        return nil
    }
    for _, v := range table.Default.Item.Rows() {
        _ = GItem.AddItem(c, v.ItemID, 10000)
    }
    return nil
}
```

注册事件监听：`g.OnEvent(def.EvtPlayerCreated, GItem.onEventPlayerCreated)`。

### 数据流

```text
客户端 MsgGiveItem ─► onMsgGiveItem
                          │ LoadRecord(bag, playerID)
                          ▼
                    修改行 / 追加行
                          │ handler 返回
                          ▼
             引擎 Commit（写库 + EPushDataSync 增量）
                          ▼
                    客户端收到背包增量
```

## Record 常用方法

| 方法 | 说明 |
| --- | --- |
| `Find(col, v)` | 按列值定位行号（-1 表示未找到） |
| `GetCell(row, col)` / `SetCell(row, col, v)` | 读写单元格 |
| `AddRowValues([]Value)` | 追加新行 |
| `DeleteRow(row)` | 删除行 |
| `RowCount()` / `Row(row)` | 行数 / 取整行 |

> **注意：** `LoadRecord` 返回的 `*data.Record` 支持行列级增量追踪，handler 返回时引擎只推送变化部分，带宽效率极高。


## 下一步

1. [实体与对象](../concepts/entity-object.md) —— Schema 定义与属性袋机制
2. [数据存储概念](../concepts/data.md) —— 数据模型与持久化
3. [数据读写示例](data.md) —— StructSchema / RecordSchema / OwnerServer 完整读写

