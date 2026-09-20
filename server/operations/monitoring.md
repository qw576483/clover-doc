## 这篇文档讲什么？

如何监控 Clover Engine 的运行状态，包括指标采集、健康检查、告警与性能剖析。本文档适用于运维人员建立监控体系。

## 前置条件

- 了解 Prometheus 监控体系
- 熟悉 Grafana 可视化工具
- 了解 Clover 的架构和关键指标

## 指标埋点

引擎在 `pkg/foundation/metrics` 提供 Prometheus 兼容的指标能力：

```go 指标埋点示例
import "clover-server-engine/pkg/foundation/metrics"

var loginTotal = metrics.CounterOf("handler.login.total")
var loginLatency = metrics.HistogramOf("handler.login.latency", []float64{1, 5, 10, 50, 100, 500})

func queryUser(id int64) (*User, error) {
    start := time.Now()
    defer func() { loginLatency.Observe(time.Since(start).Seconds()) }()
    loginTotal.Inc()
    return db.Get(id)
}
```

| 类型 | 构造方式 | 含义 |
|------|----------|------|
| `Counter` | `metrics.CounterOf(name, labels...)` | 单调递增计数 |
| `Gauge` | `metrics.GaugeOf(name, labels...)` | 可增可减的瞬时值 |
| `Histogram` | `metrics.HistogramOf(name, buckets, labels...)` | 耗时/大小分布，可算 P95/P99 |

> **警告：** 指标名与 label 值必须是有限常量集合。切勿拼接 playerID / connID / traceID 等高基数字段，否则会导致时间序列爆炸。

## HTTP 指标端点

服务默认暴露 `/metrics`（`metrics.Handler()` 注册）：

```text 指标端点
GET http://127.0.0.1:8041/metrics
```

Prometheus 采集配置：

```yaml Prometheus 配置
scrape_configs:
  - job_name: 'clover'
    static_configs:
      - targets: ['localhost:8041']   # admin.listen_addr，/metrics 挂在这里
```

### 引擎自动采集：运行时与进程指标

每次抓取都会先刷新下面两组指标（`pkg/foundation/metrics/runtime.go`），**业务无需埋点**：

| 指标 | 类型 | 说明 |
|------|------|------|
| `go_*`（goroutine / OS 线程 / GC / 堆内存…） | Gauge | 命名遵循 Prometheus 官方 `go_*` 约定，现成 Grafana Go Runtime 看板可直接复用 |
| `process_start_time_seconds` / `process_uptime_seconds` | Gauge | 进程启动时间与已运行秒数 |
| `process_cpu_seconds_total` | Gauge | 进程累计消耗的 CPU 秒数（用户态 + 内核态） |
| `process_cpu_ratio` | Gauge | 相对上一次抓取的使用率，**1.0 = 跑满一个核**（4 核满载约 4.0；换算成百分比要除以 `GOMAXPROCS`） |

> **注意：**   平台不支持进程 CPU 采集时**不导出**这两项（`proc_other.go`）——宁可不导出，也不给一条恒为 0 的假曲线。
> `process_cpu_ratio` **首次抓取没有值**（累计量必须两次采样才能求速率），第二次起才有。

> **警告：**   抓取路径上的 `runtime.ReadMemStats` 是 **STW** 操作（耗时随堆大小增长），
> 因此 `/metrics` 适合 15s~60s 抓一次，**不要高频抓取**，更不要把采集逻辑放进游戏主循环。

## 健康检查

引擎有两个不同的探测面，**别混用**：

| 端点 | 归属 | 说明 |
|------|------|------|
| `GET /ping` | admin（`admin.listen_addr`，示例 `127.0.0.1:8041`，需配置才启用） | admin 自身存活 + 列出已注册路由 |
| `GET /healthz` | **逻辑服**（`logic.http_listen`，示例 `127.0.0.1:8012`，需配置才启用） | 逻辑服存活探针 |
| `GET /ready` | 逻辑服（同上） | 就绪探针 |

> ⚠️ admin 端口上**没有** `/health`，也没有依赖明细 JSON（MySQL/Redis/etcd/NATS 的逐项状态），
> 引擎当前不提供这种聚合健康检查。K8s 的 liveness/readiness 请分别指向逻辑服的
> `/healthz` 与 `/ready`（见 `concepts/network-topology.md` 的端口表）。

## 看门狗（进程内周期巡检与告警）

