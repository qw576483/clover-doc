# 数据持久化指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的数据持久化机制，包括数据读写模式、错误处理和数据访问 API。目标读者是想要理解数据如何保存和读取的开发者。

## 前置条件

- 了解 Clover 引擎的基本架构
- 熟悉 Handler 开发模式
- 了解数据库基础概念

## 核心模式

Clover 数据流的核心模式：**读取 → 修改 → 返回**，引擎自动提交。

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgLevelUp, func(c event.Ctx) error {
        // 1. 读取：从数据库/缓存加载数据
        var player PlayerData
        if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &player); err != nil {
            return err
        }

        // 2. 修改：直接修改返回的对象
        player.Level += 1
        player.Exp += 100

        // 3. 返回：handler 返回即自动提交
        return nil
    })
})
```

> **注意：** handler 返回 `nil` 表示成功，返回 `error` 表示失败。数据修改在 handler 链返回后由引擎统一提交；**链中某个 handler 失败也照常提交**已累积的改动（尽力持久化，不回滚）——返回错误**不会**撤销已做的修改。

## 错误处理

handler 返回错误时，引擎会自动回复客户端错误码：

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgSomething, func(c event.Ctx) error {
        var player PlayerData
        if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &player); err != nil {
            return err // 自动回复客户端错误码
        }
        if player.Level < 10 {
            return def.ErrLevelTooLow // 自动回复客户端错误码
        }
        // ...
        return nil
    })
})
```

## 数据一致性

引擎的一致性口径（`internal/domain/data/session.go` 的 `Commit`）：

- handler 内的所有 LoadStruct/LoadRecord 修改在 handler 返回后**逐条落库**提交（**无跨条目事务**；每条在提交期序列化一次，之后直接写，同一份字节再复用给增量推送与跨服镜像）
- 单条落库失败会**再试一次**；仍失败只计为该条失败（返回 saved/failed 计数，**允许部分成功**）
- **无自动回滚**：已成功落库的条目保留；需要失败即撤销时由业务自行补偿

## 推送数据

handler 中通过 `g.Reply` 回复请求，通过 `g.PushToPlayer` / `g.PushToScene` / `g.PushToAll` 推送数据：

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgPlayerEnter, func(c event.Ctx) error {
        // 处理业务...

        // 回复请求
        g.Reply(c, &LoginReply{PlayerID: c.PlayerID()})

        // 推送给指定玩家
        g.PushToPlayer(targetPlayerID, def.PushPlayerEnter, PlayerEnter{ID: c.PlayerID()})

        // 场景广播
        g.PushToScene(scene, def.PushPlayerChat, PlayerChat{PlayerID: c.PlayerID()})

        return nil
    })
})
```

## 数据访问 API

| API | 说明 |
|-----|------|
| `g.LoadStruct(c, schema, id, &v)` | 按 schema 加载结构体到 v，修改后由引擎自动提交 |
| `g.LoadRecord(c, schema, id)` | 按 schema 加载为通用 Record 类型 |
| `g.PushToPlayer(playerID, msgID, v)` | 向指定玩家推送消息 |
| `g.PushToScene(scene, msgID, v)` | 场景广播 |
| `g.PushToAll(msgID, v)` | 全服广播 |
| `g.Reply(c, v)` | 回复当前请求 |

> **注意：** 不再有 `c.Data()`、`c.Reply()`、`c.Push()` 等旧式 API。数据操作通过 `app.Game` 完成。
