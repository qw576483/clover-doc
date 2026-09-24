# 工程结构

## 这篇文档讲什么？

本文档介绍 Clover 引擎的工程结构，帮助你理解代码组织方式和依赖方向。目标读者是想要了解引擎架构的开发者。

## 前置条件

- 了解 Go 语言基础
- 熟悉基本的项目结构概念

## 核心原则

Clover 引擎采用 **pkg 公共契约层 + internal 私有实现层** 的 Go 布局：

```
pkg/*：公共 API，业务会亲自使用的类型、接口和工厂函数
internal/*：引擎私有实现，外部模块不可 import
```

> **注意：** 业务代码只依赖 `pkg/*`，禁止直接 import `internal/*`。

## 仓库布局

```text
clover-server-engine/          # 引擎本体（独立仓库）
├── internal/                  # 私有实现（业务禁止 import）
├── pkg/                       # 公共契约层（业务唯一 import 入口）
└── go.mod                     # module github.com/qw576483/clover-server-engine

your-server/                   # 业务服务端工程（独立仓库）
├── go.mod                     # require github.com/qw576483/clover-server-engine
└── server/                    # 服务器工程（game + master 双逻辑）
```

## 依赖方向

```text
业务代码 (业务工程)
        │  只依赖 pkg/*
        ▼
  pkg/  ── 公共契约层（类型/接口/工厂）
        ▲
        │  import（internal 反向依赖 pkg）
        ▼
  internal/
  ┌──────────────────────────────┐
  │  3.1 app       进程编排       │
  │  3.2 foundation 日志/配置/指标 │
  │  3.3 runtime   定时器/状态机   │
  │  3.4 transport 协议/网络/事件  │
  │  3.5 domain    业务领域        │
  │  3.6 shared    工具/协议/算法  │
  └──────────────────────────────┘
```

**约束**：
- 业务只 import `pkg/*`。
- `pkg/*` 尽量不 import `internal/*`。
- `internal/*` 通过 import `pkg/*` 拿类型并实现接口。

## pkg 公共契约层

业务侧统一从 `pkg/*` import，禁止直接 import `internal/*`：

```go
import (
    "github.com/qw576483/clover-server-engine/pkg/app"             // app.Run / RunWithConfig / Game / MasterGame
    "github.com/qw576483/clover-server-engine/pkg/app/types"       // AdminConfig / TableLoader / ConnDisconnectEvent
    "github.com/qw576483/clover-server-engine/pkg/domain/data"     // Store / Record / Key / OwnerType
    "github.com/qw576483/clover-server-engine/pkg/domain/data/account" // EAccount / EChannel
    "github.com/qw576483/clover-server-engine/pkg/domain/master"   // MasterRank / PlayerLookup / RankMember / Threshold
    "github.com/qw576483/clover-server-engine/pkg/domain/mmo"      // SceneManager / Scene / Instance
    "github.com/qw576483/clover-server-engine/pkg/domain/object"   // ObjectID / Manager / Value / AttrSet
    "github.com/qw576483/clover-server-engine/pkg/domain/room"     // Module（房间外壳）/ Kernel（可插拔内核）
    "github.com/qw576483/clover-server-engine/pkg/transport/event" // Ctx / Handler / Envelope / Bus
    "github.com/qw576483/clover-server-engine/pkg/foundation/logger" // logger API
    "github.com/qw576483/clover-server-engine/pkg/shared/conv"     // 纯工具
)
```

### 当前 pkg 公开范围

