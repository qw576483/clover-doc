# 双端概念命名约定

## 本页内容

本文档定义 Clover 客户端与服务端**共享领域概念**的命名约定，用于消除「同名不同义」和「缺失概念」两类问题。

## 前置条件

- 已了解 [客户端架构](architecture.md)
- 已了解 [服务端 MMO 世界](../../server/concepts/mmo-world.md)

## 这篇文档讲什么？

服务端是 Go、客户端是 Unity C#，**实现代码无法共用**——这是运行时决定的，不是设计缺陷。但**领域概念必须同义**：同一个词在两端指的是同一个东西，否则业务开发、文档阅读、跨端沟通的成本会持续升高。

本文档把这种约定**白纸黑字固定下来**，作为双端命名的单一事实源。后续写代码（人或 AI）一律照此执行。

## 命名策略

对于跨端共享概念，采用 **"服务端为语义源、客户端加引擎前缀对齐"** 的策略：

- 服务端概念保持原名（如 `Scene`、`Room`、`GObject`）
- 客户端**仅在与服务端概念同名但含义不同**时加 `Clover` 前缀（如 `Game.CloverScene` vs Unity 的 `Game.Scene`），通过 `Game.Xxx` 门面暴露
- 协议层使用统一的 `E` 前缀载体（如 `ESceneInfoNotify`），JSON 字段名双端一致
- 门面属性允许短名（`Game.Res` / `Game.Net` / `Game.Anim`），但**不得与服务端已有同义 API 撞名**：服务端 `Game.Data()` 是三元键存储层句柄，客户端 Schema 注册表因此命名为 `Game.Schema`（`ISchemaRegistry`），而非 `Game.Data`
- 同一能力**只有一个入口**：
  - 消息注册/注销 → `Game.OnMsg` / `Game.OffMsg`（与服务端 `g.OnMsg` 同名）；`INetwork` 不含路由能力，`Game.Net.OnMsg` 已不存在
  - 数据订阅 → `Game.Sync.OnData` / `OnFullSync`；`Game.Schema` 只声明 Schema、不订阅
  - 不允许 `OnPush` / `OnReceive` 之类的近似名或第二入口

---

## 场景（Scene）

### 问题

「场景」在双端同名不同义：

| 端 | 原含义 | 实际是什么 |
|----|--------|-----------|
| 服务端 | `mmo.Scene` | 逻辑地图：Instance 分线、AOI 视野、物理碰撞 |
| 客户端 | `Scene` / `Game.Scene` | Unity 关卡：资源加载、渲染、场景卸载清理 |

两者**职责毫无交集**，却共用同一个词。比「客户端缺少某个概念」更危险——后者是"没有"，前者是"有但意思相反"。

### 约定

| 概念 | 归属 | 命名 | 含义 |
|------|------|------|------|
| **Unity 关卡** | 客户端专有 | `Game.Scene` / `ISceneManager` | 客户端本地表现层的关卡：异步加载/卸载、加载门控、场景级资源清理。对应 Unity 自身的 Scene |
| **服务端场景** | 双端共享 | `CloverScene` / `Game.CloverScene` | 服务端 `mmo.Scene` 在客户端的投影：逻辑地图标识（SceneID + InstanceID）。与服务端**同义** |
| **逻辑地图** | 服务端专有 | `mmo.Scene` | 权威逻辑地图，含 Instance 分线、AOI、碰撞。**保持原名，不改名** |
| **逻辑地图数据** | 引擎内置（数据来自服务端） | `Game.Map` / `IMapData` | 服务端权威地图在客户端的**只读空间投影**：可行走位图查询（`WalkableAt`）。**只回答空间事实**（这一格能不能走），不含本地预测解算（半径采样 / 滑墙归业务） |

### 硬规则

> **警告：**   以下为强制性约定，评审时必须检查。

