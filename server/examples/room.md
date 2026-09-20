
本示例演示基于「Master 注册表 + 连接迁移」的帧同步房间。核心思路：**房主节点权威**，非房主玩家经 `SwitchUpstream` 把连接迁移到房主节点，帧输入直达房主、零转发。

## 架构

```text
玩家A ──► gateway ──► game1（房主，权威模拟）
玩家B ──► gateway ──► game1  ← 经 SwitchUpstream 迁移
玩家C ──► gateway ──► game2 ──►（查 Master 注册表 → 迁移到 game1）
```

> **注意：** 房间列表在 Master 统一注册。加入房间时：本机有 → 直接加入；Master 查房主在其他节点 → `SwitchUpstream` 迁移连接，客户端无感知。


## 完整流程

### 定义消息

```go game/def/frame.go
const (
    MsgFrameRoomCreate   uint32 = 1002001
    MsgFrameRoomJoin     uint32 = 1002002
    MsgFrameRoomLeave    uint32 = 1002003
    MsgFrameRoomInput    uint32 = 1002004
    MsgFrameRoomSnapshot uint32 = 1002006
    MsgFrameRoomInfo     uint32 = 1002007

    // 回包不占消息号（按 requestID 配对，帧 msgID 恒为 0）

    PushFrameRoomSync   uint32 = 3002001
    PushFrameRoomClosed uint32 = 3002002
)

type FrameRoomCreateReq struct {
    RoomID    string `json:"room_id"`
    TargetFPS int    `json:"target_fps"`
}

type FrameRoomInputReq struct {
    RoomID string           `json:"room_id"`
    Input  FramePlayerInput `json:"input"`
}

type FramePlayerInput struct {
    MoveX int `json:"move_x"`
    MoveY int `json:"move_y"`
}

type FramePlayerState struct {
    PlayerID string `json:"player_id"`
    PosX     int    `json:"pos_x"`
    PosY     int    `json:"pos_y"`
    HP       int    `json:"hp"`
}

type FrameRoomReply struct {
    OK       bool   `json:"ok"`
    RoomID   string `json:"room_id,omitempty"`
    NodeAddr string `json:"node_addr,omitempty"`
}

type FrameRoomSyncNotify struct {
    RoomID       string                       `json:"room_id"`
    Frame        int64                        `json:"frame"`
    PlayerStates map[string]*FramePlayerState `json:"players"`
}
```

### 挂载与房间管理

```go game/logic/frame_room.go
package logic

import (
    "your-game/server/game/def"
    "clover-server-engine/pkg/app"
    "clover-server-engine/pkg/transport/event"
    "clover-server-engine/pkg/domain/room"
    engframe "clover-server-engine/pkg/domain/room/frame"
)

var frameRoomDemo *frameRoomDemoLogic

type frameRoomDemoLogic struct {
    roomMod *room.Module
    g       *app.Game
}

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        // 房间子系统独立组装（谁用谁自己组装）
        roomMod := room.NewModule(room.Config{
            MasterCaller: g,
            Pusher:       func(pid string, msgID uint32, v any) error { return g.PushToPlayer(pid, msgID, v) },
            NodeAddr:     g.Addr(),
        })
        frameRoomDemo = &frameRoomDemoLogic{roomMod: roomMod, g: g}
        g.OnMsg(def.MsgFrameRoomCreate, frameRoomDemo.onCreate)
        g.OnMsg(def.MsgFrameRoomJoin, frameRoomDemo.onJoin)
        g.OnMsg(def.MsgFrameRoomLeave, frameRoomDemo.onLeave)
        g.OnMsg(def.MsgFrameRoomInput, frameRoomDemo.onInput)
        g.OnMsg(def.MsgFrameRoomSnapshot, frameRoomDemo.onSnapshot)
        g.OnMsg(def.MsgFrameRoomInfo, frameRoomDemo.onInfo)
        roomMod.Frame().SetInputApplier(frameRoomDemo.applyInput)
    })
}
```

### 创建房间

```go
func (l *frameRoomDemoLogic) onCreate(c event.Ctx) error {
    var req def.FrameRoomCreateReq
    if err := c.BindMsg(&req); err != nil {
        l.replyErr(c, err)
        return nil
    }
    if req.RoomID == "" {
        req.RoomID = "demo-room"
    }
    // 外壳 API：EnsureRoom 建房间 + 注册 owner + 接管激活（与同步方式无关）
    if err := l.roomMod.EnsureRoom(req.RoomID); err != nil {
        l.replyErr(c, err)
        return nil
    }
    if _, _, err := l.roomMod.JoinRoom(c.ConnID(), req.RoomID, c.PlayerID()); err != nil {
        l.replyErr(c, err)
        return nil
    }
    l.g.Reply(c, def.FrameRoomReply{OK: true, RoomID: req.RoomID, NodeAddr: l.g.Addr()})
    return nil
}
```

### 加入房间（跨节点自动迁移）

