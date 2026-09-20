# 表设计指南

## 这篇文档讲什么？

本文档介绍 Clover 引擎的表设计方法，包括表定义、字段类型、ORM 标签和数据访问模式。目标读者是想要设计数据模型的开发者。

## 前置条件

- 了解 Go 语言结构体
- 熟悉数据库表设计概念
- 了解 ORM 基础

## 数据模型定义

每个数据模型使用 `data.StructSchema` 定义。`StructSchema` 描述数据类型标识和存储属性，字段定义由 Go 结构体本身隐式承载：

```go
package datadef

import (
    "clover-server-engine/pkg/domain/data"
)

// PlayerInfo 标识玩家信息的存储类型
// 实际字段由 PlayerInfoGo struct 定义，StructSchema 描述存储属性
var PlayerInfo = data.StructSchema{
    Type:      "player_info",            // 数据唯一标识
    OwnerType: data.OwnerPlayer,         // owner 类型
    Visibility: data.ClientVisible,     // 所有人可见
    Tier:      data.TierRedisMySQL,      // 存储等级
}
```

数据模型的字段定义通过 Go 结构体承载，加载时通过 `g.LoadStruct` 自动映射：

```go
// PlayerInfoGo 是 PlayerInfo 的 Go 结构体，字段由 struct tag 定义
type PlayerInfoGo struct {
    Account  string `json:"account"`
    Nickname string `json:"nickname"`
    Level    int32  `json:"level"`
    Exp      int64  `json:"exp"`
    Coins    int64  `json:"coins"`
}

// 使用 LoadStruct 加载
var p PlayerInfoGo
err := g.LoadStruct(c, datadef.PlayerSchema, playerID, &p)
```

> **注意：** `StructSchema` 描述数据类型和存储属性，不是 ORM 表定义。字段映射由 Go 结构体 + `json` tag 驱动。


## OwnerType（数据归属）

| 常量 | 值 | 说明 |
|------|------|------|
| `data.OwnerAccount` | `"account"` | 账号级数据（登录身份） |
| `data.OwnerPlayer` | `"player"` | 玩家级数据 |
| `data.OwnerServer` | `"server"` | 服务器级数据（区服广播） |
| `data.OwnerObject` | `"object"` | 游戏对象级数据（NPC、道具等） |
| `data.OwnerMeta` | `"meta"` | 内部簿记（非业务） |

## Visibility（客户端可见性）

| 常量 | 值 | 说明 |
|------|------|------|
| `data.ClientVisible` | 0 | 所有人可见（默认） |
| `data.ClientSelfOnly` | 1 | 仅自己可见 |
| `data.ServerOnly` | 2 | 纯服务器数据 |

## StorageTier（存储等级）

| 常量 | 值 | 说明 |
|------|------|------|
| `data.TierMemory` | 1 | 纯进程内存，进程退出即丢失 |
| `data.TierRedis` | 2 | 纯 Redis 存储 |
| `data.TierRedisMySQL` | 3 | Redis 热缓存 + MySQL 冷持久化（默认推荐） |
| `data.TierSnapshot` | 4 | 内存主存 + MySQL 快照落盘 |

## 数据访问

```go
var p datadef.Player
if err := g.LoadStruct(c, datadef.PlayerSchema, playerID, &p); err != nil {
    return err
}
// 修改 p 后，handler 返回时自动提交
```
