## 这篇文档讲什么？

Clover 开发和运维中最常见的故障场景，以及对应的排查方法。本文档适用于开发人员和运维人员快速定位和解决问题。

## 前置条件

- 了解 Clover 的架构和组件
- 熟悉基本的故障排查方法
- 了解日志和监控系统的使用

## 启动失败

### 数据库连接失败

```text 错误信息
错误：dial tcp 127.0.0.1:3306: connectex: No connection could be made
```

**排查步骤：**

1. 确认 MySQL 已启动：`mysqladmin ping`
2. 检查配置文件中的 `data.mysql.host`、`data.mysql.port`、`data.mysql.user`、`data.mysql.pass`
3. 确认 MySQL 用户有访问权限：`GRANT ALL ON *.* TO 'user'@'localhost'`
4. 检查防火墙是否放行 3306 端口

### 配置文件解析失败

```text 错误信息
Error: failed to parse config: line 15: unexpected value
```

**排查步骤：**

1. 检查 YAML 语法（缩进、冒号后空格）
2. 确认 `-config` 参数指向正确的文件或目录
3. 使用 YAML 校验工具：`python -c "import yaml; yaml.safe_load(open('server.yaml'))"`

### 日志未输出

**排查步骤：**

1. 确认 stdout/stderr 未被重定向到不存在的路径
2. 检查日志级别配置（是否设为了 `panic`）
3. 确认程序确实启动了（检查进程列表）

## 测试失败

### Windows 权限问题

```text 错误信息
Error: open C:\Users\xxx\AppData\Local\Temp\xxx: Access is denied
```

**解决方案：**

```powershell Windows 环境变量设置
$env:TMPDIR = "c:\clover-tmp"
mkdir c:\clover-tmp
```

### 依赖外部服务

```text 错误信息
Error: connection refused to etcd at 127.0.0.1:2379
```

**解决方案：**

使用 `windows-env` 启动依赖服务，或在测试中 mock 外部依赖。

### 超时

```text 错误信息
Error: context deadline exceeded
```

**排查步骤：**

1. 检查网络连通性
2. 增加测试超时时间
3. 检查外部服务是否过载

## 运行时问题

### 消息丢失

**排查步骤：**

1. 检查消息号是否在三段分配范围内
2. 确认 `OnMsg` 已正确注册
3. 检查 Handler 返回的 error 是否为 nil
4. 查看 NATS 连接状态

### 内存持续增长

**排查步骤：**

1. 使用 `pprof` 分析内存分配：

```bash pprof 内存分析
go tool pprof http://localhost:8041/debug/pprof/heap
```

2. 检查是否有 goroutine 泄漏：

```bash pprof goroutine 分析
go tool pprof http://localhost:8041/debug/pprof/goroutine
```

3. 检查对象池是否正确回收

### CPU 占用过高

**排查步骤：**

1. 使用 `pprof` 分析 CPU 热点：

```bash pprof CPU 分析
go tool pprof http://localhost:8041/debug/pprof/profile?seconds=30
```

2. 检查是否有死循环或无限递归
3. 检查定时器是否触发过于频繁

## 静态检查失败

### staticcheck

```bash staticcheck 检查
# 安装最新版
go install honnef.co/go/tools/cmd/staticcheck@latest

# 运行检查
staticcheck ./...
```

常见问题：
- Go 版本与 staticcheck 不匹配 → 更新 staticcheck
- 未使用的变量 → 删除或使用
- 不可达代码 → 检查逻辑

### errcheck

```bash errcheck 检查
# 安装
go install github.com/kisielk/errcheck@latest

# 运行检查
errcheck ./...
```

常见问题：未检查的 error 返回值 → 添加 `if err != nil` 处理

## 安全告警

### gosec

```bash gosec 安全检查
# 安装
go install github.com/securego/gosec/v2/cmd/gosec@latest

# 运行检查
gosec ./...
```

常见告警及修复：

| 告警 | 说明 | 修复 |
|------|------|------|
| G201 | SQL 注入 | 使用参数化查询 |
| G304 | 文件路径遍历 | 使用 `filepath.Clean` |
| G115 | 整数溢出 | 添加范围校验 |
| G404 | 弱随机数 | 使用 `crypto/rand` |

详见 [安全指南](../security/security-guide.md)。

## 常见问题快速解决

### 服务无法启动

**症状**：进程立即退出或无响应

**原因**：配置错误、依赖服务未就绪、端口冲突

**解决**：
1. 检查日志输出
2. 验证配置文件语法
3. 确认依赖服务状态
4. 检查端口占用情况

### 性能下降

**症状**：响应时间变长、吞吐量下降

**原因**：资源瓶颈、配置不当、代码问题

**解决**：
1. 检查系统资源使用情况
2. 分析性能指标（CPU、内存、网络）
3. 使用 pprof 进行性能剖析
4. 优化热点代码

## 下一步

1. [性能优化](performance.md) —— 性能调优策略
2. [监控告警](monitoring.md) —— 建立监控体系
3. [安全指南](../security/security-guide.md) —— 安全编码和扫描集成

