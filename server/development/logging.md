# 日志指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的日志系统，包括日志级别、日志格式、日志配置和链路追踪。目标读者是想要了解如何记录和查看日志的开发者。

## 前置条件

- 了解 Go 语言基础
- 熟悉 Clover 引擎的项目结构
- 了解基本的日志概念

## 日志级别

| 级别 | 说明 |
|------|------|
| `debug` | 调试信息，开发时使用 |
| `info` | 一般信息，记录正常流程 |
| `warn` | 警告信息，不影响运行但需关注 |
| `error` | 错误信息，影响功能但不崩溃 |
| `panic` | 严重错误，panic 后 recover 并记录 |
| `fatal` | 致命错误，进程退出 |

## 用哪个包写日志

**业务日志统一使用 [`clover-server-engine/pkg/foundation/logger`](https://github.com/qw576483/clover-server-engine/blob/main/pkg/foundation/logger.md)。**

```go
import "github.com/qw576483/clover-server-engine/pkg/foundation/logger"
```

> **不要用标准库 `log.Printf`，也不要引入第三方日志库（logrus 等）。**
> 标准库和三方库会绕过引擎的日志级别、输出格式（json/console）、按天落盘与链路追踪字段，
> 导致日志散落、级别失控、采集端对不上字段。

门面函数（签名以 `pkg/foundation/logger/facade.go` 为准）：

| 分类 | 函数 |
|---|---|
| 非格式化 | `logger.Debug / Info / Warn / Error / Panic / Fatal(msg string, fields ...zap.Field)` |
| 格式化 | `logger.Debugf / Infof / Warnf / Errorf / Panicf / Fatalf(template string, args ...any)` |
| 结构化字段 | `logger.Field(key string, val any) zap.Field`、`logger.WithTrace(id string) zap.Field` |
| context 链路 | `logger.CtxDebug / CtxInfo / CtxWarn / CtxError(ctx, msg string, fields ...zap.Field)`、`logger.CtxWithFields(ctx, fields...)` |
| 生命周期 | `logger.Init(cfg *Config) error`、`logger.DefaultConfig()`、`logger.Sync()`、`logger.Get() *zap.Logger` |

> `Init` 由引擎启动流程（`pkg/app`）自动调用，**业务不需要也不应该自己调**。
>
> `logger.Field(...)` / `logger.WithTrace(...)` 的意义：**业务代码无需 import `go.uber.org/zap`**，
> 字段构造走引擎门面即可，避免业务为了一条日志往 `go.mod` 里加三方依赖。

### ⚠️ 未初始化时不会报错，日志会被静默丢弃

`logger` 门面在**未被 `Init` 初始化**时返回 zap 的 NopLogger（`safeLogger()`，见 `pkg/foundation/logger/zap.go`）：

- 所有 `logger.Info / Error / ...` **既不输出、也不报错**（静默丢弃）；
- `logger.Fatal / Fatalf` 最终会调用 `os.Exit(1)`；未初始化时日志本身静默，但进程仍会退出。

因此：

- 在**引擎进程内**（`app.Run` 已调用 `logger.Init`）随手 `logger.*` 都安全；
- 在**独立工具 / `package main`**（自己没调 `Init`）里，要么先显式 `logger.Init(logger.DefaultConfig())`，
  要么就直接用标准库 `log`，别指望门面会输出；
- **启动阶段**（`logger.Init` 之前）的失败，如需确保错误可见，可用标准库 `log.Printf` + `os.Exit(1)`；此时门面是 Nop，`Fatal` 会退出但不会输出日志。

## 日志输出

```go
import "github.com/qw576483/clover-server-engine/pkg/foundation/logger"

// 基本日志
logger.Info("服务器启动")

// 格式化日志
logger.Infof("玩家 %d 登录成功", playerID)

// 错误日志
logger.Errorf("数据库连接失败: %v", err)

// 调试日志
logger.Infof("收到消息: msgID=%d requestID=%d", msgID, requestID)

// 结构化字段（不需要 import zap）
logger.Info("房间创建成功",
    logger.Field("room_id", roomID),
    logger.Field("player_id", playerID))

// 带链路追踪：trace_id 字段名由 logger.WithTrace 统一填充
logger.Info("处理登录请求", logger.WithTrace(c.TraceID()))
```

## 日志格式

由 `log.format` 决定输出格式：

- `json`：结构化 JSON（默认，生产环境），便于采集与检索；
- `console`：可读文本（开发环境）。

`log.stdout: true`（默认）时同步打印到控制台，便于本地调试；
`log.dir` 非空时按天落盘到 `{dir}/{YYYY-MM-DD}-{service}.log`。

## 日志配置

日志配置位于 `server/configs/all/*.yaml` 的 `log` 段，字段与 `pkg/foundation/logger.Config` 一一对应：

```yaml
# configs/all/server.yaml
log:
  level: "info"        # debug / info / warn / error / panic / fatal
  format: "json"       # json（生产）/ console（开发）
  dir: "./logs"        # 日志根目录；留空则只输出到 stdout
  stdout: true         # 是否同步打印到控制台
  service: "clover-game"   # 服务名，dir 模式下作为文件名后缀
  env: "dev"           # 运行环境：dev / test / prod
```

## 性能日志

```go
start := time.Now()
// ... 业务逻辑 ...
logger.Infof("处理耗时: %v", time.Since(start))
```

需要按字段聚合分析时，用结构化写法：

```go
logger.Info("handler completed",
    logger.WithTrace(c.TraceID()),
    logger.Field("player_id", c.PlayerID()),
    logger.Field("msg_id", c.MsgID()),
    logger.Field("duration_ms", time.Since(start).Milliseconds()))
```

## 链路追踪

追踪字段名由 `logger.GetTraceKey()` 决定，默认值是 `logger.DefaultTraceKey`（`"trace_id"`）。

**方式一：单条日志显式携带**

```go
logger.Info("处理登录请求", logger.WithTrace(c.TraceID()))
```

**方式二：绑定到 context，同链路后续日志自动携带**

```go
ctx := logger.CtxWithFields(c.Context(), logger.WithTrace(c.TraceID()))
...
logger.CtxInfo(ctx, "进入战斗")            // 自动带上 trace_id
logger.CtxError(ctx, "战斗结算失败", logger.Field("error", err))
```

## 相关文档

- [错误处理](error-handling.md) — 错误分类与「每条非预期分支都要打日志」的约定
- [日志采集与存储](../operations/logging.md) — 运维侧：采集、存储、告警
