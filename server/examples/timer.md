
定时任务统一走 `g.Timer`，任务函数为 `func()`。支持一次性延迟、定点执行、每日下一次执行、周期执行、Cron 表达式五种模式。`DailyAt` 每次只安排下一次目标时刻；需要每天持续执行请使用 Cron。

## 完整流程

### 基础用法

```go
package logic

import (
    "context"
    "time"

    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/foundation/logger"
)

func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        // 一次性：30 秒后执行一次
        g.Timer.After("demo-delay-30s", 30*time.Second, func() {
            logger.Infof("timer: 30 秒后执行一次")
        })

        // 定点：2026-08-01 14:30 执行一次（已过则立即执行）
        g.Timer.ByTime("once-at-14-30", g.Timer.Date(2026, time.August, 1, 14, 30, 0, 0), func() {
            logger.Infof("timer: 到达指定时间执行一次")
        })

        // 每天 14:30 执行
        g.Timer.DailyAt("demo-daily-14-30", 14, 30, 0, func() {
            logger.Infof("timer: 每天 14:30 执行一次")
        })

        // 周期：每 5 秒
        g.Timer.Every("demo-every-5s", 5*time.Second, func() {
            logger.Infof("timer: 每 5 秒执行一次")
        })

        // Cron：每天 12:00（各节点都执行）
        if _, err := g.Timer.Cron("demo-daily-12", "0 12 * * *", func() {
            logger.Infof("timer: 每天 12:00 执行一次")
        }); err != nil {
            logger.Errorf("cron register failed: %v", err)
        }
    })
}
```

### 全节点只执行一次（Redis 分布式锁）

Cron 任务在**所有 Game 节点**都会执行。若要求全集群只执行一次，可配合分布式锁（如 etcd lock 或 Redis SETNX）：

```go
g.Timer.Cron("demo-daily-12-singleton", "0 12 * * *", func() {
    // 引擎的 etcd 封装（internal/transport/etcd）只提供 Get/GetPrefix/Put/Delete/Register/Exists，
    // 没有分布式锁 API；需要锁时用 Raw() 取原始 clientv3 客户端，配合官方 concurrency 包。
    raw := g.GetEtcd().Raw()
    if raw == nil {
        return
    }
    sess, err := concurrency.NewSession(raw, concurrency.WithTTL(30))
    if err != nil {
        return
    }
    defer sess.Close()
    mu := concurrency.NewMutex(sess, "cron:demo-daily-12")
    if err := mu.TryLock(ctx); err != nil {
        return // 其他节点已持有锁，本节点跳过
    }
    defer mu.Unlock(ctx)
    logger.Infof("timer: 全节点只执行一次（本节点抢到锁）")
})
```

### 玩家维度定时器（TimerGroup）

引擎在断线时只会以**连接级 owner** 调用 `StopTimerGroup(owner)`——该 `owner` 取自登录回执的 `owner` 字段
（提取接线 `internal/app/bootstrap.go:456`，清理点 `internal/app/game.go:879`），并被同时当作 `AccountID`
使用（`internal/app/game.go:872-873`），**不是 `c.PlayerID()`**。因此：

```go
// 要随掉线自动清理的任务：scope 必须等于引擎传入的那个 owner
func (l *playerLogic) onMsgEnterGame(c event.Ctx) error {
    // playerScope(c) 由业务实现，返回「引擎断线时会传入的那个 owner」（取值不确定时先打一次日志确认）
    // OnTimer 接受绝对时刻
    l.g.Timer.TimerGroup(playerScope(c)).OnTimer("buff_tick", time.Now().Add(30*time.Second), func() {
        logger.Infof("timer: buff 结算")
    })
    return nil
}
```

> **注意：** 写成 `scope := "player:" + c.PlayerID()` 与 owner **不同名**，**不会**被自动清理
> （早期示例的「下线自动清理」说法是错的，已按源码更正）。离线也要继续推进的任务更不能用 owner 作 scope，见下节。

### 到期型任务：deadline 落数据（离线 / 跨重启）

行军到达、建造 / 征兵完成、挂机产出这类「到点必须发生」的事，**不能只挂内存定时器**：调度器是进程内的，
重启 / 崩溃 / 滚动发布即全部丢失；持久化也不能兜底（`DumpScope` 存的是**相对剩余**，`ImportScope` 也
**不补触发已过期**任务）。

```go
// 进游戏时重建：数据里存绝对 deadline，未到期按绝对时刻挂定时器（已过期则 OnTimer 立即触发 = 补算）
func (l *playerLogic) rebuildTodos(c event.Ctx) error {
    var v datadef.TodoData
    if err := l.g.LoadStruct(c, datadef.PlayerTodo, c.PlayerID(), &v); err != nil {
        logger.Errorf("timer: load todo failed player=%s err=%v", c.PlayerID(), err)
        return nil
    }
    group := l.g.Timer.TimerGroup("todo:" + c.PlayerID()) // 刻意不用 owner 作 scope
    for name, it := range v.Items {
        item := it
        group.OnTimer(name, time.Unix(item.Deadline, 0), func() {
            l.settleTodo(c.PlayerID(), item.Name) // 结算必须幂等
        })
    }
    return nil
}
```

> **完整模板：** 玩家维度（含幂等结算写法）与服务器维度（启动重建 + 周期兜底）见仓库
> [`clover-ai-skill/patterns/timer.md`](https://github.com/qw576483/clover-ai-skill/blob/main/patterns/timer.md) §「到期型任务」。

### 停止任务

```go
// 按名字停止单个定时器
g.Timer.StopTimer("demo-every-5s")

// 按作用域批量停止（等价于 TimerGroup(scope).Stop()）
g.Timer.StopTimerGroup(scope)
```

## API 速查

| 方法 | 说明 |
| --- | --- |
| `Timer.After(name, dur, fn)` | dur 后执行一次 |
| `Timer.ByTime(name, t, fn)` | 到达指定时间执行一次 |
| `Timer.DailyAt(name, h, m, s, fn)` | 每天指定时刻执行 |
| `Timer.Every(name, dur, fn)` | 每隔 dur 执行 |
| `Timer.Cron(name, expr, fn)` | Cron 表达式调度 |
| `Timer.TimerGroup(scope)` | 获取玩家/作用域维度的定时器组 |
| `Timer.StopTimer(name)` | 按名字停止 |
| `Timer.StopTimerGroup(scope)` | 按作用域批量停止 |

> **警告：** Cron 任务在所有 Game 节点都会触发。需要全集群只执行一次的场景，务必用 Redis 分布式锁（`SetNX`）。


## 下一步

1. [定时器概念](../concepts/timer.md) —— Timer API 与作用域机制
2. [连接生命周期](../concepts/heartbeat.md) —— 连接钩子与玩家维度清理

