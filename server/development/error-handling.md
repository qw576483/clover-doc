# 错误处理指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的错误处理机制：handler 返回错误时框架如何回包、业务如何用弹窗通知客户端、以及常见的错误处理模式。目标读者是想要构建健壮游戏服务的开发者。

## 前置条件

- 了解 Go 语言错误处理
- 熟悉 Clover 引擎的 Handler 开发模式（参见 [Handler 开发指南](handler.md)）

## 核心机制：handler 返回 error

引擎的错误处理非常简洁——**handler 返回值就是唯一的错误信号**：

```go
func myHandler(c event.Ctx) error {
    // ...
    if err != nil {
        return err  // 框架自动以 EErrorReply 回包
    }
    return nil
}
```

| 返回值 | 框架行为 |
|--------|----------|
| `return err`（非 nil） | 自动发送 `EErrorReply{Err: err.Error()}` 给客户端 |
| `return nil` 且未调用 `g.Reply` | 不回包（fire-and-forget） |
| `return nil` 且已调用 `g.Reply` | 正常回包，不触发错误回包 |

`EErrorReply` 结构（`internal/shared/proto/reply.go`）：

```go
type EErrorReply struct {
    Err  string `json:"err"`
    Code int32  `json:"code,omitempty"`
}
```

客户端收到错误回包时，`Err` 是 handler 返回 error 的字符串内容（人类可读、**仅用于展示**）；
`Code` 是机器可读错误码（`0` = 未分类，取值见 `ErrCode*` 常量）——
**业务应按码分支，不要匹配文案**（文案会变，码不会）。

## 两种通知客户端的方式

### 方式一：返回 error（自动错误回包）

适用于可预见的业务校验失败。**error 的字符串内容会直接发给客户端**，所以要写用户能理解的话：

```go
func loginHandler(c event.Ctx) error {
    var req proto.LoginRequest
    if err := c.BindMsg(&req); err != nil {
        return fmt.Errorf("参数格式错误: %w", err)
    }

    account, err := auth.Authenticate(req.Username, req.Password)
    if err != nil {
        return ErrInvalidCredentials  // 客户端收到 {"err": "invalid credentials"}
    }

    // ... 处理登录逻辑 ...

    return nil  // 正常流程不返回错误
}
```

### 方式二：g.Alert（UI 弹窗）

适用于需要在客户端弹窗显示的提示（如"金币不足"、"背包已满"）。调用 `g.Alert` 后返回 `nil`：

```go
func buyItemHandler(c event.Ctx) error {
    var req BuyRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }

    var player PlayerData
    if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &player); err != nil {
        return err
    }

    if player.Coins < req.Price {
        g.Alert(c, &proto.EAlertNotify{Title: "提示", Content: "金币不足"})
        return nil  // 已通知客户端，返回 nil
    }

    // ... 扣费逻辑 ...
    g.Reply(c, &BuyReply{OK: true})
    return nil
}
```

`EAlertNotify` 结构（`pkg/shared/proto/push.go`）：

```go
type EAlertNotify struct {
    Title   string `json:"title"`
    Content string `json:"content"`
    Level   string `json:"level,omitempty"` // info / success / warning / error
    Style   string `json:"style,omitempty"` // toast / modal
    TTL     int    `json:"ttl,omitempty"`   // 自动关闭毫秒数；0=手动关闭
}
```

### 选择哪种？

| 场景 | 推荐方式 | 原因 |
|------|----------|------|
| 参数校验失败 | `return err` | 框架自动回包，代码简洁 |
| 数据不存在 / 权限不足 | `return err` | 同上 |
| 金币不足 / 背包满等 UI 提示 | `g.Alert` | 需要标题+正文，弹窗体验更好 |
| 需要携带额外回包数据 | `g.Alert` + `g.Reply` | Alert 弹窗 + Reply 返回数据 |

> **注意：** `g.Alert` 本身不回包（它走推送通道），所以 Alert 后如果还需要回包数据，要单独调用 `g.Reply`。

## 错误定义惯例

引擎有统一的**错误码契约**（`pkg/shared/proto/errcode.go` 的 `ErrCode*` 常量与 `BizError`），但错误定义仍由业务自行管理——用标准 Go `errors.New()` 或 `fmt.Errorf()` 即可，需要机器可读错误码时用 `proto.NewBizError(code, msg)`（业务码从 1000 起）。

### 引擎预置的错误

引擎在 `pkg/domain/` 下预置了一些通用错误，业务可直接引用：

