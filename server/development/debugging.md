# 调试指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的调试工具和技巧，包括日志调试、断点调试、远程调试和性能分析。目标读者是想要定位和修复问题的开发者。

## 前置条件

- 了解 Go 语言基础
- 熟悉 Clover 引擎的项目结构
- 了解基本的调试概念

## 快速开始

### 1. 日志调试

最简单的调试方式是添加日志：

```go
func loginHandler(c event.Ctx) error {
    // 记录请求参数
    logger.Infof("登录请求: username=%s", req.Username)
    
    // 处理业务逻辑...
    
    // 记录处理结果
    logger.Infof("登录结果: playerID=%s, success=%v", c.PlayerID(), success)
    
    return nil
}
```

### 2. 断点调试

在 IDE 中设置断点：

```bash
# VS Code
# 1. 点击行号左侧设置断点
# 2. 按 F5 启动调试

# GoLand
# 1. 点击行号左侧设置断点
# 2. 点击 Debug 按钮启动调试
```

## 调试工具

### 1. Delve 调试器

Delve 是 Go 语言的调试器，支持断点、单步执行、变量查看等功能。

```bash
# 安装 Delve
go install github.com/go-delve/delve/cmd/dlv@latest

# 调试程序
dlv debug main.go

# 常用命令
(lv) break main.go:20          # 设置断点
(lv) continue                  # 继续执行
(lv) next                      # 单步执行
(lv) step                      # 进入函数
(lv) print playerID            # 打印变量
(lv) locals                    # 打印所有局部变量
(lv) args                      # 打印函数参数
(lv) goroutines                # 查看所有 goroutine
(lv) goroutine 1               # 切换到指定 goroutine
(lv) stack                     # 查看调用栈
(lv) exit                      # 退出调试器
```

### 2. pprof 性能分析

#### 推荐：用引擎内置的 admin pprof（无需改代码）

引擎的 admin 控制面在配置 `admin.pprof: true` 时即注册 `/debug/pprof/*`，
监听地址是 `admin.listen_addr`（默认 `127.0.0.1:8041`），**不需要**自己起一个 6060 服务：

```yaml
admin:
  disable: false
  listen_addr: "127.0.0.1:8041"   # 默认只绑回环
  token: ""                       # 非回环 listen_addr 时**必填**，否则启动被拒
  pprof: true                     # ★ 打开后 /debug/pprof/* 可用
```

> 下面的 `curl` / `pprof` 示例都按**默认形态**（admin 只绑回环 `127.0.0.1:8041`、未配 `admin.token`）写。
> 若把 `admin.listen_addr` 改成内网地址做跨机调试，**必须同时配 `admin.token`**（否则
> `AdminConfig.Normalize` 直接判为不安全配置、**拒绝启动**），且命令行要带上令牌头
> `-H "X-Admin-Token: <token>"`（或 `Authorization: Bearer <token>`）。

```bash
# CPU 分析
go tool pprof http://localhost:8041/debug/pprof/profile?seconds=30

# 内存分析
go tool pprof http://localhost:8041/debug/pprof/heap

# Goroutine 分析
go tool pprof http://localhost:8041/debug/pprof/goroutine

# 阻塞分析
go tool pprof http://localhost:8041/debug/pprof/block

# 互斥锁分析
go tool pprof http://localhost:8041/debug/pprof/mutex
```

#### 备选：独立进程里自建 pprof 端口

独立工具 / 未接入 admin 的场景，可以自己起一个端口（下面是通用 Go 写法，端口按需改）：

```go
import _ "net/http/pprof"

func main() {
    go func() {
        log.Println(http.ListenAndServe("localhost:6060", nil))
    }()

    // 业务逻辑...
}
```

> 这种写法端口由你自己选（示例用 6060），与引擎的 admin 端口无关；
> 生产环境请勿对公网开放。

### 3. 远程调试

支持远程调试服务器上的程序：

```bash
# 启动远程调试服务
dlv exec --headless --listen=:2345 --api-version=2 --accept-multiclient ./game.exe

# 连接远程调试器
dlv connect :2345

# 或者使用 IDE 连接
# VS Code: 修改 launch.json 添加远程调试配置
# GoLand: Run -> Edit Configurations -> 添加 Go Remote
```

