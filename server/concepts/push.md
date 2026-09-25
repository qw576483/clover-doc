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

## 路由与索引

推送的目标参数会先经网关的索引定位到连接：网关按 `p:<target>` → `a:<target>` 顺序查找，**两个前缀都未命中时既不推也不报错**（静默丢弃）。

| 目标参数 | 索引 key | 谁来建立 |
|---|---|---|
| 角色 ID | `p:<角色ID>` | 逻辑服 `Ctx.SetPlayerID` → `GWControlBind` → 网关 `addExtraID`；索引**以连接为粒度**，宽限期重连后由引擎为新连接补发 |
| 账号 | `a:<账号>` | 网关在每条登录回包提取 owner 时建立（每次登录都重建） |

- `PushToPlayer(playerID, …)`、`EPushPlayerFullSync`、数据自动同步都走 `p:<角色ID>` 这条索引。
- 需要「跨重连一定可达」时，可让目标走账号维度（`a:` 每次登录重建）；否则必须确认 `p:` 索引已建立。

## 常见问题

**Q：`PushToPlayer` 返回 `nil`、回包也正常，客户端却收不到推送？**

网关找不到目标索引时静默丢弃（不推、不打错误日志）。排查顺序：

1. 网关日志里 `bound conn <connID> -> <owner>`（登录绑定）与 `added extra idIndex key p:<角色ID> for conn <connID>`（角色索引）是否成对出现；
2. 只有 `bound conn` 而**没有** `added extra idIndex` 的会话，此后每条按角色 ID 寻址的推送都会丢——包括业务推送、引擎自动实体同步与 `EPushPlayerFullSync`；
3. 目标参数与索引前缀不对应（例如拿账号当 `PushToPlayer` 的 target）同样静默丢弃。

## 数据同步

数据 schema 的自动变更推送可通过 `event.Ctx.SetNoPush()` 关闭。需要明确的业务广播时，使用 `PushToScene` 或 `PushToAll`；推送目标不存在时检查返回的 error。

```go
func broadcast(g *app.Game, scene proto.ESceneBroadcaster, msg any) error {
    return g.PushToScene(scene, def.PushFrameRoomSync, msg)
}
```
