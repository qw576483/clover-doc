# 数据定义

## 公共数据 API

业务代码通过 [`clover-server-engine/pkg/domain/data`](https://github.com/qw576483/clover-server-engine/blob/main/pkg/domain/data.md) 声明 schema，并在 `init` 中注册；运行时通过 `app.Game.LoadStruct` / `LoadRecord` 读写。引擎负责落库、脏数据提交和跨节点广播，业务不直接依赖 `internal`。

```go
package datadef

import "github.com/qw576483/clover-server-engine/pkg/domain/data"

var PlayerSchema = data.StructSchema{
    Type:       "player",
    OwnerType:  data.OwnerPlayer,
    Visibility: data.ClientVisible,
    Tier:       data.TierRedisMySQL,
}

func init() { data.RegisterTypeBySchema(PlayerSchema) }
```

实际字段和枚举值以 `pkg/domain/data` 当前定义为准；不要使用旧版 `schema.Table`、`orm:"..."` 或 `TableName` 约定。引擎现有业务实体使用 `E` 前缀（例如 `EAccount`），SQL 表名由引擎存储层管理。

## Load-Modify-Return

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgLevelUp, func(c event.Ctx) error {
        var p PlayerData
        if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p); err != nil {
            return err
        }
        p.Level++
        return nil // 返回后由引擎提交本次 LoadStruct 的修改
    })
})
```

`LoadStruct` 的签名为 `LoadStruct(c event.Ctx, schema data.StructSchema, id string, v any) error`；记录型数据使用 `LoadRecord(c, schema, id)`，并通过 `data.Record` 的行列 API 修改。数据加载失败应返回错误，不要假定对象一定存在。

## 存储抽象

`pkg/domain/data.Store` 仅提供 `Save`、`Load`、`SaveJSON`、`LoadJSON`、`Delete`；`MemoryConfig`、`DefaultConfig`、`MMOConfig`、`RedisConfig` 用于创建不同存储配置。建表和连接生命周期由引擎装配负责。

## 业务挂载

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgGetPlayer, func(c event.Ctx) error {
            var p PlayerData
            return g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p)
        })
    })
}
```

请从 `pkg/app`、`pkg/domain/data` 和 `pkg/transport/event` 导入公开 API；不要引用 `c.Data()`、`c.Bind()` 等旧示例接口。Handler 应在 `app.Mount(app.RoleGame, func(g *app.Game){ ... })` 闭包内注册，通过闭包参数 `g` 获取 `*app.Game` 实例。