| 顶层 | 公开子包 |
|------|----------|
| `pkg/app` | `app`, `types` |
| `pkg/domain` | `data`, `data/account`, `data/bridge`, `data/order`, `data/player`, `master`, `mmo`, `mmo/ai/btree`, `mmo/aoi`, `mmo/buff`, `mmo/collide`, `mmo/combat`, `mmo/mapdata`, `mmo/mob`, `mmo/mover`, `mmo/pathfinding`, `mmo/skill`, `mmo/sync`, `object`, `object/gobject`, `object/idgen`, `object/objstore`, `room`, `room/frame` |
| `pkg/foundation` | `logbuf`, `logger`, `logstore`, `metrics`, `trace` |
| `pkg/runtime` | `async`, `fsm`, `pool`, `ratelimit`, `timer`, `watchdog` |
| `pkg/shared` | `bitset`, `bloom`, `cache`, `compress`, `conv`, `geom`, `graph`, `hyperloglog`, `id`, `json`, `jwt`, `memrank`, `proto`, `rand`, `ringbuf`, `safe`, `semaphore`, `separation`, `timeutil`, `timewindow`, `traceid`, `util`, `validate` |
| `pkg/transport` | `event` |

### 通用件：`pkg/shared/separation`（2D 圆形群体分离）

上表已列出 `pkg/shared` 的公开子包名；本节给出其中 **`separation`**（定点整数、确定性、逐 tick 位移上限的「圆形刚体群体分离」解算，供「一屏内的近战拥挤」用）的 API 与边界：

```go
import "github.com/qw576483/clover-server-engine/pkg/shared/separation"
```

| API | 说明 |
|-----|------|
| `separation.New(cfg Config) *Solver` | 构造可复用解算器（只持有临时缓冲，`Resolve` 复用、避免每 tick 分配） |
| `(*Solver).Resolve(bodies []*Body) int` | 解算一轮：把所有重叠对推开，**原地**更新各 `Body` 的 `X` / `Y`；返回本 tick 真的发生了位移的刚体数。切片元素为 `nil` 表示该位不参与 |
| `separation.Body` | 圆形刚体（调用方**内嵌**进自己的实体结构）。字段：`X, Y int64` 圆心（调用方自己的定点单位）/ `Radius int64` 碰撞半径 / `Mass int64`（`> 0` 可推动，**`≤ 0` = 不可推动**）/ `Layer int32`（**只有同层才互相分离**）/ `MaxStep int64` 本 tick 分离位移上限（按整条位移向量的**模长**收缩，`0` = 不限制） |
| `separation.Config` | 构造参数。字段：`TouchTolerance int64`（重叠 ≤ 它的对**不产生分离**，`0` = 不留容差；**本包不设默认值**）/ `Passable func(b Body, x, y int64) bool`（判定实体能否移到该点，`nil` = 总可以） |
| `separation.WalkStep(speedPerSec, ticksPerSecond int64) int64` | **`MaxStep` 的推荐取值** = 实体自己走路一个 tick 的距离（商的整数部分；商落在 (0,1) 取 1；速度 ≤ 0 ⇒ 返回 `0` = 不限制）—— 物理上自洽：**被推开的速率不超过主动移动的速率** |

**语义与边界**：

- **三步形状（不要改成"逐对立即施加"）**：① 一个 tick 内先把**所有**重叠对的分离位移按向量**累加**（全程不移动任何东西）；② 落地时按**参与的同伴数取平均**做欠松弛（除 n 后误差增益恒为 0.5，与 n 无关 —— 不除的话 `n ≥ 4` 时增益 ≥ 1 = **不收敛**）；③ 落地前把整条位移向量按模长收缩到该刚体的每 tick 额度（**按整条向量裁一次**，⛔ 不是每对推力各裁一次）。收敛由**逐 tick 的松弛**负责，tick 内不再迭代。
- **确定性**：全整数运算（调方自定定点单位，来源工程用 1/1000 格）、不调随机、不读时钟；同点重叠按**切片下标**定方向（下标小的向 −X 推）；遍历顺序 = 数组下标序 ⇒ 可直接进服务器权威模拟与离线断言。
- **不是 MMO 空间能力**：与 `pkg/domain/mmo/collide` **无 import 关系**；不做格子查询、不做宽相、不做射线、不做寻路。`pkg/shared/geom` 只收 float64 三维量、`collide` 只收 float64 米制二维原语，故本包独立存在。
- **不带生命周期 / 不带状态**：不持全局单例、不起 goroutine、不读时钟。`Solver` **不是并发安全的** ⇒ **一个 goroutine 一个 `Solver`**。
- **复杂度**：`Resolve` 是 **O(n²)** 全对枚举（不含宽相）⇒ 数量级上去时由调用方先做空间划分再分组调用。
- **不做玩法判断**：半径多大、谁不可推动、每 tick 额度多少、地形能不能进，全部由调用方经 `Body` 与 `Config.Passable` 给。
- **`Passable` 的退化顺序**（把实体塞进墙 / 河 / 阻挡格比「不分开」更糟）：先试 `(x+dx, y+dy)`，不行退化为只走一轴 `(x+dx, y)`，再不行 `(x, y+dy)`，都不行则**本次不位移**。

