# 定时器 API

Clover 服务端通过 `g.Timer` 提供进程内共享定时器。底层实现位于 [`clover-server-engine/pkg/runtime/timer`](https://github.com/qw576483/clover-server-engine/blob/main/pkg/runtime/timer.md)，由单个调度 goroutine 管理任务；任务函数在独立 goroutine 中执行，并由引擎安全封装，单个任务的 panic 不会中断调度器。

## 访问入口与生命周期

在挂载函数中通过 `*app.Game` 的 `g.Timer` 使用定时器：

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    g.Timer.After("demo-delay", 3*time.Second, func() {
        logger.Infof("3 秒后执行")
    })
})
```

`g.Timer` 的生命周期由 `Game` 统一管理。应用停止时调用 `Close`，会取消全部任务并停止调度器；关闭后注册的任务返回非活跃句柄。

## API 速查

| API | 行为 |
| --- | --- |
| `g.Timer.After(name, delay, task)` | 延迟 `delay` 后执行一次；具名任务同名注册会取消旧任务 |
| `g.Timer.Every(name, interval, task)` | 首次在 `interval` 后执行，之后按固定间隔执行；`interval <= 0` 会被忽略并返回非活跃句柄 |
| `g.Timer.ByTime(name, target, task)` | 在绝对时刻执行一次；目标已过去时立即执行，此时返回 `nil` |
| `g.Timer.DailyAt(name, hour, minute, second, task)` | 每天指定时刻执行（实际通过下一次目标时刻的一次性任务实现） |
| `g.Timer.Cron(name, spec, task)` | 按 5 字段 crontab 表达式执行（分 时 日 月 周），返回 `(timer.Timer, error)` |
| `g.Timer.StopTimer(name)` | 按名字取消任务，返回是否找到该名字 |
| `g.Timer.TimerGroup(scope)` | 获取带统一 `scope` 的 `*timer.Group` |
| `g.Timer.StopTimerGroup(scope)` | 取消该 `scope` 下全部任务 |

任务函数类型为 `timer.Task`，即 `func()`。需要句柄时保存返回值并调用 `Stop`；可用 `Active` 判断任务是否仍在调度，`Name` 获取注册名。

底层调度器也可通过 `g.Timer.Scheduler()` 获取。只有需要独立调度域（例如单元测试或独立子系统）时，才直接使用 `timer.NewScheduler`；可选配置包括 `timer.WithGranularity`（默认 100ms）和 `timer.WithLocation`（默认系统本地时区）。

## 基础用法

```go
app.Mount(app.RoleGame, func(g *app.Game) {
    // 一次性延迟任务
    g.Timer.After("buff-expire", 30*time.Second, func() {
        logger.Infof("buff 到期")
    })

    // 周期任务；保存句柄可主动停止
    heartbeat := g.Timer.Every("heartbeat", 5*time.Second, func() {
        logger.Infof("心跳")
    })
    _ = heartbeat

    // 绝对时间：用引擎时区构造时间
    target := g.Timer.Date(2026, time.August, 1, 14, 30, 0, 0)
    g.Timer.ByTime("daily-event", target, func() {
        logger.Infof("到达指定时间")
    })

    // Cron：5 字段“分 时 日 月 周”
    if _, err := g.Timer.Cron("daily-report", "0 12 * * *", func() {
        logger.Infof("每天 12:00 执行")
    }); err != nil {
        logger.Errorf("cron register failed: %v", err)
    }
})
```

`Cron` 表达式支持 `*`、单值、范围、逗号列表及步长（如 `*/5`、`1-10/2`）；周字段接受 `0-7`，其中 `0` 和 `7` 均表示周日。Cron 最小粒度为分钟，表达式解析失败会返回错误。

## 作用域与清理

需要随某个生命周期（连接 / 场景等）成批清理的任务，用 `TimerGroup(scope)` 分组：

```go
// 在 handler 中按需创建 TimerGroup
func (l *playerLogic) onMsgEnterGame(c event.Ctx) error {
    // scope 用「引擎断线时会传入的那个 owner」
    group := l.g.Timer.TimerGroup(playerScope(c))
    group.After("buff-expire", 30*time.Second, func() {
        logger.Infof("buff 到期")
    })
    group.Every("owner-check", 10*time.Second, func() {
        logger.Infof("检查在线状态")
    })
    return nil
}
```

连接断开时，引擎会以**连接级 owner** 调用 `StopTimerGroup(owner)`（`internal/app/game.go:818`）——
该 `owner` 取自登录回执的 `owner` 字段（`internal/app/bootstrap.go:431-432`），并被同时当作 `AccountID`
使用（`internal/app/game.go:901`），**不是角色 ID（`c.PlayerID()`）**。

由此得出两条互补规则：

| 任务的诉求 | scope 怎么取 |
|---|---|
| **要随掉线自动清理**（buff 结算、临时状态、在线巡检） | scope **必须等于引擎传入的那个 owner**（不确定取值时打一次日志确认，最省事的办法是自己订阅断线钩子显式 `StopTimerGroup` 自己的 scope） |
| **离线也要继续推进**（行军到达、建造 / 征兵完成、挂机产出、拍卖截止） | scope **故意不用 owner**，加前缀即可（如 `"todo:"+playerID`），并按「到期型任务」一节写（见下） |

> **注意：** `"player:" + c.PlayerID()` 这类 scope 与引擎传入的 owner **不同名**，因此**不会**被自动清理。
> 早期文档与示例把它写成「下线自动清理」是错的，本页已按源码更正。

`*timer.Group` 提供 `After(name, delay, task)`、`Every(name, interval, task)`、`OnTimer(name, when, task)` 和 `Cron(name, spec, task)`。
其中 `OnTimer` 的 `when` 是**绝对 `time.Time`**（不是持续时长），**已过去则立即执行**（`pkg/runtime/timer/timer.go:561-569`）。

具名任务也可以单独停止：

```go
g.Timer.StopTimer("heartbeat")
g.Timer.StopTimerGroup(scope)
```

同一名字再次注册具有覆盖/重启语义。使用 scope 后，同名任务在不同 scope 之间不会互相取消。

## 时区与日期

`g.Timer.Location()` 返回引擎当前时区；`g.Timer.Date(...)` 使用该时区构造时间。`g.Timer.ParseDate` 支持 `YYYY-MM-DD`、`YYYY-MM-DD HH:mm:ss` 和 ISO 风格 `YYYY-MM-DDTHH:mm:ss`。Cron 的时间匹配也使用调度器配置的时区。

## 持久化与迁移（底层 Scheduler）

> **`g.Timer` 本身不持久化。** 引擎装配的共享调度器只设置了时区、**没有注入 `PersistBackend`**
> （`internal/app/mount.go:123`），所以经 `g.Timer.Scheduler()` 调用 `PersistScope` / `RestoreScope` /
> `ClearPersist` 一律返回 `timer.ErrNoBackend`。要用持久化必须自建
> `timer.NewScheduler(timer.WithPersistence(backend))`。

直接使用 `timer.Scheduler` 时，可通过 `timer.WithPersistence(backend)` 注入实现了 `PersistBackend` 的存储后端，再调用 `PersistScope`、`RestoreScope` 和 `ClearPersist`。未配置后端时这些方法返回 `timer.ErrNoBackend`。

`DumpScope`/`ImportScope` 用于跨节点迁移具名任务。恢复前必须重新注册对应的 Task（`AfterName`、`EveryName` 或 `CronName`），否则无法重建；匿名任务不会被导出。持久化和迁移均只保存定时状态，不会跨进程自动执行任务。

**语义边界（重要）**：

- `DumpScope` 导出的 `RemainingMs` 是**相对剩余时间**（按导出时刻换算），**不是绝对到期时刻**（`pkg/runtime/timer/timer.go:644-651`）；
- `ImportScope` 按剩余量重新入堆，**不补触发已过期的任务**（`timer.go:732-744`）——
  停机 2 小时后恢复，任务会从恢复时刻**顺延**再等一遍剩余时间，而不是补算；
- 因此持久化 / 迁移**不能替代业务侧的绝对 deadline**。

## 到期型任务（延期结算 / 离线 / 跨重启）

适用于行军到达、建造 / 征兵完成、挂机产出、拍卖截止、邮件过期、CD 结束等「到点必须发生」的事。

**定性：定时器是加速器，不是真相源。** 调度器是进程内组件，重启 / 崩溃 / 滚动发布即全部丢失，因此：

1. **deadline 落数据**：数据里存**绝对时间**（Unix 秒或 RFC3339）；
2. **重建**：加载数据时把未到期的重新挂成 `OnTimer(name, deadline, …)`
   （已过期时 `OnTimer` 会立即触发，正好用来补算）；
3. **幂等结算**：结果只由数据 + deadline 决定，避免「定时器触发 / 启动扫描 / 登录补算」三条路径重复结算。

重建时机按 owner 维度选择，**不需要全表扫描**：

| owner | 重建时机 | 加载方式 |
| --- | --- | --- |
| 玩家 | 进游戏 handler（此处有 `event.Ctx`） | `g.LoadStruct(c, schema, c.PlayerID(), &v)` |
| 服务器 | 进程启动 `app.Mount` 内 + `Every` 周期兜底 | `g.Data().LoadJSON(ctx, data.Key{…}, &v)` |
| 场景对象 | 对象创建 / 加载时 | 对象自身加载路径 |

> **提示：** 定时器回调是 `func()`，**没有 `event.Ctx`**，回调内不能用 `g.LoadStruct`，要改用 `g.Data()` 的
> `Load / Save / LoadJSON / SaveJSON`（可直接写，但**不会**自动做字段级增量广播；需要同步给客户端时显式
> `g.PushToPlayer`）。

> **完整可照抄模板：** 仓库 [`clover-tools/ai-skill/patterns/timer.md`](https://github.com/qw576483/clover-tools/blob/main/ai-skill/patterns/timer.md) §「到期型任务」（玩家维度 datadef + 重建 +
> 幂等结算，服务器维度启动重建骨架）。

## 注意事项

- 调度器是进程内组件；Cron 在每个 Game 节点分别触发。全集群只执行一次时，任务体内需使用 Redis 等分布式锁协调。
- 定时任务回调在独立 goroutine 执行，访问共享业务数据时必须遵守并发安全约束。
- 调度精度受 `WithGranularity`、系统调度和负载影响，不应用于硬实时场景。
- 作用域任务应在生命周期结束时停止；长期存活 scope 反复注册具名任务会增加资源占用。
- **离线也要继续推进的任务，scope 不要用 owner**（否则掉线时会被一并清理），并按「到期型任务」以数据 deadline 为准。
