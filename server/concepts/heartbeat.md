# 心跳机制

## 核心概念

客户端定期发送心跳包，服务端检测连接是否存活。心跳间隔在 `server.yaml` 的 `logic` 配置段中设置：

```yaml
server_type: "all"
gateway:
  listen_ws: "127.0.0.1:8001"
  listen_tcp: "127.0.0.1:8002"
  listen_udp: "127.0.0.1:8003"
logic:
  listen_addr: "127.0.0.1:8011"
  heartbeat: 30s      # 网关 ↔ 逻辑服心跳间隔（默认 30s）
  frame_timeout: 30s  # 单帧处理上限
```

心跳由引擎传输层（网关 ↔ 逻辑服之间）自动维护，业务无需手动实现心跳 handler。

## 业务级心跳

如需业务级心跳（如检测玩家逻辑存活），可自行定义消息号（>= 1000101）并注册 handler：

```go
package logic

import (
    "time"
    "clover-server-engine/pkg/app"
    "clover-server-engine/pkg/transport/event"
    "your-game/def"
)

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnMsg(def.MsgHeartbeat, func(c event.Ctx) error {
            // 更新玩家最后心跳时间（示例：写入连接级 KV）
            c.SetConnValue("last_heartbeat", time.Now().Unix())
            // 回复心跳
            g.Reply(c, &HeartbeatReply{Timestamp: time.Now().Unix()})
            return nil
        })
    })
}
```

## 心跳检测

心跳超时后，网关会自动断开连接并触发断线事件。业务可监听 `app/types.ConnDisconnectEvent` 做清理。不要自行实现 `HeartbeatChecker`，引擎传输层已内置超时检测。

## 配置说明

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `logic.heartbeat` | duration | `30s` | 网关 ↔ 逻辑服心跳间隔 |
| `logic.frame_timeout` | duration | `30s` | 单帧处理上限 |
| `logic.reconnect_grace` | duration | `30s` | 重连宽限 |

## 常见问题

### 心跳超时断开

**症状**：连接频繁断开

**原因**：心跳超时时间设置过短或网络延迟

**解决**：
1. 调整 `logic.heartbeat` 配置
2. 检查网络延迟
3. 确认网关与逻辑服在低延迟网络下
