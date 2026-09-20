# 进程生命周期

## 启动

`app.Run(configPath, bootstrap...)` 从目录或文件加载配置，按 `server_type` 启动对应进程，并阻塞到退出信号。业务挂载推荐在 `init` 中调用 `app.Mount`；也可把 `func(*app.Game) error` 作为 `Run` 的可选 bootstrap。初始化数据存储、网络和共享 `Timer` 由引擎负责。

```go
package main

import (
    "github.com/qw576483/clover-server-engine/pkg/app"
    "github.com/qw576483/clover-server-engine/pkg/foundation/logger"
    _ "your-game/server/game/logic"
)

func main() {
    if err := app.Run("configs/all"); err != nil {
        logger.Fatal("启动失败", logger.Field("err", err))
    }
}
```

需要提前加载并注入配置时使用 `app.LoadConfig` + `app.RunWithConfig`；嵌入式或测试场景使用 `app.RunGame(ctx, cfg)`，其中 `ctx` 可取消。

## Mount 与 Ready

引擎执行已登记的 mount 后开始监听并处理请求。当前公开 API 没有无参数 `Ready()` 回调；不要在文档或业务中假设存在该回调。需要注册 admin 探针时，在 mount 中调用 `g.OnAdminHTTP(pattern, http.HandlerFunc)`，引擎会统一挂载到 admin HTTP 服务。

```go
func init() {
    app.Mount(app.RoleGame, func(g *app.Game) {
        g.OnAdminHTTP("/ready", func(w http.ResponseWriter, r *http.Request) {
            w.WriteHeader(http.StatusOK)
            _, _ = w.Write([]byte("ok"))
        })
    })
}
```

## Handler 生命周期

每个消息由框架创建 `event.Ctx`，完成解信封和连接/玩家注入后调用 `event.Handler`。handler 通过 `c.BindMsg` 读取请求，通过 `g.Reply` 或推送 API 回包；返回错误时由框架执行错误回包。`LoadStruct` 修改会在 handler 返回后由引擎自动提交，Ctx 随后回收。

## 关闭

收到退出信号后，`app.Run` 负责停止服务并释放引擎资源。业务定时器应通过 `g.Timer` 注册，并在对应 scope 使用 `StopTimer` / `StopTimerGroup`；不要调用不存在的 `RunWithContext`，需要可取消启动请使用 `RunGame(ctx, cfg)`。数据库和 NATS 连接由配置与引擎装配管理，业务无需在伪造的 Ready 回调中重复连接或关闭。