引擎内置 `pkg/runtime/watchdog`：按规则周期巡检，命中后抑制重复、记日志打指标、交给可替换的出口。
它**不采集数据、不定义业务阈值、不落库** —— 只负责「到点跑你的检查函数」。

**引擎已按进程统一拉起**（`internal/app/app.go` 的 `runApp`，game / gateway / master / log / auth 都生效），
不需要任何配置；业务只需注册规则：

```go 注册巡检规则
watchdog.Default().RegisterFunc("my_backlog", func() watchdog.Result {
    if n := myQueue.Len(); n > 1000 {
        return watchdog.Critical("待处理积压 %d 条", n)   // 需要关注但还没影响可用性时用 watchdog.Warn(...)
    }
    return watchdog.OK
})
```

需要去抖动 / 单独周期时用完整的 `watchdog.Rule`：

```go 去抖动的规则
watchdog.Default().Register(watchdog.Rule{
    Name:           "my_latency_high",
    Interval:       30 * time.Second, // 0 = 全局默认 10s
    Cooldown:       5 * time.Minute,  // 0 = 全局默认 5m（同一规则的告警冷却）
    MinConsecutive: 3,                // 连续 3 次命中才告警（滤瞬时毛刺）
    Check:          myLatencyCheck,
})
```

**内置规则**：`process_cpu_saturated` —— 进程 CPU 使用率 ≥ 可用核数（`GOMAXPROCS`）的 90%，
连续 3 轮（默认间隔 10s，即持续约 30s）触发 critical，冷却 10 分钟。

**接入真实告警通道**（webhook / IM / 邮件）：默认出口只保证接口不为 nil，告警一律落引擎日志；
真实通道由业务实现 `Sink` 注入：

```go 接入 webhook
func init() {
    watchdog.Install(watchdog.New(watchdog.Options{
        Sink: watchdog.SinkFunc(func(a watchdog.Alert) { myWebhook(a) }),
    }))
}
```

> **警告：**   **必须先 `Install` 再注册规则**。引擎在 `runApp` 里先安装、再进入各角色装配，
> 业务在 mount / bootstrap 里注册的规则才会落在同一个实例上；顺序反了会丢规则（引擎会打 Error 日志指出）。

运维可读的瞬时快照（与 `/metrics` 的分工是「瞬时状态 vs 时间序列」）：

| 端点 | 归属 | 说明 |
|------|------|------|
| `GET /watchdog` | admin（`admin.listen_addr`，示例 `127.0.0.1:8041`） | 每条规则的 `running` / `firing` / `consecutive` / `last_level` / `last_message` / `last_alert_at`，以及 `dropped` 计数 |

看门狗自己的指标（`clover_watchdog_*`，已在上文「关键业务指标」列出可直接告警的几条）：

| 指标 | 类型 | 解读 |
|------|------|------|
| `clover_watchdog_checks_total{rule,status}` | Counter | `status=ok/firing/skipped/panic`；`skipped` 持续增长 = 该规则卡住了 |
| `clover_watchdog_check_duration_seconds{rule}` | Histogram | 单次巡检耗时，判断规则本身是否成了负担 |
| `clover_watchdog_alerts_total{rule,level}` | Counter | 触发告警数（`level` 含 `recovered`） |

**写自定义规则的三条红线**（细节见 `pkg/runtime/watchdog/README.md`）：

- 检查函数必须**只读、快速、不阻塞**（它在独立 goroutine 里跑，卡住只会跳过自己那条规则）；
- **禁止持锁遍历 / 全表分配快照**（历史教训：drain 持锁 `ListConnIDs` 拖住房间连接派发）；
- 规则名是**有限集合**（它是指标 label 与告警冷却键），禁止拼入 player_id / conn_id / 时间戳。

> **提示：**   引擎**不做指标落库** —— 指标是拉取式，历史留存由 Prometheus / VictoriaMetrics 负责。
> 只有没有 Prometheus 的离线部署才需要自存，且属部署侧（批量落文件或 remote write），不要把写库做进进程。

## 结构化日志告警

建议对以下关键字设置告警：

| 关键字 | 含义 |
|--------|------|
| `Fatal` / `Fatalf` | 进程即将退出 |
| `unrecoverable` | 不可恢复错误 |
| `connection refused` | 数据库/缓存/中间件断连 |
| `panic recovered` | goroutine 中发生 panic |

## 关键业务指标

**引擎内置采集的（可直接告警）：**

