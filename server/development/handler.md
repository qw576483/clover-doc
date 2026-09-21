# Handler 开发指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的 Handler 开发模式，包括如何创建、配置和使用 Handler 处理客户端消息。目标读者是想要实现游戏业务逻辑的开发者。

## 前置条件

- 了解 Go 语言基础
- 熟悉 Clover 引擎的项目结构
- 了解消息号定义和协议设计

## 快速开始

### 1. 创建基本 Handler

```go
package logic

import (
    "github.com/qw576483/clover-server-engine/pkg/transport/event"
    "your-game/def"
)

func loginHandler(c event.Ctx) error {
    // 绑定请求消息
    var req def.LoginRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    
    // 处理登录逻辑（通过 g.Reply 回包，见下方注册示例）
    return nil
}
```

### 2. 注册 Handler

Handler 通过 `app.Mount(app.RoleGame, ...)` 在 `init` 中注册：

```go
package logic

import (
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/transport/event"
    "your-game/def"
)

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgLogin, loginHandler)
        g.OnMsg(def.MsgCreatePlayer, createPlayerHandler)
    })
}

func loginHandler(c event.Ctx) error {
    // 处理登录逻辑
    return nil
}

func createPlayerHandler(c event.Ctx) error {
    // 处理创建玩家逻辑
    return nil
}
```

## Handler 模式详解

### 基本结构

业务逻辑通过 `g.OnMsg` 注册的普通函数处理；函数签名为 `func(c event.Ctx) error`。

```go
// 方式一：闭包注册（g 通过闭包捕获）
g.OnMsg(def.MsgMyRequest, func(c event.Ctx) error {
    var req MyRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    
    result, err := processBusinessLogic(req)
    if err != nil {
        return err
    }
    
    // 注意：回包在 Game 上，不在 Ctx 上
    g.Reply(c, &MyReply{
        Result: result,
    })
    
    return nil
})

// 方式二：结构体方法（g 持有在结构体中）
type myLogic struct {
    g *app.Game
}

func (l *myLogic) onMsgMyRequest(c event.Ctx) error {
    var req MyRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    l.g.Reply(c, &MyReply{Result: "ok"})
    return nil
}
```

### Context API 详解

`event.Ctx` 只提供**只读上下文**；回包和推送必须通过 `*app.Game`（即 `g`）完成。

| API | 所属 | 说明 | 示例 |
|-----|------|------|------|
| `c.BindMsg(&msg)` | Ctx | 将请求体 JSON 反序列化到结构体 | `c.BindMsg(&req)` |
| `g.Reply(c, v)` | Game | 以 JSON 回复客户端（同一请求仅首次生效） | `g.Reply(c, &LoginReply{...})` |
| `g.PushToPlayer(playerID, msgID, v)` | Game | 推送给指定玩家（跨节点自动路由） | `g.PushToPlayer(pid, def.PushNotice, notice)` |
| `g.SendEventToPlayer(c, playerID, typ, payload)` | Game | 并发通道：发送领域事件给玩家 | `g.SendEventToPlayer(c, pid, "player.OnCreate", data)` |
| `g.SendQueueEventToPlayer(c, playerID, typ, payload)` | Game | 串行通道：同玩家事件 FIFO | `g.SendQueueEventToPlayer(c, pid, "battle.damage", dmg)` |
| `g.SendEventToGObject(ctx, id, typ, payload)` | Game | 并发通道：发送事件给 GObject | `g.SendEventToGObject(ctx, bossID, "death", ev)` |
| `g.SendQueueEventToGObject(ctx, id, typ, payload)` | Game | 串行通道：同对象事件互斥 | `g.SendQueueEventToGObject(ctx, bossID, "take_damage", dmg)` |
| `g.Alert(c, &proto.EAlertNotify{...})` | Game | 弹出客户端警告弹窗 | `g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: msg})` |
| `c.PlayerID()` | Ctx | 获取当前玩家 ID（string） | `playerID := c.PlayerID()` |
| `c.Account()` | Ctx | 获取当前账号名 | `account := c.Account()` |
| `c.TraceID()` / `c.SpanID()` | Ctx | 获取链路追踪 ID | `traceID := c.TraceID()` |
| `c.RequestID()` / `c.MsgID()` | Ctx | 获取请求/消息号 | `id := c.RequestID()` |
| `c.ConnID()` | Ctx | 获取连接 ID | `connID := c.ConnID()` |
| `c.ConnValue(key)` / `c.SetConnValue(key, value)` | Ctx | 连接级 KV 存储 | `c.SetConnValue("key", "value")` |
| `c.SetPlayerID(pid)` | Ctx | 设置当前连接角色 ID | `c.SetPlayerID("p_1")` |
| `c.SetNoAutoReply()` / `c.SetNoPush()` | Ctx | 关闭自动回包/数据变更推送 | `c.SetNoPush()` |
| `c.Payload()` | Ctx | 取回领域事件原始载荷（`any`，OnEvent handler 用） | `payload := c.Payload()` |
| `c.BindEvent(v)` | Ctx | 反序列化领域事件载荷到 v | `c.BindEvent(&data)` |

