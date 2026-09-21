
## 这篇文档讲什么？

Clover 引擎的输入校验原则、常用校验方法和最佳实践。

## 校验原则

> **注意：** **核心原则：不信任客户端。** 所有来自客户端的数据都可能是恶意的，必须在服务端校验。


| 原则 | 说明 |
| --- | --- |
| 不信任客户端 | 所有输入必须校验 |
| 尽早失败 | 在 Handler 入口处校验，不要等到逻辑深处 |
| 白名单优先 | 只允许已知合法值，拒绝其他所有 |
| 错误模糊化 | 返回通用错误信息，不要暴露内部实现 |

## 基础校验

### 字符串

```go
func validateString(s string, minLen, maxLen int) error {
    s = strings.TrimSpace(s)
    if len(s) < minLen || len(s) > maxLen {
        return errors.New("invalid input")
    }
    return nil
}
```

### 数值

```go
func validateInt64(v, min, max int64) error {
    if v < min || v > max {
        return errors.New("invalid input")
    }
    return nil
}
```

### 枚举

```go
func validateEnum(v string, allowed []string) error {
    for _, a := range allowed {
        if v == a {
            return nil
        }
    }
    return errors.New("invalid input")
}
```

## 白名单校验

```go
// 只允许特定字符
func validateUsername(s string) error {
    for _, c := range s {
        if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_' || c == '-') {
            return errors.New("invalid username")
        }
    }
    return nil
}
```

## 文件路径校验

```go
func validatePath(path, baseDir string) error {
    // 清理路径
    path = filepath.Clean(path)

    // 检查路径逃逸
    if strings.HasPrefix(path, "..") || filepath.IsAbs(path) {
        return errors.New("invalid path")
    }

    // 检查是否在允许的目录下
    fullPath := filepath.Join(baseDir, path)
    if !strings.HasPrefix(fullPath, baseDir) {
        return errors.New("path traversal")
    }

    return nil
}
```

## 正则校验

```go
import "regexp"

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

func validateEmail(email string) error {
    if !emailRegex.MatchString(email) {
        return errors.New("invalid email")
    }
    return nil
}
```

## SQL 注入防护

```go
// ❌ 危险：字符串拼接
query := fmt.Sprintf("SELECT * FROM player WHERE name = '%s'", name)

// ✅ 安全：参数化查询
db.Where("name = ?", name).First(&player)
```

## 反序列化安全

```go
// ❌ 危险：接受任意 JSON 字段
var data map[string]interface{}
json.Unmarshal(raw, &data)

// ✅ 安全：使用固定结构体
type LoginRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
}
var req LoginRequest
json.Unmarshal(raw, &req)
```

## 校验失败处理

| 场景 | 错误码 | 错误信息 |
| --- | --- | --- |
| 参数缺失 | 1001 | "bad request" |
| 格式错误 | 1002 | "invalid format" |
| 超出范围 | 1003 | "out of range" |
| 非法字符 | 1004 | "invalid input" |
| 路径非法 | 1005 | "invalid path" |

> **警告：** 不要在错误信息中暴露内部细节（如数据库表名、SQL 语句等）。


## 下一步

1. [Handler 开发](../development/handler.md) —— Handler 中的输入校验实践
2. [安全指南](security-guide.md) —— 安全编码和扫描集成
3. [反作弊](anti-cheat.md) —— 游戏反作弊策略

