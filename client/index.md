
# 客户端引擎

Clover 客户端引擎是一套 Unity UPM 包，提供**能力域划分 + WorldSync 世界同步**。

## 这篇文档讲什么？

本文档介绍 Clover 客户端引擎的核心概念、开发指南和最佳实践。目标读者是 Unity 开发者，希望快速集成并使用 Clover 引擎构建游戏客户端。

## 前置条件

- **Unity 6（6000.x）**
- 基本的 C# 编程知识
- 了解 Unity UPM 包管理

## Unity 版本

| 项 | 版本 | 说明 |
|---|---|---|
| 引擎包**声明**的最低兼容版本 | `6000.0` | [`clover-client-unity-engine/package.json`](https://github.com/qw576483/clover-client-unity-engine/blob/main/package.json) 的 `unity` 字段 |
| 本仓库的**开发与验证**版本 | **Unity 6（6000.x）** | 承载工程实测 `6000.6.0f1`；AI 自动化操作（编译 / 测试 / 构建）强制走 Unity 6 |
| 新建工程选哪个 | **Unity 6（6000.x）** | Unity 6 可直接打开并升级 2022.3 时代的包 |

> **提示：**   一句话：**请用 Unity 6（6000.x）建工程** —— 包 `package.json` 的 `unity` 字段写的就是 `6000.0`，且本仓库的自动化校验会直接判不过非 Unity 6 工程（它要求 `ProjectSettings/ProjectVersion.txt` 的 `m_EditorVersion` 是 `6000.x`）。

## 快速体验

```typescript C#
using CloverEngine;
using UnityEngine;

public class GameMain : MonoBehaviour
{
    async void Start()
    {
        // 1. 启动引擎
        var config = new GameConfig
        {
            ServerAddr = "127.0.0.1:8002",   // 网关 TCP 口（gateway.listen_tcp）
            MaxReconnectCount = 5,
            UseTls = true,                   // 与服务端 gateway.tcp_tls_disabled 相反（默认 false 时这里 true）
        };
        Game.Launch(config);

        // 2. 初始化网络（第 1 参 = 网关 TCP 口，第 2 参 = 网关 UDP 口 gateway.listen_udp，留空=不启用不可靠通道）
        CloverNet.Init("127.0.0.1:8002", "127.0.0.1:8003");

        // 3. 登录
        try
        {
            // 账号密码只发给账号服（HTTP）换 token；ELoginRequest 只有 token 字段。
            var token = await CloverAuth.LoginAsync("test", "123456");
            var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest { token = token });
            Debug.Log($"登录成功: owner={reply.owner}");
        }
        catch (CloverCallException ex)
        {
            Debug.LogError($"登录失败: {ex.ServerError}");
        }
    }
}
```

> **注意：**   需要 **Unity 6（6000.x）**。完整集成流程见 [快速开始](development/quick-start.md)。

## 核心特性

- **能力域划分**：Network / Entity / WorldSync / Resource / UI 模块解耦
- **TCP + UDP 双通道**：自动重连，消息收发
- **WorldSync 状态同步**：消费服务端 AOI 结果，增量同步（客户端不建 AOI 网格）
- **Entity 与 View 解耦**：数据驱动表现，对象池复用

## 浏览文档

<Columns cols={2}>
  <Card title="快速开始" icon="rocket" href="/client/development/quick-start">
    从新建 Unity 工程到连上服务端登录成功，全流程走一遍
  </Card>
  <Card title="核心概念" icon="lightbulb" href="/client/concepts/architecture">
    架构总览、设计原则、模块依赖规则
  </Card>
  <Card title="开发指南" icon="code" href="/client/development/game-facade">
    Game 门面、网络、实体、世界同步、资源管理
  </Card>
  <Card title="参考手册" icon="book" href="/client/reference/api-cheatsheet">
    API 速查、消息号、帧格式、硬约束
  </Card>
</Columns>

## 下一步

- **新用户** → [快速开始](development/quick-start.md)，集成到 Unity 项目
- **了解架构** → [架构总览](concepts/architecture.md) → [设计原则](concepts/design-principles.md)
- **开始开发** → [Game 门面](development/game-facade.md) → [网络与会话](development/network.md)
- **完整示例** → [登录流程](examples/login-flow.md)