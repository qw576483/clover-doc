# 测试指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的测试方法，包括单元测试、集成测试、性能测试和测试覆盖率。目标读者是想要编写和运行测试的开发者。

## 前置条件

- 了解 Go 语言测试基础
- 熟悉 Clover 引擎的项目结构
- 了解基本的测试概念

## 单元测试

### 数据 Schema 测试

```go
package datadef

import (
    "testing"
    "clover-server-engine/pkg/domain/data"
)

func TestPlayerSchema(t *testing.T) {
    // 验证 schema 属性
    if PlayerSchema.Type != "player" {
        t.Errorf("期望 Type 为 player, 实际 %s", PlayerSchema.Type)
    }
    if PlayerSchema.OwnerType != data.OwnerPlayer {
        t.Errorf("期望 OwnerType 为 OwnerPlayer")
    }

    // 验证 schema 的 TypeSchema 接口方法与字段一致
    if PlayerSchema.SchemaType() != PlayerSchema.Type {
        t.Errorf("SchemaType() != Type: %s vs %s", PlayerSchema.SchemaType(), PlayerSchema.Type)
    }
}
```

### 业务逻辑测试

```go
package logic

import (
    "testing"
)

func TestLevelUpLogic(t *testing.T) {
    // 测试纯业务逻辑（不依赖引擎）
    player := &PlayerData{
        Level: 1,
        Exp:   100,
    }

    // 执行升级逻辑
    if player.Exp >= 1000 {
        player.Level++
        player.Exp -= 1000
    }

    // 验证结果
    if player.Level != 1 {
        t.Errorf("期望等级不变, 实际 %d", player.Level)
    }
}
```

## 集成测试

Clover 引擎的 Handler 是函数式设计（`func(c event.Ctx) error`）。集成测试需要构建 mock 的 `event.Ctx` 来模拟请求上下文。

```go
package logic

import (
    "testing"
    // 根据实际 engine 提供的测试工具导入
)

func TestOnMsgLevelUp(t *testing.T) {
    // 构建 mock event.Ctx
    // 具体方式取决于引擎提供的测试辅助工具
    // 参考 pkg/transport/event 中的 Ctx 接口定义自行构建 mock 实现
    ctx := mockEventCtx()
    ctx.SetPlayerID("test-player-001")

    // 调用 handler
    err := onMsgLevelUp(ctx)
    if err != nil {
        t.Errorf("handler 返回错误: %v", err)
    }
}
```

> **注意：** 引擎的 `event.Ctx` 是接口类型，编写集成测试时可使用 mock 框架（如 `testify/mock`）或自行构建 mock 实现。参考 `pkg/transport/event` 包中的接口定义确定需要 mock 的方法。

## 性能测试

```go
package logic

import (
    "testing"
)

func BenchmarkOnMsgLevelUp(b *testing.B) {
    for i := 0; i < b.N; i++ {
        ctx := mockEventCtx()
        ctx.SetPlayerID("bench-player")
        onMsgLevelUp(ctx)
    }
}
```

## 测试覆盖率

```bash
# 运行测试并计算覆盖率
go test -coverprofile=coverage.out ./...

# 查看覆盖率
go tool cover -html=coverage.out

# 查看覆盖率报告
go tool cover -func=coverage.out
```

## 测试最佳实践

1. **测试命名**：使用 `Test` 前缀，清晰描述测试内容
2. **测试隔离**：每个测试独立，不依赖其他测试
3. **测试数据**：使用测试数据，不污染生产数据
4. **测试环境**：使用测试环境，不影响生产环境
5. **测试覆盖**：核心逻辑必须有测试覆盖

## 测试目录结构

```
├── datadef/
│   └── schema_test.go       # Schema 定义测试
├── logic/
│   ├── player_test.go       # 玩家逻辑测试
│   ├── item_test.go         # 道具逻辑测试
│   └── handler_test.go      # Handler 集成测试
└── integration_test.go      # 端到端集成测试
```
