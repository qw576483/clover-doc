# 推送模式

## 核心概念

服务端主动推送不需要客户端先发请求。业务通过 `app.Game` 的公开推送 API 指定目标：

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgMove, func(c event.Ctx) error {
            // 向指定玩家发送 JSON 消息
            return g.PushToPlayer(c.PlayerID(), def.PushPlayerMoved, PlayerMoved{ID: c.PlayerID()})
        })
    })
}
```

- `g.PushToPlayer(playerID, msgID, value, opts...)`：指定玩家
- `g.PushToScene(scene, msgID, value, opts...)`：场景广播
- `g.PushToAll(msgID, value, opts...)`：全服广播
- `PushToPlayerRaw`、`PushToSceneRaw`、`PushToAllRaw`：自定义编码的字节推送

这些方法默认可靠送达，可按 `proto.DeliveryMode` 选项调整。不要使用旧式 `c.Push` 或 `room.Broadcast` 示例。

## 消息号

业务推送消息号从约定区间分配（当前 demo 使用 `3002001` 起），引擎推送号由 `pkg/shared/proto` 定义，例如 `EPushPlayerFullSync`、`EPushAlert`、`EPushDataSync`、`EPushRoomTakeover`。消息号应集中放在业务 `def/push.go`，不得散落在 handler 中。

## 客户端接收

客户端按客户端 SDK 的 `MsgDef`/网络模块注册推送监听；服务端推送帧的 `requestID` 为 0，客户端不发送对应回包。

## 数据同步

数据 schema 的自动变更推送可通过 `event.Ctx.SetNoPush()` 关闭。需要明确的业务广播时，使用 `PushToScene` 或 `PushToAll`；推送目标不存在时检查返回的 error。

```go
func broadcast(g *app.Game, scene proto.ESceneBroadcaster, msg any) error {
    return g.PushToScene(scene, def.PushFrameRoomSync, msg)
}
```
