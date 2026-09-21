# 快速开始

从新建 Unity 工程，到连上服务端、登录成功。

引擎以 **UPM 包**形式分发（包名 `com.clover.unity-engine`），与服务端 [clover-server-engine](https://github.com/qw576483/clover-server-engine) 配套：两端只在**两处**对齐 —— ① API 语义（`OnMsg` / `On` / `Timer.After|Every` / `Fsm.Trigger` 的拼写与语义）；② 网络协议（帧格式、EMsg 消息号、ObjectID 位布局逐字节一致）。除此之外客户端按自己的能力域组织，**不镜像服务端目录**。

## 0. 先装 Unity 6

| 项 | 要求 |
|---|---|
| Unity | **6000.0（Unity 6）** 及以上（引擎包 `package.json` 的 `unity` 字段就声明为 `6000.0`） |
| 依赖 | `com.unity.ugui`（Unity 内置包，无需手动装） |

没装过 Unity、或者国内网络下 Hub 登录 / 下载卡住，照 [新手指南：用 AI 从零做一个 Clover 游戏](https://github.com/qw576483/clover-doc/blob/main/ai/ai-quick-start.md) 走一遍（里面写了 Hub 的登录与下载"一个要关代理、一个要开代理"的顺序）。

## 1. 装引擎包

Unity → **Window → Package Manager** → 左上 `+`：

**方式一：Git URL（推荐，分发 / 多人协作用这个）**

*Add package from git URL*，填：

```text
https://github.com/qw576483/clover-client-unity-engine.git
```

锁版本就加 tag：`...clover-client-unity-engine.git#v0.1.0`。

**方式二：本地磁盘（自己改引擎时才用）**

`+` → *Add package from disk* → 选引擎仓库根目录的 `package.json`。

或者直接写 `Packages/manifest.json`：

```json
{
  "dependencies": {
    "com.clover.unity-engine": "file:../../../clover-client-unity-engine"
  }
}
```

> **路径基准是工程的 `Packages/` 目录**（Unity 规定 `file:` 相对路径相对 `Packages/` 解析），**不是工程根**。
> 上例的 `../../../` 指的是"引擎仓库与工程仓库同父目录"那一层（`<工作区>/clover-client-unity-engine`）。
> 写成 `file:../clover-client-unity-engine` 会被解析成 `<工程根>/clover-client-unity-engine`（不存在），Unity 报
> `com.clover.unity-engine: The file [...\clover-client-unity-engine\package.json] cannot be found`。
> 要把工程发给别人，用**方式一** —— 本地路径只适合自己这台机器联调。

## 2. 工程结构

按能力域分目录，别把消息号、协议定义散落在面板脚本里：

```text
Assets/Scripts/
├── App/            # 唯一组装点（Bootstrap：按次序拉起引擎）
├── Core/           # 客户端自己的常量、事件名、工具
├── Def/            # ★ 消息号与协议定义（MsgDef / ProtoDef），先建这个目录
├── Module/         # 业务模块（Flow / Map / Combat / Match …）
└── UI/             # 面板
Assets/Configs/config.json    # 地址与账号配置（见第 4 节）
```

## 3. 最小可跑：组装点

**初始化次序是硬契约**，漏一步的后果都是**静默**的（不报错，只是按钮点不动 / 图加载不出来 / 收不到推送）。把下面这段挂到场景里的根节点上：

```csharp
using CloverEngine;
using UnityEngine;

public sealed class Bootstrap : MonoBehaviour
{
    private void Start()
    {
        // ① 引擎（只初始化核心子系统，**不联网、不挂资源**）
        Game.Launch(new GameConfig
        {
            ServerAddr = "127.0.0.1:8002",   // 网关 **TCP** 口（服务端 gateway.listen_tcp）
            UseTls = true,                   // 与服务端 gateway.tcp_tls_disabled **相反**
            LogDir = "logs",
            CallTimeoutSeconds = 10,
            MaxReconnectCount = 5,
        });

        // ② 输入 + EventSystem —— 必须在建 UI **之前**
        CloverInput.Init();

        // ②' 失焦继续跑。联机游戏的正确行为：服务端 tick 不会因为你切窗口而停
        Application.runInBackground = true;

        // ③ 网络（显式；Launch 不联网）。第 1 参 = 网关 TCP 口，第 2 参 = 网关 UDP 口，null = 不用不可靠通道
        CloverNet.Init("127.0.0.1:8002", "127.0.0.1:8003");

        // ④ 资源。参数是 **Resources 下的子目录前缀**，空串 = 直接以 Assets/Resources 为根
        CloverRes.Init(string.Empty);

        // ⑤ 账号服地址 —— 不设的话 LoginAsync / SignupAsync 直接抛 InvalidOperationException
        CloverAuth.AuthAddr = "http://127.0.0.1:8051";

        // 之后才是你的 UI / 流程
        BuildUi();
    }

    private void OnApplicationQuit() => Game.Shutdown();
}
```

每一步漏了会怎样：

| 步骤 | 漏了的后果 |
|---|---|
| `Game.Launch` | 什么都起不来（`Game.IsRunning == false`） |
| `CloverPresentation.ReferenceResolution` / `.MatchWidthOrHeight` | 只有竖版项目需要：**必须在 `Game.Launch` 之前**设，`UIManager` 在 Launch 的挂载钩子里构造、构造时只读一次，之后再设**不生效也不报错** |
| `CloverInput.Init()` | 面板能开、但**按钮全点不动**（没有 EventSystem）；且**必须早于建 UI** |
| `Application.runInBackground` | 窗口不在前台时玩家循环**完全冻结**（`Time.frameCount` 恒为 1、`Time.time` 恒为 0），**一条报错都没有** |
| `CloverNet.Init` | 能启动、能画 UI，但**永远连不上**（Launch 本身不联网） |
| `CloverRes.Init` | `Game.Res` 恒 `null`，图永远加载不出来 |
| `CloverAuth.AuthAddr` | 登录 / 注册直接抛 `InvalidOperationException` |
| 面板供给者（`PanelFactory.Install` 之类） | 第一次 `Game.UI.Open` 会去 `Resources/UI/{类名}` 找预制体并报 `Panel prefab not found` |

> ⛔ `CloverRes.Init("Assets/Resources")` 是**错的**：它会去找 `Resources/Assets/Resources/...`，一个资源都命中不了。要发根前缀就传空串。

## 4. 配置：`Assets/Configs/config.json`

```json
{
  "server": {
    "addr": "127.0.0.1:8002",          // 网关 **TCP** 口（不是 8001，8001 是 WS 口）
    "udp_addr": "",                    // 网关 UDP 口（8003）；空 = 不用不可靠通道
    "tls": false,                      // 与服务端 gateway.tcp_tls_disabled **相反**
    "auth_addr": "http://127.0.0.1:8051",
    "call_timeout": 10,
    "max_reconnect_count": 5
  },
  "account": {
    "name_prefix": "player",           // 本项目自动建号时的账号名前缀
    "password": "123456"
  }
}
```

与服务端配置的**对偶关系**（配错都是"连上就断"或"所有 Call 超时"）：

| 客户端 | 服务端 | 关系 |
|---|---|---|
| `server.addr` | `gateway.listen_tcp` | 同一个口（默认 `8002`）—— **不是** `listen_ws` 的 `8001` |
| `server.udp_addr` | `gateway.listen_udp` | 同一个口（默认 `8003`）；服务端 `quic` / 裸 UDP 都走它 |
| `server.tls` | `gateway.tcp_tls_disabled` | **必须相反**：服务端 `true`（明文）⇒ 客户端 `false` |
| `server.auth_addr` | `auth.listen` | 账号服 HTTP 地址（默认 `8051`） |

## 5. 登录 → 收推送 → 发消息

```csharp
// 1. 账号密码只发给**账号服**（HTTP）换 token；游戏服的 EMsgLogin 只有 token 字段
var token = await CloverAuth.LoginAsync("alice", "123456");

// 2. 用 token 登录游戏服
var reply = await Game.Net.Call<ELoginReply>(EMsg.Login, new ELoginRequest { token = token });
Debug.Log($"登录成功: owner={reply.owner}");

// 3. 收推送（requestID == 0 的帧按 msgID 路由到这里）
Game.OnMsg(EPushPlayerFullSync, ctx =>
{
    var full = ctx.Bind<EPushPlayerFullSync>();
    Debug.Log($"收到全量同步: player={full.player_id}");
});

// 4. 发业务消息（消息号在你的 Def/ 里定义，必须 >= 10001）
var r = await Game.Net.Call<GetPlayerListReply>(MsgDef.GetPlayerList);
```

失败的两种形态要分开看：**网络层失败**（连不上 / 超时）抛 `CloverCallException`；**业务失败**走回包里的业务字段（不要把业务错误当异常处理）。

## 6. 单机（不接服务端）

纯单机游戏不需要服务端，也不需要 `CloverNet.Init` / 登录：

```csharp
Game.Launch(new GameConfig { LogDir = "logs" });   // Launch 不联网，单机不需要 ServerAddr
CloverInput.Init();                                // 有 UI / 键鼠就必须有，且早于建 UI
BuildUi();
```

| 事项 | 单机下 |
|---|---|
| `Game.Launch` | **需要**（只初始化核心子系统，不联网） |
| `CloverInput.Init()` | **需要**（有 UI / 键鼠就必须，且早于建 UI） |
| `CloverNet.Init()` / 登录 | **不需要** |
| `Game.Net` / `Game.Http` | 为 `null`；引擎内部空安全不会崩，但业务侧不要调用 |
| `CloverData` / `CloverRes` | 按需，都不是必需 |

## 7. 完整示例

包内自带 `Samples~/LoginFlow`（注册 → 登录 → 会话建立 → 全量同步 → 断线恢复）：

1. Package Manager → 选中 `com.clover.unity-engine`；
2. 打开 **Samples** 标签；
3. **LoginFlow** → **Import**。

## 8. 验证清单

进 Play 之后逐条对：

- Unity Console **无编译错误**，且没有 `Panel prefab not found`、`unknown certificate` 这类引擎报错；
- 引擎日志里能看到你的组装点打出的地址 / TLS 信息；
- `Game.IsRunning == true`、`Game.Net != null`、`Game.Res` 能加载到一张测试图；
- 编辑器**不在前台**时游戏仍在跑（`Time.frameCount` 会涨）；
- 登录回包 `success == true`，随后收到 `EPushPlayerFullSync`。

## 9. 常见问题

| 现象 | 原因 |
|---|---|
| 按钮 / 输入框完全点不动，且无报错 | 漏 `CloverInput.Init()`，或它排在"建 UI"之后 |
| 图永远加载不出来 | 漏 `CloverRes.Init()`，或前缀写成了 `"Assets/Resources"`（应为空串） |
| 连上就断 | `server.tls` 与服务端 `tcp_tls_disabled` 配成了**同侧** |
| 连不上、随后所有 `Call` 超时 | 配到了 WS 口 `8001`；原生客户端走 TCP `8002` |
| 窗口切到后台就"卡住" | 没设 `Application.runInBackground = true` |
| `LoginAsync` 抛 `InvalidOperationException` | 没设 `CloverAuth.AuthAddr` |
| Package Manager 报 `package.json cannot be found` | 本地路径按 `Packages/` 为基准算错了层数（见第 1 节） |
| Unity 版本不兼容 | 需要 **6000.0（Unity 6）** 及以上 |

**相关链接：**

- [Game 门面](./game-facade.md) — `Game.*` 各入口
- [网络模块](./network.md) — 连接、重连、会话、推送
- [资源模块](./resource.md) — 加载、池化、热更
- [输入](./input.md) — `CloverInput` 与输入后端
- [客户端引擎总览](../index.md) — 能力域与模块全貌
