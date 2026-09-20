
数据层 API 遵循 **Load-Modify-Return** 模式：读出来、改、返回，引擎自动 Commit 并广播增量。业务无需关心底层是 TierMemory / TierRedisMySQL / TierSnapshot 哪种模式。

## 完整流程

### 结构体读写（StructSchema）

```go game/datadef/player.go
var PlayerSchema = data.StructSchema{
    Type:       "player",
    OwnerType:  data.OwnerPlayer,   // 玩家维度
    Visibility: data.ClientVisible,
}

func init() {
    data.RegisterTypeBySchema(PlayerSchema)
}

type Player struct {
    Name  string `json:"name"`
    Level int    `json:"level"`
}
```

```go game/logic/player.go
// 升级：读 → 改 → 返回，引擎自动 Commit + 增量广播
func (l *playerLogic) onMsgLevelUp(c event.Ctx) error {
    // 读
    var p datadef.Player
    _ = l.g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p)

    // 改（直接操作内存结构体）
    p.Level++

    // 返回：引擎自动 Commit + 字段级增量广播（EPushDataSync），无需手动回包
    return nil
}
```

> **提示：** `LoadStruct` 签名：`g.LoadStruct(c event.Ctx, schema data.StructSchema, id string, v any) error`
> （**没有 opts 参数**；`LoadOption` / `ReadOnly()` 目前是 internal-only，**未通过 pkg 暴露**，业务传不了）。

因此经 `g.LoadStruct` 加载的数据**一律是可修改 + 自动落库 + 自动广播**的语义：
handler 返回后引擎自动 Commit（dirty → 写库 → 字段级增量广播），除非在 handler 里调 `c.SetNoPush()`。
需要"只读、不落库"的用法，请自行用 `Store.LoadJSON` 直读，或与引擎负责人确认是否开放该选项。


### 记录集读写（RecordSchema）

记录集适合「一维 key + 多列」的表格数据，如背包（item_id 行、count 列）。

```go game/datadef/bag.go
var BagRec = data.RecordSchema{
    Type:     "bag",
    OwnerType: data.OwnerPlayer,
    ColTypes: []object.Type{object.TypeString, object.TypeInt},
    Cols:     []string{"item_id", "count"},
}

func init() {
    data.RegisterTypeBySchema(BagRec)
}
```

```go game/logic/item.go
// 加道具
func (l *itemLogic) AddItem(c event.Ctx, itemID string, count int) error {
    bag, err := l.g.LoadRecord(c, datadef.BagRec, c.PlayerID())
    if err != nil {
        return nil
    }

    row := bag.Find("item_id", object.NewString(itemID))
    if row >= 0 {
        cur := bag.GetCell(row, 1).Int()
        bag.SetCell(row, 1, object.NewInt(cur+int64(count)))
    } else {
        bag.AddRowValues([]object.Value{
            object.NewString(itemID),
            object.NewInt(int64(count)),
        })
    }
    return nil // 返回后自动 Commit
}

// 删除某行
func (l *itemLogic) DeleteItem(c event.Ctx, itemID string) error {
    bag, err := l.g.LoadRecord(c, datadef.BagRec, c.PlayerID())
    if err != nil {
        return nil
    }
    if row := bag.Find("item_id", object.NewString(itemID)); row >= 0 {
        bag.DeleteRow(row)
    }
    return nil
}
```

**Record 常用方法：**

| 方法 | 说明 |
| --- | --- |
| `Find(col, v)` | 按列值定位行号（-1 未找到） |
| `GetCell(row, col)` / `SetCell(row, col, v)` | 读写单元格 |
| `AddRowValues([]Value)` | 追加行 |
| `DeleteRow(row)` | 删除行 |
| `RowCount()` / `Row(row)` | 行数 / 取整行 |

### 服务器级数据（OwnerServer）

```go game/datadef/server.go
var ServerAnnounce = data.StructSchema{
    Type:       "announce",
    OwnerType:  data.OwnerServer, // 服务器维度：改动广播全服
    Visibility: data.ClientVisible,
    Tier:       data.TierRedisMySQL,
}

func init() {
    data.RegisterTypeBySchema(ServerAnnounce)
}
```

> **注意：** `OwnerServer` 数据的改动会自动广播给**所有在线玩家**（全服公告、开服倒计时等场景）。


### 全局数据镜像（OwnerServer + NATS）

```go 示例：OwnerServer 全局镜像 schema
var KVStore = data.StructSchema{
    Type:       "kvstore",
    OwnerType:  data.OwnerServer, // master 权威，改动经 NATS 镜像到所有 Game 节点
    Visibility: data.ClientVisible,
    Tier:       data.TierRedisMySQL,
}

func init() {
    data.RegisterTypeBySchema(KVStore)
}
```

Game 侧读 `OwnerServer` 走本地镜像缓存，写操作在 master 侧。

> 引擎能力示意：master 侧写、Game 侧自动镜像（`LoadStruct` + NATS 下行）。
> 本项目未使用此模式，故没有对应的 demo 文件。

### 会话与一致性

> **警告：** 同 handler 内重复 `LoadStruct` / `LoadRecord` 命中 **identity map**，读到的始终是同一实例。不要在 handler 外部持有数据指针，否则会引用过期数据。


| 机制 | 说明 |
| --- | --- |
| Identity Map | 同 handler 内重复加载命中同一实例 |
| Load-Modify-Return | 修改在 handler 返回时统一 Commit，无需显式 Save |
| `c.SetNoPush()` | 关闭本次请求的增量广播（如高频数值只回包不同步） |

## 相关文档


**相关链接：**

- [数据存储概念](../concepts/data.md) - 数据模型、ORM 与 Load-Modify-Return

- [实体与对象](../concepts/entity-object.md) - Schema 定义与属性袋机制


