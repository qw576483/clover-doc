
> **注意：** 以下示例中 `g.OnConnect`、`g.OnDisconnect`、`g.CreatePlayer` 都是 `pkg/app` 门面上的**公开 API**，
> 业务可直接调用：引擎的 `internal/app` 类型经 `pkg/app` 门面（`type Game = internal/app.GameFacade`，
> `GameFacade` 内嵌 `*internal/app.Game`）透出，这三个方法由内嵌结构**提升**到 `*app.Game` 的方法集上
> （同族还有 `OnSoftDisconnect` / `OnHardDisconnect`）。所以本页把连接钩子与建角放在
> `app.Mount(app.RoleGame, …)` 的业务挂载回调里，正是业务侧的写法。
> 业务侧只需定义消息 → 定义 Schema → 挂载 Handler → 实现业务，引擎自动处理登录/注册/会话恢复。

引擎内置了完整的登录与会话恢复流程（`EMsgLogin` / `EMsgResumeSession`），**业务无需编写任何登录代码**；注册走账号服 HTTP，不经过游戏服。你只需完成四步：定义消息 → 定义 Schema → 挂载 Handler → 实现业务。

> **注意：** 引擎内置了登录/会话恢复的全部逻辑，业务侧**不要**注册 `EMsgLogin` 的 handler，否则会覆盖内置逻辑。


## 完整流程

### 定义消息

```go game/def/msg.go
// C2S 消息号（从 1000101 起）
const (
    MsgGetPlayerList uint32 = 1000101 // 获取角色列表
    MsgCreatePlayer  uint32 = 1000102 // 创建角色
    MsgEnterGame     uint32 = 1000103 // 进入游戏
)

type GetPlayerListRequest struct {
    Account  string `json:"account"`
    ServerID uint32 `json:"server_id"`
}

type CreatePlayerRequest struct {
    Name     string `json:"name"`
    ServerID uint32 `json:"server_id"`
}
```

```go game/def/reply.go
// S2C 回包：不占消息号（按 requestID 配对，帧 msgID 恒为 0），只定义回复体结构

type GetPlayerListReply struct {
    PlayerIds []string `json:"player_ids"`
}

type CreatePlayerReply struct {
    PlayerID string `json:"player_id"`
    Err      string `json:"err,omitempty"`
}
```

### 定义玩家 Schema

```go game/datadef/player.go
var PlayerSchema = data.StructSchema{
    Type:       "player",
    OwnerType:  data.OwnerPlayer,  // 玩家维度，改动只广播该玩家
    Visibility: data.ClientVisible, // 客户端可见
}

func init() {
    data.RegisterTypeBySchema(PlayerSchema)
}

type Player struct {
    Name  string `json:"name"`
    Level int    `json:"level"`
}
```

> **注意：** 首次 `LoadStruct` 会自动注册 schema 和 visibility，无需手动初始化。


### 挂载消息处理

```go game/logic/player.go
package logic

import (
    "your-game/server/game/datadef"
    "your-game/server/game/def"
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/transport/event"
)

var GPlayer *playerLogic

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        GPlayer = &playerLogic{g: g}

        // 注册业务消息 handler
        g.OnMsg(def.MsgGetPlayerList, GPlayer.onMsgGetPlayerList)
        g.OnMsg(def.MsgCreatePlayer, GPlayer.onMsgCreatePlayer)
        g.OnMsg(def.MsgEnterGame, GPlayer.onMsgEnterGame)

        // 连接钩子：上线 / 下线
        g.OnConnect(func(owner string) {
            // 玩家上线：可在此推送数据、广播上线事件
        })
        g.OnDisconnect(func(owner string) {
            // 玩家下线：引擎已自动 StopTimerGroup(owner)
        })
    })
}

type playerLogic struct {
    g *app.Game
}
```

### 实现业务 Handler

```go game/logic/player.go
// 获取角色列表
func (l *playerLogic) onMsgGetPlayerList(c event.Ctx) error {
    var req def.GetPlayerListRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }

    // 从数据库查询该账号下的所有角色
    players, err := l.g.PlayerStore().GetByAccount(c.Context(), c.Account(), req.ServerID)
    if err != nil {
        l.g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "获取角色列表失败"})
        return nil
    }

    // 组装回包
    reply := def.GetPlayerListReply{}
    for _, v := range players {
        reply.PlayerIds = append(reply.PlayerIds, v.PlayerID)
    }
    l.g.Reply(c, reply)
    return nil
}

// 创建角色
func (l *playerLogic) onMsgCreatePlayer(c event.Ctx) error {
    var req def.CreatePlayerRequest
    if err := c.BindMsg(&req); err != nil {
        return err
    }
    if req.Name == "" || req.ServerID == 0 {
        l.g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: "请检查参数"})
        return nil
    }

    // 引擎侧创建玩家（含 ServerID 区服落位）
    pl, err := l.g.CreatePlayer(c.Context(), c.Account(), req.Name, req.ServerID)
    if err != nil {
        l.g.Alert(c, &proto.EAlertNotify{Title: "错误", Content: err.Error()})
        return nil
    }
    c.SetPlayerID(pl.PlayerID)

    l.g.Reply(c, def.CreatePlayerReply{PlayerID: pl.PlayerID})
    return nil
}

// 进入游戏
func (l *playerLogic) onMsgEnterGame(c event.Ctx) error {
    // 读取玩家数据（首次 Load 会自动注册到 identity map）
    var p datadef.Player
    _ = l.g.LoadStruct(c, datadef.PlayerSchema, c.PlayerID(), &p)

    l.g.Reply(c, map[string]any{"name": p.Name, "level": p.Level})
    return nil
}
```

## 全量同步

登录/建角成功后，**由业务**调用 `g.PushPlayerFullSync(playerID, account)` 下发 `EPushPlayerFullSync`（4001）
——引擎**不会**自动推送（`pkg/shared/proto/push.go` 的 `EPushPlayerFullSync` 注释）。客户端收到的完整数据结构如下：

```json
{
  "player_id": "p_10001",
  "account": "alice",
  "player": { "player_id": "p_10001", "name": "alice", "account": "alice", "server_id": 1 },
  "data": { "player": { "player": { "name": "alice", "level": 1 } } },
  "session_token": "xxxx"
}
```

> **注意：** `data` 按 `visibility` 过滤（`ServerOnly` 的数据不会下发）。
> `session_token` 供**断线重连**时 `EMsgResumeSession` 使用（TCP / WS 各条线路一致，不限 WebSocket）。
> 恢复回包**必须带 `owner`**：网关只在回包能解出非空 `owner` 时把重连后的新连接绑回原 owner，
> 否则该连接过不了登录门禁，后续业务消息会被全量拒为 `401`。


## 要点总结

| 规则 | 说明 |
| --- | --- |
| 不要注册登录 handler | `EMsgLogin` 由引擎内置处理 |
| LoadStruct 自动注册 | 首次加载会自动注册 schema 和 visibility |
| 修改即广播 | 修改 `Player` 结构体后直接返回，引擎自动 Commit + 增量广播 |
| 手动回包用 Reply | 不依赖自动广播的场景用 `g.Reply()` |

## 下一步

1. [心跳与连接生命周期](../concepts/heartbeat.md) —— 连接、会话与心跳机制
2. [协议与消息号](../concepts/proto.md) —— 消息号定义与协议规范

