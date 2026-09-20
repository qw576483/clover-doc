
> **注意：** 以下示例中 `g.OnConnect`、`g.OnDisconnect` 是引擎内部 API（`internal/app`），
> 业务代码**不可直接调用**。此处仅展示引擎心跳与连接管理的实现逻辑供参考。

引擎内置了心跳检测与会话恢复，**业务不需要实现心跳消息**。你只需订阅连接钩子（`OnConnect` / `OnDisconnect` 等）处理上线/下线逻辑。

## 完整流程

### 连接钩子

```go game/logic/hook.go
package logic

import (
    "clover-server-engine/pkg/app"
)

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnConnect(func(owner string) {
            // 首次连接（登录成功）
            // - 加载玩家数据
            // - 广播上线事件
        })

        g.OnReconnect(func(owner string) {
            // 断线后重连：恢复场景推送、刷新玩家状态
        })

        g.OnSoftDisconnect(func(owner string) {
            // 软掉线（DisconnectGrace 宽限期内）：可等待重连
        })

        g.OnHardDisconnect(func(owner string) {
            // 硬掉线（宽限结束）：清理玩家现场
        })

        g.OnKick(func(connID, owner string) {
            // 多端互踢下线
        })
    })
}
```

> **注意：** `OnDisconnect` 内部会自动执行 `StopTimerGroup(owner)`；如需在硬掉线时做额外清理，用 `OnHardDisconnect`。


### 上线加载数据

```go
g.OnConnect(func(owner string) {
    // 用连接上下文触发一次数据预热（LoadStruct 会建立 identity map）
    // 注意：钩子回调无 *event.Ctx，只做轻量初始化
    // 重量级加载放在首个业务消息 handler 中
})
```

### 心跳配置

心跳由引擎内置，业务只需在配置中按需调整（`configs/all/server.yaml`）：

```yaml configs/all/server.yaml
gateway:
  reconnect_grace: 30s   # 重连宽限（保留 owner 记录用于标记重连）；引擎默认 0=关闭，此处为业务示例值
  disconnect_grace: 10s  # 断线宽限（延迟触发 OnDisconnect）；引擎默认 0=立即触发，此处为业务示例值

logic:
  heartbeat: 30s         # 网关↔逻辑服心跳间隔
  reconnect_grace: 30s   # 重连宽限：断线后保留连接数据等待重连
```

> **提示：** 客户端只需在间隔内发任意数据即可维持连接（TCP）或依赖 WS Ping。超过心跳超时，引擎判定掉线并走宽限流程。


### 会话恢复（WS）

WebSocket 断线重连后发送 `EMsgResumeSession`（消息号 3）：

```json
{
  "player_id": "p_10001",
  "session_token": "上次全量同步下发的 token"
}
```

| 结果 | 说明 |
| --- | --- |
| token 匹配 | 回 `ResumeSessionReply{success:true, owner:...}`，数据未变免全量同步 |
| token 不匹配 | `{success:false}` + 踢连接 |

> ⚠️ **回包必须带 `owner`（归属账号），不是可选信息。** 网关只在「上游回包能被
> `auth.ExtractOwnerID` 解出非空 `owner`」时才把连接绑回 owner；而恢复会话走的是**一条新连接**
> （它没有任何登录动作），不在此处补上 `owner` 就会导致该连接过不了登录门禁 ——
> 后续**每一条**业务消息都被拒为 `401 unauthenticated`，表现为
> 「ResumeSession 成功，但连接立刻失能」。引擎已内建该行为
> （`ResumeSessionHandler` 会按 playerID 反查账号补上 `owner`）。

## 连接生命周期

```text
客户端连接 → OnConnect → 游戏中 → 超时/断网
                                  ├─ OnSoftDisconnect（宽限期内）
                                  │    ├─ 重连成功 → OnReconnect
                                  │    └─ 宽限结束 → OnHardDisconnect
                                  └─ 多端登录 → OnKick
```

## 要点总结

| 钩子 | 触发时机 | 典型用途 |
| --- | --- | --- |
| `OnConnect` | 首次连接（登录成功） | 加载数据、广播上线 |
| `OnReconnect` | 断线后重连 | 恢复场景、刷新状态 |
| `OnSoftDisconnect` | 断线宽限期内 | 等待重连、保留现场 |
| `OnHardDisconnect` | 宽限结束 | 清理玩家数据 |
| `OnKick` | 多端互踢 | 通知被踢、清理旧连接 |

## 相关文档


**相关链接：**

- [心跳概念](../concepts/heartbeat.md) - 心跳机制与宽限流程详解

- [登录与建角](login.md) - 引擎内置登录/注册/会话恢复