```go
func (l *frameRoomDemoLogic) onJoin(c event.Ctx) error {
    var req def.FrameRoomJoinReq
    if err := c.BindMsg(&req); err != nil {
        l.g.Reply(c, def.FrameRoomJoinReply{Err: err.Error()})
        return nil
    }
    owner, switched, err := l.roomMod.JoinRoom(c.ConnID(), req.RoomID, c.PlayerID())
    if err != nil {
        l.g.Reply(c, def.FrameRoomJoinReply{Err: err.Error()})
        return nil
    }
    if switched {
        // 房主在其他节点 → 网关层迁移连接，客户端无感知
        l.g.Reply(c, def.FrameRoomJoinReply{Switched: true, OwnerAddr: owner, RoomID: req.RoomID})
        return nil
    }
    reply := def.FrameRoomJoinReply{RoomID: req.RoomID}
    if pack, recErr := l.roomMod.Frame().Recovery(req.RoomID, c.PlayerID()); recErr == nil && pack.RecoveredUntil > 0 {
        reply.TakeoverRecovery = pack
    }
    l.g.Reply(c, reply)
    return nil
}
```

### 帧输入（迁移后直达房主）

```go
func (l *frameRoomDemoLogic) onInput(c event.Ctx) error {
    var req def.FrameRoomInputReq
    if err := c.BindMsg(&req); err != nil {
        l.replyErr(c, err)
        return nil
    }
    input := engframe.Input{Frame: req.Frame, Payload: req.Payload}
    if err := l.roomMod.Frame().Input(req.RoomID, c.PlayerID(), input); err != nil {
        l.replyErr(c, err)
        return nil
    }
    info, _ := l.roomMod.Frame().Info(req.RoomID)
    msg := "input accepted"
    if info.Waiting {
        msg = fmt.Sprintf("input accepted, %s", info.WaitingReason)
    }
    l.g.Reply(c, def.FrameRoomReply{OK: true, RoomID: req.RoomID, Message: msg})
    return nil
}
```

### 离开与快照

```go
func (l *frameRoomDemoLogic) onLeave(c event.Ctx) error {
    var req def.FrameRoomLeaveReq
    if err := c.BindMsg(&req); err != nil {
        l.replyErr(c, err)
        return nil
    }
    if err := l.roomMod.Frame().Leave(req.RoomID, c.PlayerID()); err != nil {
        l.replyErr(c, err)
        return nil
    }
    l.g.Reply(c, def.FrameRoomReply{OK: true, RoomID: req.RoomID, Message: "left"})
    return nil
}

func (l *frameRoomDemoLogic) onSnapshot(c event.Ctx) error {
    var req def.FrameRoomSnapshotReq
    if err := c.BindMsg(&req); err != nil {
        l.replyErr(c, err)
        return nil
    }
    snap, err := l.roomMod.Frame().Snapshot(req.RoomID)
    if err != nil {
        l.replyErr(c, err)
        return nil
    }
    l.g.Reply(c, snap)
    return nil
}
```

## 要点总结

| 要点 | 说明 |
| --- | --- |
| 帧同步模块 | 帧循环、快照、断线重连、接管恢复均由 `engframe` 负责，业务无需手写 ticker |
| 推帧 | 帧同步推送由引擎按 `WithPushMessageID` 自动下发，业务无需手动 `PushToPlayer` |
| 连接迁移 | `roomMod.JoinRoom` 在房主位于其他节点时自动 `SwitchUpstream` 迁移 |
| 房主权威 | 只有房主节点跑帧循环，其余节点只转发输入 |
| 房间清理 | 房主宕机时房间随节点消失，重连玩家经 `Frame.Recovery` 恢复帧数据 |

### ⚠️ 两个"忘了配就静默失效"的项（实测踩过）

| 项 | 不配的后果 | 怎么配 |
|---|---|---|
| `PushMessageID`（默认 **0**） | `broadcast()` / `broadcastReliable()` / `broadcastReconnectLocked()` 都判 `pushMsgID == 0` **直接 return** ⇒ 帧在推进、客户端永远收不到帧推（现象像"Broadcast 失败"，实际是没配消息号） | `frame.WithPushMessageID(<业务帧推消息号>)`；**等待态帧推也依赖它** |
| `InputTimeoutTicks`（默认 90） | 兜底判据 `frame - LastFrame >= InputTimeoutTicks` 在"Join 时 LastFrame=0、推进目标恒为 1"下**永不成立** ⇒ 无人提交输入时**帧自锁不推进** | 让业务投喂输入，或把阈值调到 ≤ 每次推进的帧号增量（通常 1） |

> 回归用例在 `clover-server-engine/internal/domain/room/frame/room_test.go`（4 条，把两个根因各钉成断言）。

## 相关文档


**相关链接：**

- [进程与挂载](../concepts/app-game.md) - `app.Mount` 与 Game 生命周期

- [跨节点与 Master](../concepts/cluster.md) - 连接迁移与集群架构

- [推送机制](../concepts/push.md) - PushToPlayer 与数据推送


