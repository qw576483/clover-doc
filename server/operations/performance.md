## 这篇文档讲什么？

从网络层、数据层、缓存层、定时器四个维度，系统梳理游戏后端的性能优化策略。本文档适用于开发者和运维人员进行性能调优。

## 前置条件

- 了解 Clover 的架构和组件
- 具备基本的性能分析能力
- 熟悉 Go 语言性能优化工具

## 网络层优化

### 连接管理

- **TCP 延迟确认**：开启 `TCP_NODELAY`，减少 Nagle 延迟
- **WebSocket 压缩**：对大包启用 `permessage-deflate` 压缩
- **连接池复用**：etcd/MySQL/Redis 使用连接池，避免频繁建连

### 消息序列化

| 方案 | 体积 | 速度 | 适用场景 |
|------|------|------|----------|
| JSON | 大 | 慢 | 调试、低频消息 |
| Protobuf | 小 | 快 | 高频消息（推荐） |
| FlatBuffers | 小 | 极快 | 超高频（帧同步） |

### 广播优化

```go 广播优化示例
// 错误：逐条发送
for _, conn := range conns {
    conn.Send(msg)
}

// 正确：批量广播
// ⛔ 引擎**没有** `gateway.BroadcastToRoom`（全仓 0 命中）；场景广播用 mmo.Broadcast：
mmo.Broadcast(scene, msgID, body)   // body 是 []byte（不是 msg 对象）
```

> **注意：** 使用 `object.Value` 的字段级增量广播（`EPushDataSync`），只推变化的字段，不推全量数据。

## AOI 与视野同步

AOI（Area of Interest）确保玩家只收到视野范围内的数据：

```text AOI 示例
玩家 A (100, 200) → 半径 500 的九宫格
├── (500, 0) 网格内玩家 B → 收到 A 的数据
├── (500, 500) 网格内玩家 C → 收到 A 的数据
└── (1000, 1000) 网格内玩家 D → 不收到 A 的数据
```

| 算法 | 复杂度 | 适用场景 |
|------|--------|----------|
| 九宫格 | O(1) | 大世界 MMO |
| 十字链表 | O(log n) | 均匀分布场景 |
| 扇形扫描 | O(n) | 2D 俯视角 |

## 数据序列化优化

### object.Value vs Bag

```go 数据序列化示例
// ⛔ 下面两行**照抄编译不过**：object 包既没有 `Set` 也没有 `Bag()` ——
//    `object.Value` 上只有 GetCell / SetCell（作用于 data.Record），不存在字段级 Set。
//    字段级增量请走 data.Record 的 SetCell / AddRowValues（见 development/table-design.md）。
// p.Set("hp", 100)             // ⛔ 不存在
// p.Bag().Set("items", ids)    // ⛔ 不存在（没有 Bag）
```

| 方案 | 推送粒度 | 序列化成本 | 适用场景 |
|------|----------|------------|----------|
| `object.Value` | 字段级 | 低 | HP/MP/等级等 |
| `Bag` | 整表级 | 高 | 背包/邮件等 |

## 缓存策略

### LRU 缓存

```go LRU 缓存示例
// 引擎内置 LRU 缓存：pkg/shared/cache，泛型 + 选项式，容量用 WithMaxNum
import enginecache "github.com/qw576483/clover-server-engine/pkg/shared/cache"
cache := enginecache.New[string, any](enginecache.WithMaxNum(1000)) // 最多 1000 条

// 读取：先查缓存，miss 再查 DB
if v, ok := cache.Get(key); ok {
    return v
}
v, _ := db.Get(key)
cache.Set(key, v)
```

### 对象池

```go 对象池示例
// 复用临时对象，减少 GC 压力
msg := msgPool.Get().(*Message)
defer msgPool.Put(msg)

msg.Reset()
msg.Type = MsgTypeGame
// ...
```

## 定时器优化

| API | 适用场景 | 精度 |
|-----|----------|------|
| `Timer.After` | 延迟执行一次 | 毫秒级 |
| `Timer.Every` | 固定间隔重复 | 毫秒级 |
| `Timer.Cron` | 定时触发 | 秒级 |
| `Timer.DailyAt` | 每天定时 | 秒级 |

> **警告：** 避免在定时器中执行耗时操作（如大量数据库写入），应异步处理或分批执行。

## 分布式优化

### 分区路由

```text 分区路由示例
玩家请求 → Gateway → 按 playerID % N 路由到对应 Game 节点
```

### 跨节点调用

```go 跨节点调用示例
// CallMaster：同步调用 Master 节点（msgID 为 uint32，req/resp 为结构体指针）
// 消息号用【业务 def 包】里的常量，引擎 proto 里没有 Msg 前缀的业务消息号。
var resp RankResponse
err := g.CallMaster(def.MsgGetRank, &RankRequest{PlayerID: playerID}, &resp)

// PushToPlayer：服务端主动推送（对象按 JSON 编码；经 NATS 下发到网关再推给客户端，不经过 Master）
g.PushToPlayer(targetPlayerID, def.MsgXxxPush, data)
```

## 压测建议

| 指标 | 目标值 | 测量方法 |
|------|--------|----------|
| 消息吞吐 | >10000 msg/s | 压测工具 + Prometheus |
| 平均延迟 | <10ms | p99 <50ms |
| 内存占用 | <500MB/节点 | `runtime.ReadMemStats` |
| CPU 占用 | <70% | `top` / `htop` |

## 典型性能指标

| 场景 | 1K 玩家 | 10K 玩家 | 100K 玩家 |
|------|---------|----------|-----------|
| 登录延迟 | <50ms | <100ms | <200ms |
| 消息广播 | <5ms | <20ms | <100ms |
| 数据持久化 | <10ms | <50ms | <200ms |

## 常见问题

### 消息延迟高

**症状**：消息处理延迟超过预期

**原因**：网络延迟、序列化开销、数据库慢查询

**解决**：
1. 检查网络延迟和带宽
2. 优化消息序列化方案
3. 分析数据库查询性能
4. 增加缓存命中率

### 内存占用过高

**症状**：进程内存占用持续增长

**原因**：内存泄漏、缓存过大、对象未释放

**解决**：
1. 使用 pprof 分析内存分配
2. 检查 goroutine 泄漏
3. 优化缓存策略
4. 检查对象池使用情况

## 下一步

1. [集群架构](../concepts/cluster.md) —— 理解多节点部署和跨节点通信
2. [网络拓扑](../concepts/network-topology.md) —— 理解三层网络架构
3. [监控告警](monitoring.md) —— 建立性能监控体系

