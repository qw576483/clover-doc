## 这篇文档讲什么？

Clover 的 **AI 开发规范（skill）体系**：两层 skill 的分工与目录结构，以及写 Clover 业务代码时必须遵守的约束。

## 触发条件

在仓库里做以下事情前，先读对应 skill：

- 新建 Clover 项目 / 搭工程骨架
- 写服务端 handler / schema / 挂载 / 定时器 / 跨服事件
- 写客户端网络 / UI / 实体绑定 / 资源加载
- 出配表（源表 → xlsx → tsv + 代码）
- 一句话做一个 demo
- 复杂项目开多 agent 编排

## 两层 skill

| | 全局 skill | 项目级 skill |
|---|---|---|
| 位置 | [`clover-ai-skill`](https://github.com/qw576483/clover-ai-skill) 仓库（安装到 `~/.codebuddy/skills/ai-skill/`） | `<项目根>/tools/ai-skill/` |
| 范围 | 所有 Clover 项目通用 | **只有该项目** |
| 内容 | 引擎 API、范式（`patterns/**`）、速查（`reference/**`）、模板（`scaffold/**`） | 该项目的消息号 / handler / 面板 / 配表登记与约束 |
| 优先级 | 通用写法 | **项目约定优先**；冲突时以项目为准 |

**动任何项目代码前，先读该项目的 `tools/ai-skill/SKILL.md`。**

## 全局 skill 的结构

```text
clover-ai-skill/
├── SKILL.md            # 入口：工作流、硬约束、目录索引
├── patterns/           # 服务端范式（handler / datadef / mount / timer / crossnode / table / game-demo …）
├── patterns/client/    # 客户端范式（network / ui / entity-view / resource / config / fsm …）
├── reference/          # 速查与团队约定（conventions / modules / client-conventions / server-env / unity-cli）
└── scaffold/           # 从零建工程的完整文件模板（new-project.md / project-skill.md）
```

## 项目级 skill 的结构

由全局 skill 在**新建项目时生成**（模板 `scaffold/project-skill.md`）：

```text
<项目根>/tools/ai-skill/
├── SKILL.md            # 入口 / 索引
├── conventions.md      # 该项目约定（消息号段、命名、目录边界、与全局 skill 的差异）
├── registry.md         # 设施登记簿（消息号 / handler / 面板 / 管理器 / 通用函数 / 配表）
├── constraints.md      # 约束与风险（引擎 / 平台固有约束 + 静默失败风险）
├── patterns/           # 项目特有写法（复杂项目才拆）
└── examples/           # 可照抄的实现范例（复杂项目才拆）
```

## 关键约束速记

### Ctx 单一职责

每个 Handler 只做一件事：

```go
// ✅ 一个 Handler 只处理一个消息
func onBuyItem(c event.Ctx) error {
    // 只处理购买逻辑
    return nil
}
```

### Load-Modify-Return

读出可修改的值，handler 返回后引擎自动保存：

```go
var player Player
g.LoadStruct(c, schema, playerID, &player)
player.Gold += 100
// handler 返回后自动保存
```

### 消息号约定

| 段 | 范围 | 用途 |
| --- | --- | --- |
| 引擎 | 1 - 10000 | 引擎内部使用，业务不要占用（硬约束：业务 C2S 必须 > 10000） |
| C2S | 1000101 起 | 客户端发送，服务端处理 |
| 回包 | 无（不占消息号） | 服务端回复（回包帧 msgID 恒为 0，按 requestID 配对） |
| 推送 | 3002001 起 | 服务端推送 |

> 完整分段与 `E` 前缀规则见 skill 的 `reference/conventions.md`。

### 依赖边界

```go
// ✅ 通过挂载拿到 *app.Game
type gameLogic struct{ g *app.Game }

// ❌ 不要直接 import internal 或具体实现
```

## 下一步

**服务端相关链接：**

- [Handler 开发](../development/handler.md) - Handler 开发详解

- [消息号与协议](../concepts/proto.md) - 消息号分配规则

- [示例](../examples/login.md) - 完整示例参考

**客户端相关链接：**

- [客户端架构](../../client/concepts/architecture.md) - 客户端模块架构

- [网络与会话](../../client/development/network.md) - 网络模块用法

- [Game 门面](../../client/development/game-facade.md) - Game 门面 API
