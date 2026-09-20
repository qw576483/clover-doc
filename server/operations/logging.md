## 这篇文档讲什么？

Clover Engine 的日志体系：从输出规范到采集存储，再到告警与安全。本文档适用于运维人员建立日志监控体系。

## 前置条件

- 了解 Clover 的日志输出机制
- 熟悉日志采集工具（Fluent Bit、Promtail）
- 了解日志存储系统（Loki、Elasticsearch）

## 日志输出规范

### 输出目标

日志输出到**标准输出/标准错误**，由容器运行时或日志采集器统一收集。

> **警告：** 避免直接写入本地文件，容器重启后日志会丢失。

### 日志格式

推荐 JSON 结构化日志：

```json 日志格式示例
{
  "time": "2026-07-20T12:00:00Z",
  "level": "INFO",
  "msg": "player login",
  "owner": "1001",
  "opcode": 1,
  "server_id": "game-01",
  "trace_id": "abc123"
}
```

### 日志字段

| 字段 | 说明 |
|------|------|
| `time` | UTC 时间 |
| `level` | DEBUG / INFO / WARN / ERROR / FATAL |
| `msg` | 日志内容 |
| `owner` | 玩家 UID |
| `opcode` | 消息号 |
| `server_id` | 进程实例 ID |
| `trace_id` | 请求链路追踪 ID |
| `error` | 错误信息 |

## 日志采集

### Fluent Bit

```yaml Fluent Bit 配置
[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            docker
    Tag               kube.*

[OUTPUT]
    Name              loki
    Match             *
    Url               http://loki:3100
    Labels            job=clover,env=prod
```

### Promtail + Loki

```yaml Promtail 配置
clients:
  - url: http://loki:3100/loki/api/v1/push
positions:
  filename: /tmp/positions.yaml
scrape_configs:
  - job_name: clover
    static_configs:
      - targets: [localhost]
        labels:
          job: clover
          __path__: /var/log/clover/*.log
```

### 云服务

阿里云 SLS、AWS CloudWatch、Google Cloud Logging 均支持容器日志采集。

## 存储与查询

| 存储 | 特点 | 适用场景 |
|------|------|----------|
| Loki | 轻量、按标签索引 | 中小规模、Kubernetes |
| Elasticsearch | 全文检索强 | 大规模、复杂查询 |
| ClickHouse | 列式存储、聚合快 | 超大规模、日志分析 |
| 对象存储 | 成本低 | 归档、冷备 |

Loki 查询示例：

```text Loki 查询示例
{job="clover"} |= "owner=1001" |= "ERROR"
```

## 日志级别与采样

| 场景 | 级别 |
|------|------|
| 生产环境 | INFO |
| 调试期 | DEBUG（临时开启） |
| 高频 DEBUG | 采样输出，避免压垮日志系统 |

## 日志告警

| 告警 | 条件 |
|------|------|
| 错误率突增 | 5 分钟内 ERROR > 100 条 |
| 登录失败率高 | 5 分钟内登录失败 > 10% |
| 慢请求 | 消息处理耗时 > 1s |
| 连接异常 | 网关断连日志突增 |

## 日志安全

> **警告：** 日志中不得包含明文密码、token、信用卡号等敏感信息。对敏感字段做脱敏或哈希，访问日志系统需权限控制。

## 常见问题

### 日志丢失

**症状**：日志采集中断或部分丢失

**原因**：日志采集器配置错误、存储空间不足、网络问题

**解决**：
1. 检查日志采集器配置和状态
2. 确认存储系统可用空间
3. 检查网络连通性
4. 增加日志缓冲区大小

### 日志查询缓慢

**症状**：日志查询响应时间过长

**原因**：索引配置不当、查询语句复杂、数据量过大

**解决**：
1. 优化索引策略（如按时间分区）
2. 简化查询语句
3. 增加存储系统资源
4. 设置查询超时时间

## 相关链接

- [监控与告警](/server/operations/monitoring) - 监控体系建设
- [故障排查](/server/operations/troubleshooting) - 常见问题排查
- [Kubernetes 部署](/server/operations/kubernetes) - K8s 部署详解
- [备份与恢复](/server/operations/backup-recovery) - 备份恢复策略