> **注意：** `event.Ctx` 上不存在 `Reply`、`Push`、`Bind`（应为 `BindMsg`）、`Data()`、`Game()`、`SpaceID()`、`Session()` 等方法（`Session()` 仅存在于引擎内部实现，公开 `Ctx` 接口上没有）。回包/推送在 `*app.Game` 上，数据读写通过 `g.LoadStruct(c, schema, id, &v)`。

## 实际示例

### 示例1：创建玩家

```go
func createPlayerHandler(c event.Ctx) error {
    var req def.CreatePlayerRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    
    // 读取已有玩家数据
    var existing def.PlayerData
    if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &existing); err != nil {
        // 加载失败（非不存在），返回错误
        return err
    }
    if existing.Name != "" {
        g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "玩家已存在"})
        return nil
    }
    
    // 创建新玩家（LoadModifyReturn）
    var p def.PlayerData
    _ = g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p)
    p.Name = req.Name
    p.Level = 1
    
    // 回复创建成功
    g.Reply(c, def.CreatePlayerReply{PlayerID: c.PlayerID()})
    
    // 发送领域事件
    g.SendEventToPlayer(c, c.PlayerID(), def.EvtPlayerCreated, def.EvtPlayerCreatedData{Name: req.Name})
    
    return nil
}
```

### 示例2：排行提交

```go
func onSubmitScore(c event.Ctx) error {
    var req def.RankSubmitRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    
    if req.Board == "" || req.Score == 0 {
        g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "请指定 board 和 score"})
        return nil
    }
    
    if c.PlayerID() == "" {
        g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "尚未进入游戏"})
        return nil
    }
    
    // 通过 master 客户端提交排行榜分数
    mr := master.NewMasterRank(g)
    if err := mr.Add(c.Context(), req.Board, c.PlayerID(), req.Score, nil); err != nil {
        g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: fmt.Sprintf("提交失败: %v", err)})
        return nil
    }
    
    g.Reply(c, map[string]any{"board": req.Board, "ok": true})
    return nil
}
```

### 示例3：查询玩家所在节点（跨服好友 / 观战）

```go
func onQueryFriend(c event.Ctx) error {
    var req def.FriendOnlineRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }

    // master 玩家定位表查询：在线时给出玩家当前所在节点
    lk := master.NewPlayerLookup(g)
    nodeID, online, err := lk.Locate(c.Context(), req.PlayerID)
    if err != nil {
        // 注意：查询通道不可用 ≠ 玩家离线，不要混用
        logger.Errorf("locate player %s: %v", req.PlayerID, err)
        return err
    }

    g.Reply(c, def.FriendOnlineReply{PlayerID: req.PlayerID, Online: online, NodeID: nodeID})
    return nil
}
```

> **模式总结：** 回包用 `g.Reply(c, v)`，警告弹窗用 `g.Alert(c, &proto.EAlertNotify{...})`，推送用 `g.PushToPlayer(pid, msgID, v)`。`event.Ctx` 上不存在这些方法。

## 错误处理

### 错误码定义（示例）

> 以下为业务侧自行定义的错误变量（不是引擎提供的）。引擎预置错误见 `pkg/domain/` 下的
> `data.ErrNotFound`、`player.ErrPlayerNotFound`、`account.ErrInvalidToken` 等。

```go
package def

import "errors"

var (
    ErrInvalidCredentials   = errors.New("账号或密码错误")
    ErrPlayerAlreadyExists  = errors.New("角色已存在")
    ErrInvalidMessageContent = errors.New("消息内容无效")
    ErrSavePlayerFailed     = errors.New("保存角色失败")
)
```

### 错误处理模式

```go
func myHandler(c event.Ctx) error {
    // 模式1：直接返回错误（框架自动以 EErrorReply 回包）
    if err := validateInput(req); err != nil {
        return err
    }
    
    // 模式2：业务错误用 g.Alert 告知客户端，返回 nil
    result, err := processRequest(req)
    if err != nil {
        g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: err.Error()})
        return nil
    }
    
    // 模式3：成功回包
    g.Reply(c, &MyReply{Result: result})
    return nil
}
```

## 定时器使用

### 基本定时器

定时器通过 `g.Timer`（`*app.Game` 的字段）访问，而非 handler 上下文。

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    // 延迟执行
    g.Timer.After("delay-task", 5*time.Second, func() {
        // 5秒后执行
        performDelayedTask()
    })
    
    // 周期性执行
    g.Timer.Every("periodic-task", 1*time.Minute, func() {
        // 每分钟执行
        performPeriodicTask()
    })
    
    // 在指定时间执行（用引擎时区构造）
    target := g.Timer.Date(2024, time.December, 25, 10, 0, 0, 0)
    g.Timer.ByTime("scheduled-task", target, func() {
        // 在指定时间执行
        performScheduledTask()
    })
    
})
```

### 定时器管理

```go
var playerTimer timer.Timer