```go
import (
    "clover-server-engine/pkg/domain/data"
    "clover-server-engine/pkg/domain/data/player"
    "clover-server-engine/pkg/domain/data/account"
)

// 数据层
data.ErrNotFound          // data: not found

// 角色
player.ErrPlayerNotFound  // 角色不存在
player.ErrPlayerExists    // 角色已存在

// 账号
account.ErrInvalidToken   // token 校验失败
account.ErrTokenExpired   // token 过期
```

### 业务自定义错误

业务错误在自己的 `game/def/` 包中定义，**命名清晰、消息对用户友好**：

```go
package def

import "errors"

var (
    ErrInvalidCredentials = errors.New("账号或密码错误")
    ErrPlayerBanned       = errors.New("账号已被封禁")
    ErrInsufficientCoins  = errors.New("金币不足")
    ErrInventoryFull      = errors.New("背包已满")
    ErrItemNotFound       = errors.New("物品不存在")
    ErrCooldownActive     = errors.New("冷却中")
)
```

> **原则：** 错误字符串会直接展示给客户端用户，所以写中文、写清楚。内部调试信息用 `logger.Error` 记录，不要混在 error 字符串里。

## 常见错误处理模式

### 1. Load-Modify-Return 数据操作

```go
func levelUpHandler(c event.Ctx) error {
    var p datadef.PlayerSchema
    if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p); err != nil {
        return fmt.Errorf("加载角色失败: %w", err)
    }

    if p.Level >= MaxLevel {
        g.Alert(c, &proto.EAlertNotify{Title: "提示", Content: "已达到最高等级"})
        return nil
    }

    p.Level++
    // Load-Modify-Return：改完字段，handler 返回 nil 后框架自动提交
    return nil
}
```

### 2. 多步操作 + 事务性错误

```go
func tradeHandler(c event.Ctx) error {
    var req TradeRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }

    // 加载买家数据
    var buyer PlayerData
    if err := g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &buyer); err != nil {
        return err
    }

    // 加载卖家数据
    var seller PlayerData
    if err := g.LoadStruct(c, datadef.PlayerSchema, req.SellerID, &seller); err != nil {
        return ErrPlayerNotFound
    }

    // 校验
    if buyer.Coins < req.Price {
        return ErrInsufficientCoins
    }

    // 扣费 + 加物品（Load-Modify-Return 模式下修改自动提交）
    buyer.Coins -= req.Price
    // ... 加物品逻辑 ...

    g.Reply(c, &TradeReply{OK: true})
    return nil
}
```

### 3. 抑制自动回包

有些场景（如心跳、广播确认）不需要回包：

```go
func heartbeatHandler(c event.Ctx) error {
    c.SetNoAutoReply()  // 抑制框架自动回包
    // 更新连接活跃时间等逻辑...
    return nil
}
```

### 4. Panic 恢复

引擎框架层已有 panic 恢复机制，业务 handler 一般不需要自己写 `defer recover()`。如果确实需要在特定 handler 中做额外恢复：

```go
func riskyHandler(c event.Ctx) error {
    defer func() {
        if r := recover(); r != nil {
            logger.Error("handler panic",
                logger.WithTrace(c.TraceID()),
                logger.Field("panic", r),
                logger.Field("stack", string(debug.Stack())))
        }
    }()

    // 业务逻辑...
    return nil
}
```

## 测试错误处理

```go
func TestLevelUpHandler_MaxLevel(t *testing.T) {
    ctx := mockEventCtx()
    ctx.SetPlayerID("test-player-001")

    // 准备一个满级角色
    setupPlayer(t, ctx, &PlayerData{Level: MaxLevel})

    err := levelUpHandler(ctx)
    if err != nil {
        t.Errorf("满级应返回 nil（用 Alert 通知），实际: %v", err)
    }

    // 验证框架回包
    reply := getReply(ctx)
    if reply == nil {
        t.Fatal("应有回包")
    }
}
```

## 最佳实践

1. **错误信息面向用户**：error 字符串直接发给客户端，写"金币不足"而非"coins < price"。
2. **内部调试走日志**：详细上下文用 `logger.Error` + `logger.Field` 记录，不要混在 error 里。
3. **区分弹窗与错误**：需要标题+正文的 UI 提示用 `g.Alert`；通用校验失败直接 `return err`。
4. **不要吞错误**：`if err != nil { return nil }` 会让客户端以为成功了，非常危险。
5. **利用引擎预置错误**：`data.ErrNotFound`、`player.ErrPlayerNotFound` 等可直接复用。

## 相关文档

- [Handler 开发指南](handler.md) — handler 签名、回包、注册
- [日志管理](logging.md) — 结构化日志与链路追踪
- [测试指南](testing.md) — 单元测试与集成测试
- [配置管理](configuration.md) — 引擎配置
