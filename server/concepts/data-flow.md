# 核心流程

## Load-Modify-Return

Clover 数据流的核心模式：**读取 → 修改 → 返回**，引擎自动提交。

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgLevelUp, func(c event.Ctx) error {
        // 1. 读取
        var player PlayerData
        if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &player); err != nil {
            return err
        }

        // 2. 修改
        player.Level += 1
        player.Exp += 100

        // 3. 返回（引擎自动提交本次 LoadStruct 的修改）
        return nil
    })
})
```

> **注意：** handler 返回 `nil` 表示成功，返回 `error` 表示失败。数据修改在 handler 链返回后由引擎统一提交；**链中某个 handler 失败也照常提交**已累积的改动（尽力持久化，不回滚）——返回错误**不会**撤销已做的修改。

## 错误处理

handler 返回错误时，引擎会自动回复客户端错误码：

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgBuyItem, func(c event.Ctx) error {
        var req BuyItemRequest
        if err := c.BindMsg(&req); err != nil {
            return err
        }
        var player PlayerData
        if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &player); err != nil {
            return err
        }
        if player.Coins < req.Price {
            return def.ErrNotEnoughCoins // 自动回复客户端错误码
        }
        player.Coins -= req.Price
        return nil
    })
})
```

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

## 代码示例

### 玩家升级

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.OnMsg(def.MsgLevelUp, func(c event.Ctx) error {
        // 1. 读取玩家数据
        var player PlayerData
        if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &player); err != nil {
            return err
        }

        // 2. 检查经验是否足够
        if player.Exp < 1000 {
            return def.ErrNotEnoughExp
        }

        // 3. 执行升级
        player.Level += 1
        player.Exp -= 1000
        player.MaxHP += 100

        // 4. 通知客户端
        g.Reply(c, &LevelUpReply{Level: player.Level, MaxHP: player.MaxHP})

        // 5. 广播给其他玩家（通过 PushToScene 或 PushToAll）
        return nil
    })
})
```

## 配置说明

数据存储配置通过 `server.yaml` 中的 `data` 段设置，包含 Redis 和 MySQL 连接信息。存储类型（`tier`）支持：

- `TierMemory` / `memory`：纯内存。**注意：只能由代码构造 —— 写进 `server.yaml` 会在加载时被拒**（见 `internal/app/config.go`）
- `TierRedis` / `redis`：仅 Redis
- `TierRedisMySQL` / `redis_mysql` / `mysql`：Redis + MySQL（默认）
- `TierSnapshot` / `snapshot` / `mmo`：大世界快照存储

## 常见问题

### 事务失败

**症状**：数据修改未生效

**原因**：handler 返回了错误

**解决**：
1. 检查 handler 返回的错误信息
2. 确认数据库连接正常
3. 查看引擎日志

### 数据不一致

**症状**：读取到过期数据

**原因**：并发修改冲突

**解决**：
1. 引擎自动重试机制
2. 检查业务逻辑是否有竞态条件
3. 使用分布式锁（如需要）
