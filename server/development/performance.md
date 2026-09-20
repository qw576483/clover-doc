# 性能优化指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的性能优化方法，包括 CPU 优化、内存优化、网络优化和数据库优化。目标读者是想要优化游戏性能的开发者。

## 前置条件

- 了解 Go 语言性能优化基础
- 熟悉 Clover 引擎的架构
- 了解性能分析工具

## CPU 优化

### 减少锁竞争

```go
// 使用读写锁
var rwLock sync.RWMutex

rwLock.RLock()
// 读操作
rwLock.RUnlock()

rwLock.Lock()
// 写操作
rwLock.Unlock()
```

### 使用对象池

```go
// 使用 sync.Pool
var pool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

buf := pool.Get().(*bytes.Buffer)
buf.Reset()
defer pool.Put(buf)
```

### 减少内存分配

```go
// 使用预分配
items := make([]*Item, 0, 100)

// 使用对象池
item := pool.Get().(*Item)
defer pool.Put(item)
```

## 内存优化

### 减少 GC 压力

```go
// 使用对象池
var pool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

// 使用预分配
items := make([]*Item, 0, 100)
```

### 内存对齐

```go
// 使用内存对齐
type Player struct {
    ID     int64  // 8 字节
    Level  int32  // 4 字节
    Exp    int64  // 8 字节
    Name   string // 16 字节
}
```

## 网络优化

### 连接复用

```go
// 使用连接池
var connPool = &sql.DB{
    MaxOpenConns: 100,
    MaxIdleConns: 10,
}
```

### 批量请求

```go
// 批量查询
players := make([]datadef.PlayerSchema, 0, 100)
for _, id := range playerIDs {
    var p datadef.PlayerSchema
    if err := g.LoadStruct(c, datadef.PlayerSchema, id, &p); err != nil {
        continue // 或 return err
    }
    players = append(players, p)
}
```

## 数据库优化

### 索引优化

```go
// 在 StructSchema 定义中使用 StorageTier 控制存储行为
// 如需通过字段查询，建议：1) 在 Redis 中用 Hash 存储；2) 在 MySQL 中建立索引列
// 做法是在 LoadStruct 加载后，按业务需要在数据库侧建立索引
```

### 查询优化

```go
// 使用主键索引查询
var p datadef.PlayerSchema
if err := g.LoadStruct(c, datadef.PlayerSchema, playerID, &p); err != nil {
    return err
}

// 批量按条件查询（遍历+过滤）
var result []datadef.PlayerSchema
var all []datadef.PlayerSchema
// 先加载全量（或通过服务端过滤接口），再本地筛选
for _, p := range all {
    if p.Level == 10 {
        result = append(result, p)
    }
}
```

### 缓存优化（伪代码）

```go
// 缓存旁路模式（cache-aside）—— 伪代码，展示思路
// 实际项目中 cache / player 变量替换为你的 Redis 封装或引擎 data 层
func GetPlayerInfo(g *app.Game, playerID string) (*Player, error) {
    // 先查缓存（业务层自行管理 key 与过期）
    if player := cacheLookup(playerID); player != nil {
        return player, nil
    }

    // 再查数据库（通过引擎 data 层，schema 用实际的 datadef.PlayerSchema）
    var p datadef.PlayerSchema
    if err := g.LoadStruct(c, datadef.PlayerSchema, playerID, &p); err != nil {
        return nil, err
    }
    cacheStore(playerID, &p)
    return &p, nil
}
```

## 性能监控

### CPU 监控

```go
import "runtime"

// 获取 CPU 使用率
cpuUsage := runtime.NumCPU()

// 获取 Goroutine 数量
goroutineNum := runtime.NumGoroutine()
```

### 内存监控

```go
import "runtime"

var memStats runtime.MemStats
runtime.ReadMemStats(&memStats)

logger.Infof("内存使用: %d MB", memStats.Alloc/1024/1024)
```

### 网络监控

```go
// 监控网络连接
connCount := len(netConns)

// 监控网络流量
bytesSent := stats.BytesSent
bytesRecv := stats.BytesRecv
```