| 指标名 | 说明 | 告警阈值参考 |
|--------|------|--------------|
| `clover_gateway_connections` | 网关连接数（Gauge） | 接近 FD 上限时告警 |
| `clover_gateway_messages_total` | 累计收发消息数（Counter） | 速率骤降时告警 |
| `process_cpu_seconds_total` / `process_cpu_ratio` | 进程 CPU（Gauge，见上文） | `process_cpu_ratio` 长期贴近核数上限时告警 |
| `clover_event_crossnode_dead_letter_total` | 跨服事件进入死信队列（Counter） | **非零即告警**：有事件永久丢失，须人工介入 |
| `clover_watchdog_alerts_total{level="critical"}` | 巡检规则命中的 critical 告警（Counter） | 任意 critical 都应有人看 |
| `clover_watchdog_alerts_dropped_total` | 告警没送出去（Counter） | **非零即告警**：出口通道太慢 |
| `clover_watchdog_rules` | 已注册的巡检规则数（Gauge） | **为 0 时告警**：没有任何规则在跑 |

**需业务自行埋点的（引擎未内置）：**

| 建议指标名 | 说明 |
|------------|------|
| `clover_online_players` | 在线玩家数 |
| `clover_msg_duration_seconds` | 消息处理耗时（注意命名规范：用秒，不用 `_latency_ms`） |
| `clover_db_query_duration_seconds` | 数据库查询耗时 |
| `clover_db_query_errors_total` | 数据库查询失败数 |
| `clover_aoi_refresh_duration_seconds` | AOI 刷新耗时 |

> 埋点用 `metrics.ForModule(metrics.ModuleXxx)`，命名规范与 label 约束见
> `pkg/foundation/metrics/naming.go`（严禁高基数 label：`player_id`/`conn_id`/`trace_id` 等）。

## 性能剖析（pprof）

在配置中开启：

```yaml pprof 配置
# 在 server.yaml 中启用 pprof（admin server 内置）
admin:
  pprof: true
```

采集 30 秒 CPU profile：

```bash pprof 命令
go tool pprof http://127.0.0.1:8041/debug/pprof/profile?seconds=30
```

> **注意：** pprof 仅在排查问题时开启，生产环境建议按需启用或限制访问 IP。

## 分布式追踪

当前阶段可通过 `event.Ctx` 的 `c.TraceID()` 获取 trace id，串联关键路径并在日志中打印。引擎未来计划接入 OpenTelemetry。

## 常见问题

### 指标采集失败

**症状**：Prometheus 无法抓取到 Clover 指标

**原因**：指标端点未暴露、网络问题、配置错误

**解决**：
1. 确认 `/metrics` 端点可访问
2. 检查 Prometheus 配置中的 target 地址
3. 验证网络连通性
4. 检查防火墙规则

### 告警规则不触发

**症状**：预期告警未触发

**原因**：告警规则配置错误、阈值设置不当、Prometheus 延迟

**解决**：
1. 检查告警规则语法
2. 验证阈值设置是否合理
3. 确认 Prometheus 评估间隔
4. 检查 Alertmanager 配置

### 看门狗规则没生效

**症状**：`GET /watchdog` 里看不到自己注册的规则，或规则长期 `last_level` 为空

**原因**：注册顺序反了（先注册后 `Install` 会丢规则）；检查函数卡住导致每轮 `skipped`；内置 CPU 规则在
不采集进程 CPU 的平台上不生效

**解决**：
1. 确认规则是在 mount / bootstrap 里用 `watchdog.Default().Register*` 注册的（引擎已先 `Install`）；
2. 看 `clover_watchdog_checks_total{rule,status}`：`skipped` 持续增长说明上一轮检查还没返回；
3. 搜日志关键字 `watchdog:` —— 平台不支持时会打一条 Warn 说明该规则不生效。

### 告警触发但外部通道没收到

**症状**：日志里有 `watchdog: ALERT`，但 webhook / IM 没消息

**原因**：`Sink` 阻塞导致投递队列满，告警被丢弃

**解决**：
1. 看 `clover_watchdog_alerts_dropped_total` 与 `/watchdog` 的 `dropped` 字段（非零 = 有告警没送出去）；
2. 给 `Sink.Notify` 加超时与异步（引擎只保证队列有界不阻塞巡检，不替外部通道兜底）。

## 相关链接

- [日志](/server/operations/logging) - 日志采集与存储
- [性能优化](/server/operations/performance) - 性能调优策略
- [故障排查](/server/operations/troubleshooting) - 常见问题排查
- [Kubernetes 部署](/server/operations/kubernetes) - K8s 部署详解