- **C1**：客户端 `Game.Scene` / `ISceneManager` **专指 Unity 关卡**，不得用于指代服务端场景。
- **C2**：客户端表示服务端场景，一律使用 `CloverScene`，通过 `Game.CloverScene` 暴露。
- **C3**：服务端 `mmo.Scene` 保持原名，不做改名。
- **C4**：客户端 `Entity.SceneGroup` 中的 Scene 同样指 **Unity 关卡**，不得赋予服务端场景语义。
- **C5**：三个概念**不可互替**，各管一件事 ——
  `Game.Scene`（Unity 关卡：加载哪个画面）/ `Game.CloverScene`（服务端场景：我在哪张图、哪条线）/ `Game.Map`（逻辑地图数据：那张图**能不能走**）。
  说"地图"时先问是哪一件：**空间查询**用 `Game.Map`，**归属/分线**用 `Game.CloverScene`，**关卡加载**用 `Game.Scene`。

---

## 分线（Instance）

| 概念 | 归属 | 命名 | 含义 |
|------|------|------|------|
| **服务端分线** | 双端共享 | `CloverScene.InstanceID` | 同一逻辑地图内的分线/副本实例 id |
| **逻辑地图** | 双端共享 | `CloverScene.SceneID` | 逻辑地图的唯一标识 |

客户端不单独建 `Instance` 类型，分线信息作为 `CloverScene` 的字段传递。

---

## 对象体系（GObject / Record / Bag）

### 服务端概念

| 概念 | 服务端 | 含义 |
|------|--------|------|
| **GObject** | `domain/object/gobject/` | 统一对象内核：承载属性（Schema/Record）+ 背包（Bag）+ 同步（AutoSync） |
| **Record** | `gobject.Record` | 强类型行存储：以序号索引字段，字段类型和名称由 `PropSchema` 定义 |
| **Bag** | `gobject.Bag` / `domain/object/bag.go` | 按名索引的属性袋，每个名下挂一个 Record |
| **AutoSync** | `gobject.EnableAutoSync` | 写即推送增量：数据修改后自动生成差量推送 |
| **Schema** | `gobject.Schema` / `PropSchema` | 字段名↔序号↔类型↔标志的映射表，双端必须一致 |

### 客户端对应

| 概念 | 客户端 | 状态 |
|------|--------|------|
| **实体** | `Entity` / `EntityInfo` | ✅ 已有，ObjectID 位布局与服务端一致 |
| **对象内核投影** | `ObjectInstance`（`Runtime/Core/ObjectData.cs`） | ✅ 已实现，对应服务端 `gobject.GObject`（Schema + Bag + Records） |
| **强类型属性集** | `ObjectBag` | ✅ 已实现，按字段名/序号读写 + 类型安全读取 |
| **Record / Bag** | `ObjectRecord` / `ObjectBag` | ✅ 已实现（`ObjectData.cs`） |
| **Schema** | `ObjectSchema` / `FieldDef` | ✅ 已实现；配合门面 `Game.Schema`（`ISchemaRegistry`）登记字段结构（数据订阅走 `Game.Sync`） |
| **AutoSync** | `IWorldSync`（`Game.Sync`）事件流 | ⚠️ 被动订阅，无主动推送能力 |

### 硬规则

- **C6**：客户端 `Entity` 是 GObject 的**最小投影**（ObjectID + 类型 + 弱类型属性），不是完整镜像；需要结构化访问时用 `ObjectInstance`。
- **C7**：客户端强类型属性访问走 `ObjectSchema` + `ObjectRecord`/`ObjectBag`，**禁止**引用服务端 `gobject.*` 类型；字段名与序号必须与服务端 `Schema.FieldName` 逐一对应。
- **C8**：`ObjectBag` / `ObjectRecord` 的 key 命名与服务端 `Schema.FieldName` 保持一致（`EntityInfo.Attrs` 已删除，不要引用）。

---

## 帧同步房间（Room）

