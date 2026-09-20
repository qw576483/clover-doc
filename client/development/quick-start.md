# 快速开始

## 这篇文档讲什么？

本指南将帮助你在 5 分钟内将 Clover 客户端引擎集成到 Unity 项目中，并完成最小接入示例。

**目标读者**：Unity 开发者，希望快速上手 Clover 客户端引擎。

## 前置条件

- **Unity 6（6000.x）**（引擎包 `package.json` 的 `unity` 字段声明为 `6000.0` —— 见 [客户端引擎总览](../index.md) 的「Unity 版本」）
- 基本的 Unity 项目结构
- 了解 C# 编程基础

## 环境要求

| 要求 | 版本 |
|------|------|
| **Unity** | **Unity 6（6000.x）**；包声明 `unity: 6000.0`，本仓库一律在 Unity 6 上开发与验证 |
| **操作系统** | Windows / macOS / Linux |
| **.NET** | .NET Standard 2.1 或更高版本 |

## 安装 UPM 包

### 方式一：本地路径（开发阶段）

在你的 Unity 项目的 `Packages/manifest.json` 中添加：

```json
{
  "dependencies": {
    "com.clover.unity-engine": "file:../../../clover-client-unity-engine"
  }
}
```

> **路径基准是工程的 `Packages/` 目录**（Unity 规定：`file:` 相对路径相对 `Packages/` 解析），**不是工程根**。
> 上例的 `../../../` 指「引擎仓库与工程仓库同父目录」的那一层（`<工作区>/clover-client-unity-engine`）。
> 写 `file:../clover-client-unity-engine` 会被解析成 `<工程根>/clover-client-unity-engine`（不存在），
> Unity 报 `com.clover.unity-engine: The file [...\clover-client-unity-engine\package.json] cannot be found`。
> 要把工程分发给别人 → 用**方式二（git URL）**，本地路径只适合自己这台机器联调。

### 方式二：Git URL

```json
{
  "dependencies": {
    "com.clover.unity-engine": "https://github.com/qw576483/clover-client-unity-engine.git"
  }
}
```

### 方式三：Git URL + Tag

```json
{
  "dependencies": {
    "com.clover.unity-engine": "https://github.com/qw576483/clover-client-unity-engine.git#v0.1.0"
  }
}
```

## 最小接入示例

以下是一个完整的最小接入示例，展示如何初始化引擎、连接服务器并登录：

```csharp
using CloverEngine;
using UnityEngine;

public class GameMain : MonoBehaviour
{
    async void Start()
    {
        // 1. 启动引擎
        var config = new GameConfig
        {
            ServerAddr = "127.0.0.1:8002",
            MaxReconnectCount = 5,
            UseTls = true,     // 与服务端 gateway.tcp_tls_disabled 相反（默认 false 时这里 true）
        };
        Game.Launch(config);

        // 2. 挂载输入模块 + 建立 EventSystem
        //    只要工程里有 UI（按钮/输入框）或键鼠操作，这一句必须排在「构建 UI」之前
        CloverInput.Init();

        // 3. 注册推送监听
        Game.OnMsg(EMsg.SomeNotify, ctx =>
        {
            var msg = ctx.Bind<SomeNotify>();
            Debug.Log($"收到推送: {msg.Data}");
        });

        // 4. 登录
        try
        {
            // 账号密码只发给账号服（HTTP）换 token；ELoginRequest 只有 token 字段。
            var token = await CloverAuth.LoginAsync("test", "123456");
            var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest
            {
                token = token,
            });
            Debug.Log($"登录成功: owner={reply.owner}");
        }
        catch (CloverCallException ex)
        {
            Debug.LogError($"登录失败: {ex.ServerError}");
        }
    }
}
```

## 步骤说明

### 1. 启动引擎

```csharp
var config = new GameConfig
{
    ServerAddr = "127.0.0.1:8002",
    MaxReconnectCount = 5,
    UseTls = true,     // 与服务端 gateway.tcp_tls_disabled 相反（默认 false 时这里 true）
};
Game.Launch(config);
```

**说明**：
- `GameConfig` 配置引擎参数
- `ServerAddr` 设置服务器地址
- `MaxReconnectCount` 设置最大重连次数
- `UseTls` 线路是否走 TLS：**必须与服务端 `gateway.tcp_tls_disabled` 相反**；证书只走系统信任链（无跳过校验开关）

### 2. 挂载输入模块

```csharp
CloverInput.Init();
```

**说明**：
- 挂载 `Game.Input`，并按当前输入后端建立 EventSystem + 匹配的 InputModule
- **必须排在「构建 UI」之前**，否则按钮点不了
- 只在纯逻辑（无 UI、无键鼠）的项目里可以省略
- 详见 [输入（Input）](./input.md)

### 3. 注册推送监听

```csharp
Game.OnMsg(EMsg.SomeNotify, ctx =>
{
    var msg = ctx.Bind<SomeNotify>();
    Debug.Log($"收到推送: {msg.Data}");
});
```

**说明**：
- `OnMsg` 注册消息监听
- `EMsg.SomeNotify` 是消息号
- `ctx.Bind<T>()` 反序列化消息体

### 4. 登录

```csharp
// 账号密码只发给账号服（HTTP）换 token；ELoginRequest 只有 token 字段
var token = await CloverAuth.LoginAsync("test", "123456");
var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest { token = token });
if (reply.success) Debug.Log($"登录成功: owner={reply.owner}");
else Debug.LogError($"登录失败: {reply.err}");
```

**说明**：
- `Game.Net.Call<T>` 发送请求并等待回包
- 使用 `try-catch` 处理业务错误和超时

## 单机（不接服务端）

纯单机游戏不需要服务端，也不需要 `CloverNet.Init` / 登录。最小接入：

```csharp
using CloverEngine;
using UnityEngine;

public class GameMain : MonoBehaviour
{
    void Start()
    {
        // 1. Game.Launch 不做任何网络连接 —— 单机不需要 ServerAddr
        Game.Launch(new GameConfig { LogDir = "logs" });

        // 2. 挂载输入 + 建立 EventSystem（有 UI / 键鼠操作就必须有，且早于构建 UI）
        CloverInput.Init();

        // 3. 构建 UI / 开始游戏
        BuildUi();
    }
}
```

| 事项 | 单机下 |
|------|--------|
| `Game.Launch` | **需要**（只初始化核心子系统，不联网） |
| `CloverInput.Init()` | **需要**（有 UI / 键鼠就必须，且早于构建 UI） |
| `CloverNet.Init()` / 登录 | **不需要** |
| `Game.Net` / `Game.Http` | 为 `null`；引擎内部空安全不会崩，但业务侧不要调用 |
| `CloverData` / `CloverRes` | 按需，都不是必需 |

## 导入示例

1. 打开 Unity Package Manager
2. 点击 `com.clover.unity-engine` 包
3. 点击 **Samples** 标签
4. 点击 **LoginFlow** 的 **Import** 按钮

## 常见问题

### 连接失败

**症状**：`connection refused`

**原因**：服务未启动或端口配置错误

**解决**：
1. 检查服务是否启动
2. 确认端口配置一致

### 登录失败

**症状**：`CloverCallException`

**原因**：账号密码错误或服务器逻辑错误

**解决**：
1. 检查账号密码是否正确
2. 查看服务器日志

## 下一步

- 了解 [Game 门面](./game-facade.md) 和模块入口
- 了解 [网络模块](./network.md) 完整用法
- 了解 [序列化协议](./serialization.md)