## 调试技巧

### 1. 结构化日志

使用结构化日志便于分析：

```go
import "clover-server-engine/pkg/foundation/logger"

func loginHandler(c event.Ctx) error {
    // 记录日志（字段用 logger.Field 构造，无需 import zap）
    logger.Info("开始处理登录请求",
        logger.WithTrace(c.TraceID()),
        logger.Field("player_id", c.PlayerID()),
        logger.Field("msg_id", c.MsgID()))
    
    // 处理业务逻辑...
    
    logger.Info("登录请求处理完成",
        logger.WithTrace(c.TraceID()),
        logger.Field("duration", time.Since(startTime)),
        logger.Field("success", success))
    
    return nil
}
```

### 2. 条件断点

设置条件断点，只在特定条件下触发：

```bash
# Delve 条件断点
(lv) break main.go:20 playerID == 123

# VS Code 条件断点
# 1. 右键点击断点
# 2. 选择 "Edit Breakpoint"
# 3. 输入条件表达式
```

### 3. 日志级别调试

临时调整日志级别：

```bash
# 通过 Admin 接口调整日志级别
curl -X PUT http://localhost:8041/log/level -d '{"level":"debug"}'

# 查看当前日志级别
curl http://localhost:8041/log/level
```

> 上面两条走的是**默认配置**（admin 只绑回环、未配 `admin.token`）。若节点配了 `admin.token`
> （`listen_addr` 不在回环时**必须**配，否则启动被拒），则 `/log/level` 要求带令牌头：
> `-H "X-Admin-Token: <token>"`（或 `Authorization: Bearer <token>`），否则被 401 拒绝。

## 常见问题调试

### 1. 程序卡住（死锁/死循环）

**诊断方法：**

```bash
# 发送 SIGQUIT 信号获取堆栈
kill -QUIT <pid>

# 查看 goroutine 堆栈
cat /proc/<pid>/stack

# 或者使用 pprof
curl http://localhost:6060/debug/pprof/goroutine?debug=1 > goroutine.txt
```

**常见原因：**
- 互斥锁未释放
- Channel 死锁
- 无限循环

**示例代码：**

```go
// 死锁示例
var mu sync.Mutex

func deadlock() {
    mu.Lock()
    // 忘记解锁
    // mu.Unlock()
}

// 解决方案
func fixed() {
    mu.Lock()
    defer mu.Unlock()
    // 业务逻辑...
}
```

### 2. 内存泄漏

**诊断方法：**

```bash
# 获取内存 profile
go tool pprof http://localhost:6060/debug/pprof/heap

# 查看内存分配
(pprof) top
(pprof) list <function_name>

# 生成内存火焰图
go tool pprof -http=:8080 http://localhost:6060/debug/pprof/heap
```

**常见原因：**
- Goroutine 泄漏
- 切片引用未释放
- 全局变量累积

**示例代码：**

```go
// Goroutine 泄漏示例
func leak() {
    ch := make(chan int)
    go func() {
        // 永远阻塞
        <-ch
    }()
    // 忘记关闭 channel
}

// 解决方案
func fixed() {
    ch := make(chan int)
    go func() {
        select {
        case <-ch:
            // 正常退出
        case <-time.After(time.Second):
            // 超时退出
        }
    }()
    close(ch)
}
```

### 3. 性能问题

**诊断方法：**

```bash
# CPU 分析
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# 查看 CPU 使用
(pprof) top
(pprof) list <function_name>

# 生成 CPU 火焰图
go tool pprof -http=:8080 http://localhost:6060/debug/pprof/profile?seconds=30
```

**优化技巧：**