| 概念 | 归属 | 命名 | 含义 |
|------|------|------|------|
| **帧同步房间** | 服务端 | `domain/room/frame/Room` | 一局逻辑世界：状态机（Idle→Ready→Running→Closed）、帧上行/下行、快照、追帧恢复 |
| **客户端帧同步** | 客户端 | `Game.FrameRoom` / `IFrameRoom` | ✅ 已实现（`Runtime/Network/FrameRoomManager.cs`）；业务经 `Configure()` 注入消息号 |

### 已有协议支持

- 消息号 `EMsg.PushRoomTakeover = 4004`（引擎推送区间）—— 断线重连时房间接管通知
- 业务层消息号示例 `1002001`~`1002011`：Create/Join/Leave/Input/Ready/Snapshot/Info/Disconnect/Reconnect/Recovery/TakeoverRecovery

### 硬规则

- **C9**：客户端帧同步房间统一用 `Game.FrameRoom`（`IFrameRoom`）。`Clover` 前缀只用于「与服务端概念同名但含义不同」的场合（如 `Game.CloverScene` vs Unity 的 `Game.Scene`），帧同步房间无同名冲突，不加前缀。
- **C10**：帧同步的帧序号（`frame` 字段）、快照格式（`snapshot`/`snapshot_bin`）双端必须一致。

---

## AOI / 视野

| 概念 | 归属 | 命名 | 含义 |
|------|------|------|------|
| **AOI 视野** | 服务端专有 | `domain/mmo/spatial/aoi/` | 九宫格/十字链表，决定哪些实体互相可见 |
| **客户端感知** | 双端共享 | `IWorldSync` 事件流 | `EntityEnter / EntityLeave / EntityMove / EntityProperty` |

客户端不建模 AOI 网格，只消费其结果（实体进出事件）。这是**服务端专有实现细节**，不属于需要对齐的概念。

---

## 会话 / 账号 / 玩家

| 概念 | 归属 | 命名 | 状态 |
|------|------|------|------|
| **会话** | 双端 | `SessionInfo` / `Session` | ✅ 双端一致 |
| **账号登录视图** | 双端 | `EAccountSyncView` | ✅ 协议一致 |
| **玩家同步视图** | 双端 | `EPlayerSyncView` | ✅ 协议一致 |
| **增量数据同步** | 双端 | 无独立载体（body 恒为顶层 `map[type]`，value 为数据体 / 字段级 diff） | ✅ 双端一致，见「协议载体命名规则」 |
| **会话 Token** | 双端 | `SessionInfo.Token` | ✅ |

---

## 协议载体命名规则

有独立结构体的服务端→客户端推送载体统一使用 `*Notify` 后缀：

| 载体 | 消息号 | 含义 |
|------|--------|------|
| `EPlayerFullSyncNotify` | 4001 | 登录后全量同步（玩家数据） |
| `EAlertNotify` | 4002 | 弹窗提示 |
| （无独立载体） | 4003 | 增量数据同步：body 恒为顶层 `map[type]json.RawMessage`（未注册类型合并下发；value 为数据体 / 字段级 diff） |
| `ERoomTakeoverNotify`（`pkg/shared/proto/push.go`；客户端同名类对照，动态 `recovery` 经 `FrameRoom.OnTakeover`） | 4004 | 房间隔线接管（断线重连） |
| `ESceneInfoNotify` | 4005 | 场景标识推送（SceneID + InstanceID） |
| `EQueuePositionNotify`（网关直发帧，不占推送段） | 7 | 排队位置通知：`ahead`（前面还有多少人）/ `total`（队列总人数）/ `ticket`（排队编号） |

### 硬规则

- **C11**：推送载体命名必须以 `Notify` 结尾（对齐 `EAlertNotify` 风格），无例外。
- **C12**：载体 JSON 字段名双端必须一致（snake_case），C# 类用下划线字段，Go 结构体用 `json` tag。
- **C13**：推送载体若**无包装**（如 4003），客户端不得凭字段名猜测形态——必须按服务端实际线格式解析（见 `Runtime/Network/WorldSync.cs`）。

---

## 弱类型约定