app.Mount(app.RoleGame, func(g *app.Game) {
    playerTimer = g.Timer.Every("player-timer", 1*time.Second, func() {
        // 定时任务
    })
})

// 取消定时器
if playerTimer != nil {
    playerTimer.Stop()
}
```

## 数据访问

### Load-Modify-Return 模式

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgLevelUp, func(c event.Ctx) error {
            // Load: 读取数据（PlayerSchema 是 datadef 中的变量，不是类型）
            var p PlayerData  // 业务自定义结构体
            if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p); err != nil {
                return err
            }
            
            // Modify: 修改结构体
            p.Level += 1
            
            // Return: handler 返回后引擎自动 Commit + 增量广播
            return nil
        })
    })
}
```

> **注意：** `LoadStruct` 签名：`g.LoadStruct(c event.Ctx, schema data.StructSchema, id string, v any) error`。同 handler 内重复 Load 命中 identity map，读到同一实例。

## 推送数据

### 推送给指定玩家

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgSendNotice, func(c event.Ctx) error {
            // 推送给当前玩家
            g.PushToPlayer(c.PlayerID(), def.PushNotice, &NoticeMsg{
                Content: "操作成功",
            })
            
            // 推送给其他指定玩家
            g.PushToPlayer(targetPlayerID, def.PushNotify, &NotifyMsg{
                From:    c.PlayerID(),
                Content: "你收到了新消息",
            })
            
            return nil
        })
    })
}
```

### 广播消息

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        // 广播给所有在线玩家
        g.PushToAll(def.PushSystemNotice, &BroadcastMsg{
            Type:    "system",
            Content: "服务器即将维护",
        })
        
        // 广播给场景内所有玩家
        g.PushToScene(scene, def.PushRoomMsg, &RoomMsg{
            Type:    "chat",
            Content: "玩家加入了房间",
        })
    })
}
```

## 最佳实践

### 1. Handler 设计原则

- **单一职责**：每个 Handler 只处理一条消息
- **无状态**：Handler 不应保存状态，使用 Session 或数据库
- **快速响应**：Handler 应在 100ms 内返回，长时间任务使用定时器
- **错误处理**：明确错误码，不要吞掉错误

### 2. 性能优化

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgGetPlayer, func(c event.Ctx) error {
            // 1. 使用 LoadStruct 读取数据（同 handler 内重复 Load 命中 identity map）
            var p PlayerData  // 业务自定义结构体
            if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p); err != nil {
                return err
            }
            
            // 2. 使用 Timer 异步处理非关键路径
            g.Timer.After("log:"+c.TraceID(), 0, func() {
                // 异步记录日志
            })
            
            return nil
        })
    })
}
```

### 3. 安全性

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgSubmitData, func(c event.Ctx) error {
            var req SubmitDataRequest
            if err := c.BindMsg(&req); err != nil {
                return err
            }
            
            // 1. 验证权限（★ 业务自建：引擎不内置 RBAC，没有 g.HasPermission/GetPlayerRole）
            if !l.hasPermission(c.PlayerID(), req.TargetID) {
                return ErrPermissionDenied
            }
            
            // 2. 防止重复提交（使用连接级存储）
            if _, exists := c.ConnValue("submit:" + req.RequestID); exists {
                return ErrDuplicateRequest
            }
            c.SetConnValue("submit:"+req.RequestID, true)
            
            // 3. 输入验证
            if err := validateInput(req); err != nil {
                return err
            }
            
            // 4. 限制频率
            if !rateLimiter.Allow(c.PlayerID()) {
                return ErrTooManyRequests
    }
    
    return nil
}
```

## 调试技巧

### 1. 日志记录

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgXxx, func(c event.Ctx) error {
            startTime := time.Now()
            logger.Infof("[%s] Handler started: playerID=%s", c.TraceID(), c.PlayerID())
            // 处理业务逻辑...
            logger.Infof("[%s] Handler completed: duration=%v", c.TraceID(), time.Since(startTime))
            return nil
        })
    })
}
```

### 2. 链路追踪

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgDebug, func(c event.Ctx) error {
            traceID := c.TraceID()
            spanID := c.SpanID()
            
            logger.Infof("[%s:%s] Handler started: playerID=%s", traceID, spanID, c.PlayerID())
            
            // 处理业务逻辑...
            
            return nil
        })
    })
}
```

### 3. 性能监控

```go
import "github.com/qw576483/clover-server-engine/pkg/foundation/metrics"

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        m := metrics.ForModule("handler")
        g.OnMsg(def.MsgDataOperation, func(c event.Ctx) error {
            // 方式一：手动计时
            start := time.Now()
            // 处理业务逻辑...
            m.Observe("msg_duration", start, nil, fmt.Sprintf("msg=%d", c.MsgID()))

            // 方式二：用 Timer 闭包自动计时
            defer m.Timer("msg_timer")()
            // 处理业务逻辑...

            return nil
        })
    })
}
```

## 下一步

1. [配置管理](configuration.md)
2. [错误处理](error-handling.md)
3. [数据持久化](persistence.md)
4. [性能优化](performance.md)
5. [测试指南](testing.md)