```go
// 1. 避免重复计算（伪代码，展示缓存旁路思路）
func optimize() (Result, error) {
    // 使用缓存（业务层自行管理，引擎提供 pkg/shared/cache 泛型缓存）
    if cached, ok := cacheLookup("key"); ok {
        return cached, nil
    }

    result, err := expensiveCalculation()
    if err != nil {
        return nil, err
    }
    cacheStore("key", result)
    return result, nil
}

// 2. 减少内存分配
func optimize() {
    // 使用对象池
    buf := bufPool.Get().([]byte)
    defer bufPool.Put(buf)
    
    // 使用缓冲区
    // ...
}

// 3. 并发优化
func optimize() {
    // 使用 goroutine 并发处理
    var wg sync.WaitGroup
    for _, item := range items {
        wg.Add(1)
        go func(item Item) {
            defer wg.Done()
            processItem(item)
        }(item)
    }
    wg.Wait()
}
```

### 4. 连接问题

**诊断方法：**

```bash
# 检查端口监听
netstat -tlnp | grep :8001

# 检查连接状态
ss -s

# 检查网络连通性
ping localhost
telnet localhost 8001
```

**常见原因：**
- 端口被占用
- 防火墙阻止
- 连接数超限

**解决方案：**

```bash
# 1. 检查端口占用
lsof -i :8001

# 2. 杀死占用进程
kill -9 <PID>

# 3. 检查防火墙
sudo ufw status

# 4. 临时关闭防火墙
sudo ufw disable
```

## 调试最佳实践

### 1. 日志规范

```go
// 使用统一的日志格式
logger.Info("用户登录成功",
    logger.WithTrace(c.TraceID()),
    logger.Field("player_id", c.PlayerID()),
    logger.Field("msg_id", c.MsgID()),
    logger.Field("action", "login"))

// 错误日志包含详细信息
logger.Error("处理请求失败",
    logger.WithTrace(c.TraceID()),
    logger.Field("error", err),
    logger.Field("stack", string(debug.Stack())))
```

### 2. 调试流程

```bash
# 1. 收集信息
# - 错误信息
# - 日志文件
# - 监控数据
# - 用户反馈

# 2. 复现问题
# - 在测试环境复现
# - 编写复现脚本
# - 收集复现步骤

# 3. 定位问题
# - 使用调试工具
# - 分析日志
# - 检查代码

# 4. 修复问题
# - 修复代码
# - 编写测试
# - 验证修复

# 5. 总结经验
# - 记录问题原因
# - 更新文档
# - 分享经验
```

### 3. 调试工具配置

```json
// VS Code launch.json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Launch Server",
            "type": "go",
            "request": "launch",
            "mode": "debug",
            "program": "${workspaceFolder}/cmd/server",
            "args": ["-config", "configs/all/server.yaml"]
        },
        {
            "name": "Attach to Process",
            "type": "go",
            "request": "attach",
            "mode": "remote",
            "remotePath": "/workspace",
            "port": 2345,
            "host": "127.0.0.1"
        }
    ]
}
```

## 监控与告警

### 1. 应用监控

```go
import "github.com/prometheus/client_golang/prometheus"

// 定义监控指标
var (
    requestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "HTTP request duration in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "path"},
    )
    
    requestCount = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )
)

func init() {
    prometheus.MustRegister(requestDuration)
    prometheus.MustRegister(requestCount)
}

func monitorRequest(method, path string, duration time.Duration, status int) {
    requestDuration.WithLabelValues(method, path).Observe(duration.Seconds())
    requestCount.WithLabelValues(method, path, strconv.Itoa(status)).Inc()
}
```

### 2. 告警配置

```yaml
# alerting.yaml
alerts:
  - name: high_error_rate
    condition: "error_rate > 0.1"  # 错误率超过 10%
    severity: critical
    message: "错误率过高: {{ .ErrorRate }}%"
    
  - name: high_latency
    condition: "p99_latency > 1s"  # P99 延迟超过 1 秒
    severity: warning
    message: "延迟过高: {{ .P99Latency }}"
    
  - name: memory_usage
    condition: "memory_usage > 80%"  # 内存使用超过 80%
    severity: warning
    message: "内存使用过高: {{ .MemoryUsage }}%"
```

## 相关文档

- [性能优化](performance.md)
- [日志管理](logging.md)
- [测试指南](testing.md)
- [监控配置](../operations/scaling.md)