`EntityInfo` 是只读快照（ObjectID / TypeID / SceneGroup），**不再提供 `Attrs` 字典**；弱类型属性一律用 `ObjectBag` / `ObjectRecord` / `ObjectInstance`（见上「对象体系」）。为降低混乱风险：

- **C14**：业务对弱类型值做类型转换必须在 DTO 层完成（`Convert.ToInt32(value)`），禁止直接 `unbox`。
- **C15**：属性 key 的命名规则由服务端 `Schema.FieldName` 决定，客户端文档/DTO 必须同步。
- **C16**：`ObjectSchema` 的字段名与序号必须与服务端 `PropSchema` 逐一对应；优先走 Schema 驱动访问，而非散落的 key 字符串。

---

## 完整命名对照表

| 服务端概念 | 服务端命名 | 客户端对应 | 客户端命名 | 对齐状态 |
|-----------|-----------|-----------|-----------|---------|
| 逻辑地图 | `mmo.Scene` | 服务端场景投影 | `CloverScene` / `Game.CloverScene` | ✅ 已实现 |
| 逻辑地图数据 | `pkg/domain/mmo/mapdata`（位图 / 碰撞体 / 出生点） | 客户端空间查询投影 | `Game.Map` / `IMapData` | ✅ 已实现（引擎烘焙 + 加载） |
| 分线实例 | `Instance` | CloverScene 的字段 | `CloverScene.InstanceID` | ✅ 已实现 |
| 帧同步房间 | `frame.Room` | 客户端帧同步 | `Game.FrameRoom` / `IFrameRoom` | ✅ 已实现（消息号业务注入） |
| 统一对象 | `GObject` | 实体投影 / 对象投影 | `Entity` / `EntityInfo`、`ObjectInstance` | ✅ 已实现 |
| 行存储 | `Record` | 行存储 | `ObjectRecord` | ✅ 已实现 |
| 属性袋 | `Bag` | 属性袋 | `ObjectBag` | ✅ 已实现 |
| 写即推送 | `AutoSync` | 被动订阅 | `IWorldSync`（`Game.Sync`）事件 | ⚠️ 单向 |
| 字段映射 | `Schema` / `PropSchema` | 字段映射 | `ObjectSchema` / `FieldDef` | ✅ 已实现 |
| Unity 关卡 | 无（服务端不用） | 关卡管理 | `Game.Scene` / `ISceneManager` | ✅ |
| AOI 视野 | `aoi.Grid` | 事件流结果 | `IWorldSync` 事件 | ✅ 服务端专有 |
| 会话 | `Session` | 会话 | `SessionInfo` | ✅ |
| 账号视图 | `EAccountSyncView` | 账号视图 | `EAccountSyncView` | ✅ |
| 玩家视图 | `EPlayerSyncView` | 玩家视图 | `EPlayerSyncView` | ✅ |
| 数据同步 | 无独立载体 | 数据同步 | 无独立载体（裸 JSON / `map[type]body`） | ✅ |
| 房间接管 | `ERoomTakeoverNotify` | 房间接管 | `ERoomTakeoverNotify`（稳定字段）+ `FrameRoom.OnTakeover`（动态 recovery） | ✅ |
| 场景标识 | `ESceneInfoNotify` | 场景标识 | `ESceneInfoNotify` | ✅ |

---

## 与架构原则的关系

[客户端架构](architecture.md) 中「与服务端的关系」一节指出：双端对齐发生在 **API 语义** 与 **网络协议** 两个层面，且客户端**不镜像服务端目录结构**。

本文档补充的是第三个层面：**领域概念的命名**。三者不冲突——

- 不镜像**目录结构** ≠ 不共享**领域词汇**；
- 共享词汇，但允许实现按各自能力域组织。

## 下一步

- **了解客户端架构** → [客户端架构](architecture.md)
- **了解设计原则** → [设计原则](design-principles.md)
- **了解服务端 MMO** → [MMO 世界](../../server/concepts/mmo-world.md)
