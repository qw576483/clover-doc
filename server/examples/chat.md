
引擎提供两种广播模式：**数据驱动**（`OwnerServer` 数据改动自动广播全服）和**命令式推送**（`PushToAll` / `PushToPlayer` 主动下发）。本示例以"设置服务器公告"为基础演示两种模式的用法。

## 完整流程

### 定义消息

```go game/def/msg.go
// C2S 消息号
const MsgSetAnnounce uint32 = 1000501

type SetAnnounceRequest struct {
    ServerID string `json:"server_id"`
    Content  string `json:"content"`
}
```

```go game/def/reply.go
// S2C 回包：不占消息号（按 requestID 配对，帧 msgID 恒为 0），只定义回复体结构
type SetAnnounceReply struct {
    Success bool   `json:"success"`
    Err     string `json:"err,omitempty"`
}
```

```go game/def/push.go
// 推送消息号
const PushDemoBroadcast uint32 = 3003001

type DemoBroadcastNotify struct {
    Content string `json:"content"`
}
```

### 实现 OwnerServer 数据驱动广播

修改 `OwnerServer` 数据后，引擎自动通过 NATS 广播到所有网关，网关群发全服客户端。

```go game/logic/server.go
package logic

import (
    "your-game/server/game/datadef"
    "your-game/server/game/def"
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/transport/event"
)

var GServer *serverLogic

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        GServer = &serverLogic{g: g}
        GServer.g.OnMsg(def.MsgSetAnnounce, GServer.onMsgSetAnnounce)
    })
}

type serverLogic struct {
    g *app.Game
}

type ServerAnnounce struct {
    Content string `json:"content"`
}

func (l *serverLogic) onMsgSetAnnounce(c event.Ctx) error {
    var req def.SetAnnounceRequest
    if err := c.BindMsg(&req); err != nil || req.ServerID == "" || req.Content == "" {
        l.g.Reply(c, def.SetAnnounceReply{Success: false, Err: "bad request"})
        return nil
    }

    // LoadStruct(OwnerServer) 首次触发自动注册 visibility + schema
    // 修改数据 → pushBatch 路由到 NATS broadcast subject → 网关群发全服
    var v ServerAnnounce
    _ = l.g.LoadStruct(c, datadef.ServerAnnounce, req.ServerID, &v)
    v.Content = req.Content
    // handler 返回后 Commit 自动 dirty → pushBatch → broadcast

    l.g.Reply(c, def.SetAnnounceReply{Success: true})
    return nil
}
```

### 主动推送（PushToAll / PushToPlayer）

`OwnerServer` 改动是数据驱动的自动广播；若需主动触发推送，用 `Game` 的推送方法：

```go
// 全服广播：入参是"任意值"，内部自动 JSON 编码
l.g.PushToAll(def.PushDemoBroadcast, def.DemoBroadcastNotify{Content: "hi"})

// 单播给指定玩家（同样自动 JSON 编码）
l.g.PushToPlayer(playerID, def.PushDemoBroadcast, def.DemoBroadcastNotify{Content: "hi"})

// 指定空间（MMO 视野广播）：要自己给编码后的字节，必须用 *Raw 版本
l.g.PushToSceneRaw(space, def.PushDemoBroadcast, body)
```

> **注意：** `mustJSON` 为 demo 内自定义辅助函数（内部调 `ujson.Marshal` 忽略错误），引擎 `pkg/shared/json` 仅提供 `Marshal`/`Unmarshal`，没有 `MustMarshal`。


### 限流（可选）

广播类接口建议限流，防止刷屏：

```go
import "github.com/qw576483/clover-server-engine/pkg/runtime/ratelimit"

limiter := ratelimit.NewManager(
    ratelimit.WithIdleTTL(10 * time.Minute),
)
// 注册限流策略：TokenBucketPolicy(rate, burst)
limiter.RegisterPolicy("announce", ratelimit.TokenBucketPolicy(5, 10))

// 每请求放行判断
if !limiter.Allow(c.PlayerID(), "announce") {
    l.g.Reply(c, def.SetAnnounceReply{Success: false, Err: "rate limited"})
    return nil
}
```

> **提示：** `ratelimit.Manager` 支持 TokenBucket / FixedWindow / SlidingWindow / GCRA 多种 policy，通过 `RegisterPolicy(name, factory)` 按名注册、按 key 维度隔离。


## 要点总结

| 模式 | 方法 | 适用场景 |
| --- | --- | --- |
| 数据驱动广播 | `OwnerServer` 数据改动自动广播 | 公告、开服倒计时等全局状态 |
| 命令式推送 | `PushToAll` / `PushToPlayer` / `PushToScene` | 主动下发事件通知 |
| 限流 | `ratelimit.Manager.Allow(key, policy)` | 防刷屏，按玩家/连接维度隔离 |
| 不回包即广播 | 纯广播场景可不 `Reply` | 客户端以推送为准 |

## 相关文档


**相关链接：**

- [推送机制](../concepts/push.md) - 数据驱动广播与命令式推送

- [数据存储](../concepts/data.md) - 数据模型与 Load-Modify-Return

- [集群与 Master](../concepts/cluster.md) - 跨节点数据同步与 NATS 广播


