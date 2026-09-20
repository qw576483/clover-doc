
## 这篇文档讲什么？

Clover 引擎集成 gosec 进行安全扫描，本文介绍常见安全规则、修复方法和扫描集成。

## 安全扫描集成

引擎在 CI/CD 流程中集成 gosec，每次提交自动扫描：

```bash
# 本地运行
gosec -fmt=json -out=results.json ./...
```

## 常见安全规则

### SQL 注入（G201）

```go
// ❌ 危险：字符串拼接
query := fmt.Sprintf("SELECT * FROM player WHERE id = %d", playerID)
db.Raw(query)

// ✅ 安全：参数化查询
db.Raw("SELECT * FROM player WHERE id = ?", playerID)
```

### 文件路径遍历（G304）

```go
// ❌ 危险：用户输入直接拼接路径
path := userInput
data, _ := os.ReadFile(path)

// ✅ 安全：清理路径
path := filepath.Clean(userInput)
if !strings.HasPrefix(path, safeDir) {
    return errors.New("path traversal")
}
data, _ := os.ReadFile(path)
```

### 整数溢出（G115）

```go
// ❌ 危险：int64 转 uint32 可能溢出
var bigNum int64 = 5000000000
smallNum := uint32(bigNum) // 溢出！

// ✅ 安全：范围校验
if bigNum < 0 || bigNum > math.MaxUint32 {
    return errors.New("out of range")
}
smallNum := uint32(bigNum)
```

### 弱随机数（G404）

```go
// ❌ 危险：math/rand 可预测
token := rand.Intn(1000000)

// ✅ 安全：crypto/rand 不可预测
token, _ := rand.Int(rand.Reader, big.NewInt(1000000))
```

### 子进程调用（G204）

```go
// ❌ 危险：用户输入直接传入命令
cmd := exec.Command("sh", "-c", userInput)

// ✅ 安全：使用固定参数
cmd := exec.Command("sh", "-c", "fixed-command")
```

### 文件权限（G301/G302/G306）

```go
// ❌ 危险：过于宽松的权限
os.MkdirAll(dir, 0777)
os.WriteFile(path, data, 0777)

// ✅ 安全：最小权限
os.MkdirAll(dir, 0750)
os.WriteFile(path, data, 0640)
```

### HTTP Slowloris（G112）

```go
// ❌ 危险：无超时限制
server := &http.Server{Addr: ":8080"}

// ✅ 安全：设置超时
server := &http.Server{
    Addr:              ":8080",
    ReadHeaderTimeout: 10 * time.Second,
    ReadTimeout:       30 * time.Second,
    WriteTimeout:      30 * time.Second,
    IdleTimeout:       120 * time.Second,
}
```

### 上下文传播（G118）

```go
// ❌ 危险：使用 context.Background()
result, _ := db.QueryContext(context.Background(), query)

// ✅ 安全：传播调用方 context
result, _ := db.QueryContext(ctx, query)
```

## 安全编码原则

| 原则 | 说明 |
| --- | --- |
| 不信任客户端 | 所有客户端输入都必须校验 |
| 最小权限 | 文件权限、数据库权限按需分配 |
| 参数化查询 | 永远不要拼接 SQL |
| 路径清理 | 使用 `filepath.Clean` 清理路径 |
| 加密随机数 | 安全相关使用 `crypto/rand` |
| 超时控制 | 所有网络操作设置超时 |

## 下一步


**相关链接：**

- [输入校验](/server/security/input-validation) - 详细的输入校验指南

- [反作弊](/server/security/anti-cheat) - 游戏反作弊策略

- [认证与权限](/server/security/auth) - 认证流程和权限控制