> ⚠️ **为什么要它（事故出处）**：旧写法「一次性把重叠量推完 / 逐对立即施加」在真机上被客户端 10 Hz 快照 + 线性插值**原样播成一帧冲刺**（实测某实体一个 tick 移动 0.573 格、前后两格各约 0.15 格 ⇒ 单格快 3.8 倍且方向相反），另一种形态是**永久振荡**（用户报「抖得厉害 / 抽搐」）。离线仿真还证伪了「改客户端插值」这条路（任何穿过快照点的插值都躲不开那段位移）⇒ 唯一无滞后的修法是让**源头的逐 tick 位移本身有界**（= `MaxStep` / `WalkStep`）。

## internal 私有实现层

`internal/` 包含引擎实现细节，外部不可见。已删除所有 internal README，文档站不再镜像 `internal` 包树。内部实现细节如需记录，会放进 `docs/internals/`（待建）。

## 服务端工程结构

```text
your-server/server/
├── main.go                  # app.Run(*cfgPath) + 空导入触发挂载
├── configs/all/             # all 模式配置（单文件 server.yaml；NATS 是其中一段）
├── game/
│   ├── def/                 # 消息号与消息结构（msg/reply/push/event/item/rank）
│   ├── datadef/             # 数据 schema（data.RegisterTypeBySchema）
│   ├── logic/               # game 侧逻辑（app.Mount(app.RoleGame, ...)）
│   ├── master_logic/        # master 侧逻辑（app.Mount(app.RoleMaster, ...)）
│   └── table/               # TSV 配置表（go:embed）
```

## 文档工程结构

```text

├── index.md                 # 首页
├── docs.json                # Mintlify 导航（新增页面必须在这里登记，否则页面上不出现）
├── STANDARDS.md             # 文档规范
├── logo/ favicon.svg styles.css
├── client/                  # 客户端文档
│   ├── index.md
│   ├── concepts/            # 核心概念
│   ├── development/         # 开发指南
│   ├── examples/            # 实战示例
│   └── reference/           # 速查（emsg / frame-format / constraints / api-cheatsheet）
└── server/                  # 服务端文档
    ├── index.md / quickstart.md
    ├── concepts/            # 核心概念
    ├── development/         # 开发指南
    ├── examples/            # 实战示例
    ├── operations/          # 运维部署
    ├── security/            # 安全
    └── tools/               # 工具链
```

> 注意：客户端与服务端各有一套 `concepts/ development/ examples/`，
> **只有 `client/` 下有 `reference/`**（客户端 API 速查）。服务端没有 `reference/` 目录。

## 常见问题

### 为什么不能直接 import internal？

**原因**：`internal/` 目录在 Go 中表示私有实现，外部模块无法 import。这是 Go 语言的包可见性规则。

**解决**：使用 `pkg/*` 中的公共 API。

### 如何扩展引擎功能？

**原因**：需要添加新的子系统或功能。

**解决**：
1. 在 `pkg/` 下添加新的公共接口和类型
2. 在 `internal/` 下实现具体逻辑
3. 通过 `pkg/` 暴露给业务代码