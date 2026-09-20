# 协议设计指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的协议设计方法，包括消息号分配、协议格式和序列化方式。目标读者是想要设计网络协议的开发者。

## 前置条件

- 了解网络协议基础
- 熟悉 Clover 引擎的项目结构
- 了解序列化概念

## 消息号分配

消息号按段隔离，避免冲突：

| 范围 | 归属 | 说明 |
|------|------|------|
| 1 - 10000 | 引擎 | `EMsgLogin`、`EMsgResumeSession` 等（1 号原为 `EMsgSignup`，已作废保留；错误回包 `EMsgError=0xFFFFFFFF` 不属于任何号段） |
| 1000101+ | 业务 C2S | `MsgGetPlayerList`、`MsgCreatePlayer` 等 |
| 无 | 业务回包 | **不占消息号**：按 requestID 配对，回包帧 msgID 恒为 0；只定义 `<请求名>Reply` 结构体 |
| 3002001+ | 业务推送 | `PushFrameRoomSync`、`PushDemoBroadcast` 等 |

> **注意：** 业务消息号约定从 1000101 起，回包**不占消息号**（按 requestID 配对、msgID 恒为 0），推送从 3002001 起。消息号定义在业务 `def` 包中。

## 消息定义

```go
// def/msg.go
package def

const (
    // 业务消息号（Msg 前缀，从 1000101 起）
    MsgGetPlayerList = 1000101
    MsgCreatePlayer  = 1000102
    MsgEnterGame     = 1000103
)

// def/reply.go
package def

// 回包**不占消息号**：引擎按 requestID 配对（回包帧 msgID 恒为 0），
// 所以这里只定义回复体结构，命名约定为「<请求名>Reply」。

// def/push.go
package def

const (
    // 推送消息号（业务推送从 3002001 起）
    PushFrameRoomSync = 3002001
    PushDemoBroadcast = 3003001
)

// def/player.go
package def

type GetPlayerListRequest struct {
    ServerID uint32 `json:"server_id"`
}

type GetPlayerListReply struct {
    PlayerIds []string `json:"player_ids"`
}
```

## 请求-回包配对

客户端发送请求，服务端通过 `g.Reply` 回复：

```go
// 客户端发送请求
// Game.Net.Call<GetPlayerListReply>(MsgDef.MsgGetPlayerList, &GetPlayerListRequest{
//     ServerID: 1,
// })

// 服务端处理
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        // 注意：登录（EMsgLogin）由引擎内置处理，业务**不要**自己注册登录 handler；
        // 且 g.OnMsg 传 <= proto.InternalMsgMax(10000) 的消息号会直接 panic（引擎保留段）。
        g.OnMsg(def.MsgGetPlayerList, func(c event.Ctx) error {
            var req def.GetPlayerListRequest
            if err := c.BindMsg(&req); err != nil {
                return err
            }
            // 处理业务...
            g.Reply(c, &def.GetPlayerListReply{PlayerIds: []string{"p_1"}})
            return nil
        })
    })
}
```

## 推送

服务端主动推送给客户端：

```go
// 向指定玩家推送
g.PushToPlayer(playerID, def.PushDemoBroadcast, &PlayerEnter{ID: playerID})

// 场景广播
g.PushToScene(scene, def.PushFrameRoomSync, &FrameData{Frame: frame})

// 全服广播
g.PushToAll(def.PushSystemNotice, &SystemNotice{Msg: "维护公告"})
```

## 错误回包

handler 返回错误时，引擎自动回复客户端错误码（`EMsgError`）：

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgSomeOperation, func(c event.Ctx) error {
            // 处理失败时
            return def.ErrSomethingWrong // 自动回复客户端错误码
        })
    })
}
```

## 网络帧格式

TCP 流：

```
[1B type][4B length][4B requestID][4B msgID][body]
```

> 首字节 `type` 是 **TCP** 传输层帧类型（0=Data / 1=…，见 `internal/transport/net/tcp/codec.go`）。
> 少了它会把 `length` 当成 type、整帧错位——历史版本的本页就漏了该字节。
> **QUIC 流的分帧不同**：`[4B 大端长度][客户端帧]`，**没有 type 字节**（见客户端
> `Runtime/Network/Quic/QuicStreamFraming.cs` 与服务端 `internal/transport/net/quic/conn.go`）。

裸 UDP：

```
[0x55][4B requestID][4B msgID][body]
```

- `requestID` == 0 表示推送
- TCP 流外加 `[1B type][4B length]`、QUIC 流外加 `[4B length]`（**无 type**）防粘包
- 裸 UDP 首字节 0x55 魔数
